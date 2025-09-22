import Foundation
import LoopKit
import Swinject
import WatchConnectivity

protocol WatchManager {}

final class BaseWatchManager: NSObject, WatchManager, Injectable {
    private let session: WCSession
    private var state = WatchState()
    private let processQueue = DispatchQueue(label: "BaseWatchManager.processQueue")

    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var apsManager: APSManager!
    @Injected() private var storage: FileStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!

    private var lifetime = Lifetime()

    init(resolver: Resolver, session: WCSession = .default) {
        self.session = session
        super.init()
        injectServices(resolver)

        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }

        broadcaster.register(GlucoseObserver.self, observer: self)
        broadcaster.register(SuggestionObserver.self, observer: self)
        broadcaster.register(SettingsObserver.self, observer: self)
        broadcaster.register(PumpHistoryObserver.self, observer: self)
        broadcaster.register(PumpSettingsObserver.self, observer: self)
        broadcaster.register(BasalProfileObserver.self, observer: self)
        broadcaster.register(TempTargetsObserver.self, observer: self)
        broadcaster.register(CarbsObserver.self, observer: self)
        broadcaster.register(EnactedSuggestionObserver.self, observer: self)
        broadcaster.register(PumpBatteryObserver.self, observer: self)
        broadcaster.register(PumpReservoirObserver.self, observer: self)

