@testable import FreeAPS
import XCTest

final class MealParityTests: XCTestCase {
    private func ensureCarbRatio(_ profile: RawJSON, default value: Decimal = 16) -> RawJSON {
        if profile.contains("\"carb_ratio\"") { return profile }
        guard let data = profile.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return profile }
        dict["carb_ratio"] = value
        guard let fixed = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let str = String(data: fixed, encoding: .utf8)
        else { return profile }
        return str
    }

    private func ensureISFProfile(_ profile: RawJSON, default sensitivity: Decimal = 90) -> RawJSON {
        guard let data = profile.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return profile }

        var isf = (dict["isfProfile"] as? [String: Any]) ?? [:]
        let sensitivities = (isf["sensitivities"] as? [[String: Any]]) ?? []
        if sensitivities.isEmpty {
            isf["sensitivities"] = [[
                "i": 0,
                "offset": 0,
                "x": 0,
                "start": "00:00:00",
                "sensitivity": sensitivity
            ]]
            dict["isfProfile"] = isf
            if let fixed = try? JSONSerialization.data(withJSONObject: dict, options: []),
               let str = String(data: fixed, encoding: .utf8)
            {
                return str
            }
        }
        return profile
    }

    private func ensureMaxCOB(_ profile: RawJSON, default value: Decimal = 120) -> RawJSON {
        guard let data = profile.data(using: .utf8),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return profile }
        if dict["maxCOB"] == nil { dict["maxCOB"] = value }
        guard let fixed = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let str = String(data: fixed, encoding: .utf8)
        else { return profile }
        return str
    }

    private func ensureClockZoned(_ clock: RawJSON) -> RawJSON {
        if let data = clock.data(using: .utf8),
           let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           (dict["date"] as? String) != nil || (dict["timestamp"] as? String) != nil
        {
            return clock
        }
        let iso = ISO8601DateFormatter()
        let now = iso.string(from: Date())
        let obj: [String: Any] = ["date": now]
        let data = try! JSONSerialization.data(withJSONObject: obj, options: [])
        return String(data: data, encoding: .utf8)!
    }

    private func ensureGlucose(_ glucose: RawJSON, minCount: Int = 4) -> RawJSON {
        if let data = glucose.data(using: .utf8),
           let arr = (try? JSONSerialization.jsonObject(with: data)) as? [Any],
           arr.count >= minCount
        {
            return glucose
        }
        let now = Date()
        var items: [[String: Any]] = []
        let iso = ISO8601DateFormatter()
        for i in 0 ..< minCount {
            let t = now.addingTimeInterval(Double(i - (minCount - 1)) * 300)
            items.append([
                "glucose": 100,
                "sgv": 100,
                "dateString": iso.string(from: t)
            ])
        }
        let data = try! JSONSerialization.data(withJSONObject: items, options: [])
        return String(data: data, encoding: .utf8)!
    }

    // Helper to run JS meal through OpenAPS pipeline without touching disk
    private func runJSMeal(
        openAPS _: OpenAPS,
        pumphistory: RawJSON,
        profile: RawJSON,
        basalProfile: RawJSON,
        clock: RawJSON,
        carbs: RawJSON,
        glucose: RawJSON
    ) -> RawJSON {
        let worker = JavaScriptWorker()
        return worker.inCommonContext { w in
            // Лишние предупреждения из Prepare.log нам не нужны для паритета
            _ = w.evaluate(script: Script(name: OpenAPS.Bundle.meal))
            _ = w.evaluate(script: Script(name: OpenAPS.Prepare.meal))
            return w.call(function: OpenAPS.Function.generate, with: [
                pumphistory,
                profile,
                clock,
                glucose,
                basalProfile,
                carbs
            ])
        }
    }

    // Append synthetic carb event to history (g at now)
    private func injectCarbs(_ carbs: RawJSON, grams: Int) -> RawJSON {
        guard let data = carbs.data(using: .utf8),
              var arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return carbs }
        let iso = ISO8601DateFormatter().string(from: Date())
        arr.append([
            "created_at": iso,
            "timestamp": iso,
            "carbs": grams,
            "enteredBy": "unittest"
        ])
        let out = (try? JSONSerialization.data(withJSONObject: arr)) ?? Data()
        return String(data: out, encoding: .utf8) ?? carbs
    }

    private func makeSyntheticCarbsCase(grams: Int) -> (clock: RawJSON, carbs: RawJSON) {
        let iso = ISO8601DateFormatter().string(from: Date())
        let clockObj: [String: Any] = ["date": iso]
        let clockData = try! JSONSerialization.data(withJSONObject: clockObj, options: [])
        let clockJSON = String(data: clockData, encoding: .utf8)!
        let carbsArr: [[String: Any]] = [[
            "created_at": iso,
            "timestamp": iso,
            "carbs": grams,
            "enteredBy": "unittest"
        ]]
        let carbsData = try! JSONSerialization.data(withJSONObject: carbsArr, options: [])
        let carbsJSON = String(data: carbsData, encoding: .utf8)!
        return (clockJSON, carbsJSON)
    }

    private func emptyCarbHistory() -> RawJSON {
        "[]"
    }

    func testParityOnSampleSnapshots() {
        // Load bundled defaults as a smoke test; real snapshots can be added later
        let pumphistory = OpenAPS.defaults(for: OpenAPS.Monitor.pumpHistory)
        let profile = OpenAPS.defaults(for: OpenAPS.Settings.profile)
        let basalProfile = OpenAPS.defaults(for: OpenAPS.Settings.basalProfile)
        let clock = OpenAPS.defaults(for: OpenAPS.Monitor.clock)
        let carbs = OpenAPS.defaults(for: OpenAPS.Monitor.carbHistory)
        let glucose = OpenAPS.defaults(for: OpenAPS.Monitor.glucose)

        let openAPS = OpenAPS(storage: BaseFileStorage())
        let baseProfile = ensureMaxCOB(ensureISFProfile(ensureCarbRatio(profile)))
        let baseClock = ensureClockZoned(clock)
        let baseGlucose = ensureGlucose(glucose)

        // Набор случаев: базовый, изменённый carb_ratio, добавленные углеводы
        let syn = makeSyntheticCarbsCase(grams: 12)
        let cases: [(name: String, profile: RawJSON, clock: RawJSON, carbs: RawJSON, glucose: RawJSON)] = [
            ("baseline", baseProfile, baseClock, emptyCarbHistory(), baseGlucose),
            ("cr+", ensureCarbRatio(baseProfile, default: 14), baseClock, emptyCarbHistory(), baseGlucose),
            ("withCarbs", baseProfile, syn.clock, syn.carbs, baseGlucose)
        ]

        for c in cases {
            let js = runJSMeal(
                openAPS: openAPS,
                pumphistory: pumphistory,
                profile: c.profile,
                basalProfile: basalProfile,
                clock: c.clock,
                carbs: c.carbs,
                glucose: c.glucose
            )

            let inputs = MealInputs(
                history: pumphistory,
                profile: c.profile,
                basalprofile: basalProfile,
                clock: c.clock,
                carbs: c.carbs,
                glucose: c.glucose
            )
            let swift = MealCalculator.compute(inputs: inputs)

            if let data = js.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let err = obj["error"] as? String {
                    let stack = (obj["stack"] as? String) ?? ""
                    XCTFail("JS error: \(err) \(stack)")
                    continue
                }
                let jsMealCOB = (obj["mealCOB"] as? NSNumber)?.decimalValue
                let jsCarbs = (obj["carbs"] as? NSNumber)?.decimalValue
                let jsCurr = (obj["currentDeviation"] as? NSNumber)?.decimalValue
                let jsMax = (obj["maxDeviation"] as? NSNumber)?.decimalValue
                let jsMin = (obj["minDeviation"] as? NSNumber)?.decimalValue
                let jsSlopeMax = (obj["slopeFromMaxDeviation"] as? NSNumber)?.decimalValue
                let jsSlopeMin = (obj["slopeFromMinDeviation"] as? NSNumber)?.decimalValue
                let jsAll = obj["allDeviations"] as? [Int]
                let jsNsCarbs = (obj["nsCarbs"] as? NSNumber)?.decimalValue
                let jsBwCarbs = (obj["bwCarbs"] as? NSNumber)?.decimalValue
                let jsJournal = (obj["journalCarbs"] as? NSNumber)?.decimalValue
                let jsBwFound = obj["bwFound"] as? Bool
                let jsAbs = (obj["carbsAbsorbed"] as? NSNumber)?.decimalValue

                XCTAssertEqual(jsMealCOB, swift.mealCOB, "\(c.name) mealCOB parity")
                XCTAssertEqual(jsCarbs, swift.carbs, "\(c.name) carbs parity")
                XCTAssertEqual(jsCurr, swift.currentDeviation, "\(c.name) currentDeviation parity")
                XCTAssertEqual(jsMax, swift.maxDeviation, "\(c.name) maxDeviation parity")
                XCTAssertEqual(jsMin, swift.minDeviation, "\(c.name) minDeviation parity")
                XCTAssertEqual(jsSlopeMax, swift.slopeFromMaxDeviation, "\(c.name) slopeFromMaxDeviation parity")
                XCTAssertEqual(jsSlopeMin, swift.slopeFromMinDeviation, "\(c.name) slopeFromMinDeviation parity")
                if let jsAll = jsAll {
                    let swiftAll = swift.allDeviations ?? []
                    let normJS = (jsAll == [0]) ? [] : jsAll
                    let normSwift = (swiftAll == [0]) ? [] : swiftAll
                    XCTAssertEqual(normJS, normSwift, "\(c.name) allDeviations parity")
                }
                XCTAssertEqual(jsNsCarbs, swift.nsCarbs, "\(c.name) nsCarbs parity")
                XCTAssertEqual(jsBwCarbs, swift.bwCarbs, "\(c.name) bwCarbs parity")
                XCTAssertEqual(jsJournal, swift.journalCarbs, "\(c.name) journalCarbs parity")
                XCTAssertEqual(jsBwFound, swift.bwFound, "\(c.name) bwFound parity")
                XCTAssertEqual(jsAbs, swift.carbsAbsorbed, "\(c.name) carbsAbsorbed parity")
            }
        }
    }
}
