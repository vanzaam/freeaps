import Combine
import Foundation
import LoopKit
import Swinject

/// ViewModel для главного экрана Dashboard
/// Объединяет данные из всех сервисов и предоставляет их для UI
@MainActor class DashboardStateModel: ObservableObject {
    // MARK: - Published Properties

    /// Текущая глюкоза
    @Published var currentGlucose: Decimal?

    /// Тренд глюкозы
    @Published var trend: String?

    /// Единицы измерения глюкозы (mg/dL или mmol/L)
    @Published var units: GlucoseUnits = .mmolL

    /// Порог низкой глюкозы (в текущих единицах)
    @Published var lowThreshold: Decimal = 70

    /// Порог высокой глюкозы (в текущих единицах)
    @Published var highThreshold: Decimal = 180

    /// IOB (Insulin on Board)
    @Published var iob: Decimal = 0

    /// COB (Carbs on Board)
    @Published var cob: Decimal = 0

    /// Данные глюкозы для графика
    @Published var glucose: [GlucoseReading] = []

    /// Предсказания глюкозы
    @Published var predictedGlucose: [PredictedGlucose] = []

    /// Данные IOB для графика (исторические)
    @Published var iobData: [IOBData] = []

    /// Прогнозные данные IOB
    @Published var iobForecastData: [IOBData] = []

    /// Данные COB для графика
    @Published var cobData: [COBData] = []

    /// События подачи инсулина
    @Published var delivery: [DeliveryEvent] = []

    /// Прогресс активного болюса (0.0 - 1.0)
    @Published var bolusPercent: Double? = nil

    /// Статус загрузки
    @Published var isLoading: Bool = false

    /// Ошибка
    @Published var lastError: Error?

    // MARK: - Loop Status Properties

    /// Статус работы Loop (закрытый/открытый цикл)
    @Published var isLooping: Bool = false

    /// Время последнего обновления
    @Published var lastUpdate = Date()

    /// Включён закрытый цикл
    @Published var closedLoop: Bool = false

    // MARK: - Pump Status Properties

    /// Имя помпы
    @Published var pumpName: String?

    /// Уровень батареи помпы (0-100%)
    @Published var pumpBattery: Int?

    /// Уровень резервуара помпы (единицы инсулина)
    @Published var pumpReservoir: Double?

    /// Подключена ли помпа
    @Published var pumpConnected: Bool = false

    // MARK: - Private Properties

    private var carbService: CarbAccountingService?
    private var glucoseService: GlucoseStorage?
    private var pumpHistoryStorage: PumpHistoryStorage?
    private var resolver: Resolver?
    private let apsService: APSManager?
    private let storage: FileStorage?
    private let settingsManager: SettingsManager?
    private let broadcaster: Broadcaster?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(resolver: Resolver) {
        self.resolver = resolver
        carbService = resolver.resolve(CarbAccountingService.self)
        glucoseService = resolver.resolve(GlucoseStorage.self)
        pumpHistoryStorage = resolver.resolve(PumpHistoryStorage.self)
        apsService = resolver.resolve(APSManager.self)
        storage = resolver.resolve(FileStorage.self)
        settingsManager = resolver.resolve(SettingsManager.self)
        broadcaster = resolver.resolve(Broadcaster.self)

        if carbService == nil {
            warning(.service, "CarbAccountingService not available")
        }
        if glucoseService == nil {
            warning(.service, "GlucoseStorage not available")
        }

        setupObservers()
    }

    // MARK: - Public Methods

