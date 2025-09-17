import Algorithms
import Combine
import Foundation
import LoopKit
import LoopKitUI
import MinimedKit
import MockKit
import OmniKit
import SwiftDate
import Swinject
import UIKit
import UserNotifications

protocol DeviceDataManager: GlucoseSource {
    var pumpManager: PumpManagerUI? { get set }
    var loopInProgress: Bool { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    var recommendsLoop: PassthroughSubject<Void, Never> { get }
    var bolusTrigger: PassthroughSubject<Bool, Never> { get }
    var errorSubject: PassthroughSubject<Error, Never> { get }
    var pumpName: CurrentValueSubject<String, Never> { get }
    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }
    func heartbeat(date: Date)
    func createBolusProgressReporter() -> DoseProgressReporter?
}

private let staticPumpManagers: [PumpManagerUI.Type] = [
    MinimedPumpManager.self,
    OmnipodPumpManager.self,
    MockPumpManager.self
]

private let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = staticPumpManagers.reduce(into: [:]) { map, Type in
    map[Type.pluginIdentifier] = Type
}

private let accessLock = NSRecursiveLock(label: "BaseDeviceDataManager.accessLock")

final class BaseDeviceDataManager: DeviceDataManager, Injectable {
    private let processQueue = DispatchQueue.markedQueue(label: "BaseDeviceDataManager.processQueue")
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var settingsManager: SettingsManager!

    @Persisted(key: "BaseDeviceDataManager.lastEventDate") var lastEventDate: Date? = nil
    @SyncAccess(lock: accessLock) @Persisted(key: "BaseDeviceDataManager.lastHeartBeatTime") var lastHeartBeatTime: Date =
        .distantPast

    let recommendsLoop = PassthroughSubject<Void, Never>()
    let bolusTrigger = PassthroughSubject<Bool, Never>()
    let errorSubject = PassthroughSubject<Error, Never>()
    let pumpNewStatus = PassthroughSubject<Void, Never>()
    @SyncAccess private var pumpUpdateCancellable: AnyCancellable?
    private var pumpUpdatePromise: Future<Bool, Never>.Promise?
    @SyncAccess var loopInProgress: Bool = false

    var pumpManager: PumpManagerUI? {
        didSet {
            pumpManager?.pumpManagerDelegate = self
            pumpManager?.delegateQueue = processQueue
            UserDefaults.standard.pumpManagerRawValue = pumpManager?.rawValue
            if let pumpManager = pumpManager {
                pumpDisplayState.value = PumpDisplayState(name: pumpManager.localizedTitle, image: pumpManager.smallImage)
                pumpName.send(pumpManager.localizedTitle)

                // Connect DefaultBluetoothProvider to the same RileyLink device provider
                // This ensures pump settings UI sees the same devices as the pump manager
                if let minimed = pumpManager as? MinimedPumpManager {
                    DefaultBluetoothProvider.shared.setRileyLinkDeviceProvider(minimed.rileyLinkDeviceProvider)
                    debug(.deviceManager, "Connected DefaultBluetoothProvider to MinimedPumpManager device provider")
                }

                if let omnipod = pumpManager as? OmnipodPumpManager {
                    guard let endTime = omnipod.state.podState?.expiresAt else {
                        pumpExpiresAtDate.send(nil)
                        return
                    }
                    pumpExpiresAtDate.send(endTime)
                }
            } else {
                pumpDisplayState.value = nil
                pumpExpiresAtDate.send(nil)
                pumpName.send("")
            }
        }
    }

    var hasBLEHeartbeat: Bool {
        (pumpManager as? MockPumpManager) == nil
    }

    let pumpDisplayState = CurrentValueSubject<PumpDisplayState?, Never>(nil)
    let pumpExpiresAtDate = CurrentValueSubject<Date?, Never>(nil)
    let pumpName = CurrentValueSubject<String, Never>("Pump")

