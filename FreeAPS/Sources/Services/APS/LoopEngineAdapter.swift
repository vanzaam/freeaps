import Combine
import Foundation
import HealthKit
import LoopKit
import Swinject

protocol LoopEngineAdapterProtocol {
    func determine(now: Date) -> AnyPublisher<Suggestion?, Never>
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

    func determine(now: Date) -> AnyPublisher<Suggestion?, Never> {
        // Gather inputs (latest windows similar to LoopPredictionInput contract)
        // Glucose history (use mg/dL; schedules carry their own units)
        let glucose: [StoredGlucoseSample] = (storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self) ?? []).map {
            StoredGlucoseSample(
                startDate: $0.date,
                quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double($0.glucose ?? 0)),
                isDisplayOnly: false
            )
        }

        // Dose history (pump)
        let doses: [DoseEntry] = pumpHistoryStorage.load().compactMap { e in
            switch e.type {
            case .bolus:
                return DoseEntry(type: .bolus, startDate: e.timestamp, endDate: e.timestamp, value: e.amount, unit: .units)
            case .nsTempBasal,
                 .tempBasal:
                return DoseEntry(
                    type: .tempBasal,
                    startDate: e.timestamp,
                    endDate: e.timestamp.addingTimeInterval(TimeInterval(e.duration) * 60),
                    value: e.rate,
                    unit: .unitsPerHour
                )
            default:
                return nil
            }
        }

        // Carbs history
        let carbEntries: [StoredCarbEntry] = (try? carbsStorage.recent()).flatMap { $0 }?.map {
            StoredCarbEntry(
                startDate: $0.date,
                quantity: HKQuantity(unit: .gram(), doubleValue: Double($0.amount)),
                absorptionTime: $0.duration
            )
        } ?? []

        // Settings
        let s = settingsManager.settings
        let displayUnit: HKUnit = s.units == .mmolL ? .millimolesPerLiter : .milligramsPerDeciliter

        guard let basal: BasalRateSchedule = settingsManager.pumpSettings.basalSchedule,
              let sensitivity: InsulinSensitivitySchedule = settingsManager.settings.insulinSensitivities,
              let carbRatio: CarbRatioSchedule = settingsManager.settings.carbRatios,
              let target: GlucoseRangeSchedule = settingsManager.settings.bgTargets
        else {
            return Just<Suggestion?>(nil).eraseToAnyPublisher()
        }

        let algoSettings = LoopAlgorithmSettings(
            insulinActivityDuration: InsulinMath.defaultInsulinActivityDuration,
            delta: GlucoseMath.defaultDelta,
            carbRatio: carbRatio,
            sensitivity: sensitivity,
            basal: basal,
            target: target,
            useIntegralRetrospectiveCorrection: true
        )

        let input = LoopPredictionInput(
            glucoseHistory: glucose,
            doses: doses,
            carbEntries: carbEntries,
            settings: algoSettings
        )

        // Generate prediction and crude dose using DoseMath automatic recommendation
        do {
            let prediction = try LoopAlgorithm.generatePrediction(input: input, startDate: now)
            // Suspend threshold: use lower bound of current target as conservative fallback
            let lowerNow = target.quantityRange(at: now).lowerBound.doubleValue(for: displayUnit)
            let suspend = HKQuantity(unit: displayUnit, doubleValue: lowerNow)
            let maxBasal = Double(settingsManager.pumpSettings.maxBasal)
            let auto = prediction.glucose.recommendedAutomaticDose(
                to: target,
                at: now,
                suspendThreshold: suspend,
                sensitivity: sensitivity,
                model: PresetInsulinModelProvider(defaultRapidActingModel: nil).model(for: .rapidActingAdult)!,
                basalRates: basal,
                maxAutomaticBolus: Double(settingsManager.pumpSettings.maxBolus),
                partialApplicationFactor: 0.5,
                lastTempBasal: nil,
                volumeRounder: { $0 },
                rateRounder: { $0 },
                isBasalRateScheduleOverrideActive: false
            )

            // Map to Suggestion
            let suggestion = Suggestion(
                reason: "LoopEngine",
                units: auto?.manualBolus.map { Decimal($0.amount) },
                insulinReq: auto?.manualBolus.map { Decimal($0.amount) },
                eventualBG: nil,
                sensitivityRatio: nil,
                rate: auto?.tempBasal.map { Decimal($0.unitsPerHour) },
                duration: auto?.tempBasal.map { Int($0.duration / 60) },
                iob: nil,
                cob: nil,
                predictions: nil,
                deliverAt: now,
                carbsReq: nil,
                temp: auto?.tempBasal != nil ? .absolute : nil,
                bg: nil,
                reservoir: nil,
                timestamp: now,
                recieved: nil
            )
            return Just<Suggestion?>(suggestion).eraseToAnyPublisher()
        } catch {
            warning(.service, "LoopAlgorithm prediction error: \(error.localizedDescription)")
            return Just<Suggestion?>(nil).eraseToAnyPublisher()
        }
    }
}