    /// Загрузить все данные
    func loadData() {
        info(.service, "Loading dashboard data")
        isLoading = true
        lastError = nil

        Task {
            // Применить текущие единицы измерения и пороги
            let rawUnits = settingsManager?.settings.units ?? .mmolL
            let rawLow = settingsManager?.settings.lowGlucose ?? 70
            let rawHigh = settingsManager?.settings.highGlucose ?? 180
            await MainActor.run {
                units = rawUnits
                lowThreshold = (rawUnits == .mmolL) ? rawLow.asMmolL : rawLow
                highThreshold = (rawUnits == .mmolL) ? rawHigh.asMmolL : rawHigh
            }

            await loadGlucoseData()
            await loadCarbData()
            await loadInsulinData()
            await loadDeliveryData()
            await loadLoopStatus()
            await loadPumpStatus()
            // Загружаем изначальный прогноз из файла (будет обновлен через SuggestionObserver)
            await loadPredictionFromSuggestionFile()

            await MainActor.run {
                isLoading = false
                lastUpdate = Date()
            }
            info(.service, "Dashboard data loaded successfully")
        }
    }

    private func loadPredictionFromSuggestionFile() async {
        guard let storage = storage else { return }
        if let suggestion = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self) {
            debug(.service, "Dashboard: Loaded suggestion from file with timestamp \(suggestion.timestamp?.description ?? "nil")")
            await MainActor.run { self.updatePredictionFromSuggestion(suggestion) }
        } else {
            debug(.service, "Dashboard: No suggestion found in file")
            await MainActor.run { self.predictedGlucose = [] }
        }
    }

    /// Обновить данные
    func refreshData() {
        info(.service, "Refreshing dashboard data")
        loadData()
    }

    /// Получить статистику
    func getStats() -> DashboardStats {
        DashboardStats(
            currentGlucose: currentGlucose,
            trend: trend,
            iob: iob,
            cob: cob,
            glucoseCount: glucose.count,
            lastUpdate: Date()
        )
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Наблюдать за изменениями в сервисах
        carbService?.$cob
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newCOB in
                self?.cob = newCOB
                Task { await self?.updateCOBData() }
            }
            .store(in: &cancellables)

        // Наблюдать за статусом Loop
        apsService?.isLooping
            .receive(on: DispatchQueue.main)
            .sink { [weak self] looping in
                self?.isLooping = looping
            }
            .store(in: &cancellables)

        // Наблюдать за именем помпы
        apsService?.pumpName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.pumpName = name
            }
            .store(in: &cancellables)

        // Наблюдать за датой последнего цикла
        apsService?.lastLoopDateSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                self?.lastUpdate = date
            }
            .store(in: &cancellables)

        // Прогресс болюса
        apsService?.bolusProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.bolusPercent = value?.doubleValue
            }
            .store(in: &cancellables)

        // Реакция на новое предложение (прогноз)
        broadcaster?.register(SuggestionObserver.self, observer: self)
    }

    private func loadGlucoseData() async {
        guard let glucoseService = glucoseService else {
            warning(.service, "GlucoseStorage not available")
            return
        }

        do {
            // Загрузить последние 24 часа данных глюкозы
            let endDate = Date()
            let startDate = endDate.addingTimeInterval(-24 * 3600)

            let bg = glucoseService.recent()
            let glucoseReadings = bg.filter { $0.dateString >= startDate && $0.dateString <= endDate }
                .sorted { $0.dateString < $1.dateString }

            glucose = glucoseReadings.map { reading in
                let raw = Decimal(reading.sgv ?? Int(reading.filtered ?? 0))
                let value = (units == .mmolL) ? raw.asMmolL : raw
                return GlucoseReading(value: value, date: reading.dateString)
            }

            // Установить текущую глюкозу и тренд
            if let latest = glucoseReadings.last {
                let raw = Decimal(latest.sgv ?? Int(latest.filtered ?? 0))
                currentGlucose = (units == .mmolL) ? raw.asMmolL : raw
                trend = getTrendString(from: glucose)
            }

            debug(.service, "Loaded \(glucose.count) glucose readings")

        } catch let err {
            error(.service, "Failed to load glucose data: \(err.localizedDescription)")
            lastError = err
        }
    }

    private func loadCarbData() async {
        guard let carbService = carbService else {
            warning(.service, "CarbAccountingService not available")
            return
        }

        // Обновить активные записи углеводов в сервисе
        await carbService.updateActiveCarbEntries()

        // Получить текущий COB
        await MainActor.run {
            cob = carbService.cob
        }

        // Обновить данные для графика
        await updateCOBData()

        debug(.service, "Loaded carb data: COB = \(cob)g")
    }

    private func loadInsulinData() async {
        guard let storage = storage else {
            warning(.service, "FileStorage not available")
            return
        }

        guard let pumpHistoryStorage = pumpHistoryStorage else {
            warning(.service, "PumpHistoryStorage not available")
            return
        }

        // Рассчитываем IOB из истории доз LoopKit (точно и динамично)
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-6 * 3600)

        // Преобразуем свежую историю помпы в DoseEntry (используем актуальные данные)
        let pumpHistory = pumpHistoryStorage.recent()
        debug(.service, "Dashboard: Loaded \(pumpHistory.count) pump events from pumpHistoryStorage.recent() for IOB calculation")
        let doseEntries: [DoseEntry] = pumpHistory.compactMap { e -> DoseEntry? in
            switch e.type {
            case .bolus,
                 .correctionBolus,
                 .mealBolus,
                 .smb,
                 .snackBolus:
                return DoseEntry(
                    type: .bolus,
                    startDate: e.timestamp,
                    endDate: e.timestamp,
                    value: NSDecimalNumber(decimal: e.amount ?? 0).doubleValue,
                    unit: .units
                )
            case .nsTempBasal,
                 .tempBasal:
                return DoseEntry(
                    type: .tempBasal,
                    startDate: e.timestamp,
                    endDate: e.timestamp.addingTimeInterval(TimeInterval((e.duration ?? e.durationMin ?? 0) * 60)),
                    value: NSDecimalNumber(decimal: e.rate ?? 0).doubleValue,
                    unit: .unitsPerHour
                )
            default:
                return nil
            }
        }

        // IOB временной ряд с шагом 5 минут для точного прогноза
        let insulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: nil)
        let iobSeries = doseEntries.insulinOnBoard(
            insulinModelProvider: insulinModelProvider,
            longestEffectDuration: InsulinMath.defaultInsulinActivityDuration,
            from: startDate,
            to: endDate,
            delta: 5 * 60
        )

        let iobDataPoints: [IOBData] = iobSeries.compactMap { InsulinValue in
            guard !InsulinValue.value.isNaN, !InsulinValue.value.isInfinite else {
                debug(.service, "⚠️ Skipping invalid IOB value: \(InsulinValue.value)")
                return nil
            }
            return IOBData(value: Decimal(InsulinValue.value), date: InsulinValue.startDate)
        }

        // Генерируем прогноз IOB на следующие 6 часов с интервалом 5 минут
        let forecastEndDate = endDate.addingTimeInterval(6 * 3600) // +6 часов
        let forecastSeries = doseEntries.insulinOnBoard(
            insulinModelProvider: insulinModelProvider,
            longestEffectDuration: InsulinMath.defaultInsulinActivityDuration,
            from: endDate,
            to: forecastEndDate,
            delta: 5 * 60
        )

        let forecastDataPoints: [IOBData] = forecastSeries.compactMap { InsulinValue in
            guard !InsulinValue.value.isNaN, !InsulinValue.value.isInfinite else {
                debug(.service, "⚠️ Skipping invalid IOB forecast value: \(InsulinValue.value)")
                return nil
            }
            return IOBData(value: Decimal(InsulinValue.value), date: InsulinValue.startDate)
        }

        await MainActor.run {
            let lastIOBValue = iobSeries.last?.value ?? 0
            if lastIOBValue.isNaN || lastIOBValue.isInfinite {
                debug(.service, "⚠️ Invalid final IOB value: \(lastIOBValue), using 0")
                iob = 0
            } else {
                iob = Decimal(lastIOBValue)
            }
            iobData = iobDataPoints
            iobForecastData = forecastDataPoints
        }

        debug(
            .service,
            "Loaded insulin data: historical=\(iobDataPoints.count), forecast=\(forecastDataPoints.count), IOB=\(iob)U"
        )
    }

    private func loadDeliveryData() async {
        guard let storage = storage else {
            warning(.service, "FileStorage not available")
            return
        }

        do {
            // Загрузить историю помпы для графика подачи
            if let pumpHistory = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) {
                // Фильтровать последние 6 часов
                let endDate = Date()
                let startDate = endDate.addingTimeInterval(-6 * 3600)

                let recentEvents = pumpHistory.filter { event in
                    event.timestamp >= startDate && event.timestamp <= endDate
                }

                let deliveryEvents: [DeliveryEvent] = recentEvents.compactMap { event in
                    let type: DeliveryType
                    let amount: Decimal

                    switch event.type {
                    case .bolus,
                         .correctionBolus,
                         .mealBolus,
                         .snackBolus:
                        type = .bolus
                        amount = event.amount ?? 0
                    case .nsTempBasal,
                         .tempBasal:
                        type = .tempBasal
                        amount = event.rate ?? 0
                    case .smb:
                        type = .bolus
                        amount = event.amount ?? 0
                    default:
                        return nil
                    }

                    return DeliveryEvent(
                        amount: amount,
                        date: event.timestamp,
                        type: type
                    )
                }

                await MainActor.run {
                    delivery = deliveryEvents.sorted { $0.date < $1.date }
                }

                debug(.service, "Loaded \(deliveryEvents.count) delivery events")
            } else {
                warning(.service, "No pump history available")
                await MainActor.run {
                    delivery = []
                }
            }
        } catch let err {
            error(.service, "Failed to load delivery data: \(err.localizedDescription)")
            await MainActor.run {
                lastError = err
                delivery = []
            }
        }
    }

    private func updateCOBData() async {
        guard let carbService = carbService else { return }

        // Получить данные COB для графика (последние 6 часов + 30 минут в будущее)
        let endDate = Date().addingTimeInterval(30 * 60) // 30 минут в будущее
        let cobForecast = carbService.getCOBForecast(until: endDate)

        await MainActor.run {
            cobData = cobForecast.compactMap { date, value -> COBData? in
                // Проверяем на некорректные значения COB
                if value.isNaN || value.isInfinite || value < 0 {
                    debug(.service, "⚠️ Skipping invalid COB value: \(value)")
                    return nil
                }
                return COBData(value: value, date: date)
            }
            debug(.service, "Updated COB forecast: \(cobData.count) points")
        }
    }

    private func getTrendString(from readings: [GlucoseReading]) -> String? {
        guard readings.count >= 2 else { return nil }

        let recent = readings.suffix(2)
        let values = recent.map(\.value.doubleValue)

        guard values.count == 2 else { return nil }

        let diff = values[1] - values[0]

        if diff > 5 { return "↗↗" }
        if diff > 2 { return "↗" }
        if diff < -5 { return "↘↘" }
        if diff < -2 { return "↘" }
        return "→"
    }
}