    init(resolver: Resolver) {
        injectServices(resolver)
        setupPumpManager()
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func setupPumpManager() {
        pumpManager = UserDefaults.standard.pumpManagerRawValue.flatMap { pumpManagerFromRawValue($0) }
    }

    func createBolusProgressReporter() -> DoseProgressReporter? {
        pumpManager?.createBolusProgressReporter(reportingOn: processQueue)
    }

    func heartbeat(date: Date) {
        guard pumpUpdateCancellable == nil else {
            warning(.deviceManager, "Pump updating already in progress. Skip updating.")
            return
        }

        guard !loopInProgress else {
            warning(.deviceManager, "Loop in progress. Skip updating.")
            return
        }

        func update(_: Future<Bool, Never>.Promise?) {}

        processQueue.safeSync {
            lastHeartBeatTime = date
            updatePumpData()
        }
    }

    private func updatePumpData() {
        guard let pumpManager = pumpManager else {
            debug(.deviceManager, "Pump is not set, skip updating")
            updateUpdateFinished(false)
            return
        }

        debug(.deviceManager, "Start updating the pump data")
        pumpUpdateCancellable = Future<Bool, Never> { [unowned self] promise in
            pumpUpdatePromise = promise
            debug(.deviceManager, "Waiting for pump update and loop recommendation")
            processQueue.safeSync {
                pumpManager.ensureCurrentPumpData { _ in
                    debug(.deviceManager, "Pump data updated.")
                }
            }
        }
        .timeout(60, scheduler: processQueue)
        .replaceError(with: false)
        .replaceEmpty(with: false)
        .sink(receiveValue: updateUpdateFinished)
    }

    private func updateUpdateFinished(_ recommendsLoop: Bool) {
        pumpUpdateCancellable = nil
        pumpUpdatePromise = nil
        if !recommendsLoop {
            warning(.deviceManager, "Loop recommendation time out or got error. Trying to loop right now.")
        }
        guard !loopInProgress else {
            warning(.deviceManager, "Loop already in progress. Skip recommendation.")
            return
        }
        self.recommendsLoop.send()
    }

    private func pumpManagerFromRawValue(_ rawValue: [String: Any]) -> PumpManagerUI? {
        guard let rawState = rawValue["state"] as? PumpManager.RawStateValue,
              let Manager = pumpManagerTypeFromRawValue(rawValue)
        else {
            return nil
        }

        return Manager.init(rawState: rawState) as? PumpManagerUI
    }

    private func pumpManagerTypeFromRawValue(_ rawValue: [String: Any]) -> PumpManager.Type? {
        // Prefer new key, fall back to legacy for backward compatibility
        let identifier = (rawValue["pluginIdentifier"] as? String)
            ?? (rawValue["managerIdentifier"] as? String)
        guard let key = identifier else { return nil }
        return staticPumpManagersByIdentifier[key]
    }

    // MARK: - GlucoseSource

    @Persisted(key: "BaseDeviceDataManager.lastFetchGlucoseDate") private var lastFetchGlucoseDate: Date = .distantPast

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        guard let medtronic = pumpManager as? MinimedPumpManager else {
            warning(.deviceManager, "Fetch minilink glucose failed: Pump is not Medtronic")
            return Just([]).eraseToAnyPublisher()
        }

        guard lastFetchGlucoseDate.addingTimeInterval(5.minutes.timeInterval) < Date() else {
            return Just([]).eraseToAnyPublisher()
        }

        medtronic.cgmManagerDelegate = self

        return Future<[BloodGlucose], Error> { promise in
            self.processQueue.async {
                medtronic.fetchNewDataIfNeeded { result in
                    switch result {
                    case .noData,
                         .unreliableData:
                        debug(.deviceManager, "Minilink glucose is empty")
                        promise(.success([]))
                    case let .newData(glucose):
                        let directions: [BloodGlucose.Direction?] = [nil]
                            + glucose.windows(ofCount: 2).map { window -> BloodGlucose.Direction? in
                                let pair = Array(window)
                                guard pair.count == 2 else { return nil }
                                let firstValue = Int(pair[0].quantity.doubleValue(for: .milligramsPerDeciliter))
                                let secondValue = Int(pair[1].quantity.doubleValue(for: .milligramsPerDeciliter))
                                return .init(trend: secondValue - firstValue)
                            }

                        let results = glucose.enumerated().map { index, sample -> BloodGlucose in
                            let value = Int(sample.quantity.doubleValue(for: .milligramsPerDeciliter))
                            return BloodGlucose(
                                _id: sample.syncIdentifier,
                                sgv: value,
                                direction: directions[index],
                                date: Decimal(Int(sample.date.timeIntervalSince1970 * 1000)),
                                dateString: sample.date,
                                unfiltered: nil,
                                filtered: nil,
                                noise: nil,
                                glucose: value,
                                type: "sgv"
                            )
                        }
                        if let lastDate = results.last?.dateString {
                            self.lastFetchGlucoseDate = lastDate
                        }

                        promise(.success(results))
                    case let .error(error):
                        warning(.deviceManager, "Fetch minilink glucose failed", error: error)
                        promise(.failure(error))
                    }
                }
            }
        }
        .timeout(60 * 3, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }
}

extension BaseDeviceDataManager: PumpManagerDelegate {
    func pumpManager(_: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        debug(.deviceManager, "didAdjustPumpClockBy \(adjustment)")
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        UserDefaults.standard.pumpManagerRawValue = pumpManager.rawValue
        if self.pumpManager == nil, let newPumpManager = pumpManager as? PumpManagerUI {
            self.pumpManager = newPumpManager
        }
        pumpName.send(pumpManager.localizedTitle)
    }

