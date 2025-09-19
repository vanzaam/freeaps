import HealthKit
import LoopKit
import LoopKitUI
import MedtrumKit
import MinimedKit
import MinimedKitUI
import MockKit
import MockKitUI
import OmniBLE
import OmniKit
import OmniKitUI
import SwiftUI
import UIKit

extension PumpConfig {
    struct PumpSetupView: UIViewControllerRepresentable {
        let pumpType: PumpType
        let pumpInitialSettings: PumpInitialSettings
        weak var completionDelegate: CompletionDelegate?
        weak var setupDelegate: PumpManagerOnboardingDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSetupView>) -> UIViewController {
            // New API returns SetupUIResult<PumpManagerViewController, PumpManagerUI>
            let bluetoothProvider = DefaultBluetoothProvider.shared
            let palette = LoopUIColorPalette(
                guidanceColors: GuidanceColors(),
                carbTintColor: .orange,
                glucoseTintColor: .green,
                insulinTintColor: .blue,
                loopStatusColorPalette: StateColorPalette(
                    unknown: .gray,
                    normal: .systemGreen,
                    warning: .systemYellow,
                    error: .systemRed
                ),
                chartColorPalette: ChartColorPalette(
                    axisLine: .clear,
                    axisLabel: .secondaryLabel,
                    grid: .tertiaryLabel,
                    glucoseTint: .systemGreen,
                    insulinTint: .systemBlue,
                    carbTint: .systemOrange
                )
            )

            let settings = PumpManagerSetupSettings(
                maxBasalRateUnitsPerHour: pumpInitialSettings.maxBasalRateUnitsPerHour,
                maxBolusUnits: pumpInitialSettings.maxBolusUnits,
                basalSchedule: pumpInitialSettings.basalSchedule
            )

            // OpenAPS: use conservative defaults; actual pump limits are preserved (no forcing)
            let minimedSettings = PumpManagerSetupSettings(
                maxBasalRateUnitsPerHour: 2,
                maxBolusUnits: 10,
                basalSchedule: pumpInitialSettings.basalSchedule
            )

            let result: SetupUIResult<PumpManagerViewController, PumpManagerUI>
            switch pumpType {
            case .minimed:
                result = MinimedPumpManager.setupViewController(
                    initialSettings: minimedSettings,
                    bluetoothProvider: bluetoothProvider,
                    colorPalette: palette,
                    allowDebugFeatures: true,
                    prefersToSkipUserInteraction: false,
                    allowedInsulinTypes: InsulinType.allCases
                )
            case .medtrum:
                result = MedtrumPumpManager.setupViewController(
                    initialSettings: settings,
                    bluetoothProvider: bluetoothProvider,
                    colorPalette: palette,
                    allowDebugFeatures: true,
                    prefersToSkipUserInteraction: false,
                    allowedInsulinTypes: InsulinType.allCases
                )
            case .omnipod:
                result = OmnipodPumpManager.setupViewController(
                    initialSettings: settings,
                    bluetoothProvider: bluetoothProvider,
                    colorPalette: palette,
                    allowDebugFeatures: true,
                    prefersToSkipUserInteraction: false,
                    allowedInsulinTypes: InsulinType.allCases
                )
            case .omnipodDash:
                result = OmniBLEPumpManager.setupViewController(
                    initialSettings: settings,
                    bluetoothProvider: bluetoothProvider,
                    colorPalette: palette,
                    allowDebugFeatures: true,
                    prefersToSkipUserInteraction: false,
                    allowedInsulinTypes: InsulinType.allCases
                )
            case .simulator:
                result = MockPumpManager.setupViewController(
                    initialSettings: settings,
                    bluetoothProvider: bluetoothProvider,
                    colorPalette: palette,
                    allowDebugFeatures: true,
                    prefersToSkipUserInteraction: false,
                    allowedInsulinTypes: InsulinType.allCases
                )
            }

            switch result {
            case var .userInteractionRequired(vc):
                vc.pumpManagerOnboardingDelegate = setupDelegate
                vc.completionDelegate = completionDelegate
                return vc
            case let .createdAndOnboarded(manager):
                // Defer delegate notifications to the next runloop to avoid publishing changes during view updates
                DispatchQueue.main.async {
                    // Preserve pump limits; do not force changes here
                    setupDelegate?.pumpManagerOnboarding(didCreatePumpManager: manager)
                    setupDelegate?.pumpManagerOnboarding(didOnboardPumpManager: manager)
                    // No actual VC to notify; wrap in a dummy notifier to satisfy delegate
                    final class DummyNotifier: CompletionNotifying {
                        weak var completionDelegate: CompletionDelegate?
                    }
                    let dummy = DummyNotifier()
                    dummy.completionDelegate = completionDelegate
                    completionDelegate?.completionNotifyingDidComplete(dummy)
                }
                return UIViewController()
            }
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSetupView>) {}
    }
}