// MARK: - Supporting Types

struct DashboardStats {
    let currentGlucose: Decimal?
    let trend: String?
    let iob: Decimal
    let cob: Decimal
    let glucoseCount: Int
    let lastUpdate: Date
}

// MARK: - SuggestionObserver

extension DashboardStateModel: SuggestionObserver {
    @MainActor func suggestionDidUpdate(_ suggestion: Suggestion) {
        debug(.service, "Dashboard: Received NEW suggestion update with timestamp \(suggestion.timestamp?.description ?? "nil")")
        updatePredictionFromSuggestion(suggestion)
    }

    @MainActor private func updatePredictionFromSuggestion(_ suggestion: Suggestion) {
        guard let preds = suggestion.predictions else {
            predictedGlucose = []
            return
        }
        let mgdlArray = preds.iob ?? preds.cob ?? preds.zt ?? preds.uam ?? []
        guard !mgdlArray.isEmpty else {
            predictedGlucose = []
            return
        }

        // Ограничиваем прогноз максимум 6 часами (72 точки по 5 минут)
        let maxForecastPoints = 72 // 6 часов * 12 точек в час (каждые 5 минут)
        let limitedArray = Array(mgdlArray.prefix(maxForecastPoints))

        let baseDate = glucose.last?.date ?? suggestion.timestamp ?? suggestion.deliverAt ?? Date()
        let step: TimeInterval = 5 * 60
        let unitAdjusted: [PredictedGlucose] = limitedArray.enumerated().compactMap { idx, mgdl in
            let dec = Decimal(mgdl)
            let value = (units == .mmolL) ? dec.asMmolL : dec

            // Проверяем на некорректные значения
            if value.isNaN || value.isInfinite || value < 0 {
                debug(.service, "⚠️ Skipping invalid glucose prediction: \(value) from mgdl=\(mgdl)")
                return nil
            }

            return PredictedGlucose(value: value, date: baseDate.addingTimeInterval(TimeInterval(idx) * step))
        }
        predictedGlucose = unitAdjusted

        debug(.service, "Glucose prediction limited to \(limitedArray.count) points (max 6 hours)")
    }
}

