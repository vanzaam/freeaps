import Combine
import Foundation
import HealthKit
import LoopKit

/// Основной сервис для управления углеводами в стиле Loop
/// Интегрирует LoopKit CarbStore с OpenAPS архитектурой
class CarbAccountingService: ObservableObject {
    // MARK: - Published Properties

    /// Текущий COB (Carbs on Board) в граммах
    @Published var cob: Decimal = 0

    /// Активные записи углеводов
    @Published var activeCarbEntries: [CarbEntry] = []

    /// Эффекты углеводов на глюкозу
    @Published var carbEffects: [GlucoseEffect] = []

    /// Прогресс абсорбции для каждой записи
    @Published var absorptionProgress: [Double] = []

    /// Статус синхронизации с Nightscout
    @Published var syncStatus: SyncStatus = .idle

    // MARK: - Private Properties

    let carbStore: CarbStore
    private let nightscoutAPIProvider: () -> NightscoutAPI?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(carbStore: CarbStore, nightscoutAPIProvider: @escaping () -> NightscoutAPI? = { nil }) {
        self.carbStore = carbStore
        self.nightscoutAPIProvider = nightscoutAPIProvider

        setupObservers()
        Task {
            await updateCOB()
        }
    }

    // MARK: - Public Methods

    /// Добавить новую запись углеводов
    func addCarbEntry(
        amount: Decimal,
        date: Date,
        absorptionDuration: TimeInterval,
        foodType: String? = nil
    ) async {
        info(.service, "Adding carb entry: \(amount)g at \(date)")

        let carbEntry = NewCarbEntry(
            date: date,
            quantity: HKQuantity(unit: .gram(), doubleValue: amount.doubleValue),
            startDate: date,
            foodType: foodType,
            absorptionTime: absorptionDuration
        )

        do {
            let storedEntry = try await carbStore.addCarbEntry(carbEntry) { _ in }
            info(.service, "Successfully added carb entry")

            // Обновить локальные данные
            await updateActiveCarbEntries()
            await updateCOB()

            // Синхронизировать с Nightscout (не критично, не прерываем UX при ошибке)
            await syncToNightscout()

        } catch let err {
            error(.service, "Failed to add carb entry: \(err.localizedDescription)")
            syncStatus = .error(err)
        }
    }

    /// Обновить существующую запись углеводов
    func updateCarbEntry(_ entry: CarbEntry, newAmount: Decimal? = nil, newDate: Date? = nil) async {
        info(.service, "Updating carb entry")

        do {
            // Создать обновлённую запись
            let updatedEntry = NewCarbEntry(
                date: newDate ?? entry.startDate,
                quantity: HKQuantity(
                    unit: .gram(),
                    doubleValue: Double(newAmount?.doubleValue ?? entry.quantity.doubleValue(for: .gram()))
                ),
                startDate: newDate ?? entry.startDate,
                foodType: nil, // CarbEntry protocol doesn't have foodType
                absorptionTime: entry.absorptionTime
            )

            // Удалить старую и добавить новую
            try await carbStore.deleteCarbEntry(entry as! StoredCarbEntry) { _ in }
            let storedEntry = try await carbStore.addCarbEntry(updatedEntry) { _ in }

            info(.service, "Successfully updated carb entry")

            // Обновить локальные данные
            await updateActiveCarbEntries()
            await updateCOB()

            // Синхронизировать с Nightscout
            await syncToNightscout()

        } catch let err {
            error(.service, "Failed to update carb entry: \(err.localizedDescription)")
            syncStatus = .error(err)
        }
    }

    /// Удалить запись углеводов
    func deleteCarbEntry(_ entry: CarbEntry) async {
        info(.service, "Deleting carb entry")

        do {
            try await carbStore.deleteCarbEntry(entry as! StoredCarbEntry) { _ in }
            info(.service, "Successfully deleted carb entry")

            // Обновить локальные данные
            await updateActiveCarbEntries()
            await updateCOB()

            // Синхронизировать с Nightscout
            await syncToNightscout()

        } catch let err {
            error(.service, "Failed to delete carb entry: \(err.localizedDescription)")
            syncStatus = .error(err)
        }
    }

