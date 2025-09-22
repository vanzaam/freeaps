import Combine
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import Swinject

protocol LoopEngineAdapterProtocol {
    func determineBasal(currentTemp: TempBasal, clock: Date) -> AnyPublisher<Suggestion?, Never>
}

final class LoopEngineAdapter: LoopEngineAdapterProtocol, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!

    private let processQueue = DispatchQueue(label: "LoopEngineAdapter.queue")

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    private func deviceInsulinType() -> InsulinType? {
        // Try to access via injected DeviceDataManager through APSManager pattern
        // We don't have a global Resolver here; fall back to rapid-acting if unavailable
        nil
    }

    func determineBasal(currentTemp _: TempBasal, clock: Date) -> AnyPublisher<Suggestion?, Never> {
        Future { promise in
            self.processQueue.async {
                do {
                    let suggestion = try self.computeSuggestion(clock: clock)
                    promise(.success(suggestion))
                } catch {
                    warning(.service, "LoopAlgorithm prediction error: \(error.localizedDescription)")
                    promise(.success(nil))
                }
            }
        }.eraseToAnyPublisher()
    }

    // MARK: - Decomposed computation to avoid type-checker blowups

    private func loadGlucoseSamples() -> (raw: [BloodGlucose], samples: [StoredGlucoseSample]) {
        // Используем свежие данные напрямую из glucoseStorage вместо файла
        let glucoseData: [BloodGlucose] = glucoseStorage.recent()
        let samples: [StoredGlucoseSample] = glucoseData.map {
            StoredGlucoseSample(
                startDate: $0.dateString,
                quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double($0.glucose ?? 0)),
                isDisplayOnly: false
            )
        }

        // Логирование для диагностики прогноза
        if let lastGlucose = glucoseData.last {
            let now = Date()
            let minutesAgo = Int(now.timeIntervalSince(lastGlucose.dateString) / 60)
            debug(
                .service,
                "LoopEngine: Last glucose for prediction = \(lastGlucose.glucose ?? 0) mg/dL at \(lastGlucose.dateString) (\(minutesAgo) min ago)"
            )
        }
        debug(.service, "LoopEngine: Loaded \(glucoseData.count) glucose samples for prediction (from glucoseStorage.recent())")

        return (glucoseData, samples)
    }

    private func loadDoseEntries() -> [DoseEntry] {
        let pumpEvents = pumpHistoryStorage.recent()
        debug(.service, "LoopEngine: Loaded \(pumpEvents.count) pump events from pumpHistoryStorage.recent()")
        let mapped: [DoseEntry] = pumpEvents.compactMap { e in
            switch e.type {
            case .bolus:
                return DoseEntry(
                    type: .bolus,
                    startDate: e.timestamp,
                    endDate: e.timestamp,
                    value: NSDecimalNumber(decimal: e.amount ?? 0).doubleValue,
                    unit: .units
                )
            case .nsTempBasal,
                 .tempBasal:
                let minutes = (e.duration ?? e.durationMin ?? 0)
                return DoseEntry(
                    type: .tempBasal,
                    startDate: e.timestamp,
                    endDate: e.timestamp.addingTimeInterval(TimeInterval(minutes * 60)),
                    value: NSDecimalNumber(decimal: e.rate ?? 0).doubleValue,
                    unit: .unitsPerHour
                )
            default:
                return nil
            }
        }
        let sortedDoses = mapped.sorted { $0.startDate < $1.startDate }
        debug(.service, "LoopEngine: Converted to \(sortedDoses.count) dose entries for LoopKit")
        return sortedDoses
    }

    private func loadCarbEntries() -> [StoredCarbEntry] {
        let carbsData: [CarbsEntry] = carbsStorage.recent()
        debug(.service, "LoopEngine: Loaded \(carbsData.count) carb entries from carbsStorage.recent()")
        let carbEntries = carbsData.map {
            StoredCarbEntry(
                startDate: $0.createdAt,
                quantity: HKQuantity(unit: .gram(), doubleValue: NSDecimalNumber(decimal: $0.carbs).doubleValue),
                absorptionTime: nil
            )
        }
        debug(.service, "LoopEngine: Converted to \(carbEntries.count) stored carb entries for LoopKit")
        return carbEntries
    }

    private func buildRepeatingSchedules() -> (
        basalItems: [RepeatingScheduleValue<Double>],
        sensitivityItems: [RepeatingScheduleValue<Double>],
        carbItems: [RepeatingScheduleValue<Double>],
        targetItems: [RepeatingScheduleValue<DoubleRange>]
    ) {
        let basalProfile: [BasalProfileEntry] = storage
            .retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) ?? []
        let sensitivitiesModel: InsulinSensitivities? = storage.retrieve(
            OpenAPS.Settings.insulinSensitivities,
            as: InsulinSensitivities.self
        )
        let carbRatiosModel: CarbRatios? = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
        let bgTargetsModel: BGTargets? = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)

        let basalItems = basalProfile.map {
            RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: NSDecimalNumber(decimal: $0.rate).doubleValue)
        }
        let sensitivityItems = (sensitivitiesModel?.sensitivities ?? []).map {
            RepeatingScheduleValue(
                startTime: TimeInterval($0.offset * 60),
                value: NSDecimalNumber(decimal: $0.sensitivity).doubleValue
            )
        }
        let carbItems = (carbRatiosModel?.schedule ?? []).map {
            RepeatingScheduleValue(startTime: TimeInterval($0.offset * 60), value: NSDecimalNumber(decimal: $0.ratio).doubleValue)
        }
        let targetItems = (bgTargetsModel?.targets ?? []).map {
            RepeatingScheduleValue(
                startTime: TimeInterval($0.offset * 60),
                value: DoubleRange(
                    minValue: NSDecimalNumber(decimal: $0.low).doubleValue,
                    maxValue: NSDecimalNumber(decimal: $0.high).doubleValue
                )
            )
        }

        return (basalItems, sensitivityItems, carbItems, targetItems)
    }

    private func makeAbsolute<T>(
        items: [RepeatingScheduleValue<T>],
        anchorStart: Date,
        endBoundary: Date
    ) -> [AbsoluteScheduleValue<T>] {
        let sorted = items.sorted { $0.startTime < $1.startTime }
        return sorted.enumerated().map { index, item in
            let start = anchorStart.addingTimeInterval(item.startTime)
            let end: Date = (index + 1 < sorted.count)
                ? anchorStart.addingTimeInterval(sorted[index + 1].startTime)
                : endBoundary
            return AbsoluteScheduleValue(startDate: start, endDate: end, value: item.value)
        }
    }

    private func computeSuggestion(clock: Date) throws -> Suggestion? {
        // Load inputs
        let glucosePayload = loadGlucoseSamples()
        let doses = loadDoseEntries()
        let carbEntries = loadCarbEntries()
        let schedules = buildRepeatingSchedules()

        // Validate schedules
        guard
            let basalSchedule = BasalRateSchedule(dailyItems: schedules.basalItems),
            let sensitivitySchedule = InsulinSensitivitySchedule(
                unit: .milligramsPerDeciliter,
                dailyItems: schedules.sensitivityItems
            ),
            let _ = CarbRatioSchedule(unit: .gram(), dailyItems: schedules.carbItems),
            let targetSchedule = GlucoseRangeSchedule(unit: .milligramsPerDeciliter, dailyItems: schedules.targetItems)
        else {
            return nil
        }

        // Absolute schedules for algorithm
        let cal = Calendar.current
        let earliestDoseStart = doses.first?.startDate
        let clockDayStart = cal.startOfDay(for: clock)
        let doseDayStart = earliestDoseStart.map { cal.startOfDay(for: $0) }
        let anchorStart = min(clockDayStart, doseDayStart ?? clockDayStart)
        let endBoundary = anchorStart.addingTimeInterval(48 * 3600)

        let basalAbs = makeAbsolute(items: schedules.basalItems, anchorStart: anchorStart, endBoundary: endBoundary)
        let sensitivityRepeatingQuantities = schedules.sensitivityItems.map {
            RepeatingScheduleValue(
                startTime: $0.startTime,
                value: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: $0.value)
            )
        }
        let sensAbs = makeAbsolute(items: sensitivityRepeatingQuantities, anchorStart: anchorStart, endBoundary: endBoundary)
        let carbAbs = makeAbsolute(items: schedules.carbItems, anchorStart: anchorStart, endBoundary: endBoundary)
        let targetRepeatingQuantities: [RepeatingScheduleValue<ClosedRange<HKQuantity>>] = schedules.targetItems.map { item in
            let lower = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: item.value.minValue)
            let upper = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: item.value.maxValue)
            let range = ClosedRange(uncheckedBounds: (lower: lower, upper: upper))
            return RepeatingScheduleValue(startTime: item.startTime, value: range)
        }
        let targetAbs = makeAbsolute(items: targetRepeatingQuantities, anchorStart: anchorStart, endBoundary: endBoundary)

        let algoSettings = LoopAlgorithmSettings(
            basal: basalAbs,
            sensitivity: sensAbs,
            carbRatio: carbAbs,
            target: targetAbs,
            delta: GlucoseMath.defaultDelta,
            insulinActivityDuration: 6 * 60 * 60,
            algorithmEffectsOptions: .all,
            maximumBasalRatePerHour: Double(settingsManager.pumpSettings.maxBasal),
            maximumBolus: Double(settingsManager.pumpSettings.maxBolus),
            suspendThreshold: GlucoseThreshold(unit: .milligramsPerDeciliter, value: 70),
            useIntegralRetrospectiveCorrection: true
        )

        let input = LoopPredictionInput(
            glucoseHistory: glucosePayload.samples,
            doses: doses,
            carbEntries: carbEntries,
            settings: algoSettings
        )

        // Prediction
        let prediction = try LoopAlgorithm.generatePrediction(input: input, startDate: clock)

        // Dose recommendation
        let toSchedule = targetSchedule
        let sensSchedule = sensitivitySchedule
        let basalSched = basalSchedule

        let presetRaw: String? = storage.retrieveRaw(OpenAPS.Settings.model)
        let selectedPreset = presetRaw.flatMap { ExponentialInsulinModelPreset(rawValue: $0) } ?? .rapidActingAdult
        let insulinModel = PresetInsulinModelProvider(defaultRapidActingModel: selectedPreset).model(for: nil)

        let auto = prediction.glucose.recommendedAutomaticDose(
            to: toSchedule,
            at: clock,
            suspendThreshold: GlucoseThreshold(unit: .milligramsPerDeciliter, value: 70).quantity,
            sensitivity: sensSchedule,
            model: insulinModel,
            basalRates: basalSched,
            maxAutomaticBolus: Double(settingsManager.pumpSettings.maxBolus),
            partialApplicationFactor: 0.5,
            lastTempBasal: nil,
            volumeRounder: { $0 },
            rateRounder: { $0 },
            isBasalRateScheduleOverrideActive: false,
            duration: 30 * 60,
            continuationInterval: 29 * 60
        )

        // Prediction series
        let horizonEnd = clock.addingTimeInterval(6 * 60 * 60)
        let trimmed: [Int] = prediction.glucose
            .filter { $0.startDate <= horizonEnd }
            .map { Int($0.quantity.doubleValue(for: .milligramsPerDeciliter).rounded()) }

        // Логирование прогноза
        if !trimmed.isEmpty {
            debug(
                .service,
                "LoopEngine: Generated prediction with \(trimmed.count) points, first=\(trimmed.first!), last=\(trimmed.last!)"
            )
            if trimmed.count > 5 {
                debug(.service, "LoopEngine: First 5 predictions: \(trimmed.prefix(5))")
            }
        }

        let preds = Predictions(
            iob: trimmed.isEmpty ? nil : trimmed,
            zt: nil,
            cob: trimmed.isEmpty ? nil : trimmed,
            uam: nil
        )

        let currentBG = Int(glucosePayload.raw.last?.glucose ?? 0)
        let eventual: Int? = trimmed.last

        let suggestion = Suggestion(
            reason: "LoopEngine",
            units: nil,
            insulinReq: nil,
            eventualBG: eventual,
            sensitivityRatio: nil,
            rate: auto?.basalAdjustment.map { Decimal($0.unitsPerHour) },
            duration: auto?.basalAdjustment.map { Int($0.duration / 60) },
            iob: nil,
            cob: nil,
            predictions: preds,
            deliverAt: clock,
            carbsReq: nil,
            temp: auto?.basalAdjustment != nil ? .absolute : nil,
            bg: Decimal(currentBG),
            reservoir: nil,
            timestamp: clock,
            recieved: true
        )

        // Сохраняем suggestion в файл для совместимости с другими компонентами
        storage.save(suggestion, as: OpenAPS.Enact.suggested)
        debug(.service, "LoopEngine: Saved suggestion with \(trimmed.count) prediction points")

        return suggestion
    }
}

// MARK: - Helpers

private enum PreditionsBuilder {
    static func buildSingleLine(values: [Int]) -> Predictions? {
        guard values.isNotEmpty else { return nil }
        // Place the single Loop prediction into IOB series to satisfy consumers of predBGs
        return Predictions(iob: values, zt: nil, cob: nil, uam: nil)
    }
}
