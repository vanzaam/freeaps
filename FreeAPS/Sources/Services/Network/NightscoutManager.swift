import Combine
import Foundation
import Swinject
import UIKit

protocol NightscoutManager: GlucoseSource {
    func fetchGlucose(since date: Date) -> AnyPublisher<[BloodGlucose], Never>
    func fetchCarbs() -> AnyPublisher<[CarbsEntry], Never>
    func fetchTempTargets() -> AnyPublisher<[TempTarget], Never>
    func fetchAnnouncements() -> AnyPublisher<[Announcement], Never>
    func deleteCarbs(at date: Date)
    func deleteTempTarget(at date: Date)
    func deleteBolus(at date: Date, amount: Decimal)
    func deleteTempBasal(at date: Date)
    func deleteSuspend(at date: Date)
    func deleteResume(at date: Date)
    func processPendingDeletions()
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
            // Process pending deletions when network becomes available
            if case .reachable = status {
                self.processPendingDeletions()
            }
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
                    // Add to pending deletions queue if failed
                    self.addToPendingDeletions(.carbs(date))
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    func deleteTempTarget(at date: Date) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        nightscout.deleteTempTarget(at: date)
            .sink { completion in
                switch completion {
                case .finished:
                    debug(.nightscout, "Temp target deleted")
                case let .failure(error):
                    debug(.nightscout, error.localizedDescription)
                    // Add to pending deletions queue if failed
                    self.addToPendingDeletions(.tempTarget(date))
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    func deleteBolus(at date: Date, amount: Decimal) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        nightscout.deleteBolus(at: date, amount: amount)
            .sink { completion in
                switch completion {
                case .finished:
                    debug(.nightscout, "Bolus deleted")
                case let .failure(error):
                    debug(.nightscout, error.localizedDescription)
                    // Add to pending deletions queue if failed
                    self.addToPendingDeletions(.bolus(date, amount))
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    func deleteTempBasal(at date: Date) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        nightscout.deleteTempBasal(at: date)
            .sink { completion in
                switch completion {
                case .finished:
                    debug(.nightscout, "Temp basal deleted")
                case let .failure(error):
                    debug(.nightscout, error.localizedDescription)
                    // Add to pending deletions queue if failed
                    self.addToPendingDeletions(.tempBasal(date))
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    func deleteSuspend(at date: Date) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        nightscout.deleteSuspend(at: date)
            .sink { completion in
                switch completion {
                case .finished:
                    debug(.nightscout, "Suspend deleted")
                case let .failure(error):
                    debug(.nightscout, error.localizedDescription)
                    // Add to pending deletions queue if failed
                    self.addToPendingDeletions(.suspend(date))
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    func deleteResume(at date: Date) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        nightscout.deleteResume(at: date)
            .sink { completion in
                switch completion {
                case .finished:
                    debug(.nightscout, "Resume deleted")
                case let .failure(error):
                    debug(.nightscout, error.localizedDescription)
                    // Add to pending deletions queue if failed
                    self.addToPendingDeletions(.resume(date))
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    // MARK: - Pending Deletions Queue

    private enum PendingDeletion: Codable, Hashable {
        case carbs(Date)
        case tempTarget(Date)
        case bolus(Date, Decimal)
        case tempBasal(Date)
        case suspend(Date)
        case resume(Date)

        enum CodingKeys: String, CodingKey {
            case type
            case date
            case amount
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .carbs(date):
                try container.encode("carbs", forKey: .type)
                try container.encode(date, forKey: .date)
            case let .tempTarget(date):
                try container.encode("tempTarget", forKey: .type)
                try container.encode(date, forKey: .date)
            case let .bolus(date, amount):
                try container.encode("bolus", forKey: .type)
                try container.encode(date, forKey: .date)
                try container.encode(amount, forKey: .amount)
            case let .tempBasal(date):
                try container.encode("tempBasal", forKey: .type)
                try container.encode(date, forKey: .date)
            case let .suspend(date):
                try container.encode("suspend", forKey: .type)
                try container.encode(date, forKey: .date)
            case let .resume(date):
                try container.encode("resume", forKey: .type)
                try container.encode(date, forKey: .date)
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            let date = try container.decode(Date.self, forKey: .date)

            switch type {
            case "carbs":
                self = .carbs(date)
            case "tempTarget":
                self = .tempTarget(date)
            case "bolus":
                let amount = try container.decode(Decimal.self, forKey: .amount)
                self = .bolus(date, amount)
            case "tempBasal":
                self = .tempBasal(date)
            case "suspend":
                self = .suspend(date)
            case "resume":
                self = .resume(date)
            default:
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown deletion type")
                )
            }
        }
    }

    private var pendingDeletions: Set<PendingDeletion> {
        get {
            guard let data = UserDefaults.standard.data(forKey: "PendingNightscoutDeletions"),
                  let deletions = try? JSONDecoder().decode(Set<PendingDeletion>.self, from: data)
            else {
                return []
            }
            return deletions
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "PendingNightscoutDeletions")
            }
        }
    }

    private func addToPendingDeletions(_ deletion: PendingDeletion) {
        var pending = pendingDeletions
        pending.insert(deletion)
        pendingDeletions = pending
    }

    func processPendingDeletions() {
        guard let nightscout = nightscoutAPI, isUploadEnabled, isNetworkReachable else {
            return
        }

        let pending = pendingDeletions
        var processed: Set<PendingDeletion> = []

        for deletion in pending {
            let publisher: AnyPublisher<Void, Swift.Error>

            switch deletion {
            case let .carbs(date):
                publisher = nightscout.deleteCarbs(at: date)
            case let .tempTarget(date):
                publisher = nightscout.deleteTempTarget(at: date)
            case let .bolus(date, amount):
                publisher = nightscout.deleteBolus(at: date, amount: amount)
            case let .tempBasal(date):
                publisher = nightscout.deleteTempBasal(at: date)
            case let .suspend(date):
                publisher = nightscout.deleteSuspend(at: date)
            case let .resume(date):
                publisher = nightscout.deleteResume(at: date)
            }

            publisher
                .sink { completion in
                    switch completion {
                    case .finished:
                        processed.insert(deletion)
                        debug(.nightscout, "Pending deletion processed: \(deletion)")
                    case let .failure(error):
                        debug(.nightscout, "Pending deletion failed: \(error.localizedDescription)")
                    }
                } receiveValue: {}
                .store(in: &lifetime)
        }

        // Remove processed deletions
        if !processed.isEmpty {
            var remaining = pendingDeletions
            remaining.subtract(processed)
            pendingDeletions = remaining
        }
    }

    func uploadStatus() {
        let iob = storage.retrieve(OpenAPS.Monitor.iob, as: [IOBEntry].self)
        var suggested = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        var enacted = storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)

        if (suggested?.timestamp ?? .distantPast) > (enacted?.timestamp ?? .distantPast) {
            enacted?.predictions = nil
        } else {
            suggested?.predictions = nil
        }

        let openapsStatus = OpenAPSStatus(
            iob: iob?.first,
            suggested: suggested,
            enacted: enacted,
            version: "0.7.0"
        )

        let battery = storage.retrieve(OpenAPS.Monitor.battery, as: Battery.self)
        var reservoir = Decimal(from: storage.retrieveRaw(OpenAPS.Monitor.reservoir) ?? "0")
        if reservoir == 0xDEAD_BEEF {
            reservoir = nil
        }
        let pumpStatus = storage.retrieve(OpenAPS.Monitor.status, as: PumpStatus.self)

        let pump = NSPumpStatus(clock: Date(), battery: battery, reservoir: reservoir, status: pumpStatus)

        let preferences = settingsManager.preferences

        let device = UIDevice.current

        let uploader = Uploader(batteryVoltage: nil, battery: Int(device.batteryLevel * 100))

        let status = NightscoutStatus(
            device: "freeaps-x://" + device.name,
            openaps: openapsStatus,
            pump: pump,
            preferences: preferences,
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
