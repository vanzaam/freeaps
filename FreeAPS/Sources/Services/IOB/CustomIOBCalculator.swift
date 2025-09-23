import Foundation
import LoopKit
import Swinject

// MARK: - Custom IOB Calculator

protocol CustomIOBCalculator: AnyObject {
    func calculateIOB() -> CustomIOBResult
}

struct CustomIOBResult {
    let totalIOB: Decimal
    let bolusIOB: Decimal
    let basalIOB: Decimal
    let systemIOB: Decimal // Для сравнения
    let calculationTime: Date
    let debugInfo: String
}

final class BaseCustomIOBCalculator: CustomIOBCalculator, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var smbBasalIobCalculator: SmbBasalIobCalculator!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func calculateIOB() -> CustomIOBResult {
        let calculationTime = Date()
        var debugInfo = "Custom IOB Calculation:\n"

        // 1. Получаем системный IOB для сравнения
        let systemIOB = getSystemIOB()
        debugInfo += "System IOB: \(systemIOB)\n"

        // 2. Рассчитываем Bolus IOB (включая SMB)
        let bolusIOB = calculateBolusIOB()
        debugInfo += "Calculated Bolus IOB: \(bolusIOB)\n"

        // 3. Рассчитываем Basal IOB с учетом SMB-basal
        let basalIOB = calculateBasalIOB()
        debugInfo += "Calculated Basal IOB: \(basalIOB)\n"

        // 4. Общий IOB
        let totalIOB = bolusIOB + basalIOB
        debugInfo += "Total Custom IOB: \(totalIOB)\n"

        // 🚨 КРИТИЧНАЯ ДИАГНОСТИКА: Детальный анализ разницы
        print("🚨 КРИТИЧНАЯ ДИАГНОСТИКА IOB:")
        print("  Время расчета: \(calculationTime)")
        print("  Системный IOB: \(systemIOB) U")
        print("  Наш Bolus IOB: \(bolusIOB) U")
        print("  Наш Basal IOB: \(basalIOB) U")
        print("  Наш Total IOB: \(totalIOB) U")
        print("  РАЗНИЦА: \(totalIOB - systemIOB) U")

        if abs(totalIOB - systemIOB) > 1.0 {
            print("🚨 КРИТИЧНО: Разница больше 1U! Требуется анализ!")
            analyzeIOBDifference(systemIOB: systemIOB, customIOB: totalIOB)
        }

        print("🧮 Custom IOB Calculator:")
        print("  System IOB: \(systemIOB)")
        print("  Custom Bolus IOB: \(bolusIOB)")
        print("  Custom Basal IOB: \(basalIOB)")
        print("  Custom Total IOB: \(totalIOB)")
        print("  Difference: \(totalIOB - systemIOB)")

