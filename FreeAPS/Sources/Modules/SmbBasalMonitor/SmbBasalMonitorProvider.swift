import Foundation

extension SmbBasalMonitor {
    final class Provider: BaseProvider, SmbBasalMonitorProvider {
        var basalProfile: [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                ?? []
        }
    }
}

protocol SmbBasalMonitorProvider: Provider {
    var basalProfile: [BasalProfileEntry] { get }
}
