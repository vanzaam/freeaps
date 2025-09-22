import LoopKit
import LoopKitUI
import MinimedKit
import SwiftUI
import UIKit

extension PumpConfig {
    struct PumpSettingsView: UIViewControllerRepresentable {
        let pumpManager: PumpManagerUI
        var completionDelegate: CompletionDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSettingsView>) -> UIViewController {
            // Set high priority refresh when user opens pump settings
            // This ensures faster response to manual pump state changes (30s vs 60s)
            if let minimed = pumpManager as? MinimedPumpManager {
                minimed.setSuspendRefreshPriority(.high)
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

    // Простая обёртка для закрытия fullScreenCover по завершению настроек
    final class PumpSettingsCompletion: NSObject, CompletionDelegate {
        private let onComplete: () -> Void
        init(_ onComplete: @escaping () -> Void) { self.onComplete = onComplete }
        func completionNotifyingDidComplete(_: CompletionNotifying) { onComplete() }
    }
}
