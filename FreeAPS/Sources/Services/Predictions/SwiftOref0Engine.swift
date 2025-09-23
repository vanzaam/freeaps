import Combine
import Foundation
import Swinject

// 🚀 Swift-версия oref0 алгоритма для FreeAPS X
// Основано на https://github.com/openaps/oref0

protocol SwiftOref0Engine: Injectable {
    func generatePredictions(
        iob: Double,
        glucose: [BloodGlucose],
        profile: [String: Any],
        autosens: [String: Any]?,
        meal: [String: Any]?,
        reservoir: [String: Any]?,
        currentTemp: [String: Any]?
    ) -> AnyPublisher<SwiftOref0Result?, Never>
}

struct SwiftOref0Result {
    let predBGs: SwiftPredictionBGs
    let iobPredBG: Double
    let cobPredBG: Double
    let uamPredBG: Double
    let minPredBG: Double
    let eventualBG: Double
    let reason: String
    let insulinReq: Double
    let rate: Double
    let duration: Int
    let units: Double
    let sensitivityRatio: Double
    let temp: String
    let COB: Double
    let bg: Double
    let timestamp: String
    let deliverAt: String
    let recieved: Bool
}

struct SwiftPredictionBGs {
    let iob: [Double]
    let zt: [Double]
    let cob: [Double]
    let uam: [Double]
}

