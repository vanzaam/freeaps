import LoopKit
import LoopKitUI
import MinimedKit
import SwiftUI
import UIKit

extension PumpConfig {
    struct PumpSettingsView: UIViewControllerRepresentable {
        let pumpManager: PumpManagerUI
        weak var completionDelegate: CompletionDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSettingsView>) -> UIViewController {
            // Ensure current pump data when user opens pump settings
            // This provides up-to-date information for the user interface
            if let minimed = pumpManager as? MinimedPumpManager {
                minimed.ensureCurrentPumpData { _ in
                    // Pump data refreshed for settings view
                }
            }

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
            var vc = pumpManager.settingsViewController(
                bluetoothProvider: DefaultBluetoothProvider.shared,
                colorPalette: palette,
                allowDebugFeatures: true,
                allowedInsulinTypes: InsulinType.allCases
            )
            vc.completionDelegate = completionDelegate
            return vc
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSettingsView>) {}
    }
}
