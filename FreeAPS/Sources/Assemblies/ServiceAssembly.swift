import Foundation
import HealthKit
import LoopKit
import Swinject

final class ServiceAssembly: Assembly {
    func assemble(container: Container) {
        container.register(NotificationCenter.self) { _ in Foundation.NotificationCenter.default }
        container.register(Broadcaster.self) { _ in BaseBroadcaster() }
        container.register(GroupedIssueReporter.self) { _ in
            let reporter = CollectionIssueReporter()
            reporter.add(reporters: [
                SimpleLogReporter()
            ])
            reporter.setup()
            return reporter
        }
        container.register(CalendarManager.self) { r in BaseCalendarManager(resolver: r) }
        container.register(HKHealthStore.self) { _ in HKHealthStore() }
        container.register(HealthKitManager.self) { r in BaseHealthKitManager(resolver: r) }
        container.register(UserNotificationsManager.self) { r in BaseUserNotificationsManager(resolver: r) }
        container.register(WatchManager.self) { r in BaseWatchManager(resolver: r) }

        // MARK: - Carb Management Services

        // CarbStore (LoopKit)
        container.register(CarbStore.self) { _ in
            // HealthKit sample store for carbs
            let hkStore = HKHealthStore()
            let hkSampleStore = HealthKitSampleStore(
                healthStore: hkStore,
                observeHealthKitSamplesFromCurrentApp: true,
                observeHealthKitSamplesFromOtherApps: true,
                type: HealthKitSampleStore.carbType,
                observationStart: nil,
                observationEnabled: true
            )

            // Persistence cache
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let cacheDir = appSupport.appendingPathComponent("OpenAPS.Cache", isDirectory: true)
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let cache = PersistenceController(directoryURL: cacheDir, isReadOnly: false)

            // Default absorption times (fast, medium, slow)
            let defaultAbsorption: CarbStore.DefaultAbsorptionTimes = (
                fast: TimeInterval(15 * 60),
                medium: TimeInterval(30 * 60),
                slow: TimeInterval(60 * 60)
            )

            // Cache length: keep at least two slow windows
            let cacheLength: TimeInterval = max(defaultAbsorption.slow * 2, TimeInterval(24 * 3600))

            return CarbStore(
                healthKitSampleStore: hkSampleStore,
                cacheStore: cache,
                cacheLength: cacheLength,
                defaultAbsorptionTimes: defaultAbsorption,
                carbRatioSchedule: nil,
                insulinSensitivitySchedule: nil,
                overrideHistory: nil,
                syncVersion: 1,
                absorptionTimeOverrun: CarbMath.defaultAbsorptionTimeOverrun,
                calculationDelta: GlucoseMath.defaultDelta,
                effectDelay: CarbMath.defaultEffectDelay,
                carbAbsorptionModel: .nonlinear,
                provenanceIdentifier: "OpenAPS"
            )
        }.inObjectScope(.container)

        // CarbAccountingService - простая синхронная регистрация
        container.register(CarbAccountingService.self) { r in
            let carbStore = r.resolve(CarbStore.self)!
            return CarbAccountingService(carbStore: carbStore) {
                // Resolve fresh NightscoutAPI each time from Keychain-backed registration
                r.resolve(NightscoutAPI.self)
            }
        }.inObjectScope(.container)

        // CarbStoreAdapter
        container.register(CarbStoreAdapter.self) { _ in
            CarbStoreAdapter()
        }.inObjectScope(.container)

        // NightscoutCarbSync
        container.register(NightscoutCarbSync.self) { r in
            let nightscoutAPI = r.resolve(NightscoutAPI.self)!
            return NightscoutCarbSync(nightscoutAPI: nightscoutAPI)
        }.inObjectScope(.container)

        // SMBAdapter
        container.register(SMBAdapter.self) { r in
            let carbService = r.resolve(CarbAccountingService.self)!
            let glucoseStorage = r.resolve(GlucoseStorage.self)!
            let settingsManager = r.resolve(SettingsManager.self)!
            let storage = r.resolve(FileStorage.self)!
            return SMBAdapter(
                carbService: carbService,
                glucoseStorage: glucoseStorage,
                settingsManager: settingsManager,
                storage: storage
            )
        }.inObjectScope(.container)
    }
}
