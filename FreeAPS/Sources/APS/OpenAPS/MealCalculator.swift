import Foundation

// Swift mirror for JS meal calculation results. This will be filled to match JS logic exactly.
struct MealResult: JSON {
    // Common JS fields observed from determine-basal usage and meal.js outputs
    var mealCOB: Decimal? // carbs on board (g)
    var carbs: Decimal? // total carbs detected / entered (g)
    var reason: String?

    // Additional fields often present in oref0 meal outputs (reserve for parity)
    var lastCarbTime: Date?
    var lastMealTime: Date?
    var bwCarbs: Decimal? // bolus wizard carbs
    var uam: Decimal? // unannounced meal signal/flag value

    // Aggregated categories and diagnostics
    var nsCarbs: Decimal?
    var journalCarbs: Decimal?
    var bwFound: Bool?

    // Deviations (rounded as in JS)
    var currentDeviation: Decimal?
    var maxDeviation: Decimal?
    var minDeviation: Decimal?
    var slopeFromMaxDeviation: Decimal?
    var slopeFromMinDeviation: Decimal?
    var allDeviations: [Int]?

    // Internal diagnostic used by aggregator
    var carbsAbsorbed: Decimal?
}

// Input container mirroring what JS receives
struct MealInputs: JSON {
    var history: RawJSON // pump history JSON string
    var profile: RawJSON // tuned profile JSON string
    var basalprofile: RawJSON // basal profile JSON string
    var clock: RawJSON // clock JSON string
    var carbs: RawJSON // carb history JSON string
    var glucose: RawJSON // glucose JSON string
}

/// Native Swift meal calculator. Initially implements the same guards and fallbacks as JS prepare/meal.js.
/// We will iteratively fill compute(inputs:) to match the JS algorithm bit-for-bit and validate via parity harness.
enum MealCalculator {
    private static let traceEnabled: Bool = {
        if let v = Bundle.main.object(forInfoDictionaryKey: "MEAL_TRACE") as? String, v == "1" { return true }
        return ProcessInfo.processInfo.environment["MEAL_TRACE"] == "1"
    }()

    private static func trace(_ message: String) {
        if traceEnabled { debug(.openAPS, "MealTrace: \(message)") }
    }

    /// Top-level: full aggregator result (JS module 2638) built on the core compute.
    static func compute(inputs: MealInputs) -> MealResult {
        aggregate(inputs: inputs)
    }

    // MARK: - Aggregator (module 2638)

