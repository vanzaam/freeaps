import Foundation
import Swinject

// MARK: - SMB-Basal Middleware Manager

protocol SmbBasalMiddleware: AnyObject {
    func setupMiddleware()
    func removeMiddleware()
}

final class BaseSmbBasalMiddleware: SmbBasalMiddleware, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var settingsManager: SettingsManager!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func setupMiddleware() {
        let middlewareScript = createSmbBasalMiddleware()
        storage.save(middlewareScript, as: OpenAPS.Middleware.determineBasal)
        print("SMB-Basal: Middleware installed successfully")
    }

    func removeMiddleware() {
        storage.remove(OpenAPS.Middleware.determineBasal)
        print("SMB-Basal: Middleware removed")
    }

    private func createSmbBasalMiddleware() -> String {
        return """
function middleware(iob, currenttemp, glucose, profile, autosens, meal, reservoir, clock) {
    // Check if SMB-basal is enabled in the profile
    if (profile && profile.smb_basal_enabled === true) {
        
        // ✅ SAFE: Only modify currenttemp to simulate basal coverage
        // This tells OpenAPS that basal is "already covered" by our SMB-basal system
        
        if (profile.current_basal && profile.current_basal > 0) {
            // Simulate that current basal rate is being delivered
            currenttemp.rate = profile.current_basal;
            currenttemp.duration = 30;  // 30 minutes coverage
            currenttemp.temp = "absolute";
            
            console.log("SMB-Basal Middleware: Simulated basal rate " + profile.current_basal + " U/h for 30 min");
            
            return "SMB-basal middleware: Simulated current basal " + profile.current_basal + " U/h, IOB unchanged";
        }
    }
    
    return "Nothing changed";
}
"""
    }
}
