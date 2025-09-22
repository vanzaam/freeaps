import Foundation

/// Global runtime flags read from Info.plist / xcconfig.
enum AppRuntimeConfig {
    /// If true, verbose debug logs are enabled. Controlled via APP_DEBUG_LOGS in Info.plist.
    static var debugLogsEnabled: Bool = {
        if let flag = Bundle.main.object(forInfoDictionaryKey: "APP_DEBUG_LOGS") as? String {
            return (flag as NSString).boolValue
        }
        if let flag = Bundle.main.object(forInfoDictionaryKey: "APP_DEBUG_LOGS") as? NSNumber {
            return flag.boolValue
        }
        return false
    }()

    /// If true, the app must use LoopKit engine instead of OpenAPS JS.
    /// Now reads from user settings instead of Info.plist.
    static var useLoopEngine: Bool {
        // Читаем из настроек пользователя
        if let storage = try? BaseFileStorage() {
            if let settings = storage.retrieve(OpenAPS.FreeAPS.settings, as: FreeAPSSettings.self) {
                return settings.apsAlgorithm == .loopKit
            }
        }

        // Fallback на Info.plist если настройки недоступны
        if let flag = Bundle.main.object(forInfoDictionaryKey: "USE_LOOP_ENGINE") as? String {
            let upper = flag.uppercased()
            if upper == "YES" || upper == "TRUE" { return true }
            if upper == "NO" || upper == "FALSE" { return false }
            return (flag as NSString).boolValue
        }
        if let flag = Bundle.main.object(forInfoDictionaryKey: "USE_LOOP_ENGINE") as? NSNumber {
            return flag.boolValue
        }
        // Safe default: enable Loop engine
        return true
    }
}
