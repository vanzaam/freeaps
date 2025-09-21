import Foundation
import HealthKit
import LoopKit

/// Расширения для расчётов углеводов
/// Интегрирует LoopKit CarbMath с OpenAPS логикой
extension CarbAccountingService {
    /// Рассчитать эффект углеводов на глюкозу с учётом профиля
    func calculateCarbEffect(
        from _: Date,
        to _: Date,
        carbRatio _: Decimal = 15.0,
        insulinSensitivity _: Decimal = 50.0
    ) -> [GlucoseEffect] {
        // Использовать CarbMath из LoopKit для точных расчётов
        // Нам нужны CarbRatioSchedule и InsulinSensitivitySchedule
        guard let ratios = carbStore.carbRatioSchedule, let sensitivities = carbStore.insulinSensitivitySchedule else {
            return []
        }

        // For now, return empty array until we implement proper LoopKit integration
        // TODO: Implement proper glucoseEffects calculation using LoopKit
        let effects: [GlucoseEffect] = []

        return effects
    }

    /// Получить оставшийся эффект углеводов
    func getRemainingCarbImpact() -> Decimal {
        let now = Date()
        var totalImpact: Decimal = 0

        for entry in activeCarbEntries {
            let timeSinceEntry = now.timeIntervalSince(entry.startDate)
            let absorptionProgress = min(1.0, timeSinceEntry / (entry.absorptionTime ?? CarbMath.defaultAbsorptionTime))

            if absorptionProgress < 1.0 {
                let remainingAmount = entry.quantity.doubleValue(for: .gram()) * (1.0 - absorptionProgress)
                // Упрощённый расчёт: 1г углеводов = ~3 мг/дл глюкозы
                totalImpact += Decimal(remainingAmount) * 3
            }
        }

        return totalImpact
    }

    /// Получить коэффициент скорости абсорбции для SMB
    func getAbsorptionSpeedFactor() -> Decimal {
        let now = Date()
        var totalFactor: Decimal = 0
        var activeEntries = 0

        for entry in activeCarbEntries {
            let timeSinceEntry = now.timeIntervalSince(entry.startDate)
            let absorptionProgress = min(1.0, timeSinceEntry / (entry.absorptionTime ?? CarbMath.defaultAbsorptionTime))

            if absorptionProgress < 1.0 {
                // Быстрая абсорбция = 1.0, медленная = 0.5
                let at = entry.absorptionTime ?? CarbMath.defaultAbsorptionTime
                let speedFactor: Double
                if at <= 15 * 60 {
                    speedFactor = 1.0
                } else if at <= 30 * 60 {
                    speedFactor = 0.8
                } else {
                    speedFactor = 0.6
                }
                totalFactor += Decimal(speedFactor)
                activeEntries += 1
            }
        }

        return activeEntries > 0 ? totalFactor / Decimal(activeEntries) : 1.0
    }

    /// Получить статистику по углеводам
    func getCarbStats() -> CarbStats {
        let now = Date()
        let last24h = now.addingTimeInterval(-24 * 3600)

        let last24hEntries = activeCarbEntries.filter { $0.startDate >= last24h }
        let totalCarbs = last24hEntries.reduce(0) { total, entry in
            total + entry.quantity.doubleValue(for: .gram())
        }

        let activeEntries = activeCarbEntries.filter { entry in
            let timeSinceEntry = now.timeIntervalSince(entry.startDate)
            return timeSinceEntry < (entry.absorptionTime ?? CarbMath.defaultAbsorptionTime)
        }

        return CarbStats(
            totalCarbsLast24h: Decimal(totalCarbs),
            activeEntries: activeEntries.count,
            currentCOB: cob,
            averageAbsorptionTime: calculateAverageAbsorptionTime()
        )
    }

    private func calculateAverageAbsorptionTime() -> TimeInterval {
        guard !activeCarbEntries.isEmpty else { return 30 * 60 } // 30 минут по умолчанию

        let totalTime = activeCarbEntries.reduce(0) { total, entry in
            total + (entry.absorptionTime ?? CarbMath.defaultAbsorptionTime)
        }

        return totalTime / Double(activeCarbEntries.count)
    }
}

// MARK: - Supporting Types

struct CarbStats {
    let totalCarbsLast24h: Decimal
    let activeEntries: Int
    let currentCOB: Decimal
    let averageAbsorptionTime: TimeInterval
}

// MARK: - Absorption Speed Helpers

extension CarbAccountingService {
    /// Получить рекомендуемую скорость абсорбции для типа пищи
    static func getAbsorptionTime(for foodType: String) -> TimeInterval {
        switch foodType.lowercased() {
        case "candy",
             "fast",
             "juice",
             "sugar":
            return 15 * 60 // 15 минут
        case "bread",
             "medium",
             "pasta",
             "rice":
            return 30 * 60 // 30 минут
        case "fatty",
             "pizza",
             "protein",
             "slow":
            return 60 * 60 // 60 минут
        default:
            return 30 * 60 // 30 минут по умолчанию
        }
    }

    /// Получить описание скорости абсорбции
    static func getAbsorptionDescription(for timeInterval: TimeInterval) -> String {
        switch timeInterval {
        case 0 ..< Double(20 * 60):
            return "Быстро (15 мин)"
        case Double(20 * 60) ..< Double(45 * 60):
            return "Средне (30 мин)"
        case Double(45 * 60)...:
            return "Медленно (60 мин)"
        default:
            return "Средне (30 мин)"
        }
    }
}
