import Combine
import LoopKitUI
import SwiftDate
import SwiftUI

extension Home {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Injected() var apsManager: APSManager!
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var smbBasalManager: SmbBasalManager!
        @Injected() var storage: FileStorage!
        @Injected() var customIOBCalculator: CustomIOBCalculator!
        @Injected() var swiftOref0Engine: SwiftOref0Engine! // Native Swift oref0
        private let timer = DispatchTimer(timeInterval: 5)
        private(set) var filteredHours = 24

        @Published var glucose: [BloodGlucose] = []
        @Published var suggestion: Suggestion?
        @Published var enactedSuggestion: Suggestion?
        @Published var smbHourlyRates: [Decimal] = []
        @Published var recentGlucose: BloodGlucose?
        @Published var glucoseDelta: Int?
        @Published var tempBasals: [PumpHistoryEvent] = []
        @Published var boluses: [PumpHistoryEvent] = []
        @Published var suspensions: [PumpHistoryEvent] = []
        @Published var maxBasal: Decimal = 2
        @Published var autotunedBasalProfile: [BasalProfileEntry] = []
        @Published var basalProfile: [BasalProfileEntry] = []
        @Published var tempTargets: [TempTarget] = []
        @Published var carbs: [CarbsEntry] = []
        @Published var timerDate = Date()
        @Published var closedLoop = false
        @Published var pumpSuspended = false
        @Published var isLooping = false
        @Published var statusTitle = ""
        @Published var lastLoopDate: Date = .distantPast
        @Published var tempRate: Decimal?
        @Published var battery: Battery?
        @Published var reservoir: Decimal?
        @Published var pumpName = ""
        @Published var pumpExpiresAtDate: Date?
        @Published var tempTarget: TempTarget?
        @Published var setupPump = false
        @Published var errorMessage: String? = nil
        @Published var errorDate: Date? = nil
        @Published var bolusProgress: Decimal?
        @Published var eventualBG: Int?
        @Published var carbsRequired: Decimal?
        @Published var allowManualTemp = false
        @Published var units: GlucoseUnits = .mmolL
        @Published var customIOB: Decimal = 0
        @Published var customIOBDifference: Decimal = 0
        @Published var showCustomIOB = false
        @Published var pumpDisplayState: PumpDisplayState?
        @Published var alarm: GlucoseAlarm?
        @Published var animatedBackground = false
        @Published var basalIob: SmbBasalIob?

        // 🎯 Custom Prediction Service результаты
        @Published var customPredBGs: PredictionBGs?
        @Published var customIOBPredBG: Double?
        @Published var customCOBPredBG: Double?
        @Published var customUAMPredBG: Double?
        @Published var customMinPredBG: Double?

        // 🚀 Swift Oref0 Engine результаты
        @Published var swiftPredBGs: SwiftPredictionBGs?
        @Published var swiftIOBPredBG: Double?
        @Published var swiftCOBPredBG: Double?
        @Published var swiftUAMPredBG: Double?
        @Published var swiftMinPredBG: Double?
        @Published var swiftEventualBG: Double?
        @Published var swiftInsulinReq: Double?

        override func subscribe() {
            setupGlucose()
            setupBasals()
            setupBoluses()
            setupSuspensions()
            setupPumpSettings()
            setupBasalProfile()
            setupTempTargets()
            setupCarbs()
            setupBattery()
            setupReservoir()

            suggestion = provider.suggestion
            enactedSuggestion = provider.enactedSuggestion
            units = settingsManager.settings.units
            allowManualTemp = !settingsManager.settings.closedLoop
            closedLoop = settingsManager.settings.closedLoop
            lastLoopDate = apsManager.lastLoopDate
            carbsRequired = suggestion?.carbsReq
            alarm = provider.glucoseStorage.alarm

            setStatusTitle()
            setupCurrentTempTarget()

            broadcaster.register(GlucoseObserver.self, observer: self)
            broadcaster.register(SuggestionObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(PumpSettingsObserver.self, observer: self)
            broadcaster.register(BasalProfileObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(CustomPredictionObserver.self, observer: self)
            broadcaster.register(CarbsObserver.self, observer: self)
            broadcaster.register(EnactedSuggestionObserver.self, observer: self)
            broadcaster.register(PumpBatteryObserver.self, observer: self)
            broadcaster.register(PumpReservoirObserver.self, observer: self)

            animatedBackground = settingsManager.settings.animatedBackground

            timer.eventHandler = {
                DispatchQueue.main.async { [weak self] in
                    self?.timerDate = Date()
                    self?.setupCurrentTempTarget()
                    self?.updateBasalIob()
                    self?.updateCustomIOB()
                    self?.generateSwiftOref0Predictions()
                }
            }
            timer.resume()

            apsManager.isLooping
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.isLooping, on: self)
                .store(in: &lifetime)

            apsManager.lastLoopDateSubject
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.lastLoopDate, on: self)
                .store(in: &lifetime)

            apsManager.pumpName
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.pumpName, on: self)
                .store(in: &lifetime)

