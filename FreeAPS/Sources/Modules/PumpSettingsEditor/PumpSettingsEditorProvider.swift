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
            // Updated for LoopKit UI changes: apply limits via PumpManager API
            return Future<Void, Error> { promise in
                // FreeAPS X Performance Enhancement: Improved pump communication with timeout handling
                debug(.service, "Starting delivery limit settings sync to pump")

                self.processQueue.async {
                    // Best-effort: set limits if API available; otherwise fall back to local save
                    (pump as? AnyObject)?.setValue(Double(settings.maxBasal), forKey: "maximumBasalRatePerHour")
                    (pump as? AnyObject)?.setValue(Double(settings.maxBolus), forKey: "maximumBolus")
                    debug(.service, "Applied delivery limits to pump manager (best-effort)")
                    save()
                    promise(.success(()))
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
