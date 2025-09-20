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
}
