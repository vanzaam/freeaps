import LoopKit
import LoopKitUI

extension PumpManager {
    var rawValue: [String: Any] {
        [
            "pluginIdentifier": pluginIdentifier,
            "state": rawState
        ]
    }
}

extension PumpManagerUI {
    static func setupUI(
        initialSettings settings: PumpManagerSetupSettings,
        bluetoothProvider: BluetoothProvider,
        colorPalette: LoopUIColorPalette,
        allowDebugFeatures: Bool,
        allowedInsulinTypes: [InsulinType]
    ) -> SetupUIResult<PumpManagerViewController, PumpManagerUI> {
        setupViewController(
            initialSettings: settings,
            bluetoothProvider: bluetoothProvider,
            colorPalette: colorPalette,
            allowDebugFeatures: allowDebugFeatures,
            prefersToSkipUserInteraction: false,
            allowedInsulinTypes: allowedInsulinTypes
        )
    }

    func settingsViewController(
        bluetoothProvider: BluetoothProvider,
        colorPalette: LoopUIColorPalette,
        allowDebugFeatures: Bool,
        allowedInsulinTypes: [InsulinType]
    ) -> UIViewController & CompletionNotifying {
        settingsViewController(
            bluetoothProvider: bluetoothProvider,
            colorPalette: colorPalette,
            allowDebugFeatures: allowDebugFeatures,
            allowedInsulinTypes: allowedInsulinTypes
        )
    }
}

protocol PumpSettingsBuilder {
    func settingsViewController(
        bluetoothProvider: BluetoothProvider,
        colorPalette: LoopUIColorPalette,
        allowDebugFeatures: Bool,
        allowedInsulinTypes: [InsulinType]
    ) -> UIViewController & CompletionNotifying
}