        configureState()
    }

    private func configureState() {
        processQueue.async {
            let glucoseValues = self.glucoseText()
            self.state.glucose = glucoseValues.glucose
            self.state.trend = glucoseValues.trend
            self.state.delta = glucoseValues.delta
            self.state.glucoseDate = self.glucoseStorage.recent().last?.dateString
            self.state.lastLoopDate = self.enactedSuggestion?.recieved == true ? self.enactedSuggestion?.deliverAt : self
                .apsManager.lastLoopDate
            self.state.bolusIncrement = self.settingsManager.preferences.bolusIncrement
            self.state.maxCOB = self.settingsManager.preferences.maxCOB
            self.state.maxBolus = self.settingsManager.pumpSettings.maxBolus
            self.state.carbsRequired = self.suggestion?.carbsReq

            let insulinRequired = self.suggestion?.insulinReq ?? 0
            self.state.bolusRecommended = self.apsManager
                .roundBolus(amount: max(insulinRequired * self.settingsManager.settings.insulinReqFraction, 0))

            let freshIOB = self.calculateFreshIOB()
            self.state.iob = freshIOB
            debug(.service, "📱 WatchManager: Set state.iob = \(freshIOB?.description ?? "nil")")

            self.state.cob = self.suggestion?.cob
            self.state.tempTargets = self.tempTargetsStorage.presets()
                .map { target -> TempTargetWatchPreset in
                    let untilDate = self.tempTargetsStorage.current().flatMap { currentTarget -> Date? in
                        guard currentTarget.id == target.id else { return nil }
                        let date = currentTarget.createdAt.addingTimeInterval(TimeInterval(currentTarget.duration * 60))
                        return date > Date() ? date : nil
                    }
                    return TempTargetWatchPreset(
                        name: target.displayName,
                        id: target.id,
                        description: self.descriptionForTarget(target),
                        until: untilDate
                    )
                }
            self.state.bolusAfterCarbs = !self.settingsManager.settings.skipBolusScreenAfterCarbs
            self.state.eventualBG = self.evetualBGStraing()

            self.sendState()
        }
    }

    private func sendState() {
        dispatchPrecondition(condition: .onQueue(processQueue))

        // OpenAPS Performance Enhancement: Improved WatchKit state management
        guard session.activationState == .activated else {
            debug(.service, "WCSession not activated, skipping sendState")
            return
        }

        guard session.isPaired else {
            debug(.service, "Watch not paired, skipping sendState")
            return
        }

        guard session.isWatchAppInstalled else {
            debug(.service, "Watch app not installed, skipping sendState")
            return
        }

        guard let data = try? JSONEncoder().encode(state) else {
            warning(.service, "Cannot encode watch state")
            return
        }

        // Validate that we have valid data to send
        guard !data.isEmpty else {
            warning(.service, "Watch state data is empty")
            return
        }

        if session.isReachable {
            // Use message data for immediate delivery
            session.sendMessageData(data, replyHandler: nil) { error in
                warning(.service, "Cannot send message to watch", error: error)
            }
        } else {
            // Use application context for background delivery
            do {
                let context = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                try session.updateApplicationContext(context)
                debug(.service, "Updated application context for watch")
            } catch {
                warning(.service, "Cannot update application context", error: error)
            }
        }
    }

    private func glucoseText() -> (glucose: String, trend: String, delta: String) {
        let glucose = glucoseStorage.recent()

        guard let lastGlucose = glucose.last, let glucoseValue = lastGlucose.glucose else { return ("--", "--", "--") }

        let delta = glucose.count >= 2 ? glucoseValue - (glucose[glucose.count - 2].glucose ?? 0) : nil

        let units = settingsManager.settings.units
        let glucoseText = glucoseFormatter
            .string(from: Double(
                units == .mmolL ? glucoseValue
                    .asMmolL : Decimal(glucoseValue)
            ) as NSNumber)!
        let directionText = lastGlucose.direction?.symbol ?? "↔︎"
        let deltaText = delta
            .map {
                self.deltaFormatter
                    .string(from: Double(
                        units == .mmolL ? $0
                            .asMmolL : Decimal($0)
                    ) as NSNumber)!
            } ?? "--"

        return (glucoseText, directionText, deltaText)
    }

    private func descriptionForTarget(_ target: TempTarget) -> String {
        let units = settingsManager.settings.units

        var low = target.targetBottom
        var high = target.targetTop
        if units == .mmolL {
            low = low?.asMmolL
            high = high?.asMmolL
        }

        let description =
            "\(targetFormatter.string(from: (low ?? 0) as NSNumber)!) - \(targetFormatter.string(from: (high ?? 0) as NSNumber)!)" +
            " for \(targetFormatter.string(from: target.duration as NSNumber)!) min"

        return description
    }

    private func evetualBGStraing() -> String? {
        guard let eventualBG = suggestion?.eventualBG else {
            return nil
        }
        let units = settingsManager.settings.units
        return "⇢ " + eventualFormatter.string(
            from: (units == .mmolL ? eventualBG.asMmolL : Decimal(eventualBG)) as NSNumber
        )!
    }

    private var glucoseFormatter: NumberFormatter {
        if settingsManager.settings.units == .mmolL {
            return FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 1, maxFractionDigits: 1)
        } else {
            return FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 0)
        }
    }

    private var eventualFormatter: NumberFormatter {
        FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 2) }

    private var deltaFormatter: NumberFormatter {
        FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 2, positivePrefix: "+") }

    private var targetFormatter: NumberFormatter {
        FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 1) }

    private var suggestion: Suggestion? {
        storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
    }

    private var enactedSuggestion: Suggestion? {
        storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)
    }

    /// Рассчитать свежий IOB из pump history (как в Dashboard)
    private func calculateFreshIOB() -> Decimal? {
        debug(.service, "🔍 WatchManager: calculateFreshIOB() called")

        guard let pumpHistoryStorage = pumpHistoryStorage else {
            debug(
                .service,
                "❌ WatchManager: pumpHistoryStorage not available, fallback to suggestion IOB=\(suggestion?.iob?.description ?? "nil")"
            )
            return suggestion?.iob
        }

        let pumpHistory = pumpHistoryStorage.recent()
        debug(.service, "🔄 WatchManager: Loaded \(pumpHistory.count) pump events from pumpHistoryStorage.recent()")

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
        debug(.service, "✅ WatchManager: Converted \(doseEntries.count) pump events to DoseEntry")

        // Определяем модель инсулина из настроек пользователя
        let defaultModel: InsulinModel
        if let curveSettings: InsulinCurveSettings = storage.retrieve(
            OpenAPS.Settings.insulinCurve,
            as: InsulinCurveSettings.self
        ) {
            let delay = curveSettings.delay * 60 // минуты в секунды
            let peakTime = curveSettings.peakTime * 60 // минуты в секунды
            let duration = curveSettings.actionDuration * 3600 // часы в секунды
            defaultModel = ExponentialInsulinModel(actionDuration: duration, peakActivityTime: peakTime, delay: delay)
        } else {
            // Fallback к Fiasp
            let preset = ExponentialInsulinModelPreset.fiasp
            defaultModel = ExponentialInsulinModel(
                actionDuration: preset.actionDuration,
                peakActivityTime: preset.peakActivity,
                delay: preset.delay
            )
        }

        let insulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: defaultModel)

        let now = Date()
        let iobSeries = doseEntries.insulinOnBoard(
            insulinModelProvider: insulinModelProvider,
            longestEffectDuration: InsulinMath.defaultInsulinActivityDuration,
            from: now.addingTimeInterval(-6 * 3600),
            to: now,
            delta: 5 * 60
        )

        let lastIOBValue = iobSeries.last?.value ?? 0
        debug(
            .service,
            "💊 WatchManager: Calculated fresh IOB=\(lastIOBValue), from \(doseEntries.count) doses, \(iobSeries.count) IOB points"
        )

        if lastIOBValue.isNaN || lastIOBValue.isInfinite {
            debug(
                .service,
                "❌ WatchManager: Invalid IOB value: \(lastIOBValue), using suggestion fallback=\(suggestion?.iob?.description ?? "nil")"
            )
            return suggestion?.iob
        }

        let freshIOB = Decimal(lastIOBValue)
        debug(.service, "✅ WatchManager: Fresh IOB calculated successfully: \(freshIOB)")
        return freshIOB
    }
}