            apsManager.pumpExpiresAtDate
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.pumpExpiresAtDate, on: self)
                .store(in: &lifetime)

            apsManager.lastError
                .receive(on: DispatchQueue.main)
                .map { [weak self] error in
                    self?.errorDate = error == nil ? nil : Date()
                    if let error = error {
                        info(.default, error.localizedDescription)
                    }
                    return error?.localizedDescription
                }
                .weakAssign(to: \.errorMessage, on: self)
                .store(in: &lifetime)

            apsManager.bolusProgress
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.bolusProgress, on: self)
                .store(in: &lifetime)

            apsManager.pumpDisplayState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self else { return }
                    self.pumpDisplayState = state
                    if state == nil {
                        self.reservoir = nil
                        self.battery = nil
                        self.pumpName = ""
                        self.pumpExpiresAtDate = nil
                        self.setupPump = false
                    } else {
                        self.setupBattery()
                        self.setupReservoir()
                    }
                }
                .store(in: &lifetime)

            $setupPump
                .sink { [weak self] show in
                    guard let self = self else { return }
                    if show, let pumpManager = self.provider.apsManager.pumpManager {
                        let view = PumpConfig.PumpSettingsView(pumpManager: pumpManager, completionDelegate: self).asAny()
                        self.router.mainSecondaryModalView.send(view)
                    } else {
                        self.router.mainSecondaryModalView.send(nil)
                    }
                }
                .store(in: &lifetime)
        }

        func addCarbs() {
            showModal(for: .addCarbs)
        }

        func runLoop() {
            provider.heartbeatNow()
        }

        func cancelBolus() {
            apsManager.cancelBolus()
        }

        private func setupGlucose() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.glucose = self.provider.filteredGlucose(hours: self.filteredHours)
                self.recentGlucose = self.glucose.last
                if self.glucose.count >= 2 {
                    self.glucoseDelta = (self.recentGlucose?.glucose ?? 0) - (self.glucose[self.glucose.count - 2].glucose ?? 0)
                } else {
                    self.glucoseDelta = nil
                }
                self.alarm = self.provider.glucoseStorage.alarm
            }
        }

        private func setupBasals() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.tempBasals = self.provider.pumpHistory(hours: self.filteredHours).filter {
                    $0.type == .tempBasal || $0.type == .tempBasalDuration
                }
                let lastTempBasal = Array(self.tempBasals.suffix(2))
                guard lastTempBasal.count == 2 else {
                    self.tempRate = nil
                    return
                }

                guard let lastRate = lastTempBasal[0].rate, let lastDuration = lastTempBasal[1].durationMin else {
                    self.tempRate = nil
                    return
                }
                let lastDate = lastTempBasal[0].timestamp
                guard Date().timeIntervalSince(lastDate.addingTimeInterval(lastDuration.minutes.timeInterval)) < 0 else {
                    self.tempRate = nil
                    return
                }
                self.tempRate = lastRate
            }
        }

        private func setupBoluses() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                // Exclude SMB-Basal and locally-deleted boluses
                let events = self.provider.pumpHistory(hours: self.filteredHours)
                self.boluses = events.filter { event in
                    guard event.type == .bolus || event.type == .smb else { return false }
                    // Always hide locally deleted boluses on the main screen
                    return !DeletedTreatmentsStore.shared.containsBolus(
                        date: event.timestamp,
                        amount: event.effectiveInsulinAmount
                    )
                }
            }
        }

        private func setupSuspensions() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.suspensions = self.provider.pumpHistory(hours: self.filteredHours).filter {
                    $0.type == .pumpSuspend || $0.type == .pumpResume
                }

                let last = self.suspensions.last
                let tbr = self.tempBasals.first { $0.timestamp > (last?.timestamp ?? .distantPast) }

                self.pumpSuspended = tbr == nil && last?.type == .pumpSuspend
            }
        }

        private func setupPumpSettings() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.maxBasal = self.provider.pumpSettings().maxBasal
            }
        }

        private func setupBasalProfile() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.autotunedBasalProfile = self.provider.autotunedBasalProfile()
                self.basalProfile = self.provider.basalProfile()
            }
        }

        private func setupTempTargets() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.tempTargets = self.provider.tempTargets(hours: self.filteredHours)
            }
        }

        private func setupCarbs() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.carbs = self.provider.carbs(hours: self.filteredHours)
            }
        }

        private func setStatusTitle() {
            guard let suggestion = suggestion else {
                statusTitle = "No suggestion"
                return
            }

            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short
            if closedLoop,
               let enactedSuggestion = enactedSuggestion,
               let timestamp = enactedSuggestion.timestamp,
               enactedSuggestion.deliverAt == suggestion.deliverAt, enactedSuggestion.recieved == true
            {
                statusTitle = "Enacted at \(dateFormatter.string(from: timestamp))"
            } else if let suggestedDate = suggestion.deliverAt {
                statusTitle = "Suggested at \(dateFormatter.string(from: suggestedDate))"
            } else {
                statusTitle = "Suggested"
            }

            eventualBG = suggestion.eventualBG
        }

        private func setupReservoir() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.reservoir = self.provider.pumpReservoir()
            }
        }

        private func setupBattery() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.battery = self.provider.pumpBattery()
            }
        }

        private func setupCurrentTempTarget() {
            tempTarget = provider.tempTarget()
        }

        func openCGM() {
            guard var url = nightscoutManager.cgmURL else { return }

            switch url.absoluteString {
            case "http://127.0.0.1:1979":
                url = URL(string: "spikeapp://")!
            case "http://127.0.0.1:17580":
                url = URL(string: "diabox://")!
            case CGMType.libreTransmitter.appURL?.absoluteString:
                showModal(for: .libreConfig)
            default: break
            }
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}

