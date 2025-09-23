import Foundation
import LoopKit
import Swinject

protocol SmbBasalIobCalculator: AnyObject {
    func calculateBasalIob(at date: Date) -> SmbBasalIob
}

final class BaseSmbBasalIobCalculator: SmbBasalIobCalculator, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var settingsManager: SettingsManager!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func calculateBasalIob(at date: Date = Date()) -> SmbBasalIob {
        let pulses = storage.retrieve(OpenAPS.Monitor.smbBasalPulses, as: [SmbBasalPulse].self) ?? []

        guard !pulses.isEmpty else {
            return SmbBasalIob(iob: 0, timestamp: date, activePulses: 0, oldestPulseAge: 0)
        }

        let insulinModel = currentInsulinModel()
        let effectDuration = insulinModel.effectDuration

        let now = date
        var totalIob: Double = 0
        var activePulses = 0
        var oldestActiveAge: TimeInterval = 0

        for pulse in pulses {
            let ageSeconds = now.timeIntervalSince(pulse.timestamp)
            let ageMinutes = ageSeconds / 60

            // Skip pulses older than insulin effect duration
            guard ageSeconds >= 0, ageSeconds <= effectDuration else { continue }

            let remainingPercentage = insulinModel.percentEffectRemaining(at: ageSeconds)
            let remainingIob = Double(truncating: pulse.units as NSNumber) * remainingPercentage

            if remainingIob > 0.001 { // Only count meaningful amounts
                totalIob += remainingIob
                activePulses += 1
                oldestActiveAge = max(oldestActiveAge, ageMinutes)
            }
        }

        return SmbBasalIob(
            iob: Decimal(totalIob),
            timestamp: now,
            activePulses: activePulses,
            oldestPulseAge: oldestActiveAge
        )
    }

    // MARK: - Private

    private func currentInsulinModel() -> ExponentialInsulinModel {
        let preferences = settingsManager.preferences

        switch preferences.curve {
        case .rapidActing:
            let peakTime = preferences.useCustomPeakTime ?
                TimeInterval(Double(truncating: preferences.insulinPeakTime as NSNumber) * 60) :
                TimeInterval(minutes: 75)
            return ExponentialInsulinModel(
                actionDuration: TimeInterval(hours: 6),
                peakActivityTime: peakTime,
                delay: TimeInterval(minutes: 10)
            )

        case .ultraRapid:
            let peakTime = preferences.useCustomPeakTime ?
                TimeInterval(Double(truncating: preferences.insulinPeakTime as NSNumber) * 60) :
                TimeInterval(minutes: 55)
            return ExponentialInsulinModel(
                actionDuration: TimeInterval(hours: 5),
                peakActivityTime: peakTime,
                delay: TimeInterval(minutes: 10)
            )

        case .bilinear:
            // For bilinear, we'll use the same approach but with rapid-acting defaults
            return ExponentialInsulinModel(
                actionDuration: TimeInterval(hours: 6),
                peakActivityTime: TimeInterval(minutes: 75),
                delay: TimeInterval(minutes: 10)
            )
        }
    }
}
