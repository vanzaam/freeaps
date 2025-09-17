import Combine
import Foundation
import G7SensorKit
import HealthKit
import LoopKit
import Swinject
import UserNotifications

final class DexcomSourceG7: GlucoseSource, Injectable {
    private let processQueue = DispatchQueue(label: "DexcomG7Source.processQueue")

    @Injected() private var glucoseStorage: GlucoseStorage!

    private var promise: Future<[BloodGlucose], Error>.Promise?
    private let cgmManager: CGMManager

    init(resolver: Resolver) {
        cgmManager = G7CGMManager()
        cgmManager.delegateQueue = processQueue
        injectServices(resolver)
        cgmManager.cgmManagerDelegate = self
    }

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            guard let self = self else { return }
            self.promise = promise
            self.processQueue.async { [weak self] in
                guard let self = self else { return }
                self.cgmManager.fetchNewDataIfNeeded { result in
                    self.handle(result: result)
                }
            }
        }
        .timeout(60, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    private func handle(result: CGMReadingResult) {
        switch result {
        case let .newData(samples):
            let glucose: [BloodGlucose] = samples.map { s in
                let mgdl = Int(s.quantity.doubleValue(for: .milligramsPerDeciliter))

                // Get trend from G7CGMManager's latest reading
                let direction: BloodGlucose.Direction? = {
                    guard let g7Manager = cgmManager as? G7CGMManager,
                          let latestReading = g7Manager.latestReading,
                          let trendType = latestReading.trendType
                    else {
                        return nil
                    }
                    return BloodGlucose.Direction(trendType: trendType)
                }()

                return BloodGlucose(
                    _id: s.syncIdentifier,
                    sgv: mgdl,
                    direction: direction,
                    date: Decimal(Int(s.date.timeIntervalSince1970 * 1000)),
                    dateString: s.date,
                    unfiltered: Decimal(mgdl),
                    filtered: nil,
                    noise: nil,
                    glucose: mgdl,
                    type: "sgv"
                )
            }
            promise?(.success(glucose))
        case .noData:
            break
        case .unreliableData:
            // Treat as no actionable data
            break
        case let .error(error):
            promise?(.failure(error))
        }
    }

    // MARK: - Control

    func startScan() {
        (cgmManager as? G7CGMManager)?.scanForNewSensor()
    }

    // MARK: - SourceInfoProvider

    func sourceInfo() -> [String: Any]? {
        if let g7 = cgmManager as? G7CGMManager {
            return [
                "type": "Dexcom G7",
                "sensorId": g7.state.sensorID ?? "unknown",
                "sensorFound": g7.state.sensorID != nil,
                "lastReadingTimestamp": g7.latestReadingTimestamp as Any
            ]
        }
        return ["type": "Dexcom G7"]
    }
}

extension DexcomSourceG7: CGMManagerDelegate {
    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        glucoseStorage.syncDate()
    }

    func cgmManager(_: CGMManager, hasNew readingResult: CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        handle(result: readingResult)
    }

    func cgmManagerWantsDeletion(_: CGMManager) {}
    func cgmManagerDidUpdateState(_: CGMManager) {}
    func credentialStoragePrefix(for _: CGMManager) -> String {
        if let bundleId = Bundle.main.bundleIdentifier { return "com.freeaps.dexcomg7." + bundleId }
        return "com.freeaps.dexcomg7"
    }

    func deviceManager(
        _: DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type _: DeviceLogEntryType,
        message: String,
        completion: ((Error?) -> Void)?
    ) {
        debug(.deviceManager, "G7 event [\(deviceIdentifier ?? "-")]: \(message)")
        completion?(nil)
    }

    func issueAlert(_: Alert) {}
    func retractAlert(identifier _: Alert.Identifier) {}
    func cgmManager(_: CGMManager, didUpdate _: CGMManagerStatus) {}
    func cgmManager(_: CGMManager, hasNew _: [PersistedCgmEvent]) {}

    // DeviceManagerDelegate (notifications)
    func scheduleNotification(
        for _: DeviceManager,
        identifier _: String,
        content _: UNNotificationContent,
        trigger _: UNNotificationTrigger?
    ) {}

    func clearNotification(for _: DeviceManager, identifier _: String) {}

    func removeNotificationRequests(for _: DeviceManager, identifiers _: [String]) {}
}

// MARK: - Alerts

extension DexcomSourceG7: PersistedAlertStore {
    func doesIssuedAlertExist(identifier _: Alert.Identifier, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false))
    }

    func lookupAllUnretracted(managerIdentifier _: String, completion: @escaping (Result<[PersistedAlert], Error>) -> Void) {
        completion(.success([]))
    }

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion: @escaping (Result<[PersistedAlert], Error>) -> Void
    ) {
        completion(.success([]))
    }

    func recordRetractedAlert(_ _: Alert, at _: Date) {}
}

// MARK: - G7 Trend Conversion

extension BloodGlucose.Direction {
    init(trendType: LoopKit.GlucoseTrend) {
        switch trendType {
        case .upUpUp:
            self = .doubleUp // Быстро вверх (⬆⬆⬆)
        case .upUp:
            self = .singleUp // Прямо вверх (⬆⬆)
        case .up:
            self = .fortyFiveUp // Под углом вверх (↗) - ЭТО БЫЛО НЕПРАВИЛЬНО!
        case .flat:
            self = .flat // Плоско (→)
        case .down:
            self = .fortyFiveDown // Под углом вниз (↘)
        case .downDown:
            self = .singleDown // Прямо вниз (⬇⬇)
        case .downDownDown:
            self = .doubleDown // Быстро вниз (⬇⬇⬇)
        }
    }
}
