import Combine
import Foundation
import Swinject

// MARK: - Failed Pulse Tracking

struct FailedPulse {
    let id: String
    let timestamp: Date
    let units: Decimal
    let reason: FailureReason

    enum FailureReason: String, CaseIterable {
        case pumpError = "Pump Error"
        case communicationError = "Communication Error"
        case bolusInProgress = "Bolus In Progress"
        case pumpSuspended = "Pump Suspended"
        case lowBattery = "Low Battery"
        case other = "Other Error"
    }
}

// MARK: - Public API

protocol SmbBasalManager: AnyObject {
    var isEnabled: Bool { get }
    func start()
    func stop()
    func currentBasalIob() -> SmbBasalIob
}

// MARK: - Implementation

final class BaseSmbBasalManager: SmbBasalManager, Injectable, SettingsObserver {
    @Injected() private var apsManager: APSManager!
    @Injected() private var storage: FileStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var basalIobCalculator: SmbBasalIobCalculator!
    @Injected() private var middleware: SmbBasalMiddleware!
    @Injected() private var glucoseStorage: GlucoseStorage!

    private let workQueue = DispatchQueue(label: "SmbBasalManager.queue", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lifetime = Lifetime()

    private var accumulatorUnits: Decimal = 0
    private var lastPulseAt: Date?
    private var lastZeroBasalSetAt: Date?
    private var missedUnitsFromLowGlucose: Decimal = 0 // Track units not delivered due to low glucose
    private var failedPulses: [FailedPulse] = [] // Track failed pulses for compensation
    private var compensationUnits: Decimal = 0 // Accumulated units to compensate

    private(set) var isEnabled: Bool = false

    init(resolver: Resolver) {
        injectServices(resolver)
        // Observe app settings changes to auto start/stop
        resolver.resolve(Broadcaster.self)!.register(SettingsObserver.self, observer: self)

        // Initialize state from persisted settings
        isEnabled = settingsManager.settings.smbBasalEnabled
        print("SMB-Basal Manager initialized: isEnabled=\(isEnabled)")
        if isEnabled {
            print("SMB-Basal Manager starting...")
            start()
        }
    }

    // MARK: - SettingsObserver

    @MainActor func settingsDidChange(_ settings: FreeAPSSettings) {
        print("SMB-Basal: Settings changed - smbBasalEnabled=\(settings.smbBasalEnabled), current isEnabled=\(isEnabled)")
        workQueue.async { [weak self] in
            guard let self = self else { return }

            // Sync smbBasalEnabled with OpenAPS preferences
            self.settingsManager.updatePreferences { prefs in
                prefs.smbBasalEnabled = settings.smbBasalEnabled
            }

            if settings.smbBasalEnabled, !self.isEnabled {
                print("SMB-Basal: Enabling and starting SMB-basal system")
                self.isEnabled = true
                self.start()
            } else if !settings.smbBasalEnabled, self.isEnabled {
                print("SMB-Basal: Disabling and stopping SMB-basal system")
                self.isEnabled = false
                self.stop()
            }
        }
    }

    // MARK: - Control

    func start() {
        workQueue.async {
            guard self.timer == nil else { return }
            self.middleware.setupMiddleware() // Install OpenAPS middleware
            self.setupTimer()
        }
    }

    func stop() {
        workQueue.async {
            self.timer?.cancel()
            self.timer = nil
            self.accumulatorUnits = 0
            self.lastPulseAt = nil
            self.middleware.removeMiddleware() // Remove OpenAPS middleware
        }
    }

    // MARK: - Timer / Scheduling

    private func setupTimer() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(60), leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        guard isEnabled else {
            print("SMB-Basal: tick() called but manager is disabled")
            return
        }

        // Wait for main loop to complete before delivering pulses
        if apsManager.isLooping.value {
            print("SMB-Basal: Main loop is running, waiting for completion")
            return
        }

        print("SMB-Basal: tick() - processing basal replacement")
        // Clean up old failed pulses and update compensation units
        updateCompensationUnits()

        // Always keep 0 U/h temp basal while SMB-basal is active. All basal will be replaced by pulses.
        maintainZeroTempBasalIfNeeded()

        // 2) Accumulate basal dose and fire step boluses when enough units are accumulated
        guard let step = optionalBolusStep(), step > 0 else { return }

        // Check glucose threshold before delivering basal
        if isGlucoseBelowThreshold() {
            let unitsPerMinute = effectiveBasalRate() / 60
            missedUnitsFromLowGlucose += unitsPerMinute
            print("SMB-Basal: Glucose below threshold, skipping pulse. Missed units: \(missedUnitsFromLowGlucose)")
            return
        }

        // Use OpenAPS suggested temp basal as effective basal when option is enabled; otherwise use scheduled basal
        let effectiveRate = effectiveBasalRate()
        if effectiveRate <= 0 {
            return // pause pulses (e.g., hypo protection or zero suggestion)
        }

        let unitsPerMinute = effectiveRate / 60
        accumulatorUnits += unitsPerMinute

        // Reset missed units counter when glucose is above threshold
        if missedUnitsFromLowGlucose > 0 {
            print("SMB-Basal: Glucose above threshold, resetting missed units counter (was \(missedUnitsFromLowGlucose))")
            missedUnitsFromLowGlucose = 0
        }

        let minIntervalMinutes = max(1, Int(truncating: settingsManager.preferences.smbInterval as NSNumber))
        let now = Date()
        if let last = lastPulseAt, now.timeIntervalSince(last) < Double(minIntervalMinutes * 60) {
            return
        }

        // Add compensation units to current accumulator
        let totalUnitsToDeliver = accumulatorUnits + compensationUnits

        if totalUnitsToDeliver >= step {
            // Deliver one step and keep remainder to avoid jitter
            deliverPulse(units: step) { [weak self] success in
                guard let self = self else { return }
                if success {
                    // Successful delivery - deduct from both accumulator and compensation
                    if self.compensationUnits > 0 {
                        let compensationUsed = min(step, self.compensationUnits)
                        self.compensationUnits -= compensationUsed
                        let accumulatorUsed = step - compensationUsed
                        self.accumulatorUnits -= accumulatorUsed
                        print("SMB-Basal: Delivered \(step) U (compensation: \(compensationUsed) U, new: \(accumulatorUsed) U)")
                    } else {
                        self.accumulatorUnits -= step
                    }
                    self.lastPulseAt = Date()
                } else {
                    // Failed delivery already recorded in deliverPulse method
                    print("SMB-Basal: Pulse delivery failed, added to compensation queue")
                }
            }
        }
    }

