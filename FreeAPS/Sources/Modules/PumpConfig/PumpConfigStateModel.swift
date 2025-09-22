import Foundation
import LoopKit
import LoopKitUI
import MedtrumKit
import MinimedKit
import OmniBLE
import OmniKit
import SwiftDate
import SwiftUI

extension PumpConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var setupPump = false
        private(set) var setupPumpType: PumpType = .minimed
        @Published var pumpState: PumpDisplayState?
        private(set) var initialSettings: PumpInitialSettings = .default
        private var basalObserver: NSObjectProtocol?
        @Published var showInteractiveInsulinCurve = false

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
                forName: Notification.Name("OpenAPS.MinimedClampedBasal"),
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

// MARK: - Insulin Type helpers

extension PumpConfig.StateModel {
    func insulinTypeDisplay(for pumpManager: PumpManagerUI) -> String {
        // Try to read from status first (most accurate)
        if let statusType = pumpManager.status.insulinType {
            return statusType.brandName
        }
        // Fallback: read last persisted value saved by APSManager
        if let raw = provider.storage.retrieveRaw(OpenAPS.Settings.insulinType),
           let intVal = Int(raw),
           let t = InsulinType(rawValue: intVal)
        {
            return t.brandName
        }
        return "Unknown"
    }

    func canOpenInsulinTypeChooser(_ pumpManager: PumpManagerUI) -> Bool {
        pumpManager is OmniBLEPumpManager || pumpManager is OmnipodPumpManager || pumpManager is MedtrumPumpManager ||
            pumpManager is MinimedPumpManager
    }

    func openInsulinTypeChooser(_: PumpManagerUI) {
        // Leverage each manager's settings screen for changing insulin type
        setupPump = true
    }
}
