import Combine
import Foundation
import Swinject

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

    private let workQueue = DispatchQueue(label: "SmbBasalManager.queue", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lifetime = Lifetime()

    private var accumulatorUnits: Decimal = 0
    private var lastPulseAt: Date?
    private var lastZeroBasalSetAt: Date?

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
            self.setupTimer()
        }
    }

    func stop() {
        workQueue.async {
            self.timer?.cancel()
            self.timer = nil
            self.accumulatorUnits = 0
            self.lastPulseAt = nil
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

        print("SMB-Basal: tick() - processing basal replacement")

        // 1) Ensure zero temp basal is maintained (30 min window, refresh every 25 min)
        maintainZeroTempBasalIfNeeded()

        // 2) Accumulate basal dose and fire step boluses when enough units are accumulated
        guard let step = optionalBolusStep(), step > 0 else { return }

        let unitsPerMinute = currentScheduledBasalRate() / 60
        accumulatorUnits += unitsPerMinute

        let minIntervalMinutes = max(1, Int(truncating: settingsManager.preferences.smbInterval as NSNumber))
        let now = Date()
        if let last = lastPulseAt, now.timeIntervalSince(last) < Double(minIntervalMinutes * 60) {
            return
        }

        if accumulatorUnits >= step {
            // Deliver one step and keep remainder to avoid jitter
            deliverPulse(units: step) { [weak self] success in
                guard let self = self else { return }
                if success {
                    self.accumulatorUnits -= step
                    self.lastPulseAt = Date()
                }
            }
        }
    }

    // MARK: - Helpers

    private func maintainZeroTempBasalIfNeeded() {
        let now = Date()

        // Check every 5 minutes instead of every 25 minutes
        if let last = lastZeroBasalSetAt, now.timeIntervalSince(last) < TimeInterval(5 * 60) {
            return
        }

        // Check if current temp basal is already 0 U/h
        if isCurrentTempBasalZero() {
            print("SMB-Basal: Current temp basal is already 0 U/h, skipping")
            lastZeroBasalSetAt = now // Update timer even if we skip
            return
        }

        // Set zero temp basal for 30 minutes if not already zero
        print("SMB-Basal: Current temp basal is NOT zero, setting zero temp basal for 30 minutes")
        apsManager.enactTempBasal(rate: 0, duration: TimeInterval(30 * 60))
        print("SMB-Basal: Zero temp basal command sent")
        lastZeroBasalSetAt = now
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

    private func deliverPulse(units: Decimal, completion: @escaping (Bool) -> Void) {
        let amount = Double(truncating: units as NSNumber)
        apsManager.enactBolus(amount: amount, isSMB: true, isBasalReplacement: true)
        // We don't get immediate completion callback from APSManager here; assume success optimistically and persist.
        persistPulse(units: units)
        completion(true)
    }

    private func persistPulse(units: Decimal) {
        var pulses = storage.retrieve(OpenAPS.Monitor.smbBasalPulses, as: [SmbBasalPulse].self) ?? []
        pulses.append(SmbBasalPulse(id: UUID().uuidString, timestamp: Date(), units: units))
        storage.save(pulses.suffix(2000), as: OpenAPS.Monitor.smbBasalPulses) // keep recent history bounded
    }

    // MARK: - Public API Implementation

    func currentBasalIob() -> SmbBasalIob {
        basalIobCalculator.calculateBasalIob(at: Date())
    }
}
