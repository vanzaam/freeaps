import Foundation
import HealthKit
import LoopKit

/// Адаптер для интеграции LoopKit CarbStore с OpenAPS
/// Обеспечивает безопасную работу с HealthKit и graceful fallback
class CarbStoreAdapter {
    private let carbStore: CarbStore

    // MARK: - Initialization

    init(healthStore: HKHealthStore? = nil, observeHealthKitData: Bool = true) {
        let healthStore = healthStore ?? HKHealthStore()

        // Проверить доступность HealthKit
        if !HKHealthStore.isHealthDataAvailable() {
            warning(.service, "HealthKit not available, using local storage only")
        }

        let healthKitSampleStore = HealthKitSampleStore(
            healthStore: healthStore,
            type: HealthKitSampleStore.carbType,
            observationEnabled: observeHealthKitData && HKHealthStore.isHealthDataAvailable()
        )

        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let persistenceController = PersistenceController(directoryURL: appSupportDirectory)

        carbStore = CarbStore(
            healthKitSampleStore: healthKitSampleStore,
            cacheStore: persistenceController,
            cacheLength: .hours(24),
            defaultAbsorptionTimes: (fast: .minutes(15), medium: .minutes(30), slow: .hours(1)),
            provenanceIdentifier: Bundle.main.bundleIdentifier!
        )

        info(
            .service,
            "CarbStoreAdapter initialized with HealthKit: \(observeHealthKitData && HKHealthStore.isHealthDataAvailable())"
        )
    }

    // MARK: - Public Methods

    /// Получить экземпляр CarbStore
    func getCarbStore() -> CarbStore {
        carbStore
    }

    /// Проверить доступность HealthKit
    func isHealthKitAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Запросить разрешения HealthKit
    func requestHealthKitPermissions() async -> Bool {
        guard isHealthKitAvailable() else {
            warning(.service, "HealthKit not available")
            return false
        }

        let healthStore = HKHealthStore()

        // Запросить разрешения для углеводов
        let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!
        let readTypes: Set<HKObjectType> = [carbType]
        let writeTypes: Set<HKSampleType> = [carbType]

        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
            info(.service, "HealthKit permissions granted")
            return true
        } catch let err {
            error(.service, "Failed to request HealthKit permissions: \(err.localizedDescription)")
            return false
        }
    }

    /// Получить статус разрешений HealthKit
    func getHealthKitAuthorizationStatus() -> HKAuthorizationStatus {
        guard isHealthKitAvailable() else {
            return .notDetermined
        }

        let carbType = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates)!
        return HKHealthStore().authorizationStatus(for: carbType)
    }

    /// Создать CarbStore с настройками по умолчанию
    static func createDefault() -> CarbStore {
        let healthStore = HKHealthStore()
        let healthKitSampleStore = HealthKitSampleStore(
            healthStore: healthStore,
            type: HealthKitSampleStore.carbType,
            observationEnabled: HKHealthStore.isHealthDataAvailable()
        )

        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let persistenceController = PersistenceController(directoryURL: appSupportDirectory)

        return CarbStore(
            healthKitSampleStore: healthKitSampleStore,
            cacheStore: persistenceController,
            cacheLength: .hours(24),
            defaultAbsorptionTimes: (fast: .minutes(15), medium: .minutes(30), slow: .hours(1)),
            provenanceIdentifier: Bundle.main.bundleIdentifier!
        )
    }
}

// MARK: - Extensions

extension CarbStoreAdapter {
    /// Получить информацию о CarbStore
    func getStoreInfo() -> [String: Any] {
        [
            "healthKitAvailable": isHealthKitAvailable(),
            "authorizationStatus": getHealthKitAuthorizationStatus().rawValue,
            "observeHealthKitData": true // TODO: Get from CarbStore configuration
        ]
    }
}
