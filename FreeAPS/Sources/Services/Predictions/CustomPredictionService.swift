import Combine
import Foundation
import JavaScriptCore
import Swinject

// 🎯 Кастомный сервис прогнозов, использующий oref0 с нашими правильными IOB данными
protocol CustomPredictionService {
    func generatePredictionsWithCustomIOB() -> AnyPublisher<CustomPredictionResult?, Never>
}

struct CustomPredictionResult {
    let predBGs: PredictionBGs
    let eventualBG: Double
    let minPredBG: Double
    let minGuardBG: Double
    let iobPredBG: Double
    let cobPredBG: Double
    let uamPredBG: Double
    let reason: String
}

struct PredictionBGs {
    let iob: [Double]
    let cob: [Double]
    let zt: [Double]
    let uam: [Double]
}

final class BaseCustomPredictionService: CustomPredictionService, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var smbBasalMiddleware: SmbBasalMiddleware!
    @Injected() private var customIOBCalculator: CustomIOBCalculator!
    @Injected() private var swiftOref0Engine: SwiftOref0Engine!

    private let jsWorker = JavaScriptWorker()
    private let processQueue = DispatchQueue(label: "CustomPredictionService.processQueue", qos: .utility)

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func generatePredictionsWithCustomIOB() -> AnyPublisher<CustomPredictionResult?, Never> {
        // 🚀 Use native SwiftOref0Engine instead of JS
        let glucoseArray = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self) ?? []

        func parseDict(_ raw: String) -> [String: Any]? {
            guard !raw.isEmpty, let data = raw.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return dict
        }

        let profileRaw = storage.retrieve(OpenAPS.Settings.profile, as: RawJSON.self) ?? ""
        let autosensRaw = storage.retrieve(OpenAPS.Settings.autosense, as: RawJSON.self) ?? ""
        let mealRaw = storage.retrieve(OpenAPS.Monitor.meal, as: RawJSON.self) ?? ""
        let reservoirRaw = storage.retrieve(OpenAPS.Monitor.reservoir, as: RawJSON.self) ?? ""
        let tempBasalRaw = storage.retrieve(OpenAPS.Monitor.tempBasal, as: RawJSON.self) ?? ""

        var profile = parseDict(profileRaw) ?? [:]
        if profile["isf"] == nil { profile["isf"] = 50.0 }
        if profile["cr"] == nil { profile["cr"] = 15.0 }
        if profile["target"] == nil { profile["target"] = 100.0 }

        let autosens = parseDict(autosensRaw)
        let meal = parseDict(mealRaw)
        let reservoir = parseDict(reservoirRaw)
        let currentTemp = parseDict(tempBasalRaw)

        let iobData = customIOBCalculator.calculateIOB()
        let totalIOB = Double(truncating: iobData.totalIOB as NSDecimalNumber)

        debug(.openAPS, "🚀 CustomPredictionService: Using native SwiftOref0Engine with IOB: \(totalIOB)")

        return swiftOref0Engine
            .generatePredictions(
                iob: totalIOB,
                glucose: glucoseArray,
                profile: profile,
                autosens: autosens,
                meal: meal,
                reservoir: reservoir,
                currentTemp: currentTemp
            )
            .map { result in
                guard let r = result else { return nil }
                let predBGs = PredictionBGs(iob: r.predBGs.iob, cob: r.predBGs.cob, zt: r.predBGs.zt, uam: r.predBGs.uam)
                return CustomPredictionResult(
                    predBGs: predBGs,
                    eventualBG: r.eventualBG,
                    minPredBG: r.minPredBG,
                    minGuardBG: r.minPredBG,
                    iobPredBG: r.iobPredBG,
                    cobPredBG: r.cobPredBG,
                    uamPredBG: r.uamPredBG,
                    reason: r.reason
                )
            }
            .eraseToAnyPublisher()
    }

    private func generateCustomIOBData() -> String {
        // 🎯 Получаем правильные IOB данные из CustomIOBCalculator
        let iobData = customIOBCalculator.calculateIOB()

        let totalIOB = iobData.totalIOB
        let bolusIOB = iobData.bolusIOB
        let basalIOB = iobData.basalIOB
        let activity = max(totalIOB * 0.0025, 0.001) // Разумная activity

        // Создаем IOB структуру в формате oref0
        let customIOBJSON = """
        [{
            "iob": \(totalIOB),
            "basaliob": \(basalIOB),
            "bolusiob": \(bolusIOB),
            "activity": \(activity),
            "netbasalinsulin": \(basalIOB),
            "bolusinsulin": \(bolusIOB),
            "time": "\(Date().toISOString())",
            "lastBolusTime": null,
            "lastTemp": null,
            "iobWithZeroTemp": null
        }]
        """

        debug(.openAPS, "🎯 Custom IOB Data Generated:")
        debug(.openAPS, "  Total IOB: \(totalIOB)U")
        debug(.openAPS, "  Basal IOB: \(basalIOB)U")
        debug(.openAPS, "  Bolus IOB: \(bolusIOB)U")
        debug(.openAPS, "  Activity: \(activity)")

        return customIOBJSON
    }

    private func callOref0WithCustomIOB(
        iob: String,
        currentTemp: String,
        glucose: String,
        profile: String,
        autosens: String,
        meal: String,
        reservoir: String,
        clock _: Date
    ) -> CustomPredictionResult? {
        debug(.openAPS, "🔧 callOref0WithCustomIOB started")

        return jsWorker.inCommonContext { worker in
            debug(.openAPS, "🔧 JavaScript context acquired, loading scripts...")

            // Загружаем oref0 скрипты
            worker.evaluate(script: Script(name: OpenAPS.Prepare.log))
            worker.evaluate(script: Script(name: OpenAPS.Prepare.determineBasal))
            worker.evaluate(script: Script(name: OpenAPS.Bundle.basalSetTemp))
            worker.evaluate(script: Script(name: OpenAPS.Bundle.getLastGlucose))
            worker.evaluate(script: Script(name: OpenAPS.Bundle.determineBasal))

            debug(.openAPS, "🔧 Scripts loaded, calling oref0...")

            // 🎯 Вызываем oref0 с нашими правильными IOB данными
            let resultJSON = worker.call(
                function: OpenAPS.Function.generate,
                with: [
                    iob, // 🚀 Наши правильные IOB!
                    currentTemp,
                    glucose,
                    profile,
                    autosens.isEmpty ? .null : autosens,
                    meal,
                    "true", // microbolusAllowed - в JavaScript формате
                    reservoir,
                    Date().toISOString(), // clock - передаем ISO строку
                    .null // pump_history (не нужен для прогнозов)
                ]
            )

            debug(.openAPS, "🔧 oref0 call completed, result: \(String(resultJSON.prefix(200)))...")

            // Парсим результат из oref0
            let parsedResult = parseOref0Result(resultJSON)
            debug(.openAPS, "🔧 Parsing result: \(parsedResult != nil ? "SUCCESS" : "FAILED")")
            return parsedResult
        }
    }

    private func parseOref0Result(_ json: String) -> CustomPredictionResult? {
        debug(.openAPS, "🔧 parseOref0Result: parsing JSON length \(json.count)")

        guard let data = json.data(using: .utf8) else {
            debug(.openAPS, "❌ parseOref0Result: Failed to convert to data")
            return nil
        }

        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            debug(.openAPS, "❌ parseOref0Result: Failed to parse JSON")
            debug(.openAPS, "Raw JSON: \(String(json.prefix(500)))")
            return nil
        }

        debug(.openAPS, "🔧 parseOref0Result: JSON parsed successfully, keys: \(result.keys.joined(separator: ", "))")

        // Извлекаем predBGs
        guard let predBGsData = result["predBGs"] as? [String: [Double]] else {
            debug(.openAPS, "❌ parseOref0Result: No predBGs found in result")
            return nil
        }

        let predBGs = PredictionBGs(
            iob: predBGsData["IOB"] ?? [],
            cob: predBGsData["COB"] ?? [],
            zt: predBGsData["ZT"] ?? [],
            uam: predBGsData["UAM"] ?? []
        )

        let customResult = CustomPredictionResult(
            predBGs: predBGs,
            eventualBG: result["eventualBG"] as? Double ?? 0,
            minPredBG: result["minPredBG"] as? Double ?? 0,
            minGuardBG: result["minGuardBG"] as? Double ?? 0,
            iobPredBG: result["IOBpredBG"] as? Double ?? 0,
            cobPredBG: result["COBpredBG"] as? Double ?? 0,
            uamPredBG: result["UAMpredBG"] as? Double ?? 0,
            reason: result["reason"] as? String ?? ""
        )

        debug(
            .openAPS,
            "✅ parseOref0Result: Success! EventualBG: \(customResult.eventualBG), IOBpredBG: \(customResult.iobPredBG)"
        )
        return customResult
    }

    private func loadFileFromStorage(name: String) -> String {
        storage.retrieve(name, as: RawJSON.self) ?? ""
    }
}

// Расширения для удобства
extension Date {
    func toISOString() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}
