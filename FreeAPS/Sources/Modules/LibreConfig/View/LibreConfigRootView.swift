import HealthKit
import LibreTransmitter
import LibreTransmitterUI
import LoopKit
import LoopKitUI
import SwiftUI
import Swinject

extension LibreConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            Group {
                if state.configured, let manager = state.source.manager {
                    LibreSettingsView(manager: manager) {
                        self.state.source.manager = nil
                        self.state.configured = false
                    } completion: {
                        state.hideModal()
                    }
                } else {
                    LibreSetupView(unit: state.unit) { manager in
                        self.state.source.manager = manager
                        self.state.configured = true
                    } completion: {
                        state.hideModal()
                    }
                }
            }
            .navigationBarTitle("")
            .navigationBarHidden(true)
            .onAppear(perform: configureView)
        }
    }
}

// MARK: - UIKit bridges

private struct LibreSetupView: UIViewControllerRepresentable {
    let unit: HKUnit
    let created: (LibreTransmitterManagerV3) -> Void
    let completion: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let bluetooth = DefaultBluetoothProvider.shared
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

        let displayPref = DisplayGlucosePreference(displayGlucoseUnit: unit)
        let result = LibreTransmitterManagerV3.setupViewController(
            bluetoothProvider: bluetooth,
            displayGlucosePreference: displayPref,
            colorPalette: palette,
            allowDebugFeatures: true,
            prefersToSkipUserInteraction: false
        )

        switch result {
        case var .userInteractionRequired(vc):
            vc.completionDelegate = context.coordinator
            return vc
        case let .createdAndOnboarded(manager):
            if let m = manager as? LibreTransmitterManagerV3 { created(m) }
            // Return empty VC; caller will dismiss
            return UIViewController()
        }
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(created: created, completion: completion) }

    final class Coordinator: NSObject, CompletionDelegate {
        let created: (LibreTransmitterManagerV3) -> Void
        let completion: () -> Void
        init(created: @escaping (LibreTransmitterManagerV3) -> Void, completion: @escaping () -> Void) {
            self.created = created
            self.completion = completion
        }

        func completionNotifyingDidComplete(_: CompletionNotifying) {
            // Expect the VC to have created manager already
            completion()
        }
    }
}

private struct LibreSettingsView: UIViewControllerRepresentable {
    let manager: LibreTransmitterManagerV3
    let cleared: () -> Void
    let completion: () -> Void

    func makeUIViewController(context _: Context) -> UIViewController {
        let bluetooth = DefaultBluetoothProvider.shared
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
        let displayPref = DisplayGlucosePreference(displayGlucoseUnit: .millimolesPerLiter)
        let vc = manager.settingsViewController(
            bluetoothProvider: bluetooth,
            displayGlucosePreference: displayPref,
            colorPalette: palette,
            allowDebugFeatures: true
        )
        return vc
    }

    func updateUIViewController(_: UIViewController, context _: Context) {}
}
