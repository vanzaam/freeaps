import Foundation
import HealthKit
import LoopKit

/// Сервис для синхронизации углеводов с Nightscout
/// Конвертирует CarbEntry в Nightscout treatments и отправляет их
class NightscoutCarbSync {
    private let nightscoutAPI: NightscoutAPI

    // MARK: - Initialization

    init(nightscoutAPI: NightscoutAPI) {
        self.nightscoutAPI = nightscoutAPI
        info(.service, "NightscoutCarbSync initialized")
    }

    // MARK: - Public Methods

    /// Синхронизировать все активные записи углеводов
    func syncCarbEntries(_ entries: [CarbEntry]) async throws {
        info(.service, "Syncing \(entries.count) carb entries to Nightscout")

        for entry in entries {
            let treatment = convertToNightscoutTreatment(entry)
            try await nightscoutAPI.uploadTreatmentDictionary(treatment)
            debug(.service, "Synced carb entry: \(entry.startDate)")
        }

        info(.service, "Successfully synced all carb entries to Nightscout")
    }

    /// Синхронизировать одну запись углеводов
    func syncCarbEntry(_ entry: CarbEntry) async throws {
        info(.service, "Syncing single carb entry to Nightscout: \(entry.startDate)")

        let treatment = convertToNightscoutTreatment(entry)
        try await nightscoutAPI.uploadTreatmentDictionary(treatment)

        info(.service, "Successfully synced carb entry to Nightscout")
    }

    /// Удалить запись углеводов из Nightscout
    func deleteCarbEntry(_ entry: CarbEntry) async throws {
        info(.service, "Deleting carb entry from Nightscout: \(entry.startDate)")

        // Создать treatment для удаления
        let deleteTreatment = [
            "eventType": "Carbs",
            "created_at": entry.startDate.iso8601String,
            "carbs": 0, // 0 углеводов означает удаление
            "enteredBy": "OpenAPS",
            "deleted": true
        ] as [String: Any]

        try await nightscoutAPI.uploadTreatmentDictionary(deleteTreatment)

        info(.service, "Successfully deleted carb entry from Nightscout")
    }

    /// Получить углеводы из Nightscout
    func getCarbEntries(from startDate: Date, to endDate: Date) async throws -> [CarbEntry] {
        info(.service, "Fetching carb entries from Nightscout: \(startDate) to \(endDate)")

        let treatments = try await nightscoutAPI.fetchTreatments(from: startDate, to: endDate)

        let carbEntries = treatments.compactMap { treatment in
            convertFromNightscoutTreatment(treatment)
        }

        info(.service, "Fetched \(carbEntries.count) carb entries from Nightscout")
        return carbEntries
    }

    // MARK: - Private Methods

    private func convertToNightscoutTreatment(_ entry: CarbEntry) -> [String: Any] {
        let amount = entry.quantity.doubleValue(for: .gram())

        return [
            "eventType": "Carbs",
            "created_at": entry.startDate.iso8601String,
            "carbs": amount,
            "enteredBy": "OpenAPS",
            "absorptionTime": entry.absorptionTime ?? 30 * 60
        ] as [String: Any]
    }

    private func convertFromNightscoutTreatment(_ treatment: [String: Any]) -> NewCarbEntry? {
        guard let eventType = treatment["eventType"] as? String,
              eventType == "Carbs",
              let created_at = treatment["created_at"] as? String,
              let date = ISO8601DateFormatter().date(from: created_at),
              let carbs = treatment["carbs"] as? Double,
              carbs > 0
        else {
            return nil
        }

        let absorptionTime = treatment["absorptionTime"] as? TimeInterval ?? 30 * 60 // 30 минут по умолчанию
        let foodType = treatment["foodType"] as? String

        let quantity = HKQuantity(unit: .gram(), doubleValue: carbs)
        return NewCarbEntry(
            date: date,
            quantity: quantity,
            startDate: date,
            foodType: foodType,
            absorptionTime: absorptionTime
        )
    }
}

// MARK: - Extensions

extension NightscoutCarbSync {
    /// Получить статистику синхронизации
    func getSyncStats() -> [String: Any] {
        [
            "lastSync": Date(),
            "nightscoutAvailable": true, // TODO: Проверить реальную доступность
            "syncEnabled": true
        ]
    }
}

// MARK: - Helper Extensions

// Removed invalid extension that tried to add initializer to protocol-constrained type