    func pumpManagerBLEHeartbeatDidFire(_: PumpManager) {
        debug(.deviceManager, "Pump Heartbeat: checking for suspend state changes")
        if let minimed = pumpManager as? MinimedPumpManager {
            // Check app state on main thread, then continue on background queue
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let isActive = UIApplication.shared.applicationState == .active
                self.processQueue.async {
                    // Set adaptive refresh priority based on app state
                    // Active app (user viewing) = faster refresh (30s)
                    // Background app = slower refresh (60s) to save battery
                    let priority = isActive ? MinimedPumpManager.SuspendRefreshPriority.high : MinimedPumpManager.SuspendRefreshPriority.normal
                    minimed.setSuspendRefreshPriority(priority)
                    
                    // Use lightweight suspend state refresh on heartbeat
                    // This provides rapid response to manual pump suspend/resume actions
                    // while minimizing radio traffic through built-in throttling
                    minimed.refreshSuspendState {
                        // Completion handler - heartbeat processed
                        debug(.deviceManager, "Heartbeat suspend state check completed")
                    }
                }
            }
        }
    }

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool {
        true
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "New pump status Bolus: \(status.bolusState)")
        debug(.deviceManager, "New pump status Basal: \(String(describing: status.basalDeliveryState))")

        if case .inProgress = status.bolusState {
            bolusTrigger.send(true)
        } else {
            bolusTrigger.send(false)
        }

        let batteryPercent = Int((status.pumpBatteryChargeRemaining ?? 1) * 100)
        let battery = Battery(
            percent: batteryPercent,
            voltage: nil,
            string: batteryPercent >= 10 ? .normal : .low,
            display: pumpManager.status.pumpBatteryChargeRemaining != nil
        )
        storage.save(battery, as: OpenAPS.Monitor.battery)
        broadcaster.notify(PumpBatteryObserver.self, on: processQueue) {
            $0.pumpBatteryDidChange(battery)
        }

        if let omnipod = pumpManager as? OmnipodPumpManager {
            let reservoir = omnipod.state.podState?.lastInsulinMeasurements?.reservoirLevel ?? 0xDEAD_BEEF

            storage.save(Decimal(reservoir), as: OpenAPS.Monitor.reservoir)
            broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
                $0.pumpReservoirDidChange(Decimal(reservoir))
            }

            guard let endTime = omnipod.state.podState?.expiresAt else {
                pumpExpiresAtDate.send(nil)
                return
            }
            pumpExpiresAtDate.send(endTime)
        }
    }

    func pumpManagerWillDeactivate(_: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        pumpManager = nil
    }

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents _: Bool) {}

    func pumpManager(_: PumpManager, didError error: PumpManagerError) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "error: \(error.localizedDescription), reason: \(String(describing: error.failureReason))")
        errorSubject.send(error)
    }

    func pumpManager(
        _: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation _: Date?,
        replacePendingEvents _: Bool,
        completion: @escaping (_ error: Error?) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "New pump events:\n\(events.map(\.title).joined(separator: "\n"))")

        // filter buggy TBRs > maxBasal from MDT
        let events = events.filter {
            // type is optional...
            guard let type = $0.type, type == .tempBasal else { return true }
            return $0.dose?.unitsPerHour ?? 0 <= Double(settingsManager.pumpSettings.maxBasal)
        }
        pumpHistoryStorage.storePumpEvents(events)
        lastEventDate = events.last?.date
        completion(nil)
    }

    func pumpManager(
        _: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (Result<
            (newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool),
            Error
        >) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "Reservoir Value \(units), at: \(date)")
        storage.save(Decimal(units), as: OpenAPS.Monitor.reservoir)
        broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
            $0.pumpReservoirDidChange(Decimal(units))
        }

        completion(.success((
            newValue: Reservoir(startDate: Date(), unitVolume: units),
            lastValue: nil,
            areStoredValuesContinuous: true
        )))
    }

    func pumpManagerRecommendsLoop(_: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "Pump recommends loop")
        guard let promise = pumpUpdatePromise else {
            warning(.deviceManager, "We do not waiting for loop recommendation at this time.")
            return
        }
        promise(.success(true))
    }

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        lastEventDate?.addingTimeInterval(-15.minutes.timeInterval) ?? Date().addingTimeInterval(-2.hours.timeInterval)
    }

    func pumpManagerPumpWasReplaced(_ _: PumpManager) {
        debug(.deviceManager, "Pump hardware was replaced")
        // Reset any cached state we rely on; keep it simple for now
        lastEventDate = nil
    }

    func pumpManager(
        _ _: PumpManager,
        didRequestBasalRateScheduleChange _: BasalRateSchedule,
        completion: @escaping (Error?) -> Void
    ) {
        // This app does not push a new schedule proactively here; acknowledge without error
        completion(nil)
    }

    var detectedSystemTimeOffset: TimeInterval { 0 }
    var automaticDosingEnabled: Bool { true }
}

