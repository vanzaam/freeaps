import Combine
import Foundation
import LoopKit
import Swinject

protocol IOBPredictorService: AnyObject {
    /// Текущий IOB
    var currentIOB: Decimal { get }

    /// Прогноз IOB на следующие 6 часов с интервалом 5 минут
    var iobForecast: [IOBForecastPoint] { get }

    /// Обновить прогноз на основе текущих доз
    func updateForecast()

    /// Добавить новую дозу для прогнозирования
    func addDose(_ dose: DoseEntry)
}

struct IOBForecastPoint: Identifiable {
    let id = UUID()
    let date: Date
    let iobValue: Decimal
    let activityLevel: Decimal
    let minutesFromNow: Int

    var timeString: String {
        if minutesFromNow == 0 {
            return "Сейчас"
        } else if minutesFromNow < 60 {
            return "+\(minutesFromNow)м"
        } else {
            let hours = minutesFromNow / 60
            let minutes = minutesFromNow % 60
            return minutes > 0 ? "+\(hours)ч\(minutes)м" : "+\(hours)ч"
        }
    }
}

final class BaseIOBPredictorService: IOBPredictorService, Injectable {
    @Injected() var storage: FileStorage!
    @Injected() var broadcaster: Broadcaster!

    @Published var currentIOB: Decimal = 0
    @Published var iobForecast: [IOBForecastPoint] = []

    private var activeDoses: [DoseEntry] = []
    private let predictionInterval: TimeInterval = 5 * 60 // 5 минут
    private let forecastDuration: TimeInterval = 6 * 3600 // 6 часов

    init(resolver: Resolver) {
        injectServices(resolver)
        loadInsulinCurveSettings()
        updateForecast()
    }

    // MARK: - Insulin Curve Settings

    private var insulinCurveSettings: InsulinCurveSettings?

    private func loadInsulinCurveSettings() {
        insulinCurveSettings = storage.retrieve(OpenAPS.Settings.insulinCurve, as: InsulinCurveSettings.self)
    }

    private func getInsulinModel() -> InsulinModel {
        guard let settings = insulinCurveSettings else {
            // Fallback to default rapid-acting
            return ExponentialInsulinModel(
                actionDuration: .minutes(360),
                peakActivityTime: .minutes(75),
                delay: .minutes(10)
            )
        }

        return ExponentialInsulinModel(
            actionDuration: .minutes(settings.actionDuration),
            peakActivityTime: .minutes(settings.peakTime),
            delay: .minutes(settings.delay)
        )
    }

    // MARK: - IOB Calculation

    func updateForecast() {
        loadActiveDoses()
        calculateIOBForecast()
    }

    private func loadActiveDoses() {
        // Загружаем историю помпы за последние 6 часов
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-6 * 3600)

        let pumpHistory = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) ?? []

        activeDoses = pumpHistory.compactMap { event in
            // Только события с инсулином после startDate
            guard event.timestamp >= startDate else { return nil }

            switch event.type {
            case .bolus,
                 .correctionBolus,
                 .mealBolus,
                 .smb,
                 .snackBolus:
                return DoseEntry(
                    type: .bolus,
                    startDate: event.timestamp,
                    endDate: event.timestamp,
                    value: NSDecimalNumber(decimal: event.amount ?? 0).doubleValue,
                    unit: .units
                )
            case .nsTempBasal,
                 .tempBasal:
                let duration = TimeInterval((event.duration ?? event.durationMin ?? 0) * 60)
                return DoseEntry(
                    type: .tempBasal,
                    startDate: event.timestamp,
                    endDate: event.timestamp.addingTimeInterval(duration),
                    value: NSDecimalNumber(decimal: event.rate ?? 0).doubleValue,
                    unit: .unitsPerHour
                )
            default:
                return nil
            }
        }

        debug(.service, "IOBPredictor: Loaded \(activeDoses.count) active doses")
    }

    private func calculateIOBForecast() {
        let now = Date()
        let insulinModel = getInsulinModel()
        var forecastPoints: [IOBForecastPoint] = []

        // Генерируем прогноз с интервалом 5 минут
        let numberOfPoints = Int(forecastDuration / predictionInterval)

        for i in 0 ... numberOfPoints {
            let forecastTime = now.addingTimeInterval(TimeInterval(i) * predictionInterval)
            let minutesFromNow = i * Int(predictionInterval / 60)

            var totalIOB: Double = 0
            var totalActivity: Double = 0

            // Суммируем вклад всех активных доз
            for dose in activeDoses {
                let timeSinceDose = forecastTime.timeIntervalSince(dose.startDate)

                // Только если доза еще активна
                if timeSinceDose >= 0, timeSinceDose <= insulinModel.effectDuration {
                    let iobPercent = insulinModel.percentEffectRemaining(at: timeSinceDose)
                    let activityLevel = calculateActivity(at: timeSinceDose, model: insulinModel)

                    totalIOB += dose.netBasalUnits * iobPercent
                    totalActivity += dose.netBasalUnits * activityLevel
                }
            }

            forecastPoints.append(IOBForecastPoint(
                date: forecastTime,
                iobValue: Decimal(totalIOB),
                activityLevel: Decimal(totalActivity),
                minutesFromNow: minutesFromNow
            ))
        }

        DispatchQueue.main.async { [weak self] in
            self?.iobForecast = forecastPoints
            self?.currentIOB = forecastPoints.first?.iobValue ?? 0
        }

        debug(
            .service,
            "IOBPredictor: Generated forecast with \(forecastPoints.count) points, current IOB: \(forecastPoints.first?.iobValue ?? 0)U"
        )
    }

    private func calculateActivity(at time: TimeInterval, model: InsulinModel) -> Double {
        // Приближенная активность через производную IOB
        let dt: TimeInterval = 60 // 1 минута
        let iob1 = model.percentEffectRemaining(at: time)
        let iob2 = model.percentEffectRemaining(at: time + dt)

        return abs(iob1 - iob2) / (dt / 60.0) // Активность в единицах/час
    }

    // MARK: - Public Methods

    func addDose(_ dose: DoseEntry) {
        activeDoses.append(dose)
        calculateIOBForecast()

        debug(.service, "IOBPredictor: Added new dose: \(dose.netBasalUnits)U at \(dose.startDate)")
    }
}

// MARK: - Settings Observer

extension BaseIOBPredictorService: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        // Перезагружаем настройки кривой инсулина при изменении
        loadInsulinCurveSettings()
        updateForecast()
    }
}

// MARK: - Supporting Types

extension IOBPredictorService {
    func forecastForNextHours(_ hours: Int) -> [IOBForecastPoint] {
        let maxMinutes = hours * 60
        return iobForecast.filter { $0.minutesFromNow <= maxMinutes }
    }

    func forecastAt(minutesFromNow: Int) -> IOBForecastPoint? {
        iobForecast.first { $0.minutesFromNow == minutesFromNow }
    }
}
