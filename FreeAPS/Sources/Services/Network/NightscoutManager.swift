import Combine
import Foundation
import LoopKit
import Swinject
import UIKit

protocol NightscoutManager: GlucoseSource {
    func fetchGlucose(since date: Date) -> AnyPublisher<[BloodGlucose], Never>
    func fetchCarbs() -> AnyPublisher<[CarbsEntry], Never>
    func fetchTempTargets() -> AnyPublisher<[TempTarget], Never>
    func fetchAnnouncements() -> AnyPublisher<[Announcement], Never>
    func deleteCarbs(at date: Date)
    func uploadStatus()
    func uploadGlucose()
    func uploadProfile()
    func uploadManualGlucose(entry: BloodGlucose, note: String)
    var cgmURL: URL? { get }
}

final class BaseNightscoutManager: NightscoutManager, Injectable {
    @Injected() private var keychain: Keychain!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var announcementsStorage: AnnouncementsStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var reachabilityManager: ReachabilityManager!

    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")
    private var ping: TimeInterval?

    private var lifetime = Lifetime()

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
    }

    private var isUploadEnabled: Bool {
        settingsManager.settings.isUploadEnabled
    }

    private var isUploadGlucoseEnabled: Bool {
        settingsManager.settings.uploadGlucose
    }

    private var nightscoutAPI: NightscoutAPI? {
        guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              let url = URL(string: urlString),
              let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        else {
            return nil
        }
        return NightscoutAPI(url: url, secret: secret)
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        broadcaster.register(PumpHistoryObserver.self, observer: self)
        broadcaster.register(CarbsObserver.self, observer: self)
        broadcaster.register(TempTargetsObserver.self, observer: self)
        _ = reachabilityManager.startListening(onQueue: processQueue) { status in
            debug(.nightscout, "Network status: \(status)")
        }
    }

    func sourceInfo() -> [String: Any]? {
        if let ping = ping {
            return [GlucoseSourceKey.nightscoutPing.rawValue: ping]
        }
        return nil
    }

    var cgmURL: URL? {
        if let url = settingsManager.settings.cgm.appURL {
            return url
        }

        let useLocal = settingsManager.settings.useLocalGlucoseSource

        let maybeNightscout = useLocal
            ? NightscoutAPI(url: URL(string: "http://127.0.0.1:\(settingsManager.settings.localGlucosePort)")!)
            : nightscoutAPI

        return maybeNightscout?.url
    }

    func fetchGlucose(since date: Date) -> AnyPublisher<[BloodGlucose], Never> {
        let useLocal = settingsManager.settings.useLocalGlucoseSource
        ping = nil

        if !useLocal {
            guard isNetworkReachable else {
                return Just([]).eraseToAnyPublisher()
            }
        }

        let maybeNightscout = useLocal
            ? NightscoutAPI(url: URL(string: "http://127.0.0.1:\(settingsManager.settings.localGlucosePort)")!)
            : nightscoutAPI

        guard let nightscout = maybeNightscout else {
            return Just([]).eraseToAnyPublisher()
        }

        let startDate = Date()

        return nightscout.fetchLastGlucose(sinceDate: date)
            .tryCatch({ (error) -> AnyPublisher<[BloodGlucose], Error> in
                print(error.localizedDescription)
                return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
            })
            .replaceError(with: [])
            .handleEvents(receiveOutput: { value in
                guard value.isNotEmpty else { return }
                self.ping = Date().timeIntervalSince(startDate)
            })
            .eraseToAnyPublisher()
    }

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        fetchGlucose(since: glucoseStorage.syncDate())
    }

    func fetchCarbs() -> AnyPublisher<[CarbsEntry], Never> {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return Just([]).eraseToAnyPublisher()
        }

        let since = carbsStorage.syncDate()
        return nightscout.fetchCarbs(sinceDate: since)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func fetchTempTargets() -> AnyPublisher<[TempTarget], Never> {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return Just([]).eraseToAnyPublisher()
        }

        let since = tempTargetsStorage.syncDate()
        return nightscout.fetchTempTargets(sinceDate: since)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func fetchAnnouncements() -> AnyPublisher<[Announcement], Never> {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return Just([]).eraseToAnyPublisher()
        }

        let since = announcementsStorage.syncDate()
        return nightscout.fetchAnnouncement(sinceDate: since)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func deleteCarbs(at date: Date) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            carbsStorage.deleteCarbs(at: date)
            return
        }

        nightscout.deleteCarbs(at: date)
            .sink { completion in
                switch completion {
                case .finished:
                    self.carbsStorage.deleteCarbs(at: date)
                    debug(.nightscout, "Carbs deleted")
                case let .failure(error):
                    debug(.nightscout, error.localizedDescription)
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    func uploadStatus() {
        // Рассчитываем свежий IOB вместо чтения старого файла
        let freshIOBValue = calculateFreshIOB()
        let now = Date()
        let iob: [IOBEntry]? = freshIOBValue > 0 ? [IOBEntry(
            iob: freshIOBValue,
            activity: 0, // Упрощенная версия для Nightscout
            basaliob: 0,
            bolusiob: freshIOBValue,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            iobWithZeroTemp: IOBEntry.WithZeroTemp(
                iob: freshIOBValue,
                activity: 0,
                basaliob: 0,
                bolusiob: freshIOBValue,
                netbasalinsulin: 0,
                bolusinsulin: 0,
                time: now
            ),
            lastBolusTime: nil,
            lastTemp: nil,
            time: now
        )] : nil

        var suggested = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        var enacted = storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)

        // Freshen timestamps for Nightscout OpenAPS plugin (avoid stale data classification)
        var latestIOB = iob?.first
        if let current = latestIOB {
            let now = Date()
            let refreshedLastTemp: IOBEntry.LastTemp? = {
                if let lt = current.lastTemp {
                    return IOBEntry.LastTemp(
                        rate: lt.rate,
                        timestamp: now,
                        started_at: lt.started_at,
                        date: lt.date,
                        duration: lt.duration
                    )
                }
                return nil
            }()
            latestIOB = IOBEntry(
                iob: current.iob,
                activity: current.activity,
                basaliob: current.basaliob,
                bolusiob: current.bolusiob,
                netbasalinsulin: current.netbasalinsulin,
                bolusinsulin: current.bolusinsulin,
                iobWithZeroTemp: current.iobWithZeroTemp,
                lastBolusTime: current.lastBolusTime,
                lastTemp: refreshedLastTemp,
                time: now
            )
        }

        // OpenAPS plugin compatibility: provide predBGs (IOB) in BOTH suggested and enacted
        if let preds = (suggested?.predictions ?? enacted?.predictions) {
            let fullSeries = preds.iob ?? preds.cob ?? preds.zt ?? preds.uam ?? []
            // Ограничиваем прогноз максимум 6 часами (72 точки по 5 минут) для Nightscout
            let maxForecastPoints = 72 // 6 часов * 12 точек в час
            let iobSeries = Array(fullSeries.prefix(maxForecastPoints))

            if iobSeries.isNotEmpty {
                let normalized = Predictions(iob: iobSeries, zt: nil, cob: nil, uam: nil)
                if var s = suggested { s.predictions = normalized
                    suggested = s }
                if var e = enacted { e.predictions = normalized
                    enacted = e }
                debug(.nightscout, "Glucose prediction for Nightscout limited to \(iobSeries.count) points (max 6 hours)")
            }
        }

        let openapsStatus = OpenAPSStatus(
            name: "openaps",
            iob: latestIOB,
            suggested: suggested,
            enacted: enacted,
            version: "0.7.1"
        )

        let battery = storage.retrieve(OpenAPS.Monitor.battery, as: Battery.self)
        var reservoir = Decimal(from: storage.retrieveRaw(OpenAPS.Monitor.reservoir) ?? "0")
        if reservoir == 0xDEAD_BEEF {
            reservoir = nil
        }
        var pumpStatus = storage.retrieve(OpenAPS.Monitor.status, as: PumpStatus.self)
        pumpStatus?.timestamp = Date()

        let pump = NSPumpStatus(clock: Date(), battery: battery, reservoir: reservoir, status: pumpStatus)

        let preferences = settingsManager.preferences

        let device = UIDevice.current

        let uploader = Uploader(batteryVoltage: nil, battery: Int(device.batteryLevel * 100), type: "PHONE")

        let status = NightscoutStatus(
            device: "openaps://" + device.name,
            openaps: openapsStatus,
            pump: pump,
            preferences: nil,
            uploader: uploader
        )

        storage.save(status, as: OpenAPS.Upload.nsStatus)

        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        processQueue.async {
            nightscout.uploadStatus(status)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Status uploaded")
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    func uploadProfile() {
        // These should be modified anyways and not the defaults
        guard let sensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self),
              let basalProfile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self),
              let carbRatios = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self),
              let targets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
        else {
            NSLog("NightscoutManager uploadProfile Not all settings found to build profile!")
            return
        }

        let sens = sensitivities.sensitivities.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.sensitivity,
                timeAsSeconds: item.offset
            )
        }

        let target_low = targets.targets.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.low,
                timeAsSeconds: item.offset
            )
        }
        let target_high = targets.targets.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.high,
                timeAsSeconds: item.offset
            )
        }
        let cr = carbRatios.schedule.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.ratio,
                timeAsSeconds: item.offset
            )
        }

        let basal = basalProfile.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.rate,
                timeAsSeconds: item.minutes * 60
            )
        }
        var nsUnits = ""
        switch settingsManager.settings.units {
        case .mgdL:
            nsUnits = "mg/dl"
        case .mmolL:
            nsUnits = "mmol"
        }

        var carbs_hr: Decimal = 0
        if let isf = sensitivities.sensitivities.map(\.sensitivity).first,
           let cr = carbRatios.schedule.map(\.ratio).first,
           isf > 0, cr > 0
        {
            // CarbImpact -> Carbs/hr = CI [mg/dl/5min] * 12 / ISF [mg/dl/U] * CR [g/U]
            carbs_hr = settingsManager.preferences.min5mCarbimpact * 12 / isf * cr
            if settingsManager.settings.units == .mmolL {
                carbs_hr = carbs_hr * GlucoseUnits.exchangeRate
            }
            // No, Decimal has no rounding function.
            carbs_hr = Decimal(round(Double(carbs_hr) * 10.0)) / 10
        }
        let ps = ScheduledNightscoutProfile(
            dia: settingsManager.pumpSettings.insulinActionCurve,
            carbs_hr: Int(carbs_hr),
            delay: 0,
            timezone: TimeZone.current.identifier,
            target_low: target_low,
            target_high: target_high,
            sens: sens,
            basal: basal,
            carbratio: cr,
            units: nsUnits
        )
        let defaultProfile = "default"
        let now = Date()
        let p = NightscoutProfileStore(
            defaultProfile: defaultProfile,
            startDate: now,
            mills: Int(now.timeIntervalSince1970) * 1000,
            units: nsUnits,
            enteredBy: NigtscoutTreatment.local,
            store: [defaultProfile: ps]
        )

        if let uploadedProfile = storage.retrieve(OpenAPS.Nightscout.uploadedProfile, as: NightscoutProfileStore.self),
           (uploadedProfile.store[defaultProfile]?.rawJSON ?? "") == ps.rawJSON
        {
            NSLog("NightscoutManager uploadProfile, no profile change")
            return
        }
        guard let nightscout = nightscoutAPI, isNetworkReachable, isUploadEnabled else {
            return
        }
        processQueue.async {
            nightscout.uploadProfile(p)
                .sink { completion in
                    switch completion {
                    case .finished:
                        self.storage.save(p, as: OpenAPS.Nightscout.uploadedProfile)
                        debug(.nightscout, "Profile uploaded")
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    func uploadManualGlucose(entry: BloodGlucose, note: String) {
        // If Nightscout is not configured or upload disabled, just skip quietly
        guard let _ = nightscoutAPI, isUploadEnabled, isUploadGlucoseEnabled else {
            debug(
                .nightscout,
                "uploadManualGlucose: Nightscout not configured or uploads disabled — skipping network upload",
                printToConsole: true
            )
            return
        }

        // 1) Upload glucose entry as normal
        uploadGlucose([entry], fileToSave: OpenAPS.Nightscout.uploadedGlucose)

        // 2) Also upload a Note treatment to mark the source
        let noteTreatment = NigtscoutTreatment(
            duration: nil,
            rawDuration: nil,
            rawRate: nil,
            absolute: nil,
            rate: nil,
            eventType: .note,
            createdAt: entry.dateString,
            enteredBy: NigtscoutTreatment.local,
            bolus: nil,
            insulin: nil,
            notes: note,
            carbs: nil,
            targetTop: nil,
            targetBottom: nil
        )

        uploadTreatments([noteTreatment], fileToSave: OpenAPS.Nightscout.uploadedPumphistory)
    }

    func uploadGlucose() {
        uploadGlucose(glucoseStorage.nightscoutGlucoseNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedGlucose)
    }

    private func uploadPumpHistory() {
        uploadTreatments(pumpHistoryStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedPumphistory)
    }

    private func uploadCarbs() {
        uploadTreatments(carbsStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedCarbs)
    }

    private func uploadTempTargets() {
        uploadTreatments(tempTargetsStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedTempTargets)
    }

    private func uploadGlucose(_ glucose: [BloodGlucose], fileToSave: String) {
        guard !glucose.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled, isUploadGlucoseEnabled else {
            return
        }

        processQueue.async {
            glucose.chunks(ofCount: 100)
                .map { chunk -> AnyPublisher<Void, Error> in
                    nightscout.uploadGlucose(Array(chunk))
                }
                .reduce(
                    Just(()).setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                ) { (result, next) -> AnyPublisher<Void, Error> in
                    Publishers.Concatenate(prefix: result, suffix: next).eraseToAnyPublisher()
                }
                .dropFirst()
                .sink { completion in
                    switch completion {
                    case .finished:
                        self.storage.save(glucose, as: fileToSave)
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    private func uploadTreatments(_ treatments: [NigtscoutTreatment], fileToSave: String) {
        guard !treatments.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        processQueue.async {
            treatments.chunks(ofCount: 100)
                .map { chunk -> AnyPublisher<Void, Error> in
                    nightscout.uploadTreatments(Array(chunk))
                }
                .reduce(
                    Just(()).setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                ) { (result, next) -> AnyPublisher<Void, Error> in
                    Publishers.Concatenate(prefix: result, suffix: next).eraseToAnyPublisher()
                }
                .dropFirst()
                .sink { completion in
                    switch completion {
                    case .finished:
                        self.storage.save(treatments, as: fileToSave)
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    /// Рассчитать свежий IOB из pump history (как в Dashboard и LoopStatus)
    private func calculateFreshIOB() -> Decimal {
        let pumpHistory = pumpHistoryStorage.recent()
        debug(.nightscout, "Nightscout: Loaded \(pumpHistory.count) pump events for IOB calculation")

        // Используем ту же логику конвертации что и в Dashboard
        let doseEntries: [DoseEntry] = pumpHistory.compactMap { e -> DoseEntry? in
            switch e.type {
            case .bolus,
                 .correctionBolus,
                 .mealBolus,
                 .smb,
                 .snackBolus:
                return DoseEntry(
                    type: .bolus,
                    startDate: e.timestamp,
                    endDate: e.timestamp,
                    value: NSDecimalNumber(decimal: e.amount ?? 0).doubleValue,
                    unit: .units
                )
            case .nsTempBasal,
                 .tempBasal:
                return DoseEntry(
                    type: .tempBasal,
                    startDate: e.timestamp,
                    endDate: e.timestamp.addingTimeInterval(TimeInterval((e.duration ?? e.durationMin ?? 0) * 60)),
                    value: NSDecimalNumber(decimal: e.rate ?? 0).doubleValue,
                    unit: .unitsPerHour
                )
            default:
                return nil
            }
        }
        debug(.nightscout, "Nightscout: Converted \(doseEntries.count) pump events to DoseEntry")

        // IOB временной ряд с шагом 5 минут (как в Dashboard)
        let insulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: nil)
        let now = Date()
        let iobSeries = doseEntries.insulinOnBoard(
            insulinModelProvider: insulinModelProvider,
            longestEffectDuration: InsulinMath.defaultInsulinActivityDuration,
            from: now.addingTimeInterval(-6 * 3600),
            to: now,
            delta: 5 * 60
        )

        let lastIOBValue = iobSeries.last?.value ?? 0
        debug(.nightscout, "Nightscout: Calculated fresh IOB=\(lastIOBValue), from \(doseEntries.count) doses")

        if lastIOBValue.isNaN || lastIOBValue.isInfinite {
            debug(.nightscout, "Nightscout: Invalid IOB value: \(lastIOBValue), using 0")
            return 0
        }

        let freshIOB = Decimal(lastIOBValue)
        debug(.nightscout, "Nightscout: Fresh IOB calculated successfully: \(freshIOB)")
        return freshIOB
    }
}

extension BaseNightscoutManager: PumpHistoryObserver {
    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        uploadPumpHistory()
    }
}

extension BaseNightscoutManager: CarbsObserver {
    func carbsDidUpdate(_: [CarbsEntry]) {
        uploadCarbs()
    }
}

extension BaseNightscoutManager: TempTargetsObserver {
    func tempTargetsDidUpdate(_: [TempTarget]) {
        uploadTempTargets()
    }
}
