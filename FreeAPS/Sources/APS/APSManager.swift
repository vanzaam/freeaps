import Combine
import Foundation
import LoopKit
import LoopKitUI
import SwiftDate
import Swinject

protocol APSManager {
    func heartbeat(date: Date)
    func autotune() -> AnyPublisher<Autotune?, Never>
    func enactBolus(amount: Double, isSMB: Bool)
    var pumpManager: PumpManagerUI? { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    var pumpName: CurrentValueSubject<String, Never> { get }
    var isLooping: CurrentValueSubject<Bool, Never> { get }
    var lastLoopDate: Date { get }
    var lastLoopDateSubject: PassthroughSubject<Date, Never> { get }
    var bolusProgress: CurrentValueSubject<Decimal?, Never> { get }
    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }
    func enactTempBasal(rate: Double, duration: TimeInterval)
    func makeProfiles() -> AnyPublisher<Bool, Never>
    func determineBasal() -> AnyPublisher<Bool, Never>
    func determineBasalSync()
    func roundBolus(amount: Decimal) -> Decimal
    var lastError: CurrentValueSubject<Error?, Never> { get }
    func cancelBolus()
    func enactAnnouncement(_ announcement: Announcement)
}

enum APSError: LocalizedError {
    case pumpError(Error)
    case invalidPumpState(message: String)
    case glucoseError(message: String)
    case apsError(message: String)
    case deviceSyncError(message: String)

    var errorDescription: String? {
        switch self {
        case let .pumpError(error):
            return "Pump error: \(error.localizedDescription)"
        case let .invalidPumpState(message):
            return "Error: Invalid Pump State: \(message)"
        case let .glucoseError(message):
            return "Error: Invalid glucose: \(message)"
        case let .apsError(message):
            return "APS error: \(message)"
        case let .deviceSyncError(message):
            return "Sync error: \(message)"
        }
    }
}

