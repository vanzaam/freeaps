import Combine
import LoopKit
import LoopKitUI

protocol PumpSettingsObserver {
    func pumpSettingsDidChange(_ pumpSettings: PumpSettings)
}

extension PumpSettingsEditor {
    final class Provider: BaseProvider, PumpSettingsEditorProvider {
        private let processQueue = DispatchQueue(label: "PumpSettingsEditorProvider.processQueue")
        @Injected() private var broadcaster: Broadcaster!

        func settings() -> PumpSettings {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 5, maxBolus: 10, maxBasal: 2)
        }

        func save(settings: PumpSettings) -> AnyPublisher<Void, Error> {
            func save() {
                storage.save(settings, as: OpenAPS.Settings.settings)
                processQueue.async {
                    self.broadcaster.notify(PumpSettingsObserver.self, on: self.processQueue) {
                        $0.pumpSettingsDidChange(settings)
                    }
                }
            }

            guard let pump = deviceManager?.pumpManager else {
                save()
                return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
            // Don't ask why 🤦‍♂️
            let sync = DeliveryLimitSettingsTableViewController(style: .grouped)
            sync.maximumBasalRatePerHour = Double(settings.maxBasal)
            sync.maximumBolus = Double(settings.maxBolus)
            return Future<Void, Error> { promise in
                // FreeAPS X Performance Enhancement: Improved pump communication with timeout handling
                debug(.service, "Starting delivery limit settings sync to pump")

                self.processQueue.async {
                    pump.syncDeliveryLimitSettings(for: sync) { result in
                        switch result {
                        case .success:
                            debug(.service, "Delivery limit settings sync successful")
                            save()
                            promise(.success(()))
                        case let .failure(error):
                            warning(.service, "Delivery limit settings sync failed", error: error)
                            // Still save locally even if pump sync fails
                            save()
                            promise(.failure(error))
                        }
                    }
                }
            }
            .timeout(60, scheduler: processQueue) // 60 second timeout to prevent hangs
            .catch { (error: Error) -> AnyPublisher<Void, Error> in
                // Handle timeout and other errors gracefully
                warning(.service, "Delivery limit settings operation failed: \(error)")
                save() // Always save locally
                return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
        }
    }
}