    // MARK: - Helpers

    private func maintainZeroTempBasalIfNeeded() {
        // Always enforce 0 U/h while SMB-basal is active
        if isCurrentTempBasalZero() {
            return
        }
        apsManager.enactTempBasal(rate: 0, duration: TimeInterval(30 * 60))
        lastZeroBasalSetAt = Date()
    }

    private func isCurrentTempBasalZero() -> Bool {
        // Get current temp basal state from storage (same as APSManager uses)
        guard let temp = storage.retrieve(OpenAPS.Monitor.tempBasal, as: TempBasal.self) else {
            print("SMB-Basal: No temp basal found in storage, assuming not zero")
            return false
        }

        let now = Date()
        let delta = Int((now.timeIntervalSince1970 - temp.timestamp.timeIntervalSince1970) / 60)
        let remainingDuration = max(0, temp.duration - delta)

        // If temp basal expired, it's not zero anymore
        guard remainingDuration > 0 else {
            print("SMB-Basal: Temp basal expired, not zero anymore")
            return false
        }

        // Check if rate is zero (within small tolerance)
        let isZero = abs(temp.rate) < 0.01
        print("SMB-Basal: Current temp basal rate: \(temp.rate) U/h, remaining: \(remainingDuration) min, isZero: \(isZero)")
        return isZero
    }