final class BaseAPSManager: APSManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseAPSManager.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var announcementsStorage: AnnouncementsStorage!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var nightscout: NightscoutManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var smbAdapter: SMBAdapter!
    @Injected() private var loopEngine: LoopEngineAdapterProtocol!
    @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date()
    @Persisted(key: "lastLoopDate") var lastLoopDate: Date = .distantPast {
        didSet {
            lastLoopDateSubject.send(lastLoopDate)
        }
    }

    private var openAPS: OpenAPS!

    private var lifetime = Lifetime()

    var pumpManager: PumpManagerUI? {
        get { deviceDataManager.pumpManager }
        set { deviceDataManager.pumpManager = newValue }
    }

    let isLooping = CurrentValueSubject<Bool, Never>(false)
    let lastLoopDateSubject = PassthroughSubject<Date, Never>()
    let lastError = CurrentValueSubject<Error?, Never>(nil)

    let bolusProgress = CurrentValueSubject<Decimal?, Never>(nil)

    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> {
        deviceDataManager.pumpDisplayState
    }

    var pumpName: CurrentValueSubject<String, Never> {
        deviceDataManager.pumpName
    }

    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> {
        deviceDataManager.pumpExpiresAtDate
    }

    var settings: FreeAPSSettings {
        get { settingsManager.settings }
        set { settingsManager.settings = newValue }
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        openAPS = OpenAPS(storage: storage)
        subscribe()
        lastLoopDateSubject.send(lastLoopDate)

        isLooping
            .weakAssign(to: \.deviceDataManager.loopInProgress, on: self)
            .store(in: &lifetime)
    }

    private func subscribe() {
        deviceDataManager.recommendsLoop
            .receive(on: processQueue)
            .sink { [weak self] in
                self?.loop()
            }
            .store(in: &lifetime)
        pumpManager?.addStatusObserver(self, queue: processQueue)

        deviceDataManager.errorSubject
            .receive(on: processQueue)
            .map { APSError.pumpError($0) }
            .sink {
                self.processError($0)
            }
            .store(in: &lifetime)

        deviceDataManager.bolusTrigger
            .receive(on: processQueue)
            .sink { bolusing in
                if bolusing {
                    self.createBolusReporter()
                } else {
                    self.clearBolusReporter()
                }
            }
            .store(in: &lifetime)
    }

    func heartbeat(date: Date) {
        deviceDataManager.heartbeat(date: date)
    }

    // Loop entry point
    private func loop() {
        guard !isLooping.value else {
            warning(.apsManager, "Already looping, skip")
            return
        }

        debug(.apsManager, "Starting loop")
        isLooping.send(true)
        determineBasal()
            .replaceEmpty(with: false)
            .flatMap { [weak self] success -> AnyPublisher<Void, Error> in
                guard let self = self, success else {
                    return Fail(error: APSError.apsError(message: "Determine basal failed")).eraseToAnyPublisher()
                }

                // Open loop completed
                guard self.settings.closedLoop else {
                    return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
                }

                self.nightscout.uploadStatus()

                // Closed loop - enact suggested
                return self.enactSuggested()
            }
            .sink { [weak self] completion in
                guard let self = self else { return }
                if case let .failure(error) = completion {
                    self.loopCompleted(error: error)
                } else {
                    self.loopCompleted()
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    // Loop exit point
    private func loopCompleted(error: Error? = nil) {
        isLooping.send(false)

        if let error = error {
            warning(.apsManager, "Loop failed with error: \(error.localizedDescription)")
            processError(error)
        } else {
            debug(.apsManager, "Loop succeeded")
            lastLoopDate = Date()
            lastError.send(nil)
        }

        if settings.closedLoop {
            reportEnacted(received: error == nil)
        }
    }

    private func verifyStatus() -> Error? {
        guard let pump = pumpManager else {
            return APSError.invalidPumpState(message: "Pump not set")
        }
        let status = pump.status.pumpStatus

        guard !status.bolusing else {
            return APSError.invalidPumpState(message: "Pump is bolusing")
        }

        guard !status.suspended else {
            return APSError.invalidPumpState(message: "Pump suspended")
        }

        let reservoir = storage.retrieve(OpenAPS.Monitor.reservoir, as: Decimal.self) ?? 100
        guard reservoir > 0 else {
            return APSError.invalidPumpState(message: "Reservoir is empty")
        }

        return nil
    }

    // Removed autosens/UAM for Loop engine. Keep no-op for compatibility.
    private func autosens() -> AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    func determineBasal() -> AnyPublisher<Bool, Never> {
        debug(.apsManager, "Start determine basal")
        guard let glucose = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self), glucose.isNotEmpty else {
            debug(.apsManager, "Not enough glucose data")
            processError(APSError.glucoseError(message: "Not enough glucose data"))
            return Just(false).eraseToAnyPublisher()
        }

        let lastGlucoseDate = glucoseStorage.lastGlucoseDate()
        guard lastGlucoseDate >= Date().addingTimeInterval(-12.minutes.timeInterval) else {
            debug(.apsManager, "Glucose data is stale")
            processError(APSError.glucoseError(message: "Glucose data is stale"))
            return Just(false).eraseToAnyPublisher()
        }

        guard glucoseStorage.isGlucoseNotFlat() else {
            debug(.apsManager, "Glucose data is too flat")
            processError(APSError.glucoseError(message: "Glucose data is too flat"))
            return Just(false).eraseToAnyPublisher()
        }

        let now = Date()
        let temp = currentTemp(date: now)

        let baseSuggestionPublisher: AnyPublisher<Suggestion?, Never>
        if AppRuntimeConfig.useLoopEngine {
            // Short-circuit all JS paths to avoid Script bundle loading
            debug(
                .apsManager,
                "🔄 Using LoopEngineAdapter (JS disabled) - AppRuntimeConfig.useLoopEngine=\(AppRuntimeConfig.useLoopEngine)"
            )
            baseSuggestionPublisher = loopEngine
                .determineBasal(currentTemp: temp, clock: now)
                .eraseToAnyPublisher()
        } else {
            debug(.apsManager, "🔄 Using JavaScript OpenAPS - AppRuntimeConfig.useLoopEngine=\(AppRuntimeConfig.useLoopEngine)")
            baseSuggestionPublisher = makeProfiles()
                .flatMap { _ in self.autosens() }
                .flatMap { _ in self.dailyAutotune() }
                .flatMap { _ -> AnyPublisher<Suggestion?, Never> in
                    self.openAPS.determineBasal(currentTemp: temp, clock: now).eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()
        }

        let mainPublisher: AnyPublisher<Bool, Never> = baseSuggestionPublisher
            .flatMap { suggestion -> AnyPublisher<Suggestion?, Never> in
                guard let suggestion = suggestion else {
                    return Just(nil).eraseToAnyPublisher()
                }
                // Интеграция SMB адаптера
                return self.enhanceSuggestionWithSMB(suggestion: suggestion, at: now)
            }
            .map { suggestion -> Bool in
                if let suggestion = suggestion {
                    // Build and persist OpenAPS-style suggested.json based on Loop output
                    let toSave = self.augmentSuggestionForStorage(suggestion)
                    self.storage.save(toSave, as: OpenAPS.Enact.suggested)

                    // mark loop finished successfully before notifying observers
                    self.isLooping.send(false)
                    self.lastLoopDate = Date()
                    DispatchQueue.main.async {
                        self.broadcaster.notify(SuggestionObserver.self, on: .main) {
                            $0.suggestionDidUpdate(toSave)
                        }
                    }
                }
                return suggestion != nil
            }
            .eraseToAnyPublisher()

        if temp.duration == 0,
           settings.closedLoop,
           settingsManager.preferences.unsuspendIfNoTemp,
           let pump = pumpManager,
           pump.status.pumpStatus.suspended
        {
            return pump.resumeDelivery()
                .flatMap { _ in mainPublisher }
                .replaceError(with: false)
                .eraseToAnyPublisher()
        }

        return mainPublisher
    }

    func determineBasalSync() {
        determineBasal().cancellable().store(in: &lifetime)
    }

    func makeProfiles() -> AnyPublisher<Bool, Never> {
        openAPS.makeProfiles(useAutotune: settings.useAutotune)
            .map { tunedProfile in
                if let basalProfile = tunedProfile?.basalProfile {
                    self.processQueue.async {
                        self.broadcaster.notify(BasalProfileObserver.self, on: self.processQueue) {
                            $0.basalProfileDidChange(basalProfile)
                        }
                    }
                }

                return tunedProfile != nil
            }
            .eraseToAnyPublisher()
    }

    func roundBolus(amount: Decimal) -> Decimal {
        guard let pump = pumpManager else { return amount }
        let rounded = Decimal(pump.roundToSupportedBolusVolume(units: Double(amount)))
        let maxBolus = Decimal(pump.roundToSupportedBolusVolume(units: Double(settingsManager.pumpSettings.maxBolus)))
        return min(rounded, maxBolus)
    }

    /// Улучшить предложение OpenAPS с помощью SMB адаптера
    private func enhanceSuggestionWithSMB(suggestion: Suggestion, at date: Date) -> AnyPublisher<Suggestion?, Never> {
        Future { promise in
            Task {
                let smbDose = await self.smbAdapter.calculateSMB()
                let isSafe = await self.smbAdapter.isSMBSafe()

                // Если SMB безопасен и есть доза для введения
                if isSafe, smbDose > 0.01 {
                    let roundedSMB = self.roundBolus(amount: smbDose)

                    if roundedSMB > 0.01 {
                        // Создать новое предложение с SMB
                        let enhancedSuggestion = Suggestion(
                            reason: (suggestion.reason ?? "") + " + SMB \(roundedSMB)U for carbs",
                            units: roundedSMB,
                            insulinReq: suggestion.insulinReq,
                            eventualBG: suggestion.eventualBG,
                            sensitivityRatio: suggestion.sensitivityRatio,
                            rate: suggestion.rate,
                            duration: suggestion.duration,
                            iob: suggestion.iob,
                            cob: suggestion.cob,
                            predictions: suggestion.predictions,
                            deliverAt: date,
                            carbsReq: suggestion.carbsReq,
                            temp: suggestion.temp,
                            bg: suggestion.bg,
                            reservoir: suggestion.reservoir,
                            timestamp: suggestion.timestamp,
                            recieved: suggestion.recieved
                        )

                        info(.apsManager, "SMB enhanced suggestion: \(roundedSMB)U")

                        // Отправить уведомление об SMB
                        self.nightscout.uploadStatus()

                        promise(.success(enhancedSuggestion))
                        return
                    }
                } else {
                    debug(.apsManager, "SMB not recommended: safe=\(isSafe), dose=\(smbDose)")
                }

                // Вернуть оригинальное предложение если SMB не нужен
                promise(.success(suggestion))
            }
        }
        .eraseToAnyPublisher()
    }

    private var bolusReporter: DoseProgressReporter?

    func enactBolus(amount: Double, isSMB: Bool) {
        if let error = verifyStatus() {
            processError(error)
            processQueue.async {
                self.broadcaster.notify(BolusFailureObserver.self, on: self.processQueue) {
                    $0.bolusDidFail()
                }
            }
            return
        }

        guard let pump = pumpManager else { return }

        let roundedAmout = pump.roundToSupportedBolusVolume(units: amount)
        guard roundedAmout > 0 else {
            warning(.apsManager, "Skip bolus: rounded amount is 0")
            return
        }

        debug(.apsManager, "Enact bolus \(roundedAmout), manual \(!isSMB)")

        // Auto-adjust bolus increment preference to pump capability on first success
        adjustBolusIncrementIfNeeded(pump: pump, roundedUnits: roundedAmout)

        pump.enactBolus(units: roundedAmout, activationType: isSMB ? .automatic : .manualNoRecommendation).sink { completion in
            if case let .failure(error) = completion {
                warning(.apsManager, "Bolus failed with error: \(error.localizedDescription)")
                self.processError(APSError.pumpError(error))
                if !isSMB {
                    self.processQueue.async {
                        self.broadcaster.notify(BolusFailureObserver.self, on: self.processQueue) {
                            $0.bolusDidFail()
                        }
                    }
                }
            } else {
                debug(.apsManager, "Bolus succeeded")
                if !isSMB {
                    self.determineBasal().sink { _ in }.store(in: &self.lifetime)
                }
                self.bolusProgress.send(0)
            }
        } receiveValue: { _ in }
            .store(in: &lifetime)
    }

    func cancelBolus() {
        guard let pump = pumpManager, pump.status.pumpStatus.bolusing else { return }
        debug(.apsManager, "Cancel bolus")
        pump.cancelBolus().sink { completion in
            if case let .failure(error) = completion {
                debug(.apsManager, "Bolus cancellation failed with error: \(error.localizedDescription)")
                self.processError(APSError.pumpError(error))
            } else {
                debug(.apsManager, "Bolus cancelled")
            }

            self.bolusReporter?.removeObserver(self)
            self.bolusReporter = nil
            self.bolusProgress.send(nil)
        } receiveValue: { _ in }
            .store(in: &lifetime)
    }

    func enactTempBasal(rate: Double, duration: TimeInterval) {
        if let error = verifyStatus() {
            processError(error)
            return
        }

        guard let pump = pumpManager else { return }
        debug(.apsManager, "Enact temp basal \(rate) - \(duration)")

        // Clamp by app-level maxBasal and round to pump-supported rate
        let appMaxBasal = Double(settingsManager.pumpSettings.maxBasal)
        let clampedRate = min(rate, appMaxBasal)
        let roundedAmout = pump.roundToSupportedBasalRate(unitsPerHour: clampedRate)
        pump.enactTempBasal(unitsPerHour: roundedAmout, for: duration) { error in
            if let error = error {
                debug(.apsManager, "Temp Basal failed with error: \(error.localizedDescription)")
                self.processError(APSError.pumpError(error))
            } else {
                debug(.apsManager, "Temp Basal succeeded")
                let temp = TempBasal(duration: Int(duration / 60), rate: Decimal(rate), temp: .absolute, timestamp: Date())
                self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
                if rate == 0, duration == 0 {
                    self.pumpHistoryStorage.saveCancelTempEvents()
                }
            }
        }
    }

    // Removed autotune for Loop engine. Keep no-op to preserve call sites.
    func dailyAutotune() -> AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }

    func autotune() -> AnyPublisher<Autotune?, Never> { Just(nil).eraseToAnyPublisher() }

    func enactAnnouncement(_ announcement: Announcement) {
        guard let action = announcement.action else {
            warning(.apsManager, "Invalid Announcement action")
            return
        }

        guard let pump = pumpManager else {
            warning(.apsManager, "Pump is not set")
            return
        }

        debug(.apsManager, "Start enact announcement: \(action)")

        switch action {
        case let .bolus(amount):
            if let error = verifyStatus() {
                processError(error)
                return
            }
            let roundedAmount = pump.roundToSupportedBolusVolume(units: Double(amount))
            guard roundedAmount > 0 else {
                warning(.apsManager, "Skip announcement bolus: rounded amount is 0")
                return
            }
            adjustBolusIncrementIfNeeded(pump: pump, roundedUnits: roundedAmount)
            pump.enactBolus(units: roundedAmount, activationType: .manualNoRecommendation) { error in
                if let error = error {
                    warning(.apsManager, "Announcement Bolus failed with error: \(error.localizedDescription)")
                } else {
                    debug(.apsManager, "Announcement Bolus succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    self.bolusProgress.send(0)
                }
            }
        case let .pump(pumpAction):
            switch pumpAction {
            case .suspend:
                if let error = verifyStatus() {
                    processError(error)
                    return
                }
                pump.suspendDelivery { error in
                    if let error = error {
                        debug(.apsManager, "Pump not suspended by Announcement: \(error.localizedDescription)")
                    } else {
                        debug(.apsManager, "Pump suspended by Announcement")
                        self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                        self.nightscout.uploadStatus()
                    }
                }
            case .resume:
                guard pump.status.pumpStatus.suspended else {
                    return
                }
                pump.resumeDelivery { error in
                    if let error = error {
                        warning(.apsManager, "Pump not resumed by Announcement: \(error.localizedDescription)")
                    } else {
                        debug(.apsManager, "Pump resumed by Announcement")
                        self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                        self.nightscout.uploadStatus()
                    }
                }
            }
        case let .looping(closedLoop):
            settings.closedLoop = closedLoop
            debug(.apsManager, "Closed loop \(closedLoop) by Announcement")
            announcementsStorage.storeAnnouncements([announcement], enacted: true)
        case let .tempbasal(rate, duration):
            if let error = verifyStatus() {
                processError(error)
                return
            }
            guard !settings.closedLoop else {
                return
            }
            // Clamp announcement rate by app-level maxBasal
            let appMaxBasal = Double(settingsManager.pumpSettings.maxBasal)
            let clampedRate = min(Double(truncating: rate as NSNumber), appMaxBasal)
            let roundedRate = pump.roundToSupportedBasalRate(unitsPerHour: clampedRate)
            pump.enactTempBasal(unitsPerHour: roundedRate, for: TimeInterval(duration) * 60) { error in
                if let error = error {
                    warning(.apsManager, "Announcement TempBasal failed with error: \(error.localizedDescription)")
                } else {
                    debug(.apsManager, "Announcement TempBasal succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                }
            }
        }
    }

    private func currentTemp(date: Date) -> TempBasal {
        let defaultTemp = { () -> TempBasal in
            guard let temp = storage.retrieve(OpenAPS.Monitor.tempBasal, as: TempBasal.self) else {
                return TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
            }
            let delta = Int((date.timeIntervalSince1970 - temp.timestamp.timeIntervalSince1970) / 60)
            let duration = max(0, temp.duration - delta)
            return TempBasal(duration: duration, rate: temp.rate, temp: .absolute, timestamp: date)
        }()

        guard let state = pumpManager?.status.basalDeliveryState else { return defaultTemp }
        switch state {
        case .active:
            return TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: date)
        case let .tempBasal(dose):
            let rate = Decimal(dose.unitsPerHour)
            let durationMin = max(0, Int((dose.endDate.timeIntervalSince1970 - date.timeIntervalSince1970) / 60))
            return TempBasal(duration: durationMin, rate: rate, temp: .absolute, timestamp: date)
        default:
            return defaultTemp
        }
    }

    private func enactSuggested() -> AnyPublisher<Void, Error> {
        guard let suggested = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self) else {
            return Fail(error: APSError.apsError(message: "Suggestion not found")).eraseToAnyPublisher()
        }

        guard Date().timeIntervalSince(suggested.deliverAt ?? .distantPast) < Config.eхpirationInterval else {
            return Fail(error: APSError.apsError(message: "Suggestion expired")).eraseToAnyPublisher()
        }

        guard let pump = pumpManager else {
            return Fail(error: APSError.apsError(message: "Pump not set")).eraseToAnyPublisher()
        }

        let basalPublisher: AnyPublisher<Void, Error> = Deferred { () -> AnyPublisher<Void, Error> in
            if let error = self.verifyStatus() {
                return Fail(error: error).eraseToAnyPublisher()
            }

            guard let rate = suggested.rate, let duration = suggested.duration else {
                // No temp recommended by algorithm → enforce neutral temp basal to refresh VBS
                let now = Date()
                let neutralRate = self.currentProfileBasalRate(at: now)
                let appMaxBasal = Double(self.settingsManager.pumpSettings.maxBasal)
                let clampedRate = min(neutralRate, appMaxBasal)
                let roundedRate = pump.roundToSupportedBasalRate(unitsPerHour: clampedRate)
                let neutralDuration: TimeInterval = 30 * 60
                debug(.apsManager, "Enact neutral temp basal \(roundedRate) U/h for 30 min")
                return pump.enactTempBasal(unitsPerHour: roundedRate, for: neutralDuration)
                    .map { _ in
                        let temp = TempBasal(
                            duration: Int(neutralDuration / 60),
                            rate: Decimal(roundedRate),
                            temp: .absolute,
                            timestamp: Date()
                        )
                        self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)

                        // Ensure suggested contains neutral temp for Nightscout openaps.js (rate/duration expected)
                        if var suggestedStored = self.storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self) {
                            let updated = Suggestion(
                                reason: suggestedStored.reason,
                                units: suggestedStored.units,
                                insulinReq: suggestedStored.insulinReq,
                                eventualBG: suggestedStored.eventualBG,
                                sensitivityRatio: suggestedStored.sensitivityRatio,
                                rate: Decimal(roundedRate),
                                duration: Int(neutralDuration / 60),
                                iob: suggestedStored.iob,
                                cob: suggestedStored.cob,
                                predictions: suggestedStored.predictions,
                                deliverAt: suggestedStored.deliverAt ?? Date(),
                                carbsReq: suggestedStored.carbsReq,
                                temp: .absolute,
                                bg: suggestedStored.bg,
                                reservoir: suggestedStored.reservoir,
                                timestamp: suggestedStored.timestamp ?? Date(),
                                recieved: suggestedStored.recieved
                            )
                            self.storage.save(updated, as: OpenAPS.Enact.suggested)
                        }
                        return ()
                    }
                    .eraseToAnyPublisher()
            }
            // Clamp by app-level maxBasal and round to pump-supported rate
            let appMaxBasal = Double(self.settingsManager.pumpSettings.maxBasal)
            let clampedRate = min(Double(truncating: rate as NSNumber), appMaxBasal)
            let roundedRate = pump.roundToSupportedBasalRate(unitsPerHour: clampedRate)
            return pump.enactTempBasal(unitsPerHour: roundedRate, for: TimeInterval(duration * 60))
                .map { _ in
                    let temp = TempBasal(duration: duration, rate: rate, temp: .absolute, timestamp: Date())
                    self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
                    return ()
                }
                .eraseToAnyPublisher()
        }.eraseToAnyPublisher()

        let bolusPublisher: AnyPublisher<Void, Error> = Deferred { () -> AnyPublisher<Void, Error> in
            if let error = self.verifyStatus() {
                return Fail(error: error).eraseToAnyPublisher()
            }
            // SAFETY: For Loop engine path, never enact auto-bolus here. SMBAdapter will decide boluses separately.
            guard let units = suggested.units, units > 0, !AppRuntimeConfig.useLoopEngine else {
                // It is OK, no bolus required
                debug(.apsManager, "No bolus required")
                return Just(()).setFailureType(to: Error.self)
                    .eraseToAnyPublisher()
            }
            let rounded = pump.roundToSupportedBolusVolume(units: Double(units))
            guard rounded > 0 else {
                debug(.apsManager, "Rounded suggested bolus to 0; skipping")
                return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
            self.adjustBolusIncrementIfNeeded(pump: pump, roundedUnits: rounded)
            return pump.enactBolus(units: rounded, activationType: .automatic)
                .map { _ in
                    self.bolusProgress.send(0)
                    return ()
                }
                .eraseToAnyPublisher()
        }.eraseToAnyPublisher()

        return basalPublisher.flatMap { bolusPublisher }.eraseToAnyPublisher()
    }

    // MARK: - Bolus Increment Auto-Adjust

    private func adjustBolusIncrementIfNeeded(pump: PumpManagerUI, roundedUnits _: Double) {
        // Determine pump step by probing rounding of a small delta around 0.05 and 0.1
        // Fallback to 0.05 as default desired step
        let desiredDefaultStep: Decimal = 0.05
        var currentPrefs = settingsManager.preferences
        let currentStep = currentPrefs.bolusIncrement

        // Detect pump step from rounding behaviour
        // Try to see what pump rounds 0.05 to
        let probeSmall = pump.roundToSupportedBolusVolume(units: 0.05)
        let probeLarge = pump.roundToSupportedBolusVolume(units: 0.1)
        let detectedStep: Decimal = probeSmall > 0 ? 0.05 :
            (probeLarge > 0 ? 0.1 : Decimal(probeSmall > 0 ? probeSmall : probeLarge))

        // If no change needed, return
        guard detectedStep > 0, detectedStep != currentStep else { return }

        // Update preferences
        settingsManager.updatePreferences { prefs in
            prefs.bolusIncrement = detectedStep
        }
        debug(.apsManager, "Bolus increment adjusted to \(detectedStep) based on pump capability")
    }

    private func reportEnacted(received: Bool) {
        if let suggestion = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self), suggestion.deliverAt != nil {
            var enacted = augmentSuggestionForStorage(suggestion)
            enacted.timestamp = Date()
            enacted.recieved = received
            storage.save(enacted, as: OpenAPS.Enact.enacted)
            debug(.apsManager, "Suggestion enacted. Received: \(received)")
            DispatchQueue.main.async {
                self.broadcaster.notify(EnactedSuggestionObserver.self, on: .main) {
                    $0.enactedSuggestionDidUpdate(enacted)
                }
            }
            nightscout.uploadStatus()
        }
    }

    private func processError(_ error: Error) {
        warning(.apsManager, "\(error.localizedDescription)")
        lastError.send(error)
    }

    private func createBolusReporter() {
        bolusReporter = pumpManager?.createBolusProgressReporter(reportingOn: processQueue)
        bolusReporter?.addObserver(self)
    }

    private func clearBolusReporter() {
        bolusReporter?.removeObserver(self)
        bolusReporter = nil
        processQueue.asyncAfter(deadline: .now() + 1) {
            self.bolusProgress.send(nil)
        }
    }
}

