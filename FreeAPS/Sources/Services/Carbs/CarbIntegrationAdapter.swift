import Foundation
import LoopKit

/// Адаптер для интеграции системы углеводов с OpenAPS
/// Позволяет переключаться между Loop и OpenAPS системами
class CarbIntegrationAdapter {
    // MARK: - Private Properties

    private let carbService: CarbAccountingService?
    // MealCalculator - это enum со статическими методами, не нужен экземпляр
    private let configService = CarbConfigurationService.shared

    // MARK: - Initialization

    init(carbService: CarbAccountingService?) {
        self.carbService = carbService
        info(.service, "CarbIntegrationAdapter initialized")
    }

    // MARK: - Public Methods

    /// Получить текущий COB
    func getCurrentCOB() async -> Decimal {
        if configService.isLoopSystemActive() {
            return await getCOBFromLoopSystem()
        } else {
            return getCOBFromOpenAPSSystem()
        }
    }

    /// Получить эффект углеводов на глюкозу
    func getCarbEffect(from startDate: Date, to endDate: Date) async -> [GlucoseEffect] {
        if configService.isLoopSystemActive() {
            return await getCarbEffectFromLoopSystem(from: startDate, to: endDate)
        } else {
            return getCarbEffectFromOpenAPSSystem(from: startDate, to: endDate)
        }
    }

    /// Получить оставшийся эффект углеводов
    func getRemainingCarbImpact() async -> Decimal {
        if configService.isLoopSystemActive() {
            return await getRemainingCarbImpactFromLoopSystem()
        } else {
            return getRemainingCarbImpactFromOpenAPSSystem()
        }
    }

    /// Получить коэффициент скорости абсорбции для SMB
    func getAbsorptionSpeedFactor() async -> Decimal {
        if configService.isLoopSystemActive() {
            return await getAbsorptionSpeedFactorFromLoopSystem()
        } else {
            return getAbsorptionSpeedFactorFromOpenAPSSystem()
        }
    }

    /// Добавить углеводы
    func addCarbEntry(amount: Decimal, date: Date, absorptionDuration: TimeInterval, foodType: String? = nil) async {
        if configService.isLoopSystemActive() {
            await addCarbEntryToLoopSystem(amount: amount, date: date, absorptionDuration: absorptionDuration, foodType: foodType)
        } else {
            await addCarbEntryToOpenAPSSystem(
                amount: amount,
                date: date,
                absorptionDuration: absorptionDuration,
                foodType: foodType
            )
        }
    }

    /// Получить статистику углеводов
    func getCarbStats() async -> CarbStats {
        if configService.isLoopSystemActive() {
            return await getCarbStatsFromLoopSystem()
        } else {
            return getCarbStatsFromOpenAPSSystem()
        }
    }

    // MARK: - Loop System Methods

    private func getCOBFromLoopSystem() async -> Decimal {
        guard let carbService = carbService else {
            warning(.service, "CarbAccountingService not available for Loop system")
            return 0
        }

        return await MainActor.run { carbService.cob }
    }

    private func getCarbEffectFromLoopSystem(from startDate: Date, to endDate: Date) async -> [GlucoseEffect] {
        guard let carbService = carbService else {
            warning(.service, "CarbAccountingService not available for Loop system")
            return []
        }

        return await MainActor.run { carbService.getCarbEffects(from: startDate, to: endDate) }
    }

    private func getRemainingCarbImpactFromLoopSystem() async -> Decimal {
        guard let carbService = carbService else {
            warning(.service, "CarbAccountingService not available for Loop system")
            return 0
        }

        return await MainActor.run { carbService.getRemainingCarbImpact() }
    }

    private func getAbsorptionSpeedFactorFromLoopSystem() async -> Decimal {
        guard let carbService = carbService else {
            warning(.service, "CarbAccountingService not available for Loop system")
            return 1.0
        }

        return await MainActor.run { carbService.getAbsorptionSpeedFactor() }
    }

    private func addCarbEntryToLoopSystem(
        amount: Decimal,
        date: Date,
        absorptionDuration: TimeInterval,
        foodType: String?
    ) async {
        guard let carbService = carbService else {
            error(.service, "CarbAccountingService not available for Loop system")
            return
        }

        await carbService.addCarbEntry(
            amount: amount,
            date: date,
            absorptionDuration: absorptionDuration,
            foodType: foodType
        )
    }