extension Home.StateModel:
    GlucoseObserver,
    SuggestionObserver,
    SettingsObserver,
    PumpHistoryObserver,
    PumpSettingsObserver,
    BasalProfileObserver,
    TempTargetsObserver,
    CarbsObserver,
    EnactedSuggestionObserver,
    PumpBatteryObserver,
    PumpReservoirObserver,
    CustomPredictionObserver
{
    @MainActor func glucoseDidUpdate(_: [BloodGlucose]) {
        setupGlucose()
    }

    @MainActor func suggestionDidUpdate(_ suggestion: Suggestion) {
        self.suggestion = suggestion
        carbsRequired = suggestion.carbsReq
        setStatusTitle()

        // 🚀 Генерируем нативные Swift Oref0 прогнозы
        generateSwiftOref0Predictions()
    }

    @MainActor func settingsDidChange(_ settings: FreeAPSSettings) {
        allowManualTemp = !settings.closedLoop
        closedLoop = settingsManager.settings.closedLoop
        units = settingsManager.settings.units
        animatedBackground = settingsManager.settings.animatedBackground
        setupGlucose()
    }

    @MainActor func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        setupBasals()
        setupBoluses()
        setupSuspensions()
        computeSmbHourlyRates()
    }

    @MainActor func pumpSettingsDidChange(_: PumpSettings) {
        setupPumpSettings()
    }

    @MainActor func basalProfileDidChange(_: [BasalProfileEntry]) {
        setupBasalProfile()
    }

    @MainActor func tempTargetsDidUpdate(_: [TempTarget]) {
        setupTempTargets()
    }

    @MainActor func carbsDidUpdate(_: [CarbsEntry]) {
        setupCarbs()
    }

    @MainActor func enactedSuggestionDidUpdate(_ suggestion: Suggestion) {
        enactedSuggestion = suggestion
        setStatusTitle()
    }

    @MainActor func pumpBatteryDidChange(_: Battery) {
        setupBattery()
    }

    @MainActor func pumpReservoirDidChange(_: Decimal) {
        setupReservoir()
    }

    @MainActor private func updateBasalIob() {
        guard smbBasalManager.isEnabled else {
            basalIob = nil
            return
        }

        basalIob = smbBasalManager.currentBasalIob()
        computeSmbHourlyRates()
    }

    @MainActor private func updateCustomIOB() {
        let result = customIOBCalculator.calculateIOB()

        customIOB = result.totalIOB
        customIOBDifference = result.totalIOB - result.systemIOB
        showCustomIOB = abs(customIOBDifference) > 0.05 // Показываем если разница больше 0.05U

        print("🧮 Custom IOB Update:")
        print("  System IOB: \(result.systemIOB)")
        print("  Custom IOB: \(result.totalIOB)")
        print("  Difference: \(customIOBDifference)")
        print("  Show Custom: \(showCustomIOB)")
    }

    private func computeSmbHourlyRates() {
        let pulses = storage.retrieve(OpenAPS.Monitor.smbBasalPulses, as: [SmbBasalPulse].self) ?? []
        let now = Date()
        let start = now.addingTimeInterval(-24 * 3600)
        var bins = Array(repeating: Decimal(0), count: 24)
        for p in pulses {
            guard p.timestamp >= start else { continue }
            let idx = min(23, max(0, Int(p.timestamp.timeIntervalSince(start) / 3600)))
            bins[idx] += p.units
        }

        DispatchQueue.main.async { [weak self] in
            self?.smbHourlyRates = bins
        }
    }

    // 🚀 Custom Prediction Service результаты из APSManager
    @MainActor func customPredictionDidUpdate(_ prediction: CustomPredictionResult) {
        debug(.openAPS, "🎯 HomeStateModel: Received custom predictions from APSManager!")

        // Обновляем UI с правильными прогнозами
        customPredBGs = prediction.predBGs
        customIOBPredBG = prediction.iobPredBG
        customCOBPredBG = prediction.cobPredBG
        customUAMPredBG = prediction.uamPredBG
        customMinPredBG = prediction.minPredBG

        debug(.openAPS, "✅ Custom Predictions UI Updated:")
        debug(.openAPS, "  IOB PredBG: \(prediction.iobPredBG)")
        debug(.openAPS, "  COB PredBG: \(prediction.cobPredBG)")
        debug(.openAPS, "  UAM PredBG: \(prediction.uamPredBG)")
        debug(.openAPS, "  Min PredBG: \(prediction.minPredBG)")
        debug(.openAPS, "  Eventual BG: \(prediction.eventualBG)")
    }

    // 🚀 Swift Oref0 Engine - нативный алгоритм прогнозов
    @MainActor func generateSwiftOref0Predictions() {
        // Получаем данные для Swift Oref0
        let iobData = customIOBCalculator.calculateIOB()
        let totalIOB = Double(truncating: iobData.totalIOB as NSDecimalNumber)

        // Загружаем профиль (с безопасным фолбэком)
        let profileData = storage.retrieve(OpenAPS.Settings.profile, as: RawJSON.self) ?? ""
        let profile: [String: Any]
        if let data = profileData.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            profile = parsed
        } else {
            debug(.openAPS, "⚠️ SwiftOref0: Failed to load profile, using default fallback")
            profile = [
                "isf": 50.0, // mg/dL per U
                "cr": 15.0, // g/U
                "target": 100.0 // mg/dL
            ]
        }

        // Загружаем autosens
        let autosensData = storage.retrieve(OpenAPS.Settings.autosense, as: RawJSON.self) ?? ""
        let autosens = autosensData
            .isEmpty ? nil :
            (try? JSONSerialization.jsonObject(with: autosensData.data(using: .utf8) ?? Data()) as? [String: Any])

        // Загружаем meal
        let mealData = storage.retrieve(OpenAPS.Monitor.meal, as: RawJSON.self) ?? ""
        let meal = mealData
            .isEmpty ? nil : (try? JSONSerialization.jsonObject(with: mealData.data(using: .utf8) ?? Data()) as? [String: Any])

        // Загружаем reservoir
        let reservoirData = storage.retrieve(OpenAPS.Monitor.reservoir, as: RawJSON.self) ?? ""
        let reservoir = reservoirData
            .isEmpty ? nil :
            (try? JSONSerialization.jsonObject(with: reservoirData.data(using: .utf8) ?? Data()) as? [String: Any])

        // Загружаем current temp
        let tempData = storage.retrieve(OpenAPS.Monitor.tempBasal, as: RawJSON.self) ?? ""
        let currentTemp = tempData
            .isEmpty ? nil : (try? JSONSerialization.jsonObject(with: tempData.data(using: .utf8) ?? Data()) as? [String: Any])

        debug(.openAPS, "🚀 SwiftOref0: Starting native oref0 with IOB: \(totalIOB)")

        swiftOref0Engine.generatePredictions(
            iob: totalIOB,
            glucose: glucose,
            profile: profile,
            autosens: autosens,
            meal: meal,
            reservoir: reservoir,
            currentTemp: currentTemp
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] result in
            guard let self = self, let result = result else { return }

            // Обновляем UI с нативными Swift прогнозами
            self.swiftPredBGs = result.predBGs
            self.swiftIOBPredBG = result.iobPredBG
            self.swiftCOBPredBG = result.cobPredBG
            self.swiftUAMPredBG = result.uamPredBG
            self.swiftMinPredBG = result.minPredBG
            self.swiftEventualBG = result.eventualBG
            self.swiftInsulinReq = result.insulinReq

            debug(.openAPS, "🚀 Swift Oref0 Predictions Updated:")
            debug(.openAPS, "  IOB PredBG: \(result.iobPredBG)")
            debug(.openAPS, "  COB PredBG: \(result.cobPredBG)")
            debug(.openAPS, "  UAM PredBG: \(result.uamPredBG)")
            debug(.openAPS, "  Min PredBG: \(result.minPredBG)")
            debug(.openAPS, "  Eventual BG: \(result.eventualBG)")
            debug(.openAPS, "  Insulin Req: \(result.insulinReq)")
            debug(.openAPS, "  Reason: \(result.reason)")
        }
        .store(in: &lifetime)
    }
}

extension Home.StateModel: CompletionDelegate {
    @MainActor func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupPump = false
    }
}
