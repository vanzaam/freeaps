import Combine
import Foundation
// Access DeletedTreatmentsStore blacklist
import JavaScriptCore

final class OpenAPS {
    private let jsWorker = JavaScriptWorker()
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)

    private let storage: FileStorage
    private var smbBasalMiddleware: SmbBasalMiddleware?

    init(storage: FileStorage) {
        self.storage = storage
    }

    func setSmbBasalMiddleware(_ middleware: SmbBasalMiddleware) {
        smbBasalMiddleware = middleware
    }

    // 🎯 Структура для чтения Custom IOB данных из FileStorage
    private struct CustomIOBData: JSON {
        let totalIOB: Double
        let bolusIOB: Double
        let basalIOB: Double
        let calculationTime: Double
        let debugInfo: String
    }

    private func getCustomIOBData() -> String? {
        debug(.openAPS, "🔍 Attempting to load Custom IOB data from middleware/custom-iob.json")

        if let customIOBData = storage.retrieve("middleware/custom-iob.json", as: CustomIOBData.self) {
            debug(.openAPS, "✅ Custom IOB data loaded successfully from main location!")
            debug(
                .openAPS,
                "📊 Total IOB: \(customIOBData.totalIOB)U, Bolus: \(customIOBData.bolusIOB)U, Basal: \(customIOBData.basalIOB)U"
            )
            return convertToJsonString(customIOBData)
        }

        // 🆘 FALLBACK: Попробуем читать из backup файла
        if let customIOBData = storage.retrieve("custom-iob-backup.json", as: CustomIOBData.self) {
            debug(.openAPS, "✅ Custom IOB data loaded from BACKUP location!")
            debug(
                .openAPS,
                "📊 Total IOB: \(customIOBData.totalIOB)U, Bolus: \(customIOBData.bolusIOB)U, Basal: \(customIOBData.basalIOB)U"
            )
            return convertToJsonString(customIOBData)
        }

        debug(.openAPS, "❌ Custom IOB data not found in main or backup locations")
        return nil
    }

    private func convertToJsonString(_ customIOBData: CustomIOBData) -> String? {
        // Преобразуем в JSON строку для JavaScript
        do {
            let jsonData = try JSONEncoder().encode(customIOBData)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            debug(.openAPS, "🔄 Converted to JSON string for JavaScript: \(String(jsonString.prefix(150)))...")
            return jsonString
        } catch {
            debug(.openAPS, "❌ Failed to convert CustomIOBData to JSON: \(error)")
            return nil
        }
    }

    func determineBasal(currentTemp: TempBasal, clock: Date = Date()) -> Future<Suggestion?, Never> {
        Future { promise in
            self.processQueue.async {
                debug(.openAPS, "Start determineBasal")

                // 🚨 ОТКЛЮЧЕНО: Custom IOB расчеты отключены вместе с middleware
                // if let middleware = self.smbBasalMiddleware as? BaseSmbBasalMiddleware {
                //     middleware.updateCustomIOBForMiddleware()
                // }

                // clock
                self.storage.save(clock, as: Monitor.clock)

                // temp_basal - оставляем реальные данные помпы без изменений
                let tempBasal = currentTemp.rawJSON
                self.storage.save(tempBasal, as: Monitor.tempBasal)

                // meal
                var pumpHistory = self.loadFileFromStorage(name: OpenAPS.Monitor.pumpHistory)
                // Filter locally deleted boluses from pumpHistory JSON before IOB/meal
                pumpHistory = self.filterDeletedBoluses(in: pumpHistory)
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

                // Debug: Log pumpHistory before IOB calculation
                print("OpenAPS: PumpHistory before IOB calculation (first 500 chars): \(pumpHistory.prefix(500))")

                let iob = self.iob(
                    pumphistory: pumpHistory,
                    profile: profile,
                    clock: clock,
                    autosens: autosens.isEmpty ? .null : autosens
                )

                // Debug: Log IOB result
                print("OpenAPS: IOB calculation result: \(iob.prefix(200))")

                // Override saved Monitor.iob with synthesized JSON based on Custom IOB (to avoid negative/system IOB drift)
                var iobToSave = iob
                if let customIOBData = self.storage.retrieve("middleware/custom-iob.json", as: CustomIOBData.self) {
                    let activity = max(customIOBData.totalIOB * 0.0025, 0.001)
                    let timeString = ISO8601DateFormatter().string(from: Date())
                    let entry: [String: Any?] = [
                        "iob": customIOBData.totalIOB,
                        "activity": activity,
                        "basaliob": customIOBData.basalIOB,
                        "bolusiob": customIOBData.bolusIOB,
                        "netbasalinsulin": customIOBData.basalIOB,
                        "bolusinsulin": customIOBData.bolusIOB,
                        "time": timeString,
                        "lastBolusTime": nil,
                        "lastTemp": nil,
                        "iobWithZeroTemp": nil
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: [entry], options: []),
                       let json = String(data: data, encoding: .utf8)
                    {
                        debug(
                            .openAPS,
                            "🔧 Overriding Monitor.iob with CustomIOB (was JS IOB). TotalIOB=\(customIOBData.totalIOB)"
                        )
                        iobToSave = json
                    }
                }

                self.storage.save(iobToSave, as: Monitor.iob)

                // determine-basal
                let reservoir = self.loadFileFromStorage(name: Monitor.reservoir)

                var suggested = self.determineBasal(
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
                // Override IOB in suggestion with Custom IOB (to avoid negative IOB from 0 U/h SMB-basal)
                if let customIOBData = self.storage.retrieve("middleware/custom-iob.json", as: CustomIOBData.self) {
                    if let suggestedData = suggested.data(using: .utf8),
                       var suggestedDict = try? JSONSerialization.jsonObject(with: suggestedData) as? [String: Any]
                    {
                        let oldIOB = suggestedDict["IOB"]
                        suggestedDict["IOB"] = customIOBData.totalIOB
                        if let newData = try? JSONSerialization.data(withJSONObject: suggestedDict, options: []),
                           let newSuggested = String(data: newData, encoding: .utf8)
                        {
                            debug(
                                .openAPS,
                                "🔧 Overriding Suggestion IOB: old=\(String(describing: oldIOB)) → new=\(customIOBData.totalIOB)"
                            )
                            suggested = newSuggested
                        }
                    }
                }
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
                    autotune: RawJSON.null
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
            // Filter out SMB-basal pulses from pumpHistory fed to IOB to avoid double-counting background insulin
            // SMB basal pulses are stored separately; pump history contains actual delivered insulin from pump
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                clock,
                autosens
            ])
        }
    }

    // Remove locally deleted boluses for last 24h from pumpHistory RawJSON
    // Ensures SMB boluses are included in IOB calculation unless manually deleted
    private func filterDeletedBoluses(in pumpHistory: RawJSON) -> RawJSON {
        guard let data = pumpHistory.data(using: .utf8),
              var array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return pumpHistory }

        let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let recentCutoff = Date().addingTimeInterval(-120) // don't filter very recent boluses (<2 min)

        // Get SMB-basal pulses to avoid filtering them
        let smbBasalPulses = storage.retrieve(OpenAPS.Monitor.smbBasalPulses, as: [SmbBasalPulse].self) ?? []

        array.removeAll { dict in
            guard let type = dict["_type"] as? String,
                  type.lowercased().contains("bolus") || type.lowercased() == "smb" else { return false }
            // created_at or timestamp
            let dateString = (dict["created_at"] as? String) ?? (dict["timestamp"] as? String) ?? ""
            guard let date = Formatter.iso8601withFractionalSeconds.date(from: dateString) else { return false }
            guard date > dayAgo else { return false }
            // Keep very recent boluses to ensure IOB reflects them immediately
            guard date < recentCutoff else { return false }
            // Try both "insulin" and "amount" fields for bolus amount
            let insulinField = dict["insulin"] as? NSNumber
            let amountField = dict["amount"] as? NSNumber
            let insulin = insulinField?.decimalValue ?? amountField?.decimalValue

            // Debug logging for SMB boluses
            if type.lowercased() == "smb" {
                print(
                    "OpenAPS: SMB bolus debug - insulin field: \(insulinField), amount field: \(amountField), final insulin: \(insulin)"
                )
            }

            // Don't filter SMB-Basal pulses - they should always contribute to IOB calculation
            let isSmbBasal = smbBasalPulses.contains { pulse in
                let timeDiff = abs(date.timeIntervalSince(pulse.timestamp))
                let amountMatch = abs((insulin ?? 0) - pulse.units) < 0.001
                return timeDiff < 30 && amountMatch
            }

            if isSmbBasal {
                return false // Never filter SMB-Basal pulses
            }

            // Check if it's a regular SMB bolus (not SMB-Basal)
            let isSmbBolus = type.lowercased() == "smb"

            // Only filter manually deleted boluses
            // SMB boluses should always be included in IOB unless manually deleted
            if isSmbBolus {
                // SMB boluses are only filtered if manually deleted
                let shouldFilter = DeletedTreatmentsStore.shared.containsBolus(date: date, amount: insulin)
                print("OpenAPS: SMB bolus \(insulin)U at \(date) - shouldFilter: \(shouldFilter)")
                return shouldFilter
            }

            // Regular boluses - filter if manually deleted
            let shouldFilter = DeletedTreatmentsStore.shared.containsBolus(date: date, amount: insulin)
            print("OpenAPS: Regular bolus \(insulin)U at \(date) - shouldFilter: \(shouldFilter)")
            return shouldFilter
        }

        if let filteredData = try? JSONSerialization.data(withJSONObject: array),
           let filteredString = String(data: filteredData, encoding: .utf8)
        {
            return filteredString
        }
        return pumpHistory
    }

    private func meal(pumphistory: JSON, profile: JSON, basalProfile: JSON, clock: JSON, carbs: JSON, glucose: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluate(script: Script(name: Prepare.log))
            worker.evaluate(script: Script(name: Bundle.meal))
            worker.evaluate(script: Script(name: Prepare.meal))
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                clock,
                glucose,
                basalProfile,
                carbs
            ])
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

            // 🚨 СРОЧНО ОТКЛЮЧЕНО: Middleware вызывает критически низкие прогнозы (8.5 mg/dL)!
            // Это опасно для жизни! Нужно исследовать проблему.
            debug(.openAPS, "⚠️ MIDDLEWARE ОТКЛЮЧЕН из-за критических ошибок в прогнозах!")

            // if let middleware = self.middlewareScript(name: OpenAPS.Middleware.determineBasal) {
            //     // Middleware temporarily disabled due to dangerous prediction errors
            // }

            // Pass current clock as Date (JSON encodes to quoted ISO8601 string)
            let clockNow = Date()
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
                    clockNow, // clock as JSON string
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