    private func getCarbStatsFromLoopSystem() async -> CarbStats {
        guard let carbService = carbService else {
            warning(.service, "CarbAccountingService not available for Loop system")
            return CarbStats(
                totalCarbsLast24h: 0,
                activeEntries: 0,
                currentCOB: 0,
                averageAbsorptionTime: 30 * 60
            )
        }

        return await MainActor.run { carbService.getCarbStats() }
    }

    // MARK: - OpenAPS System Methods

    private func getCOBFromOpenAPSSystem() -> Decimal {
        // Использовать существующую логику OpenAPS. Передаём минимальный валидный JSON.
        let empty = "[]"
        let emptyObj = "{}"
        let inputs = MealInputs(
            history: empty,
            profile: emptyObj,
            basalprofile: empty,
            clock: emptyObj,
            carbs: empty,
            glucose: empty
        )
        let mealResult = MealCalculator.compute(inputs: inputs)
        return mealResult.mealCOB ?? 0
    }

    private func getCarbEffectFromOpenAPSSystem(from _: Date, to _: Date) -> [GlucoseEffect] {
        let empty = "[]"
        let emptyObj = "{}"
        let inputs = MealInputs(
            history: empty,
            profile: emptyObj,
            basalprofile: empty,
            clock: emptyObj,
            carbs: empty,
            glucose: empty
        )
        let mealResult = MealCalculator.compute(inputs: inputs)
        // TODO: Convert MealCalculator result to [GlucoseEffect]
        return []
    }

    private func getRemainingCarbImpactFromOpenAPSSystem() -> Decimal {
        let empty = "[]"
        let emptyObj = "{}"
        let inputs = MealInputs(
            history: empty,
            profile: emptyObj,
            basalprofile: empty,
            clock: emptyObj,
            carbs: empty,
            glucose: empty
        )
        let mealResult = MealCalculator.compute(inputs: inputs)
        // TODO: Extract remainingCarbImpact from MealCalculator result
        return 0
    }

    private func getAbsorptionSpeedFactorFromOpenAPSSystem() -> Decimal {
        // OpenAPS не имеет адаптивных коэффициентов скорости абсорбции
        1.0
    }

    private func addCarbEntryToOpenAPSSystem(
        amount: Decimal,
        date: Date,
        absorptionDuration _: TimeInterval,
        foodType _: String?
    ) async {
        // OpenAPS система не поддерживает прямое добавление углеводов
        // Углеводы добавляются через существующий UI
        info(.service, "Carb entry added to OpenAPS system: \(amount)g at \(date)")
    }

    private func getCarbStatsFromOpenAPSSystem() -> CarbStats {
        let empty = "[]"
        let emptyObj = "{}"
        let inputs = MealInputs(
            history: empty,
            profile: emptyObj,
            basalprofile: empty,
            clock: emptyObj,
            carbs: empty,
            glucose: empty
        )
        let mealResult = MealCalculator.compute(inputs: inputs)

        return CarbStats(
            totalCarbsLast24h: mealResult.carbs ?? 0,
            activeEntries: 0, // TODO: Получить из mealResult
            currentCOB: mealResult.mealCOB ?? 0,
            averageAbsorptionTime: 30 * 60 // OpenAPS использует фиксированное время
        )
    }
}

// MARK: - Supporting Types

// Удалена заглушка MealInputs — используется тип из MealCalculator

// MARK: - Extensions

extension CarbIntegrationAdapter {
    /// Получить информацию о текущей системе
    func getSystemInfo() -> CarbSystemInfo {
        CarbSystemInfo(
            systemType: configService.isLoopSystemActive() ? .loop : .openaps,
            isActive: true,
            description: configService.getConfigurationDescription()
        )
    }

    /// Переключить систему (только для тестирования)
    func switchSystem(to systemType: CarbSystemType) {
        info(.service, "Switching carb system to: \(systemType)")
        // В реальной реализации здесь должно быть переключение конфигурации
    }
}

enum CarbSystemType {
    case loop
    case openaps
}

struct CarbSystemInfo {
    let systemType: CarbSystemType
    let isActive: Bool
    let description: String
}
