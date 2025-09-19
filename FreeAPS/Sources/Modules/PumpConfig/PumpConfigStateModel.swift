import Foundation
import LoopKit
import LoopKitUI
import SwiftDate
import SwiftUI

extension PumpConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var setupPump = false
        private(set) var setupPumpType: PumpType = .minimed
        @Published var pumpState: PumpDisplayState?
        private(set) var initialSettings: PumpInitialSettings = .default
        private var basalObserver: NSObjectProtocol?

        override func subscribe() {
            provider.pumpDisplayState
                .receive(on: DispatchQueue.main)
                .assign(to: \.pumpState, on: self)
                .store(in: &lifetime)

            let basalSchedule = BasalRateSchedule(
                dailyItems: provider.basalProfile().map {
                    RepeatingScheduleValue(startTime: $0.minutes.minutes.timeInterval, value: Double($0.rate))
                }
            )

            let pumpSettings = provider.pumpSettings()

            initialSettings = PumpInitialSettings(
                maxBolusUnits: Double(pumpSettings.maxBolus),
                maxBasalRateUnitsPerHour: Double(pumpSettings.maxBasal),
                basalSchedule: basalSchedule!
            )

            // Refresh initial settings if a clamped basal profile is imported during onboarding
            basalObserver = Foundation.NotificationCenter.default.addObserver(
                forName: Notification.Name("FreeAPS.MinimedClampedBasal"),
                object: nil,
                queue: OperationQueue.main,
                using: { [weak self] _ in
                    guard let self = self else { return }
                    let updated = BasalRateSchedule(
                        dailyItems: self.provider.basalProfile().map {
                            RepeatingScheduleValue(startTime: $0.minutes.minutes.timeInterval, value: Double($0.rate))
                        }
                    )
                    let settings = self.provider.pumpSettings()
                    self.initialSettings = PumpInitialSettings(
                        maxBolusUnits: Double(settings.maxBolus),
                        maxBasalRateUnitsPerHour: Double(settings.maxBasal),
                        basalSchedule: updated!
                    )
                }
            )
        }

        deinit {
            if let obs = basalObserver {
                Foundation.NotificationCenter.default.removeObserver(obs)
            }
        }

        func addPump(_ type: PumpType) {
            setupPump = true
            setupPumpType = type
        }
    }
}

extension PumpConfig.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupPump = false
    }
}

extension PumpConfig.StateModel: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        provider.setPumpManager(pumpManager)
        // Set default desired bolus step to 0.05 for a new pump
        settingsManager.updatePreferences { prefs in
            prefs.bolusIncrement = 0.05
        }
        setupPump = false
    }

    func pumpManagerOnboarding(didOnboardPumpManager pumpManager: PumpManagerUI) {
        provider.setPumpManager(pumpManager)
        // Set default desired bolus step to 0.05 for a new pump
        settingsManager.updatePreferences { prefs in
            prefs.bolusIncrement = 0.05
        }
        setupPump = false
    }

    func pumpManagerOnboarding(didPauseOnboarding _: PumpManagerUI) {
        // no-op
    }
}
