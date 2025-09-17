import CoreBluetooth
import Foundation
import LoopKit
import MinimedKit
import RileyLinkBLEKit

final class DefaultBluetoothProvider: NSObject, BluetoothProvider {
    static let shared = DefaultBluetoothProvider()
    private let central: CBCentralManager
    private var observers: [(observer: BluetoothObserver, queue: DispatchQueue)] = []

    // Access to the same RileyLink device provider used by pump managers
    weak var rileyLinkDeviceProvider: RileyLinkDeviceProvider?

    override init() {
        central = CBCentralManager(delegate: nil, queue: nil)
        super.init()
        central.delegate = self
    }

    /// Set the RileyLink device provider to use the same instance as pump managers
    func setRileyLinkDeviceProvider(_ provider: RileyLinkDeviceProvider) {
        rileyLinkDeviceProvider = provider
    }

    var bluetoothAuthorization: BluetoothAuthorization {
        switch CBCentralManager.authorization {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .allowedAlways: return .authorized
        @unknown default: return .restricted
        }
    }

    var bluetoothState: BluetoothState {
        switch central.state {
        case .unknown: return .unknown
        case .resetting: return .resetting
        case .unsupported: return .unsupported
        case .unauthorized: return .unauthorized
        case .poweredOff: return .poweredOff
        case .poweredOn: return .poweredOn
        @unknown default: return .unknown
        }
    }

    func authorizeBluetooth(_ completion: @escaping (BluetoothAuthorization) -> Void) {
        // CBCentralManager prompts automatically upon usage; if already determined, return immediately
        if bluetoothAuthorization != .notDetermined {
            completion(bluetoothAuthorization)
        } else {
            // Trigger state evaluation; completion called when state updates
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                completion(self.bluetoothAuthorization)
            }
        }
    }

    func addBluetoothObserver(_ observer: BluetoothObserver, queue: DispatchQueue) {
        observers.append((observer: observer, queue: queue))
        // Notify current state immediately
        let state = bluetoothState
        queue.async { [weak observer] in
            observer?.bluetoothDidUpdateState(state)
        }
    }

    func removeBluetoothObserver(_ observer: BluetoothObserver) {
        observers.removeAll { $0.observer === observer }
    }
}

extension DefaultBluetoothProvider: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_: CBCentralManager) {
        let state = bluetoothState
        for entry in observers {
            entry.queue.async { [weak observer = entry.observer] in
                observer?.bluetoothDidUpdateState(state)
            }
        }
    }
}
