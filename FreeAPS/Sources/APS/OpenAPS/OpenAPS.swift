import Combine
import Foundation
import JavaScriptCore

final class OpenAPS {
    private let jsWorker = JavaScriptWorker()
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)

    private let storage: FileStorage

    init(storage: FileStorage) {
        self.storage = storage
    }

    func determineBasal(currentTemp: TempBasal, clock: Date = Date()) -> Future<Suggestion?, Never> {
        Future { promise in
            // Gate: if Loop engine is enabled, skip JS path
            if Foundation.Bundle.main.object(forInfoDictionaryKey: "USE_LOOP_ENGINE") as? String == "YES" {
                warning(.openAPS, "JS determineBasal skipped: USE_LOOP_ENGINE is ON")
                promise(.success(nil))
                return
            }
            self.processQueue.async {
                debug(.openAPS, "Start determineBasal")
                // clock
                self.storage.save(clock, as: Monitor.clock)

                // temp_basal
                let tempBasal = currentTemp.rawJSON
                self.storage.save(tempBasal, as: Monitor.tempBasal)

                // meal
                let pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
                let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)
                let glucose = self.loadFileFromStorage(name: Monitor.glucose)
                let profile = self.loadFileFromStorage(name: Settings.profile)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)

                let meal = self.meal(
                    pumphistory: pumpHistory,
                    profile: profile,
                    basalProfile: basalProfile,
                    clock: clock,
                    carbs: carbs,
                    glucose: glucose
                )

                self.storage.save(meal, as: Monitor.meal)

                // iob
                let autosens = self.loadFileFromStorage(name: Settings.autosense)
                let iob = self.iob(
                    pumphistory: pumpHistory,
                    profile: profile,
                    clock: clock,
                    autosens: autosens.isEmpty ? .null : autosens
                )

                self.storage.save(iob, as: Monitor.iob)

                // determine-basal
                let reservoir = self.loadFileFromStorage(name: Monitor.reservoir)

                let suggested = self.determineBasal(
                    glucose: glucose,
                    currentTemp: tempBasal,
                    iob: iob,
                    profile: profile,
                    autosens: autosens.isEmpty ? .null : autosens,
                    meal: meal,
                    microBolusAllowed: true,
                    reservoir: reservoir,
                    pumpHistory: pumpHistory
                )
                debug(.openAPS, "SUGGESTED: \(suggested)")

                if var suggestion = Suggestion(from: suggested) {
                    suggestion.timestamp = suggestion.deliverAt ?? clock
                    self.storage.save(suggestion, as: Enact.suggested)
                    promise(.success(suggestion))
                } else {
                    warning(.openAPS, "Failed to parse suggestion from JavaScript result: \(suggested.prefix(200))...")
                    promise(.success(nil))
                }
            }
        }
    }

    func autosense() -> Future<Autosens?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start autosens")
                let pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
                let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)
                let glucose = self.loadFileFromStorage(name: Monitor.glucose)
                let profile = self.loadFileFromStorage(name: Settings.profile)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
                let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)
                let autosensResult = self.autosense(
                    glucose: glucose,
                    pumpHistory: pumpHistory,
                    basalprofile: basalProfile,
                    profile: profile,
                    carbs: carbs,
                    temptargets: tempTargets
                )

                debug(.openAPS, "AUTOSENS: \(autosensResult)")
                if var autosens = Autosens(from: autosensResult) {
                    autosens.timestamp = Date()
                    self.storage.save(autosens, as: Settings.autosense)
                    promise(.success(autosens))
                } else {
                    warning(.openAPS, "Failed to parse autosens from JavaScript result: \(autosensResult.prefix(200))...")
                    promise(.success(nil))
                }
            }
        }
    }

    func autotune(categorizeUamAsBasal: Bool = false, tuneInsulinCurve: Bool = false) -> Future<Autotune?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start autotune")
                let pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
                let glucose = self.loadFileFromStorage(name: Monitor.glucose)
                let profile = self.loadFileFromStorage(name: Settings.profile)
                let pumpProfile = self.loadFileFromStorage(name: Settings.pumpProfile)
                let carbs = self.loadFileFromStorage(name: Monitor.carbHistory)

                let autotunePreppedGlucose = self.autotunePrepare(
                    pumphistory: pumpHistory,
                    profile: profile,
                    glucose: glucose,
                    pumpprofile: pumpProfile,
                    carbs: carbs,
                    categorizeUamAsBasal: categorizeUamAsBasal,
                    tuneInsulinCurve: tuneInsulinCurve
                )
                debug(.openAPS, "AUTOTUNE PREP: \(autotunePreppedGlucose)")

                let previousAutotune = self.storage.retrieve(Settings.autotune, as: RawJSON.self)

                let autotuneResult = self.autotuneRun(
                    autotunePreparedData: autotunePreppedGlucose,
                    previousAutotuneResult: previousAutotune ?? profile,
                    pumpProfile: pumpProfile
                )

                debug(.openAPS, "AUTOTUNE RESULT: \(autotuneResult)")

                if let autotune = Autotune(from: autotuneResult) {
                    self.storage.save(autotuneResult, as: Settings.autotune)
                    promise(.success(autotune))
                } else {
                    warning(.openAPS, "Failed to parse autotune from JavaScript result: \(autotuneResult.prefix(200))...")
                    promise(.success(nil))
                }
            }
        }
    }

    func makeProfiles(useAutotune: Bool) -> Future<Autotune?, Never> {
        Future { promise in
            debug(.openAPS, "Start makeProfiles")
            self.processQueue.async {
                var preferences = self.loadFileFromStorage(name: Settings.preferences)
                if preferences.isEmpty {
                    preferences = Preferences().rawJSON
                }
                let pumpSettings = self.loadFileFromStorage(name: Settings.settings)
                let bgTargets = self.loadFileFromStorage(name: Settings.bgTargets)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
                let isf = self.loadFileFromStorage(name: Settings.insulinSensitivities)
                let cr = self.loadFileFromStorage(name: Settings.carbRatios)
                let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)
                let model = self.loadFileFromStorage(name: Settings.model)
                let autotune = useAutotune ? self.loadFileFromStorage(name: Settings.autotune) : .empty

                let pumpProfile = self.makeProfile(
                    preferences: preferences,
                    pumpSettings: pumpSettings,
                    bgTargets: bgTargets,
                    basalProfile: basalProfile,
                    isf: isf,
                    carbRatio: cr,
                    tempTargets: tempTargets,
                    model: model,
                    autotune: "null"
                )

                let profile = self.makeProfile(
                    preferences: preferences,
                    pumpSettings: pumpSettings,
                    bgTargets: bgTargets,
                    basalProfile: basalProfile,
                    isf: isf,
                    carbRatio: cr,
                    tempTargets: tempTargets,
                    model: model,
                    autotune: autotune.isEmpty ? .null : autotune
                )

                self.storage.save(pumpProfile, as: Settings.pumpProfile)
                self.storage.save(profile, as: Settings.profile)

                if let tunedProfile = Autotune(from: profile) {
                    promise(.success(tunedProfile))
                    return
                }

                warning(.openAPS, "Failed to parse profile from JavaScript result: \(profile.prefix(200))...")
                promise(.success(nil))
            }
        }
    }

    // MARK: - Private

    private func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.iob))
            worker.evaluate(script: Script(name: Prepare.iob))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                clock,
                autosens
            ])
        }
    }

    private func meal(pumphistory: JSON, profile: JSON, basalProfile: JSON, clock: JSON, carbs: JSON, glucose: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        // Normalize clock to avoid 'clock unzoned' warnings in JS
        let normalizedClock: RawJSON = {
            if let s = clock.rawJSON.data(using: .utf8),
               let dict = (try? JSONSerialization.jsonObject(with: s)) as? [String: Any],
               (dict["date"] as? String) != nil || (dict["timestamp"] as? String) != nil
            {
                return clock.rawJSON
            }
            let iso = ISO8601DateFormatter().string(from: Date())
            let obj: [String: Any] = ["date": iso]
            let data = try! JSONSerialization.data(withJSONObject: obj, options: [])
            return String(data: data, encoding: .utf8)!
        }()
        // Ensure carbs entries have timestamp for JS compatibility
        let normalizedCarbs: RawJSON = {
            guard let data = carbs.rawJSON.data(using: .utf8),
                  var arr = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [[String: Any]]
            else {
                return carbs.rawJSON
            }
            var changed = false
            for index in arr.indices {
                if arr[index]["timestamp"] == nil, let created = arr[index]["created_at"] as? String {
                    arr[index]["timestamp"] = created
                    changed = true
                }
                if arr[index]["eventType"] == nil {
                    arr[index]["eventType"] = "Carb Correction"
                    changed = true
                }
                // Remove "enteredBy" when это локальные записи от приложений (openaps/freeaps), чтобы JS не фильтровал их
                if let by = arr[index]["enteredBy"] as? String {
                    let lower = by.lowercased()
                    if lower.contains("openaps") || lower.contains("freeaps") {
                        arr[index].removeValue(forKey: "enteredBy")
                        changed = true
                    }
                }
            }
            guard changed, let out = try? JSONSerialization.data(withJSONObject: arr, options: []) else {
                return carbs.rawJSON
            }
            return String(data: out, encoding: .utf8) ?? carbs.rawJSON
        }()

        // Debug: preview carbs payload
        if let data = normalizedCarbs.data(using: .utf8),
           let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        {
            let cnt = arr.count
            let preview = String(normalizedCarbs.prefix(300))
            debug(.openAPS, "MEAL input carbs count=\(cnt) preview=\(preview)")
        }

        // JS meal отключён: Swift — источник истины

        // Swift parity harness: compute native result and compare key fields
        let inputs = MealInputs(
            history: pumphistory.rawJSON,
            profile: profile.rawJSON,
            basalprofile: basalProfile.rawJSON,
            clock: normalizedClock,
            carbs: normalizedCarbs,
            glucose: glucose.rawJSON
        )
        let swiftResult = MealCalculator.compute(inputs: inputs)

        // Возвращаем meal, сформированный из Swift
        do {
            var out: [String: Any] = [:]
            if let v = swiftResult.mealCOB { out["mealCOB"] = NSDecimalNumber(decimal: v) }
            if let v = swiftResult.carbs { out["carbs"] = NSDecimalNumber(decimal: v) }
            if let v = swiftResult.carbsAbsorbed { out["carbsAbsorbed"] = NSDecimalNumber(decimal: v) }
            if let v = swiftResult.bwCarbs { out["bwCarbs"] = NSDecimalNumber(decimal: v) }
            if let v = swiftResult.nsCarbs { out["nsCarbs"] = NSDecimalNumber(decimal: v) }
            if let v = swiftResult.journalCarbs { out["journalCarbs"] = NSDecimalNumber(decimal: v) }
            if let v = swiftResult.bwFound { out["bwFound"] = v }
            if let v = swiftResult.reason { out["reason"] = v }
            if let v = swiftResult.lastCarbTime { out["lastCarbTime"] = Formatter.iso8601withFractionalSeconds.string(from: v) }
            if let v = swiftResult.lastMealTime { out["mealTime"] = Formatter.iso8601withFractionalSeconds.string(from: v) }
            if let v = swiftResult.currentDeviation { out["currentDeviation"] = NSDecimalNumber(decimal: v) }
            if let v = swiftResult.maxDeviation { out["maxDeviation"] = NSDecimalNumber(decimal: v) }
            if let v = swiftResult.minDeviation { out["minDeviation"] = NSDecimalNumber(decimal: v) }
            if let v = swiftResult.slopeFromMaxDeviation { out["slopeFromMaxDeviation"] = NSDecimalNumber(decimal: v) }
            if let v = swiftResult.slopeFromMinDeviation { out["slopeFromMinDeviation"] = NSDecimalNumber(decimal: v) }
            if let v = swiftResult.allDeviations { out["allDeviations"] = v }
            let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .withoutEscapingSlashes])
            let raw = String(data: data, encoding: .utf8) ?? "{}"
            debug(.openAPS, "MEAL swift output used")
            return raw
        } catch {
            warning(.openAPS, "Failed to encode Swift meal JSON: \(error.localizedDescription)")
            return "{}"
        }
    }

    private func autotunePrepare(
        pumphistory: JSON,
        profile: JSON,
        glucose: JSON,
        pumpprofile: JSON,
        carbs: JSON,
        categorizeUamAsBasal: Bool,
        tuneInsulinCurve: Bool
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.autotunePrep))
            worker.evaluate(script: Script(name: Prepare.autotunePrep))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                glucose,
                pumpprofile,
                carbs,
                categorizeUamAsBasal,
                tuneInsulinCurve
            ])
        }
    }

    private func autotuneRun(
        autotunePreparedData: JSON,
        previousAutotuneResult: JSON,
        pumpProfile: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.autotuneCore))
            worker.evaluate(script: Script(name: Prepare.autotuneCore))
            return worker.call(function: Function.generate, with: [
                autotunePreparedData,
                previousAutotuneResult,
                pumpProfile
            ])
        }
    }

    private func determineBasal(
        glucose: JSON,
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: JSON,
        pumpHistory: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Prepare.determineBasal))
            worker.evaluate(script: Script(name: Bundle.basalSetTemp))
            worker.evaluate(script: Script(name: Bundle.getLastGlucose))
            worker.evaluate(script: Script(name: Bundle.determineBasal))

            if let middleware = self.middlewareScript(name: OpenAPS.Middleware.determineBasal) {
                worker.evaluate(script: middleware)
            }

            return worker.call(
                function: Function.generate,
                with: [
                    iob,
                    currentTemp,
                    glucose,
                    profile,
                    autosens,
                    meal,
                    microBolusAllowed,
                    reservoir,
                    false, // clock
                    pumpHistory
                ]
            )
        }
    }

    private func autosense(
        glucose: JSON,
        pumpHistory: JSON,
        basalprofile: JSON,
        profile: JSON,
        carbs: JSON,
        temptargets: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.autosens))
            worker.evaluate(script: Script(name: Prepare.autosens))
            return worker.call(
                function: Function.generate,
                with: [
                    glucose,
                    pumpHistory,
                    basalprofile,
                    profile,
                    carbs,
                    temptargets
                ]
            )
        }
    }

    private func exportDefaultPreferences() -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.profile))
            worker.evaluate(script: Script(name: Prepare.profile))
            return worker.call(function: Function.exportDefaults, with: [])
        }
    }

    private func makeProfile(
        preferences: JSON,
        pumpSettings: JSON,
        bgTargets: JSON,
        basalProfile: JSON,
        isf: JSON,
        carbRatio: JSON,
        tempTargets: JSON,
        model: JSON,
        autotune: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.profile))
            worker.evaluate(script: Script(name: Prepare.profile))
            return worker.call(
                function: Function.generate,
                with: [
                    pumpSettings,
                    bgTargets,
                    isf,
                    basalProfile,
                    preferences,
                    carbRatio,
                    tempTargets,
                    model,
                    autotune
                ]
            )
        }
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Foundation.Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }

    private func loadFileFromStorage(name: String) -> RawJSON {
        storage.retrieveRaw(name) ?? OpenAPS.defaults(for: name)
    }

    private func middlewareScript(name: String) -> Script? {
        if let body = storage.retrieveRaw(name) {
            return Script(name: "Middleware", body: body)
        }

        if let url = Foundation.Bundle.main.url(forResource: "javascript/\(name)", withExtension: "") {
            return Script(name: "Middleware", body: try! String(contentsOf: url))
        }

        return nil
    }

    static func defaults(for file: String) -> RawJSON {
        let prefix = file.hasSuffix(".json") ? "json/defaults" : "javascript"
        guard let url = Foundation.Bundle.main.url(forResource: "\(prefix)/\(file)", withExtension: "") else {
            return ""
        }
        return (try? String(contentsOf: url)) ?? ""
    }
}