    private static func aggregate(inputs: MealInputs) -> MealResult {
        // Parse treatments (carb history). We expect items with created_at and carbs, optionally nsCarbs/bwCarbs/journalCarbs
        let now = nowFromClockJSON(inputs.clock) ?? Date()
        let windowStart = Date(timeInterval: -6 * 3600, since: now)
        let treatments: [[String: Any]] = decodeJSONArray(inputs.carbs)?.compactMap { $0 as? [String: Any] } ?? []

        // Totals
        var totalCarbs: Decimal = 0
        var includedCarbsSum: Decimal = 0
        var totalNsCarbs: Decimal = 0
        var totalBwCarbs: Decimal = 0
        var totalJournalCarbs: Decimal = 0
        var bwFound = false
        var lastCarbTime: Date?
        var mealCOB: Decimal = 0

        // Partition trackers
        var partCarbs: Decimal = 0
        var partNs: Decimal = 0
        var partBw: Decimal = 0
        var partJournal: Decimal = 0

        // Sort by timestamp desc
        let sorted = treatments.sorted { a, b in
            let ta = dateFromAny(a["timestamp"] ?? a["created_at"]) ?? .distantPast
            let tb = dateFromAny(b["timestamp"] ?? b["created_at"]) ?? .distantPast
            return ta > tb
        }

        var coreMealTime: Date = now
        var maxCOBObserved: Decimal = 0
        var lastAbsorbed: Decimal = 0
        var includedEvents = 0
        var sawCOBPeak = false
        for ev in sorted {
            guard let ts = dateFromAny(ev["timestamp"] ?? ev["created_at"]) else { continue }
            guard ts > windowStart, ts <= now else { continue }
            let carbsVal = decimalAny(ev["carbs"]) ?? 0
            guard carbsVal >= 1 else { continue }

            // Categories if present
            let nsVal = decimalAny(ev["nsCarbs"]) ?? 0
            let bwVal = decimalAny(ev["bwCarbs"]) ?? 0
            let journalVal = decimalAny(ev["journalCarbs"]) ?? 0

            // Totals
            totalCarbs += carbsVal
            includedCarbsSum += carbsVal
            includedEvents += 1
            if nsVal >= 1 { totalNsCarbs += nsVal }
            else if bwVal >= 1 { totalBwCarbs += bwVal
                bwFound = true } else if journalVal >= 1 { totalJournalCarbs += journalVal }

            coreMealTime = ts
            lastCarbTime = max(lastCarbTime ?? ts, ts)

            // Compute carbsAbsorbed at given mealTime
            let core = computeCore(inputs: inputs, ciTime: now, mealTime: ts)
            let absorbed = core.carbsAbsorbed
            lastAbsorbed = absorbed
            // JS uses COB drop detection on a running COB series, not the simple sum
            // Approximate with lastAbsorbed against included sum up to current event
            let l = max(0, includedCarbsSum - absorbed)
            trace(
                "agg ev ts=\(ts) carbs=\(carbsVal) totalCarbsBefore=\(totalCarbs) absorbed=\(absorbed) l=\(l) maxCOBObservedBefore=\(maxCOBObserved)"
            )
            if !sawCOBPeak || l > maxCOBObserved {
                maxCOBObserved = l
                sawCOBPeak = true
                // reset partition trackers
                partCarbs = 0
                partNs = 0
                partBw = 0
                partJournal = 0
                trace("agg increase -> maxCOBObserved=\(maxCOBObserved), reset partition")
            } else if l < maxCOBObserved {
                // l decreased: accumulate partition to remove later
                partCarbs += carbsVal
                if nsVal >= 1 { partNs += nsVal }
                else if bwVal >= 1 { partBw += bwVal }
                else if journalVal >= 1 { partJournal += journalVal }
                trace("agg decrease -> partCarbs+=\(carbsVal) (ns=\(partNs) bw=\(partBw) journal=\(partJournal))")
            }
        }

        // Remove last partition
        totalCarbs -= partCarbs
        totalNsCarbs -= partNs
        totalBwCarbs -= partBw
        totalJournalCarbs -= partJournal
        trace(
            "agg after partition removal: totalCarbs=\(totalCarbs) ns=\(totalNsCarbs) bw=\(totalBwCarbs) journal=\(totalJournalCarbs)"
        )
        trace("agg meta: includedEvents=\(includedEvents) partCarbs=\(partCarbs) maxCOBObserved=\(maxCOBObserved)")
        // Fallback parity with JS: if we have one included event and no partition to remove, keep its carbs
        if includedEvents == 1, partCarbs == 0, totalCarbs == 0 {
            if let only = sorted.first, let v = decimalAny(only["carbs"]) { totalCarbs = v }
        }
        var finalReportedCarbs = max(0, includedCarbsSum - partCarbs)
        trace(
            "agg report pre-fix: includedCarbsSum=\(includedCarbsSum) partCarbs=\(partCarbs) -> finalReportedCarbs=\(finalReportedCarbs)"
        )
        if includedEvents >= 1, partCarbs == 0, finalReportedCarbs == 0 {
            // Defensive parity: single fresh entry should be reported as-is
            finalReportedCarbs = includedCarbsSum
            trace("agg report single-event fix -> finalReportedCarbs=\(finalReportedCarbs)")
        }
        if finalReportedCarbs == 0 {
            // Extra safety: sum carbs within window directly from input
            let rawArr = decodeJSONArray(inputs.carbs)?.compactMap { $0 as? [String: Any] } ?? []
            var sum: Decimal = 0
            for e in rawArr {
                guard let ts = dateFromAny(e["timestamp"] ?? e["created_at"]) else { continue }
                guard ts > windowStart, ts <= now else { continue }
                let v = decimalAny(e["carbs"]) ?? 0
                if v >= 1 { sum += v }
            }
            if sum > 0 { finalReportedCarbs = sum }
            trace("agg report sum-from-raw fix -> sum=\(sum) finalReportedCarbs=\(finalReportedCarbs)")
        }

        // Current deviations (for safety conditions)
        let coreNow = computeCore(inputs: inputs, ciTime: now, mealTime: Date(timeInterval: -6 * 3600, since: now))

        // Compute current remaining COB and clamp by maxCOB (JS parity)
        let profileDict = decodeJSONDictionary(inputs.profile) ?? [:]
        let maxCOB = (profileDict["maxCOB"] as? NSNumber)?.decimalValue ?? 120
        let currentCOBNow = max(0, finalReportedCarbs - lastAbsorbed)
        mealCOB = min(maxCOB, currentCOBNow)

        // Assemble result mirroring JS rounding (module 2638)
        // Use deviations as computed by core
        let finalAllDeviations = coreNow.allDeviations.count < 2 ? [] : coreNow.allDeviations
        // JS returns numeric defaults when insufficient data: maxDev=0, minDev=999, slopeMax=0, slopeMin=999
        let devCount = finalAllDeviations.count
        let normalizedMaxDev: Decimal? = devCount < 2 ? 0 : coreNow.maxDeviation
        let normalizedMinDev: Decimal? = devCount < 2 ? 999 : coreNow.minDeviation
        let normalizedSlopeMax: Decimal? = devCount < 2 ? 0 : coreNow.slopeFromMaxDeviation
        let normalizedSlopeMin: Decimal? = devCount < 2 ? 999 : coreNow.slopeFromMinDeviation

        let result = MealResult(
            mealCOB: round0(mealCOB),
            carbs: round3(finalReportedCarbs),
            reason: nil,
            lastCarbTime: lastCarbTime,
            lastMealTime: coreNow.mealTime,
            bwCarbs: round3(totalBwCarbs),
            uam: computeUAMFlag(core: coreNow),
            nsCarbs: round3(totalNsCarbs),
            journalCarbs: round3(totalJournalCarbs),
            bwFound: bwFound,
            currentDeviation: round2(coreNow.currentDeviation),
            maxDeviation: round2(normalizedMaxDev),
            minDeviation: round2(normalizedMinDev),
            slopeFromMaxDeviation: normalizedSlopeMax.map { round3($0) },
            slopeFromMinDeviation: normalizedSlopeMin.map { round3($0) },
            allDeviations: finalAllDeviations,
            carbsAbsorbed: lastAbsorbed == 0 ? nil : round3(lastAbsorbed)
        )
        return result
    }