    private func currentScheduledBasalRate() -> Decimal {
        // Use app basal profile from storage (same as editors/UI)
        guard let profile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self), !profile.isEmpty else {
            return 0
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: Date())
        let minutesNow = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        var current: BasalProfileEntry = profile[0]
        for item in profile.sorted(by: { $0.minutes < $1.minutes }) {
            if item.minutes <= minutesNow { current = item } else { break }
        }
        return current.rate
    }

    private func optionalBolusStep() -> Decimal? {
        let step = settingsManager.preferences.bolusIncrement
        return step > 0 ? step : nil
    }

    private func effectiveBasalRate() -> Decimal {
        if settingsManager.settings.useOpenAPSForTempBasalWhenSmbBasal,
           let suggestion = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self),
           let rate = suggestion.rate
        {
            if let ts = suggestion.timestamp, Date().timeIntervalSince(ts) <= 20 * 60 {
                return rate
            } else {
                print("SMB-Basal: suggestion is stale (>20 min), fallback to 0 U/h")
                return 0
            }
        }
        return currentScheduledBasalRate()
    }

    private func deliverPulse(units: Decimal, completion: @escaping (Bool) -> Void) {
        let amount = Double(truncating: units as NSNumber)

        // Check for obvious failure conditions before attempting delivery
        guard let pumpManager = apsManager.pumpManager else {
            print("SMB-Basal: No pump manager available")
            // Record failure after method is defined
            workQueue.async { [weak self] in
                self?.recordFailedPulse(units: units, reason: .pumpError)
            }
            completion(false)
            return
        }

        // Check if pump is suspended
        if case .suspended = pumpManager.status.basalDeliveryState {
            print("SMB-Basal: Pump is suspended, cannot deliver pulse")
            workQueue.async { [weak self] in
                self?.recordFailedPulse(units: units, reason: .pumpSuspended)
            }
            completion(false)
            return
        }

        // Check if bolus is already in progress
        if case .inProgress = pumpManager.status.bolusState {
            print("SMB-Basal: Bolus already in progress, cannot deliver pulse")
            workQueue.async { [weak self] in
                self?.recordFailedPulse(units: units, reason: .bolusInProgress)
            }
            completion(false)
            return
        }

        // Check battery level
        if let batteryLevel = pumpManager.status.pumpBatteryChargeRemaining, batteryLevel < 0.1 {
            print("SMB-Basal: Low battery (\(Int(batteryLevel * 100))%), cannot deliver pulse")
            workQueue.async { [weak self] in
                self?.recordFailedPulse(units: units, reason: .lowBattery)
            }
            completion(false)
            return
        }

        // Attempt delivery
        apsManager.enactBolus(amount: amount, isSMB: true, isBasalReplacement: true)

        // For now, we assume success optimistically since we don't get immediate feedback
        // In a real implementation, we would wait for confirmation from the pump
        persistPulse(units: units)
        completion(true)
    }

    private func persistPulse(units: Decimal) {
        var pulses = storage.retrieve(OpenAPS.Monitor.smbBasalPulses, as: [SmbBasalPulse].self) ?? []
        pulses.append(SmbBasalPulse(id: UUID().uuidString, timestamp: Date(), units: units))
        storage.save(pulses.suffix(2000), as: OpenAPS.Monitor.smbBasalPulses) // keep recent history bounded
    }

    private func isGlucoseBelowThreshold() -> Bool {
        let recentGlucose = glucoseStorage.recent()
        guard !recentGlucose.isEmpty, let latestGlucose = recentGlucose.first else {
            print("SMB-Basal: No recent glucose data available")
            return true // Be conservative - suspend if no data
        }

        let thresholdMmol = settingsManager.settings.smbBasalGlucoseThreshold
        let currentGlucoseMmol: Decimal

        // Extract glucose value safely
        let glucoseValue: Double
        if let glucose = latestGlucose.glucose as? Double {
            glucoseValue = glucose
        } else if let glucose = latestGlucose.glucose as? Int {
            glucoseValue = Double(glucose)
        } else {
            print("SMB-Basal: Invalid glucose data type")
            return true // Be conservative - suspend if invalid data
        }

        // BloodGlucose.glucose is stored in mg/dL regardless of display units.
        // Always convert mg/dL -> mmol/L for threshold comparison.
        currentGlucoseMmol = Decimal(glucoseValue) / 18.0

        let isBelowThreshold = currentGlucoseMmol < thresholdMmol
        if isBelowThreshold {
            print("SMB-Basal: Current glucose \(currentGlucoseMmol) mmol/L is below threshold \(thresholdMmol) mmol/L")
        }

        return isBelowThreshold
    }

    // MARK: - Failed Pulse Management

    private func recordFailedPulse(units: Decimal, reason: FailedPulse.FailureReason) {
        let failedPulse = FailedPulse(
            id: UUID().uuidString,
            timestamp: Date(),
            units: units,
            reason: reason
        )

        failedPulses.append(failedPulse)
        print("SMB-Basal: Recorded failed pulse: \(units) U, reason: \(reason.rawValue)")

        // Clean up old failed pulses and update compensation units
        updateCompensationUnits()
    }

    private func updateCompensationUnits() {
        let maxMinutes = settingsManager.settings.smbBasalErrorCompensationMaxMinutes
        let cutoffTime = Date().addingTimeInterval(-Double(maxMinutes * 60))

        // Remove old failed pulses
        let validFailedPulses = failedPulses.filter { $0.timestamp > cutoffTime }
        failedPulses = validFailedPulses

        // Calculate total compensation units from valid failed pulses
        let totalCompensation = validFailedPulses.reduce(Decimal(0)) { $0 + $1.units }
        compensationUnits = totalCompensation

        print("SMB-Basal: Updated compensation units: \(compensationUnits) U from \(validFailedPulses.count) failed pulses")
    }

    private func getFailedPulsesInfo() -> (count: Int, totalUnits: Decimal, oldestAge: TimeInterval) {
        guard !failedPulses.isEmpty else {
            return (0, 0, 0)
        }

        let count = failedPulses.count
        let totalUnits = failedPulses.reduce(Decimal(0)) { $0 + $1.units }
        let oldestAge = Date().timeIntervalSince(failedPulses.first?.timestamp ?? Date())

        return (count, totalUnits, oldestAge)
    }

    // MARK: - Public API Implementation

    func currentBasalIob() -> SmbBasalIob {
        basalIobCalculator.calculateBasalIob(at: Date())
    }
}