        return CustomIOBResult(
            totalIOB: totalIOB,
            bolusIOB: bolusIOB,
            basalIOB: basalIOB,
            systemIOB: systemIOB,
            calculationTime: calculationTime,
            debugInfo: debugInfo
        )
    }

    // MARK: - Bolus IOB Calculation

    private func calculateBolusIOB() -> Decimal {
        let now = Date()

        // Получаем все болюсы (включая SMB)
        let pumpHistory: [PumpHistoryEvent] = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) ?? []

        // Используем ту же модель инсулина что и в SMB Basal
        let insulinModel = currentInsulinModel()
        let effectDuration = insulinModel.effectDuration

        let boluses = pumpHistory.filter { event in
            let ageSeconds = now.timeIntervalSince(event.timestamp)
            guard ageSeconds >= 0, ageSeconds <= effectDuration else { return false }
            return event.type == .bolus || event.type == .smb
        }

        var totalBolusIOB: Double = 0

        for bolus in boluses {
            let ageSeconds = now.timeIntervalSince(bolus.timestamp)
            guard ageSeconds >= 0, ageSeconds <= effectDuration else { continue }

            let amount = bolus.effectiveInsulinAmount ?? 0
            guard amount > 0 else { continue }

            // 🎯 ИСПОЛЬЗУЕМ ТУ ЖЕ ФОРМУЛУ ЧТО И В SMB BASAL!
            let remainingPercentage = insulinModel.percentEffectRemaining(at: ageSeconds)
            let bolusIOB = Double(truncating: amount as NSNumber) * remainingPercentage

            if bolusIOB > 0.001 { // Only count meaningful amounts
                totalBolusIOB += bolusIOB
                print("  Bolus: \(amount)U at \(bolus.timestamp), age: \(Int(ageSeconds / 60))min, IOB: \(Decimal(bolusIOB))")
            }
        }

        return Decimal(totalBolusIOB)
    }

    // MARK: - Basal IOB Calculation

    private func calculateBasalIOB() -> Decimal {
        // 🎯 ИСПОЛЬЗУЕМ ГОТОВЫЙ РАСЧЕТ SMB-BASAL IOB!
        let smbBasalIOB = smbBasalIobCalculator.calculateBasalIob(at: Date())
        print("  SMB-Basal IOB: \(smbBasalIOB.iob)U (from \(smbBasalIOB.activePulses) pulses)")

        // Добавляем IOB от обычного базала (temp basal) - пока 0, так как SMB-basal замещает базал
        let regularBasalIOB: Decimal = 0 // TODO: Добавить расчет temp basal IOB если нужно
        print("  Regular Basal IOB: \(regularBasalIOB)U (SMB-basal замещает обычный базал)")

        let totalBasalIOB = smbBasalIOB.iob + regularBasalIOB
        print("  Total Basal IOB: \(totalBasalIOB)U")

        return totalBasalIOB
    }

    // MARK: - Insulin Model (same as SMB Basal)

    private func currentInsulinModel() -> ExponentialInsulinModel {
        let preferences = settingsManager.preferences

        switch preferences.curve {
        case .rapidActing:
            let peakTime = preferences.useCustomPeakTime ?
                TimeInterval(Double(truncating: preferences.insulinPeakTime as NSNumber) * 60) :
                TimeInterval(minutes: 75)
            return ExponentialInsulinModel(
                actionDuration: TimeInterval(hours: 6),
                peakActivityTime: peakTime,
                delay: TimeInterval(minutes: 10)
            )

        case .ultraRapid:
            let peakTime = preferences.useCustomPeakTime ?
                TimeInterval(Double(truncating: preferences.insulinPeakTime as NSNumber) * 60) :
                TimeInterval(minutes: 55)
            return ExponentialInsulinModel(
                actionDuration: TimeInterval(hours: 5),
                peakActivityTime: peakTime,
                delay: TimeInterval(minutes: 10)
            )

        case .bilinear:
            // For bilinear, we'll use the same approach but with rapid-acting defaults
            return ExponentialInsulinModel(
                actionDuration: TimeInterval(hours: 6),
                peakActivityTime: TimeInterval(minutes: 75),
                delay: TimeInterval(minutes: 10)
            )
        }
    }

    // MARK: - System IOB

    private func getSystemIOB() -> Decimal {
        let suggestion: Suggestion? = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        let systemIOB = suggestion?.iob ?? 0

        // 🔍 КРИТИЧНАЯ ДИАГНОСТИКА: Проверяем также raw IOB result
        let rawIOBResult: RawJSON? = storage.retrieve(OpenAPS.Monitor.iob, as: RawJSON.self)
        let iobEntry: IOBEntry? = storage.retrieve(OpenAPS.Monitor.iob, as: IOBEntry.self)

        print("🔍 СИСТЕМНЫЙ IOB ДИАГНОСТИКА:")
        print("  Suggestion IOB: \(systemIOB)")
        print("  Raw IOB Result: \(rawIOBResult?.prefix(200) ?? "nil")")

        if let iobEntry = iobEntry {
            print("  IOBEntry total IOB: \(iobEntry.iob)")
            print("  IOBEntry basal IOB: \(iobEntry.basaliob)")
            print("  IOBEntry bolus IOB: \(iobEntry.bolusiob)")
        } else {
            print("  IOBEntry: не удалось распарсить")
        }

        if let suggestion = suggestion {
            print("  COB: \(suggestion.cob ?? 0)")
            print("  Timestamp: \(suggestion.timestamp ?? Date())")
            print("  Reason: \(suggestion.reason)")
        }

        return systemIOB
    }

    // MARK: - Diagnostic Analysis

    private func analyzeIOBDifference(systemIOB _: Decimal, customIOB _: Decimal) {
        print("🔍 АНАЛИЗ РАЗЛИЧИЙ IOB:")

        // Анализ болюсов
        let now = Date()
        let pumpHistory: [PumpHistoryEvent] = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) ?? []
        let insulinModel = currentInsulinModel()
        let effectDuration = insulinModel.effectDuration

        print("📊 Модель инсулина:")
        print("  Длительность действия: \(effectDuration / 3600) часов")
        print("  Пик активности: \(insulinModel.peakActivityTime / 60) минут")

        let recentBoluses = pumpHistory.filter { event in
            let ageSeconds = now.timeIntervalSince(event.timestamp)
            guard ageSeconds >= 0, ageSeconds <= effectDuration else { return false }
            return event.type == .bolus || event.type == .smb
        }

        print("📋 Активные болюсы (последние \(Int(effectDuration / 3600)) часов):")
        for bolus in recentBoluses.prefix(10) { // Показываем первые 10
            let ageMinutes = Int(now.timeIntervalSince(bolus.timestamp) / 60)
            let amount = bolus.effectiveInsulinAmount ?? 0
            let remainingPercentage = insulinModel.percentEffectRemaining(at: now.timeIntervalSince(bolus.timestamp))
            let iob = Double(truncating: amount as NSNumber) * remainingPercentage

            print(
                "  \(bolus.type.rawValue): \(amount)U, возраст: \(ageMinutes)мин, остаток: \(String(format: "%.1f", remainingPercentage * 100))%, IOB: \(String(format: "%.3f", iob))U"
            )
        }

        if recentBoluses.count > 10 {
            print("  ... и еще \(recentBoluses.count - 10) болюсов")
        }

        print("🎯 Возможные причины различий:")
        print("  1. Разные модели инсулина (OpenAPS vs наша)")
        print("  2. Разные временные зоны или расчеты возраста")
        print("  3. Разные наборы данных (мы учитываем больше болюсов)")
        print("  4. Middleware корректирует системный IOB")
        print("  5. SMB-basal IOB не учитывается в системном расчете")
    }
}