    // MARK: - Core compute (module 6873)

    private struct CoreResult {
        let carbsAbsorbed: Decimal
        let currentDeviation: Decimal?
        let maxDeviation: Decimal?
        let minDeviation: Decimal?
        let slopeFromMaxDeviation: Decimal?
        let slopeFromMinDeviation: Decimal?
        let allDeviations: [Int]
        let mealTime: Date
    }

    private static func computeCore(inputs: MealInputs, ciTime: Date, mealTime: Date) -> CoreResult {
        // Profile
        let profileDict = decodeJSONDictionary(inputs.profile) ?? [:]
        let carbRatio: Decimal = (profileDict["carb_ratio"] as? NSNumber)?.decimalValue ?? 0
        let min5mCarbImpact: Decimal = (profileDict["min_5m_carbimpact"] as? NSNumber)?.decimalValue ?? 8
        let isfProfile = (profileDict["isfProfile"] as? [String: Any]) ?? [:]
        let sensitivities = (isfProfile["sensitivities"] as? [[String: Any]]) ?? []
        let basalSchedule = decodeJSONArray(inputs.basalprofile)?.compactMap { $0 as? [String: Any] } ?? []
        let glucoseArray = decodeJSONArray(inputs.glucose) ?? []

        var b: [[String: Any]] = glucoseArray.compactMap { item in
            guard var it = item as? [String: Any] else { return nil }
            if it["glucose"] == nil, let sgv = it["sgv"] { it["glucose"] = sgv }
            return it
        }

        // Aggregate A[]
        var A: [[String: Any]] = []
        if let first = b.first { A.append(first) }
        var s = 0
        var qIndex = 0
        if b.first == nil || (b.first?["glucose"] as? NSNumber)?.intValue ?? 0 < 39 { qIndex = -1 }
        if b.count > 1 {
            for u in 1 ..< b.count {
                guard let cur = (b[u] as? [String: Any]) ?? b[u] as? [String: Any],
                      let glucose = (cur["glucose"] as? NSNumber)?.intValue, glucose >= 39 else { continue }
                guard let currentTime = bgDate(cur) else { continue }
                let hoursFromMeal = currentTime.timeIntervalSince(mealTime) / 3600
                if hoursFromMeal > 6 { break }
                let ciWindow = ciTime.timeIntervalSince(currentTime) / (45 * 60)
                if ciWindow > 1 || ciWindow < 0 { continue }
                let lastBGTime: Date? = {
                    if let last = A.last, let t = bgDate(last) { return t }
                    if qIndex >= 0 { return bgDate(b[qIndex]) }
                    return nil
                }()
                guard let W = lastBGTime else { continue }
                var L = Int(currentTime.timeIntervalSince(W) / 60)
                if abs(L) > 8 {
                    var f: Double = {
                        if qIndex >= 0, let n = (b[qIndex]["glucose"] as? NSNumber)?.doubleValue { return n }
                        if let n = (A.last?["glucose"] as? NSNumber)?.doubleValue { return n }
                        return Double(glucose)
                    }()
                    var Lrem = min(240, abs(L))
                    var lastTime = W
                    while Lrem > 5 {
                        let h = Date(timeInterval: -300, since: lastTime)
                        s += 1
                        if A.count <= s { A.append([:]) }
                        A[s]["date"] = h.timeIntervalSince1970 * 1000
                        let R = f + 5.0 / Double(Lrem) * (Double(glucose) - f)
                        A[s]["glucose"] = NSNumber(value: round(R))
                        Lrem -= 5
                        f = R
                        lastTime = h
                    }
                } else if abs(L) > 2 {
                    s += 1
                    if A.count <= s { A.append([:]) }
                    A[s] = cur
                    A[s]["date"] = currentTime.timeIntervalSince1970 * 1000
                } else {
                    let prevG = (A[s]["glucose"] as? NSNumber)?.doubleValue ?? 0
                    A[s]["glucose"] = NSNumber(value: (prevG + Double(glucose)) / 2)
                }
                qIndex = u
            }
        }

        var carbsAbsorbed: Decimal = 0
        var currentDeviation: Decimal?
        var maxDeviation: Decimal?
        var minDeviation: Decimal?
        var slopeFromMaxDeviation: Decimal?
        var slopeFromMinDeviation: Decimal?
        var lastMaxDev: Decimal = -999
        var lastMinDev: Decimal = 999
        var allDeviations: [Int] = []

        trace("Starting loop: A.count=\(A.count), loop range: 0..<\(max(0, A.count - 3))")
        for u in 0 ..< max(0, A.count - 3) {
            guard let Dn = (A[u]["glucose"] as? NSNumber)?.doubleValue, Dn >= 39,
                  let g3 = (A[u + 3]["glucose"] as? NSNumber)?.doubleValue, g3 >= 39,
                  let t0 = bgDate(A[u]),
                  let g1 = (A[u + 1]["glucose"] as? NSNumber)?.doubleValue else { continue }
            let k = (Dn - g3) / 3.0
            let N = Dn - g1
            let isf = Double(isfLookup(sensitivities: sensitivities, at: t0))
            _ = basalLookup(schedule: basalSchedule, at: t0)
            let activity = jsActivityAt(clock: t0, pumphistory: inputs.history, profile: inputs.profile)
            let w = round((-activity * isf * 5) * 100) / 100
            let v = N - w
            trace("u=\(u) t0=\(t0) Dn=\(Dn) g1=\(g1) g3=\(g3) k=\(k) N=\(N) isf=\(isf) activity=\(activity) w=\(w) v=\(v)")
            if u == 0 {
                currentDeviation = Decimal(round((k - w) * 1000) / 1000)
                // JS часто пушит первый r даже при равенстве времени; добавим безусловно для паритета
                allDeviations.append(Int(NSDecimalNumber(decimal: currentDeviation!).intValue))
                trace("Initial deviation added: \(currentDeviation!) -> allDeviations=\(allDeviations)")
            } else {
                let S = round((k - w) * 1000) / 1000
                trace("u=\(u) S=\(S) ciTime=\(ciTime) t0=\(t0) ciTime>t0=\(ciTime > t0)")
                if ciTime > t0 {
                    let deltaMinutes = ciTime.timeIntervalSince(t0) / 60
                    if deltaMinutes > 0 {
                        let F = (S - Double(truncating: NSDecimalNumber(decimal: currentDeviation ?? 0))) / deltaMinutes * 5
                        if S > Double(truncating: NSDecimalNumber(decimal: lastMaxDev)) {
                            slopeFromMaxDeviation = Decimal(min(0, F))
                            lastMaxDev = Decimal(S)
                            maxDeviation = max(maxDeviation ?? -1E9, Decimal(S))
                            trace("updateMax S=\(S) F=\(F) maxDev=\(String(describing: maxDeviation)) lastMax=\(lastMaxDev)")
                        }
                        if S < Double(truncating: NSDecimalNumber(decimal: lastMinDev)) {
                            slopeFromMinDeviation = Decimal(max(0, F))
                            lastMinDev = Decimal(S)
                            minDeviation = min(minDeviation ?? 1E9, Decimal(S))
                            trace("updateMin S=\(S) F=\(F) minDev=\(String(describing: minDeviation)) lastMin=\(lastMinDev)")
                        }
                    }
                    allDeviations.append(Int(S.rounded()))
                    trace("S=\(S) allDeviations.count=\(allDeviations.count)")
                }
            }
            if t0 > mealTime {
                let maxComponent = max(Decimal(v), (currentDeviation ?? 0) / 2, min5mCarbImpact)
                if isf > 0 {
                    let deltaCarbs = maxComponent * carbRatio / Decimal(isf)
                    carbsAbsorbed += deltaCarbs
                    trace("absorb maxComp=\(maxComponent) deltaCarbs=\(deltaCarbs) carbsAbsorbed=\(carbsAbsorbed)")
                }
            }
        }

        return CoreResult(
            carbsAbsorbed: carbsAbsorbed,
            currentDeviation: currentDeviation,
            maxDeviation: maxDeviation,
            minDeviation: minDeviation,
            slopeFromMaxDeviation: slopeFromMaxDeviation,
            slopeFromMinDeviation: slopeFromMinDeviation,
            allDeviations: allDeviations,
            mealTime: mealTime
        )
    }