    /// Синхронизировать с Nightscout
    func syncToNightscout() async {
        guard let nightscoutAPI = nightscoutAPIProvider() else {
            warning(.service, "NightscoutAPI not available for sync")
            return
        }

        syncStatus = .syncing

        do {
            // Получить все активные записи
            let entries = activeCarbEntries

            // Конвертировать в Nightscout treatments
            let treatments = entries.map { entry in
                [
                    "eventType": "Carbs",
                    "created_at": entry.startDate.iso8601String,
                    "carbs": entry.quantity.doubleValue(for: .gram()),
                    "enteredBy": "OpenAPS",
                    "absorptionTime": entry.absorptionTime ?? 1800
                ] as [String: Any]
            }

            // Отправить в Nightscout
            for treatment in treatments {
                try await nightscoutAPI.uploadTreatmentDictionary(treatment)
            }

            syncStatus = .synced
            info(.service, "Successfully synced \(entries.count) carb entries to Nightscout")

        } catch let err {
            // Не падать при сетевой ошибке Nightscout — логируем как warning и продолжаем
            warning(.service, "Failed to sync to Nightscout: \(err.localizedDescription)")
            syncStatus = .error(err)
        }
    }

    /// Рассчитать текущий COB
    func calculateCOB() -> Decimal {
        let now = Date()
        var totalCOB: Decimal = 0

        for entry in activeCarbEntries {
            let timeSinceEntry = now.timeIntervalSince(entry.startDate)
            let absorptionProgress = min(1.0, timeSinceEntry / (entry.absorptionTime ?? 1800))

            if absorptionProgress < 1.0 {
                let remainingAmount = entry.quantity.doubleValue(for: .gram()) * (1.0 - absorptionProgress)
                totalCOB += Decimal(remainingAmount)
            }
        }

        return totalCOB
    }

    /// Получить эффект углеводов на глюкозу
    func getCarbEffects(from _: Date, to _: Date) -> [GlucoseEffect] {
        // TODO: Implement proper CarbMath integration
        []
    }

    /// Получить прогноз COB для графика
    func getCOBForecast(until endDate: Date) -> [(Date, Decimal)] {
        let startDate = Date().addingTimeInterval(-6 * 3600) // 6 часов назад
        var forecast: [(Date, Decimal)] = []

        // Генерируем точки каждые 15 минут
        let interval: TimeInterval = 15 * 60 // 15 минут
        var currentDate = startDate

        while currentDate <= endDate {
            let cobAtTime = calculateCOBAtTime(currentDate)
            forecast.append((currentDate, cobAtTime))
            currentDate = currentDate.addingTimeInterval(interval)
        }

        return forecast
    }

    /// Рассчитать COB на определённый момент времени
    private func calculateCOBAtTime(_ time: Date) -> Decimal {
        var totalCOB: Decimal = 0

        for entry in activeCarbEntries {
            // Учитывать только записи, которые были добавлены до указанного времени
            guard entry.startDate <= time else { continue }

            let timeSinceEntry = time.timeIntervalSince(entry.startDate)
            let absorptionTime = entry.absorptionTime ?? 1800 // 3 часа по умолчанию
            let absorptionProgress = min(1.0, max(0.0, timeSinceEntry / absorptionTime))

            if absorptionProgress < 1.0 {
                let remainingAmount = entry.quantity.doubleValue(for: .gram()) * (1.0 - absorptionProgress)
                totalCOB += Decimal(remainingAmount)
            }
        }

        return totalCOB
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Наблюдать за изменениями в CarbStore
        // Обновляем данные каждые 30 секунд и при инициализации
        Timer.publish(every: 30, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.updateActiveCarbEntries()
                    await self?.updateCOB()
                }
            }
            .store(in: &cancellables)

        info(.service, "CarbStore observers configured")
    }

    func updateActiveCarbEntries() async {
        do {
            let entries = try await carbStore.getCarbEntries(start: Date().addingTimeInterval(-24 * 3600))
            activeCarbEntries = entries.filter { entry in
                // Показать только активные записи (в течение 6 часов)
                Date().timeIntervalSince(entry.startDate) < 6 * 3600
            }

            debug(.service, "Updated active carb entries: \(activeCarbEntries.count)")

        } catch let err {
            error(.service, "Failed to update active carb entries: \(err.localizedDescription)")
        }
    }

    private func updateCOB() async {
        cob = calculateCOB()
        debug(.service, "Updated COB: \(cob)g")
    }
}

// MARK: - Supporting Types

extension CarbAccountingService {
    enum SyncStatus {
        case idle
        case syncing
        case synced
        case error(Error)
    }
}

// MARK: - Extensions

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