// MARK: - Extensions

extension DashboardStateModel {
    /// Получить цвет глюкозы
    func getGlucoseColor(_ glucose: Decimal) -> String {
        let value = glucose.doubleValue
        if value < 70 { return "red" }
        if value > 180 { return "red" }
        if value < 80 || value > 160 { return "orange" }
        return "green"
    }

    /// Получить цвет тренда
    func getTrendColor(_ trend: String) -> String {
        switch trend {
        case "↗",
             "↗↗": return "red"
        case "↘",
             "↘↘": return "blue"
        default: return "gray"
        }
    }

    // MARK: - Loop Status Loading

    private func loadLoopStatus() async {
        // Получить статус Loop из APSManager
        guard let apsService = apsService else {
            warning(.service, "APSManager not available for loop status")
            return
        }

        await MainActor.run {
            // Получить реальный статус из APSManager
            isLooping = apsService.isLooping.value
            lastUpdate = apsService.lastLoopDate
            closedLoop = settingsManager?.settings.closedLoop ?? false
        }

        debug(.service, "Loaded loop status: isLooping=\(isLooping), lastLoop=\(lastUpdate)")
    }

    private func loadPumpStatus() async {
        // Получить статус помпы из DeviceDataManager или APSManager
        guard let apsService = apsService,
              let storage = storage
        else {
            warning(.service, "APSManager or FileStorage not available for pump status")
            return
        }

        await MainActor.run {
            // Получить имя помпы
            pumpName = apsService.pumpName.value.isEmpty ? "DASH" : apsService.pumpName.value

            // Получить данные батареи помпы
            if let battery = storage.retrieve(OpenAPS.Monitor.battery, as: Battery.self) {
                pumpBattery = battery.percent
            }

            // Получить данные резервуара
            if let reservoirValue = storage.retrieveRaw(OpenAPS.Monitor.reservoir),
               let reservoir = Decimal(string: reservoirValue),
               reservoir != 0xDEAD_BEEF
            {
                pumpReservoir = Double(truncating: reservoir as NSNumber)
            }

            // Получить статус подключения помпы
            pumpConnected = apsService.pumpManager != nil
        }

        debug(
            .service,
            "Loaded pump status: \(pumpName ?? "Unknown"), battery=\(pumpBattery ?? 0)%, reservoir=\(pumpReservoir ?? 0)U, connected=\(pumpConnected)"
        )
    }
}