final class BaseSwiftOref0Engine: SwiftOref0Engine, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var customIOBCalculator: CustomIOBCalculator!

    private let processQueue = DispatchQueue(label: "SwiftOref0Engine.processQueue", qos: .utility)

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func generatePredictions(
        iob: Double,
        glucose: [BloodGlucose],
        profile: [String: Any],
        autosens _: [String: Any]?,
        meal: [String: Any]?,
        reservoir _: [String: Any]?,
        currentTemp _: [String: Any]?
    ) -> AnyPublisher<SwiftOref0Result?, Never> {
        Future { [weak self] promise in
            guard let self = self else {
                debug(.openAPS, "❌ SwiftOref0Engine: self is nil")
                promise(.success(nil))
                return
            }

            debug(.openAPS, "🚀 SwiftOref0Engine: Starting native oref0 algorithm")

            self.processQueue.async {
                do {
                    // 🎯 Получаем последний глюкозный показатель
                    guard let lastGlucose = glucose.last else {
                        debug(.openAPS, "❌ SwiftOref0Engine: No glucose data")
                        promise(.success(nil))
                        return
                    }

                    let currentBG = Double(lastGlucose.glucose ?? 0)
                    let currentTime = lastGlucose.dateString

                    debug(.openAPS, "🔧 SwiftOref0Engine: Current BG: \(currentBG), Time: \(currentTime)")

                    // 🎯 Вычисляем COB (Carbs on Board)
                    debug(.openAPS, "🔧 SwiftOref0Engine: Meal data: \(meal ?? [:])")
                    let cob = self.calculateCOB(meal: meal, currentTime: currentTime)

                    // 🎯 Вычисляем BGI (Blood Glucose Impact)
                    let bgi = self.calculateBGI(iob: iob, profile: profile)

                    // 🎯 Получаем настройки профиля
                    let isf = self.getISF(profile: profile, currentTime: currentTime)
                    let cr = self.getCR(profile: profile, currentTime: currentTime)
                    let target = self.getTarget(profile: profile, currentTime: currentTime)

                    debug(.openAPS, "🔧 SwiftOref0Engine: ISF: \(isf), CR: \(cr), Target: \(target)")

                    // 🎯 Вычисляем прогнозы
                    let predictions = self.calculatePredictions(
                        currentBG: currentBG,
                        iob: iob,
                        cob: cob,
                        isf: isf,
                        cr: cr,
                        target: target,
                        profile: profile,
                        currentTime: currentTime
                    )

                    // 🎯 Вычисляем рекомендации по инсулину
                    let insulinReq = self.calculateInsulinRequirement(
                        currentBG: currentBG,
                        target: target,
                        isf: isf,
                        iob: iob,
                        cob: cob
                    )

                    // 🎯 Создаем результат
                    let result = SwiftOref0Result(
                        predBGs: predictions,
                        iobPredBG: predictions.iob.first ?? currentBG,
                        cobPredBG: predictions.cob.first ?? currentBG,
                        uamPredBG: predictions.uam.first ?? currentBG,
                        minPredBG: min(predictions.iob.min() ?? currentBG, predictions.cob.min() ?? currentBG),
                        eventualBG: predictions.iob.last ?? currentBG,
                        reason: self.generateReason(
                            cob: cob,
                            bgi: bgi,
                            isf: isf,
                            cr: cr,
                            target: target,
                            minPredBG: min(predictions.iob.min() ?? currentBG, predictions.cob.min() ?? currentBG),
                            iobPredBG: predictions.iob.first ?? currentBG,
                            cobPredBG: predictions.cob.first ?? currentBG,
                            insulinReq: insulinReq,
                            eventualBG: predictions.iob.last ?? currentBG
                        ),
                        insulinReq: insulinReq,
                        rate: 0.0, // Будет вычислено позже
                        duration: 30,
                        units: 0.0, // Будет вычислено позже
                        sensitivityRatio: 1.0, // Будет вычислено позже
                        temp: "absolute",
                        COB: cob,
                        bg: currentBG,
                        timestamp: currentTime.toISOString(),
                        deliverAt: currentTime.toISOString(),
                        recieved: true
                    )

                    debug(.openAPS, "✅ SwiftOref0Engine: Native oref0 completed successfully!")
                    debug(.openAPS, "  IOB PredBG: \(result.iobPredBG)")
                    debug(.openAPS, "  COB PredBG: \(result.cobPredBG)")
                    debug(.openAPS, "  Eventual BG: \(result.eventualBG)")
                    debug(.openAPS, "  Insulin Req: \(result.insulinReq)")

                    promise(.success(result))

                } catch {
                    debug(.openAPS, "❌ SwiftOref0Engine Error: \(error)")
                    promise(.success(nil))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Core oref0 Algorithm Implementation

    private func calculateCOB(meal: [String: Any]?, currentTime: Date) -> Double {
        guard let meal = meal else { return 0.0 }

        // Упрощенный расчет COB - в реальности нужен более сложный алгоритм
        // Безопасное получение carbs из разных типов
        let carbs: Double
        if let carbsDouble = meal["carbs"] as? Double {
            carbs = carbsDouble
        } else if let carbsDecimal = meal["carbs"] as? Decimal {
            carbs = Double(truncating: carbsDecimal as NSDecimalNumber)
        } else if let carbsInt = meal["carbs"] as? Int {
            carbs = Double(carbsInt)
        } else {
            return 0.0
        }

        if carbs > 0 {
            // Безопасное получение timestamp
            let mealTime: Date
            if let timestamp = meal["timestamp"] as? Date {
                mealTime = timestamp
            } else if let timestampString = meal["timestamp"] as? String,
                      let parsedDate = ISO8601DateFormatter().date(from: timestampString)
            {
                mealTime = parsedDate
            } else {
                mealTime = currentTime
            }
            let timeSinceMeal = currentTime.timeIntervalSince(mealTime)
            let hoursSinceMeal = timeSinceMeal / 3600.0

            // COB уменьшается со временем (примерно 4 часа для полного усвоения)
            let remainingCOB = max(0, carbs * (1.0 - min(1.0, hoursSinceMeal / 4.0)))
            return remainingCOB
        }

        return 0.0
    }

    private func calculateBGI(iob: Double, profile: [String: Any]) -> Double {
        // BGI = IOB * ISF (упрощенно)
        let isf = getISF(profile: profile, currentTime: Date())
        return iob * isf
    }

    private func getISF(profile: [String: Any], currentTime _: Date) -> Double {
        // Получаем ISF из профиля (упрощенно)
        if let isf = profile["isf"] as? Double {
            return isf
        }
        return 50.0 // Значение по умолчанию
    }

    private func getCR(profile: [String: Any], currentTime _: Date) -> Double {
        // Получаем CR из профиля (упрощенно)
        if let cr = profile["cr"] as? Double {
            return cr
        }
        return 15.0 // Значение по умолчанию
    }

    private func getTarget(profile: [String: Any], currentTime _: Date) -> Double {
        // Получаем Target из профиля (упрощенно)
        if let target = profile["target"] as? Double {
            return target
        }
        return 100.0 // Значение по умолчанию
    }

    private func calculatePredictions(
        currentBG: Double,
        iob: Double,
        cob: Double,
        isf: Double,
        cr: Double,
        target _: Double,
        profile: [String: Any],
        currentTime _: Date
    ) -> SwiftPredictionBGs {
        // Параметры модели
        let steps = 48
        let stepMinutes = 7.5
        let stepHours = stepMinutes / 60.0
        let insulinDurationHours = 4.0
        let cobDurationHours = 4.0

        // Текущий базал (если нет в профиле, берём разумный дефолт)
        let basalRate = (profile["basal"] as? Double)
            ?? (profile["currentBasal"] as? Double)
            ?? 0.8

        // Внутренние состояния для симуляции
        var bgIOB = currentBG
        var bgZT = currentBG
        var bgCOB = currentBG
        var bgUAM = currentBG
        var iobRemaining = max(0.0, iob)
        var cobRemaining = max(0.0, cob)

        var iobSeries: [Double] = [currentBG]
        var ztSeries: [Double] = [currentBG]
        var cobSeries: [Double] = [currentBG]
        var uamSeries: [Double] = [currentBG]

        for _ in 1 ..< steps {
            // Инсулин: скорость падения BG пропорциональна IOB/длительности действия
            let insulinRateMgdlPerHour = (iobRemaining * isf) / insulinDurationHours
            let insulinDrop = insulinRateMgdlPerHour * stepHours

            // Базал: считаем НEЙТРАЛЬНЫМ (держит ровно). Его влияние не вычитаем.
            // Для Zero Temp добавим положительный дрейф = отсутствующий базал.
            let basalRateMgdlPerHour = basalRate * isf
            let basalRise = basalRateMgdlPerHour * stepHours

            // Углеводы: расходуются равномерно за cobDurationHours
            let cobBurnGPerHour = min(cobRemaining, cobRemaining / max(0.25, cobDurationHours))
            let cobRateMgdlPerHour = (cobBurnGPerHour / max(1E-6, cr)) * isf
            let cobRise = cobRateMgdlPerHour * stepHours

            // IOB линия (без учёта базала)
            bgIOB = clampBG(bgIOB - insulinDrop + cobRise)
            iobSeries.append(bgIOB)

            // ZeroTemp линия (базал отсутствует → положительный дрейф)
            bgZT = clampBG(bgZT - insulinDrop + basalRise + cobRise)
            ztSeries.append(bgZT)

            // COB линия (аналогично IOB, без базала)
            bgCOB = clampBG(bgCOB - insulinDrop + cobRise)
            cobSeries.append(bgCOB)

            // UAM (упрощённо как COB)
            bgUAM = clampBG(bgUAM - insulinDrop + cobRise)
            uamSeries.append(bgUAM)

            // Обновляем состояния на следующий шаг
            // IOB экспоненциально/линейно уменьшается за время действия
            let iobDecay = iobRemaining * (stepHours / insulinDurationHours)
            iobRemaining = max(0.0, iobRemaining - iobDecay)

            // COB убывает согласно сгоранию
            cobRemaining = max(0.0, cobRemaining - cobBurnGPerHour * stepHours)
        }

        return SwiftPredictionBGs(iob: iobSeries, zt: ztSeries, cob: cobSeries, uam: uamSeries)
    }

    private func clampBG(_ value: Double) -> Double {
        max(40.0, min(400.0, value))
    }

    private func calculateInsulinRequirement(
        currentBG: Double,
        target: Double,
        isf: Double,
        iob: Double,
        cob _: Double
    ) -> Double {
        let bgDifference = currentBG - target
        let insulinNeeded = bgDifference / isf

        // Учитываем существующий IOB
        let netInsulin = insulinNeeded - iob

        return max(0, netInsulin)
    }

    private func generateReason(
        cob: Double,
        bgi: Double,
        isf: Double,
        cr: Double,
        target: Double,
        minPredBG: Double,
        iobPredBG: Double,
        cobPredBG: Double,
        insulinReq: Double,
        eventualBG: Double
    ) -> String {
        let dev = bgi
        let minGuardBG = minPredBG

        let comp = eventualBG >= target ? ">=" : "<"
        let microbolusText: String
        if insulinReq > 0.0 {
            let mb = min(0.1, insulinReq)
            microbolusText = "Microbolusing \(String(format: "%.2f", mb))U."
        } else {
            microbolusText = "No microbolus."
        }

        return "COB: \(Int(cob)), Dev: \(String(format: "%.1f", dev)), BGI: \(String(format: "%.1f", bgi)), ISF: \(String(format: "%.1f", isf)), CR: \(Int(cr)), Target: \(String(format: "%.1f", target)), minPredBG \(String(format: "%.1f", minPredBG)), minGuardBG \(String(format: "%.1f", minGuardBG)), IOBpredBG \(String(format: "%.1f", iobPredBG)), COBpredBG \(String(format: "%.1f", cobPredBG)); Eventual BG \(String(format: "%.1f", eventualBG)) \(comp) \(String(format: "%.1f", target)), insulinReq \(String(format: "%.2f", insulinReq)); \(microbolusText)"
    }
}

// MARK: - Extensions

// Note: toISOString() method is already defined elsewhere in the project
