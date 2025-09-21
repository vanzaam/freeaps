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

    /// Данные IOB для графика
    @Published var iobData: [IOBData] = []

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
    private var resolver: Resolver?
    private let apsService: APSManager?
    private let storage: FileStorage?
    private let settingsManager: SettingsManager?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(resolver: Resolver) {
        self.resolver = resolver
        carbService = resolver.resolve(CarbAccountingService.self)
        glucoseService = resolver.resolve(GlucoseStorage.self)
        apsService = resolver.resolve(APSManager.self)
        storage = resolver.resolve(FileStorage.self)
        settingsManager = resolver.resolve(SettingsManager.self)

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

            await MainActor.run {
                isLoading = false
                lastUpdate = Date()
            }
            info(.service, "Dashboard data loaded successfully")
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

        do {
            // Загрузить IOB из файла monitor/iob.json
            if let iobEntries = storage.retrieve(OpenAPS.Monitor.iob, as: [IOBEntry].self),
               let latestIOB = iobEntries.first
            {
                await MainActor.run {
                    iob = latestIOB.iob
                }

                // Создать данные для графика IOB (последние 6 часов)
                let endDate = Date()
                let startDate = endDate.addingTimeInterval(-6 * 3600)

                let iobDataPoints: [IOBData] = stride(
                    from: startDate.timeIntervalSince1970,
                    through: endDate.timeIntervalSince1970,
                    by: 15 * 60 // Каждые 15 минут
                ).map { timestamp in
                    IOBData(
                        value: latestIOB.iob, // Упрощенно - используем текущий IOB
                        date: Date(timeIntervalSince1970: timestamp)
                    )
                }

                await MainActor.run {
                    iobData = iobDataPoints
                }

                debug(.service, "Loaded insulin data: IOB = \(iob)U")
            } else {
                warning(.service, "No IOB data available")
                await MainActor.run {
                    iob = 0
                    iobData = []
                }
            }
        } catch let err {
            error(.service, "Failed to load IOB data: \(err.localizedDescription)")
            await MainActor.run {
                lastError = err
                iob = 0
                iobData = []
            }
        }
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
            cobData = cobForecast.map { date, value in
                COBData(
                    value: value,
                    date: date
                )
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
