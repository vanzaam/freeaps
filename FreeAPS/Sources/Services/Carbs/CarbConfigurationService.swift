import Foundation

/// Сервис для управления конфигурацией системы углеводов
/// Позволяет переключаться между OpenAPS meal.js и Loop carb absorption
class CarbConfigurationService {
    // MARK: - Singleton

    static let shared = CarbConfigurationService()

    // MARK: - Private Properties

    // MARK: - Configuration Properties

    /// Использовать ли Loop систему углеводов
    var useLoopCarbAbsorption: Bool {
        getBoolValue(for: "USE_LOOP_CARB_ABSORPTION", defaultValue: true)
    }

    /// Скорость абсорбции по умолчанию
    var defaultAbsorptionSpeed: AbsorptionSpeed {
        let speedString = getStringValue(for: "CARB_ABSORPTION_DEFAULT_SPEED", defaultValue: "medium")
        return AbsorptionSpeed(rawValue: speedString) ?? .medium
    }

    /// Быстрая абсорбция в минутах
    var fastAbsorptionMinutes: Int {
        getIntValue(for: "CARB_ABSORPTION_FAST_MINUTES", defaultValue: 15)
    }

    /// Средняя абсорбция в минутах
    var mediumAbsorptionMinutes: Int {
        getIntValue(for: "CARB_ABSORPTION_MEDIUM_MINUTES", defaultValue: 30)
    }

    /// Медленная абсорбция в минутах
    var slowAbsorptionMinutes: Int {
        getIntValue(for: "CARB_ABSORPTION_SLOW_MINUTES", defaultValue: 60)
    }

    /// Синхронизация с Nightscout
    var nightscoutSyncEnabled: Bool {
        getBoolValue(for: "CARB_NIGHTSCOUT_SYNC", defaultValue: true)
    }

    /// Интеграция с HealthKit
    var healthKitIntegrationEnabled: Bool {
        getBoolValue(for: "CARB_HEALTHKIT_INTEGRATION", defaultValue: true)
    }

    // MARK: - Initialization

    private init() {
        info(.service, "CarbConfigurationService initialized")
        logCurrentConfiguration()
    }

    // MARK: - Public Methods

    /// Получить время абсорбции для скорости
    func getAbsorptionTime(for speed: AbsorptionSpeed) -> TimeInterval {
        switch speed {
        case .fast:
            return TimeInterval(fastAbsorptionMinutes * 60)
        case .medium:
            return TimeInterval(mediumAbsorptionMinutes * 60)
        case .slow:
            return TimeInterval(slowAbsorptionMinutes * 60)
        }
    }

    /// Получить рекомендуемую скорость для типа пищи
    func getRecommendedSpeed(for foodType: String) -> AbsorptionSpeed {
        switch foodType.lowercased() {
        case "быстро",
             "конфеты",
             "сахар",
             "сок",
             "candy",
             "fast",
             "juice",
             "sugar":
            return .fast
        case "паста",
             "рис",
             "средне",
             "хлеб",
             "bread",
             "medium",
             "pasta",
             "rice":
            return .medium
        case "белковое",
             "жирное",
             "медленно",
             "пицца",
             "fatty",
             "pizza",
             "protein",
             "slow":
            return .slow
        default:
            return defaultAbsorptionSpeed
        }
    }

    /// Проверить, активна ли Loop система
    func isLoopSystemActive() -> Bool {
        useLoopCarbAbsorption
    }

    /// Проверить, активна ли OpenAPS система
    func isOpenAPSSystemActive() -> Bool {
        !useLoopCarbAbsorption
    }

    /// Получить конфигурацию для отображения
    func getConfigurationInfo() -> CarbConfigurationInfo {
        CarbConfigurationInfo(
            useLoopSystem: useLoopCarbAbsorption,
            defaultSpeed: defaultAbsorptionSpeed,
            fastMinutes: fastAbsorptionMinutes,
            mediumMinutes: mediumAbsorptionMinutes,
            slowMinutes: slowAbsorptionMinutes,
            nightscoutSync: nightscoutSyncEnabled,
            healthKitIntegration: healthKitIntegrationEnabled
        )
    }

    // MARK: - Private Methods

    private func getBoolValue(for key: String, defaultValue: Bool) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            warning(.service, "Configuration key '\(key)' not found, using default: \(defaultValue)")
            return defaultValue
        }

        let boolValue = value.lowercased() == "yes" || value.lowercased() == "true"
        debug(.service, "Configuration '\(key)': \(boolValue)")
        return boolValue
    }

    private func getStringValue(for key: String, defaultValue: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            warning(.service, "Configuration key '\(key)' not found, using default: \(defaultValue)")
            return defaultValue
        }

        debug(.service, "Configuration '\(key)': \(value)")
        return value
    }

    private func getIntValue(for key: String, defaultValue: Int) -> Int {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let intValue = Int(value)
        else {
            warning(.service, "Configuration key '\(key)' not found or invalid, using default: \(defaultValue)")
            return defaultValue
        }

        debug(.service, "Configuration '\(key)': \(intValue)")
        return intValue
    }

    private func logCurrentConfiguration() {
        info(.service, "Current carb configuration:")
        info(.service, "  Use Loop system: \(useLoopCarbAbsorption)")
        info(.service, "  Default speed: \(defaultAbsorptionSpeed.rawValue)")
        info(.service, "  Fast: \(fastAbsorptionMinutes) min")
        info(.service, "  Medium: \(mediumAbsorptionMinutes) min")
        info(.service, "  Slow: \(slowAbsorptionMinutes) min")
        info(.service, "  Nightscout sync: \(nightscoutSyncEnabled)")
        info(.service, "  HealthKit integration: \(healthKitIntegrationEnabled)")
    }
}

// MARK: - Supporting Types

struct CarbConfigurationInfo {
    let useLoopSystem: Bool
    let defaultSpeed: AbsorptionSpeed
    let fastMinutes: Int
    let mediumMinutes: Int
    let slowMinutes: Int
    let nightscoutSync: Bool
    let healthKitIntegration: Bool
}

// MARK: - Extensions

extension CarbConfigurationService {
    /// Получить описание текущей конфигурации
    func getConfigurationDescription() -> String {
        if useLoopCarbAbsorption {
            return "Loop система углеводов активна"
        } else {
            return "OpenAPS meal.js система активна"
        }
    }

    /// Получить рекомендации по настройке
    func getConfigurationRecommendations() -> [String] {
        var recommendations: [String] = []

        if !nightscoutSyncEnabled {
            recommendations.append("Рекомендуется включить синхронизацию с Nightscout")
        }

        if !healthKitIntegrationEnabled {
            recommendations.append("Рекомендуется включить интеграцию с HealthKit")
        }

        if fastAbsorptionMinutes < 10 || fastAbsorptionMinutes > 20 {
            recommendations.append("Быстрая абсорбция должна быть 10-20 минут")
        }

        if slowAbsorptionMinutes < 45 || slowAbsorptionMinutes > 90 {
            recommendations.append("Медленная абсорбция должна быть 45-90 минут")
        }

        return recommendations
    }
}