    // MARK: - Helpers

    private static func decodeJSONArray(_ s: String) -> [Any]? {
        guard let data = s.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any] else { return nil }
        return arr
    }

    private static func decodeJSONDictionary(_ s: String) -> [String: Any]? {
        guard let data = s.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return nil }
        return dict
    }

    private static func bgDate(_ item: [String: Any]) -> Date? {
        if let disp = item["display_time"] as? String { return DateFormatter.iso8601Flexible(dateString: disp) }
        if let dstr = item["dateString"] as? String { return DateFormatter.iso8601Flexible(dateString: dstr) }
        if let ms = item["date"] as? NSNumber { return Date(timeIntervalSince1970: ms.doubleValue / 1000.0) }
        return nil
    }

    private static func nowFromClockJSON(_ s: String) -> Date? {
        if let dict = decodeJSONDictionary(s) {
            if let ds = dict["date"] as? String { return DateFormatter.iso8601Flexible(dateString: ds) }
            if let ts = dict["timestamp"] as? String { return DateFormatter.iso8601Flexible(dateString: ts) }
        }
        return nil
    }

    private static func basalLookup(schedule: [[String: Any]], at date: Date) -> Decimal {
        let minutes = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
        var selected: Decimal = 0
        var lastStart = -1
        for e in schedule {
            let start = (e["minutes"] as? NSNumber)?.intValue ?? (e["i"] as? NSNumber)?.intValue ?? -1
            let rate = (e["rate"] as? NSNumber)?.decimalValue ?? 0
            if start <= minutes, start >= lastStart { selected = rate
                lastStart = start }
        }
        return selected
    }

    private static func isfLookup(sensitivities: [[String: Any]], at date: Date) -> Decimal {
        let minutes = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
        let sorted = sensitivities.sorted { (a, b) -> Bool in
            let oa = (a["offset"] as? NSNumber)?.intValue ?? 0
            let ob = (b["offset"] as? NSNumber)?.intValue ?? 0
            return oa < ob
        }
        var current: Decimal = (sorted.last?["sensitivity"] as? NSNumber)?.decimalValue ?? 0
        for i in 0 ..< max(0, sorted.count - 1) {
            let s = sorted[i]
            let e = sorted[i + 1]
            let off = (s["offset"] as? NSNumber)?.intValue ?? 0
            let nextOff = (e["offset"] as? NSNumber)?.intValue ?? 1440
            if minutes >= off, minutes < nextOff { current = (s["sensitivity"] as? NSNumber)?.decimalValue ?? current
                break }
        }
        return current
    }

    private static func jsActivityAt(clock: Date, pumphistory: RawJSON, profile: RawJSON) -> Double {
        let iso = Formatter.iso8601withFractionalSeconds.string(from: clock)
        let clockJSON = "{\"date\":\"\(iso)\"}"
        let worker = JavaScriptWorker()
        _ = worker.evaluate(script: Script(name: OpenAPS.Prepare.log))
        _ = worker.evaluate(script: Script(name: OpenAPS.Bundle.iob))
        _ = worker.evaluate(script: Script(name: OpenAPS.Prepare.iob))
        let result = worker
            .call(
                function: OpenAPS.Function.generate,
                with: [pumphistory, profile, clockJSON, "null"]
            ) // pass JSON null as string
        if let data = result.data(using: .utf8), let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let activity = dict["activity"] as? NSNumber { return activity.doubleValue }
        }
        return 0
    }

    // MARK: - UAM Flag

    // In oref0, UAM usage is decided later in determine-basal, but for diagnostics we expose a simple signal
    // when deviations are present without sufficient COB absorption. This mirrors the common heuristic and aids parity checks.
    private static func computeUAMFlag(core: CoreResult) -> Decimal? {
        guard let curr = core.currentDeviation, let maxDev = core.maxDeviation else { return nil }
        // Positive deviations with minimal absorption suggest UAM; use 1 as a boolean-like indicator
        if curr > 0, maxDev > 0 { return 1 }
        return 0
    }

    private static func dateFromAny(_ v: Any?) -> Date? {
        if let s = v as? String { return DateFormatter.iso8601Flexible(dateString: s) }
        if let ms = v as? NSNumber { return Date(timeIntervalSince1970: ms.doubleValue / 1000.0) }
        return nil
    }

    private static func decimalAny(_ v: Any?) -> Decimal? {
        if let n = v as? NSNumber { return n.decimalValue }
        if let s = v as? String, let d = Double(s) { return Decimal(d) }
        return nil
    }

    private static func round0(_ d: Decimal) -> Decimal {
        Decimal(string: String(format: "%.0f", NSDecimalNumber(decimal: d).doubleValue)) ?? d
    }

    private static func round3(_ d: Decimal)
        -> Decimal { Decimal(string: String(format: "%.3f", NSDecimalNumber(decimal: d).doubleValue)) ?? d }
    private static func round2(_ d: Decimal?) -> Decimal? {
        guard let d = d else { return nil }
        return Decimal(string: String(format: "%.2f", NSDecimalNumber(decimal: d).doubleValue)) ?? d
    }
}

private extension DateFormatter {
    static func iso8601Flexible(dateString: String) -> Date? {
        let s = dateString.replacingOccurrences(of: "T", with: " ")
        if let d = Formatter.iso8601withFractionalSeconds.date(from: dateString) { return d }
        if let d = Formatter.iso8601withFractionalSeconds.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: dateString)
    }
}