// MARK: - Suggestion augmentation

private extension BaseAPSManager {
    func currentProfileBasalRate(at date: Date) -> Double {
        // Load basal profile and compute active rate at time-of-day
        let profile: [BasalProfileEntry] = storage
            .retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
            ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]

        let seconds = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutesSinceMidnight = (seconds.hour ?? 0) * 60 + (seconds.minute ?? 0)

        // Find last entry whose start <= now, fallback to first
        let active = profile
            .sorted { $0.minutes < $1.minutes }
            .last { $0.minutes <= minutesSinceMidnight } ?? profile.sorted { $0.minutes < $1.minutes }.first!

        return Double(truncating: active.rate as NSNumber)
    }

    func augmentSuggestionForStorage(_ s: Suggestion) -> Suggestion {
        // Fill in BG and reservoir if missing to match OpenAPS schema
        var bg = s.bg
        if bg == nil, let last = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self)?.last?.glucose {
            bg = Decimal(last)
        }

        var reservoir = s.reservoir
        if reservoir == nil, let raw = storage.retrieveRaw(OpenAPS.Monitor.reservoir) {
            reservoir = Decimal(from: raw)
        }

        var stamped = s
        stamped.timestamp = s.timestamp ?? Date()
        return Suggestion(
            reason: stamped.reason,
            units: stamped.units,
            insulinReq: stamped.insulinReq,
            eventualBG: stamped.eventualBG,
            sensitivityRatio: stamped.sensitivityRatio,
            rate: stamped.rate,
            duration: stamped.duration,
            iob: stamped.iob,
            cob: stamped.cob,
            predictions: stamped.predictions,
            deliverAt: stamped.deliverAt ?? Date(),
            carbsReq: stamped.carbsReq,
            temp: stamped.temp,
            bg: bg,
            reservoir: reservoir,
            timestamp: stamped.timestamp,
            recieved: stamped.recieved
        )
    }
}