// MARK: - DeviceManagerDelegate

extension BaseDeviceDataManager: DeviceManagerDelegate {
    func scheduleNotification(
        for _: DeviceManager,
        identifier: String,
        content: UNNotificationContent,
        trigger: UNNotificationTrigger?
    ) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        DispatchQueue.main.async {
            UNUserNotificationCenter.current().add(request)
        }
    }

    func clearNotification(for _: DeviceManager, identifier: String) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    func removeNotificationRequests(for _: DeviceManager, identifiers: [String]) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func deviceManager(
        _: DeviceManager,
        logEventForDeviceIdentifier _: String?,
        type _: DeviceLogEntryType,
        message: String,
        completion _: ((Error?) -> Void)?
    ) {
        debug(.deviceManager, "Device message: \(message)")
    }
}

extension BaseDeviceDataManager: CGMManagerDelegate {
    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        glucoseStorage.syncDate().addingTimeInterval(-10.minutes.timeInterval) // additional time to calculate directions
    }

    func cgmManager(_: CGMManager, hasNew _: CGMReadingResult) {}

    func cgmManagerWantsDeletion(_: CGMManager) {}

    func cgmManagerDidUpdateState(_: CGMManager) {}

    func credentialStoragePrefix(for _: CGMManager) -> String { "BaseDeviceDataManager" }

    func cgmManager(_: CGMManager, didUpdate _: CGMManagerStatus) {}

    func cgmManager(_: CGMManager, hasNew _: [PersistedCgmEvent]) {}
}

// MARK: - Alerts

extension BaseDeviceDataManager: AlertIssuer {
    func issueAlert(_: Alert) {}
    func retractAlert(identifier _: Alert.Identifier) {}
}

extension BaseDeviceDataManager: PersistedAlertStore {
    private static var inMemoryAlerts: [Alert.Identifier: PersistedAlert] = [:]

    func doesIssuedAlertExist(identifier: Alert.Identifier, completion: @escaping (Result<Bool, Error>) -> Void) {
        let existing = Self.inMemoryAlerts[identifier]
        completion(.success(existing != nil && existing?.retractedDate == nil))
    }

    func lookupAllUnretracted(managerIdentifier: String, completion: @escaping (Result<[PersistedAlert], Error>) -> Void) {
        let results = Self.inMemoryAlerts.values
            .filter { $0.retractedDate == nil && $0.alert.identifier.managerIdentifier == managerIdentifier }
        completion(.success(results))
    }

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier: String,
        completion: @escaping (Result<[PersistedAlert], Error>) -> Void
    ) {
        let results = Self.inMemoryAlerts.values.filter {
            $0.retractedDate == nil && $0.acknowledgedDate == nil && $0.alert.identifier.managerIdentifier == managerIdentifier
        }
        completion(.success(results))
    }

    func recordRetractedAlert(_ alert: Alert, at date: Date) {
        let persisted = PersistedAlert(alert: alert, issuedDate: date, retractedDate: date, acknowledgedDate: nil)
        Self.inMemoryAlerts[alert.identifier] = persisted
    }
}

// MARK: Others

protocol PumpReservoirObserver {
    func pumpReservoirDidChange(_ reservoir: Decimal)
}

protocol PumpBatteryObserver {
    func pumpBatteryDidChange(_ battery: Battery)
}