extension BaseWatchManager: WCSessionDelegate {
    func sessionDidBecomeInactive(_: WCSession) {}

    func sessionDidDeactivate(_: WCSession) {}

    func session(_: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        debug(.service, "WCSession is activated: \(state == .activated)")

        // OpenAPS Performance Enhancement: Improve WatchKit error handling
        if let error = error {
            warning(.service, "WCSession activation error: \(error.localizedDescription)")
        }

        // Check if watch app is installed and reachable
        if state == .activated {
            debug(.service, "WCSession activated successfully")
            if session.isPaired {
                debug(.service, "Watch is paired")
                if session.isWatchAppInstalled {
                    debug(.service, "Watch app is installed")
                    // Send initial state if watch is ready
                    processQueue.async {
                        self.sendState()
                    }
                } else {
                    debug(.service, "Watch app is not installed")
                }
            } else {
                debug(.service, "Watch is not paired")
            }
        } else {
            warning(.service, "WCSession activation failed with state: \(state)")
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        debug(.service, "WCSession got message: \(message)")

        if let stateRequest = message["stateRequest"] as? Bool, stateRequest {
            processQueue.async {
                self.sendState()
            }
        }
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        debug(.service, "WCSession got message with reply handler: \(message)")

        if let carbs = message["carbs"] as? Double, carbs > 0 {
            carbsStorage.storeCarbs([
                CarbsEntry(createdAt: Date(), carbs: Decimal(carbs), enteredBy: CarbsEntry.manual)
            ])

            if settingsManager.settings.skipBolusScreenAfterCarbs {
                apsManager.determineBasalSync()
                replyHandler(["confirmation": true])
                return
            } else {
                apsManager.determineBasal()
                    .sink { _ in
                        replyHandler(["confirmation": true])
                    }
                    .store(in: &lifetime)
                return
            }
        }

        if let tempTargetID = message["tempTarget"] as? String {
            if var preset = tempTargetsStorage.presets().first(where: { $0.id == tempTargetID }) {
                preset.createdAt = Date()
                tempTargetsStorage.storeTempTargets([preset])
                replyHandler(["confirmation": true])
                return
            } else if tempTargetID == "cancel" {
                let entry = TempTarget(
                    name: TempTarget.cancel,
                    createdAt: Date(),
                    targetTop: 0,
                    targetBottom: 0,
                    duration: 0,
                    enteredBy: TempTarget.manual,
                    reason: TempTarget.cancel
                )
                tempTargetsStorage.storeTempTargets([entry])
                replyHandler(["confirmation": true])
                return
            }
        }

        if let bolus = message["bolus"] as? Double, bolus > 0 {
            apsManager.enactBolus(amount: bolus, isSMB: false)
            replyHandler(["confirmation": true])
            return
        }

        replyHandler(["confirmation": false])
    }

    func session(_: WCSession, didReceiveMessageData _: Data) {}

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            processQueue.async {
                self.sendState()
            }
        }
    }
}

extension BaseWatchManager:
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
    PumpReservoirObserver
{
    @MainActor func glucoseDidUpdate(_: [BloodGlucose]) {
        processQueue.async {
            self.configureState()
        }
    }

    @MainActor func suggestionDidUpdate(_: Suggestion) {
        processQueue.async {
            self.configureState()
        }
    }

    @MainActor func settingsDidChange(_: FreeAPSSettings) {
        processQueue.async {
            self.configureState()
        }
    }

    @MainActor func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        // TODO:
    }

    @MainActor func pumpSettingsDidChange(_: PumpSettings) {
        processQueue.async {
            self.configureState()
        }
    }

    @MainActor func basalProfileDidChange(_: [BasalProfileEntry]) {
        // TODO:
    }

    @MainActor func tempTargetsDidUpdate(_: [TempTarget]) {
        processQueue.async {
            self.configureState()
        }
    }

    @MainActor func carbsDidUpdate(_: [CarbsEntry]) {
        // TODO:
    }

    @MainActor func enactedSuggestionDidUpdate(_: Suggestion) {
        processQueue.async {
            self.configureState()
        }
    }

    @MainActor func pumpBatteryDidChange(_: Battery) {
        // TODO:
    }

    @MainActor func pumpReservoirDidChange(_: Decimal) {
        // TODO:
    }
}