private extension PumpManager {
    func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval) -> AnyPublisher<Void, Error> {
        Future { promise in
            self.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) { error in
                if let error = error {
                    debug(.apsManager, "Temp basal failed: \(unitsPerHour) for: \(duration)")
                    promise(.failure(error))
                } else {
                    debug(.apsManager, "Temp basal succeeded: \(unitsPerHour) for: \(duration)")
                    promise(.success(()))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }

    func enactBolus(units: Double, activationType: BolusActivationType) -> AnyPublisher<Void, Error> {
        Future { promise in
            self.enactBolus(units: units, activationType: activationType) { error in
                if let error = error {
                    debug(.apsManager, "Bolus failed: \(units)")
                    promise(.failure(error))
                } else {
                    debug(.apsManager, "Bolus succeeded: \(units)")
                    promise(.success(()))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }

    func cancelBolus() -> AnyPublisher<DoseEntry?, Error> {
        Future { promise in
            self.cancelBolus { result in
                switch result {
                case let .success(dose):
                    debug(.apsManager, "Cancel Bolus succeded")
                    promise(.success(dose))
                case let .failure(error):
                    debug(.apsManager, "Cancel Bolus failed")
                    promise(.failure(error))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }

    func suspendDelivery() -> AnyPublisher<Void, Error> {
        Future { promise in
            self.suspendDelivery { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }

    func resumeDelivery() -> AnyPublisher<Void, Error> {
        Future { promise in
            self.resumeDelivery { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }
}

extension BaseAPSManager: PumpManagerStatusObserver {
    func pumpManager(_: PumpManager, didUpdate status: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        let percent = Int((status.pumpBatteryChargeRemaining ?? 1) * 100)
        let battery = Battery(
            percent: percent,
            voltage: nil,
            string: percent > 10 ? .normal : .low,
            display: status.pumpBatteryChargeRemaining != nil
        )
        storage.save(battery, as: OpenAPS.Monitor.battery)
        storage.save(status.pumpStatus, as: OpenAPS.Monitor.status)
        if let insulinType = status.insulinType {
            storage.save(insulinType.rawValue, as: OpenAPS.Settings.insulinType)
        }
    }
}

extension BaseAPSManager: DoseProgressObserver {
    func doseProgressReporterDidUpdate(_ doseProgressReporter: DoseProgressReporter) {
        bolusProgress.send(Decimal(doseProgressReporter.progress.percentComplete))
        if doseProgressReporter.progress.isComplete {
            clearBolusReporter()
        }
    }
}

extension PumpManagerStatus {
    var pumpStatus: PumpStatus {
        let bolusing = bolusState != .noBolus
        let suspended = basalDeliveryState?.isSuspended ?? true
        let type = suspended ? StatusType.suspended : (bolusing ? .bolusing : .normal)
        return PumpStatus(status: type, bolusing: bolusing, suspended: suspended, timestamp: Date())
    }
}
