import Foundation
import Swinject

final class NetworkAssembly: Assembly {
    func assemble(container: Container) {
        container.register(ReachabilityManager.self) { _ in
            NetworkReachabilityManager()!
        }

        container.register(NightscoutManager.self) { r in BaseNightscoutManager(resolver: r) }

        // Build NightscoutAPI from Keychain (fallback to localhost only if missing)
        container.register(NightscoutAPI.self) { r in
            let keychain = r.resolve(Keychain.self)
            if let urlString = keychain?.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
               let url = URL(string: urlString)
            {
                let secret = keychain?.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
                return NightscoutAPI(url: url, secret: secret)
            }
            // Fallback to placeholder if Keychain not configured yet
            return NightscoutAPI(url: URL(string: "http://localhost")!)
        }.inObjectScope(.transient)
    }
}
