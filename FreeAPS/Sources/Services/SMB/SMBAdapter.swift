import Combine
import Foundation
import LoopKit

/// SMB (Super Micro Bolus) адаптер для работы с Loop системой углеводов
/// Рассчитывает безопасные SMB дозы на основе активных углеводов и профиля пользователя
class SMBAdapter: ObservableObject {
    // MARK: - Published Properties

    /// Рекомендуемая SMB доза
    @Published var recommendedSMB: Decimal = 0

    /// Активность SMB системы
    @Published var isEnabled: Bool = false

    /// Последний рассчитанный карб импакт
    @Published var carbImpact: Decimal = 0

    /// Статус безопасности для SMB
    @Published var safetyStatus: SafetyStatus = .safe

    // MARK: - Dependencies

    private let carbService: CarbAccountingService
    private let glucoseStorage: GlucoseStorage
    private let settingsManager: SettingsManager
    private let storage: FileStorage

    // MARK: - Configuration

    private var maxSMB: Decimal = 1.0 // Максимальная SMB доза в единицах
    private var maxIOB: Decimal = 5.0 // Максимальный IOB
    private var minDelta: Decimal = 5.0 // Минимальная дельта глюкозы для активации SMB
    private var carbsRequired: Bool = true // Требуются ли активные углеводы

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        carbService: CarbAccountingService,
        glucoseStorage: GlucoseStorage,
        settingsManager: SettingsManager,
        storage: FileStorage
    ) {
        self.carbService = carbService
        self.glucoseStorage = glucoseStorage
        self.settingsManager = settingsManager
        self.storage = storage

        loadConfiguration()
        setupObservers()

        info(.service, "SMBAdapter initialized")
    }

    // MARK: - Public Methods

    /// Рассчитать рекомендуемую SMB дозу
    func calculateSMB() async -> Decimal {
        guard isEnabled else {
            debug(.service, "SMB disabled")
            return 0
        }

        // Проверить безопасность
        let safetyCheck = await performSafetyCheck()
        await MainActor.run {
            safetyStatus = safetyCheck
        }

        guard safetyCheck == .safe else {
            debug(.service, "SMB safety check failed: \(safetyCheck)")
            return 0
        }

        // Рассчитать карб импакт
        let impact = await calculateCarbImpact()
        await MainActor.run {
            carbImpact = impact
        }

        // Рассчитать SMB дозу на основе карб импакта
        let smbDose = calculateSMBFromCarbImpact(impact)

        await MainActor.run {
            recommendedSMB = smbDose
        }

        info(.service, "SMB calculated: \(smbDose)U (carb impact: \(impact)mg/dL)")
        return smbDose
    }

    /// Применить ограничения к SMB дозе
    func applySMBConstraints(_ dose: Decimal) -> Decimal {
        let constrainedDose = min(dose, maxSMB)

        if constrainedDose != dose {
            debug(.service, "SMB dose constrained: \(dose) → \(constrainedDose)")
        }

        return constrainedDose
    }

    /// Проверить, безопасно ли давать SMB
    func isSMBSafe() async -> Bool {
        let status = await performSafetyCheck()
        return status == .safe
    }

    // MARK: - Configuration

    func updateConfiguration(
        maxSMB: Decimal? = nil,
        maxIOB: Decimal? = nil,
        minDelta: Decimal? = nil,
        carbsRequired: Bool? = nil,
        enabled: Bool? = nil
    ) {
        if let maxSMB = maxSMB { self.maxSMB = maxSMB }
        if let maxIOB = maxIOB { self.maxIOB = maxIOB }
        if let minDelta = minDelta { self.minDelta = minDelta }
        if let carbsRequired = carbsRequired { self.carbsRequired = carbsRequired }
        if let enabled = enabled { isEnabled = enabled }

        info(.service, "SMB configuration updated: maxSMB=\(self.maxSMB), maxIOB=\(self.maxIOB), enabled=\(isEnabled)")
    }

    // MARK: - Private Methods

    private func loadConfiguration() {
        // Загрузить настройки из Preferences
        let preferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
            ?? Preferences()

        // SMB настройки: комбинируем стандартные и Loop CarbStore
        let standardSMBEnabled = preferences.enableSMBWithCOB || preferences.enableSMBAfterCarbs
        let loopCarbSMBEnabled = preferences.enableLoopCarbSMB

        isEnabled = standardSMBEnabled || loopCarbSMBEnabled

        // Для Loop CarbStore SMB используем специальные настройки
        if loopCarbSMBEnabled {
            maxSMB = preferences.carbSMBMaxDose
            minDelta = preferences.carbSMBMinDelta
        } else {
            maxSMB = preferences.maxSMBBasalMinutes / 60 // Преобразовать минуты в единицы
            minDelta = 5.0 // Стандартное значение
        }

        maxIOB = preferences.maxIOB
        carbsRequired = !preferences.enableSMBAlways // Если не всегда, то нужны углеводы

        debug(
            .service,
            "SMB configuration loaded: enabled=\(isEnabled), maxSMB=\(maxSMB), maxIOB=\(maxIOB), loopCarb=\(loopCarbSMBEnabled)"
        )
    }

    private func setupObservers() {
        // Наблюдать за изменениями углеводов
        carbService.$cob
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.calculateSMB()
                }
            }
            .store(in: &cancellables)

        // Наблюдать за изменениями активных записей углеводов
        carbService.$activeCarbEntries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.calculateSMB()
                }
            }
            .store(in: &cancellables)
    }

    private func performSafetyCheck() async -> SafetyStatus {
        // Проверка 1: Требуются ли активные углеводы
        if carbsRequired, carbService.cob <= 0 {
            return .noActiveCarbs
        }

        // Проверка 2: Минимальная дельта глюкозы
        let currentGlucose = getCurrentGlucose()
        let trend = getGlucoseTrend()

        if currentGlucose < 70 {
            return .lowGlucose
        }

        if trend < minDelta {
            return .insufficientDelta
        }

        // Проверка 3: Максимальный IOB
        let currentIOB = await getCurrentIOB()
        if currentIOB >= maxIOB {
            return .maxIOBReached
        }

        return .safe
    }

    private func calculateCarbImpact() async -> Decimal {
        let now = Date()
        let futureTime = now.addingTimeInterval(30 * 60) // 30 минут в будущее

        // Получить прогноз углеводного эффекта
        let carbEffects = carbService.getCarbEffects(from: now, to: futureTime)

        // Рассчитать суммарный импакт
        let totalImpact = carbEffects.reduce(0) { sum, effect in
            sum + Decimal(effect.quantity.doubleValue(for: .milligramsPerDeciliter))
        }

        return totalImpact
    }

    private func calculateSMBFromCarbImpact(_ impact: Decimal) -> Decimal {
        // Получить текущую чувствительность к инсулину из профиля
        let insulinSensitivity = getCurrentInsulinSensitivity()

        // Рассчитать необходимую дозу: impact / sensitivity
        let rawSmbDose = impact / insulinSensitivity

        // Применить safety multiplier для Loop CarbStore SMB
        let preferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) ?? Preferences()
        let safetyMultiplier = preferences.enableLoopCarbSMB ? preferences.carbSMBSafetyMultiplier : 1.0
        let smbDose = rawSmbDose * safetyMultiplier

        // Применить дополнительные ограничения
        let constrainedDose = applySMBConstraints(smbDose)

        debug(
            .service,
            "SMB calculation: impact=\(impact), ISF=\(insulinSensitivity), raw=\(rawSmbDose), safety=\(safetyMultiplier), final=\(constrainedDose)"
        )

        return constrainedDose
    }

    private func getCurrentInsulinSensitivity() -> Decimal {
        // Получить профиль чувствительности к инсулину
        let sensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)

        guard let profile = sensitivities, !profile.sensitivities.isEmpty else {
            warning(.service, "No insulin sensitivity profile found, using default 50 mg/dL")
            return 50 // Fallback значение
        }

        // Найти текущую чувствительность по времени
        let now = Date()
        let currentTimeMinutes = Calendar.current.component(.hour, from: now) * 60 +
            Calendar.current.component(.minute, from: now)

        // Найти подходящую запись
        let currentSensitivity = profile.sensitivities
            .sorted { $0.offset < $1.offset }
            .last { $0.offset <= currentTimeMinutes }
            ?? profile.sensitivities.first

        let sensitivity = currentSensitivity?.sensitivity ?? 50

        // Применить autosens коррекцию если доступна
        if let autosens = storage.retrieve(OpenAPS.Settings.autosense, as: Autosens.self) {
            let adjustedSensitivity = sensitivity / autosens.ratio
            debug(.service, "Insulin sensitivity: \(sensitivity) → \(adjustedSensitivity) (autosens: \(autosens.ratio))")
            return adjustedSensitivity
        }

        return sensitivity
    }

    private func getCurrentGlucose() -> Decimal {
        let recent = glucoseStorage.recent()
        guard let latest = recent.last else { return 100 } // Fallback
        return Decimal(latest.sgv ?? Int(latest.filtered ?? 100))
    }

    private func getGlucoseTrend() -> Decimal {
        let recent = glucoseStorage.recent()
        guard recent.count >= 2 else { return 0 }

        let last = recent.suffix(2)
        let values = last.compactMap { Decimal($0.sgv ?? Int($0.filtered ?? 0)) }

        guard values.count == 2 else { return 0 }
        return values[1] - values[0]
    }

    private func getCurrentIOB() async -> Decimal {
        // TODO: Получить текущий IOB из APSManager или DeviceDataManager
        // Пока возвращаем заглушку
        0
    }
}

// MARK: - Supporting Types

extension SMBAdapter {
    enum SafetyStatus: Equatable {
        case safe
        case noActiveCarbs
        case lowGlucose
        case insufficientDelta
        case maxIOBReached
        case error(String)

        var description: String {
            switch self {
            case .safe:
                return "Safe for SMB"
            case .noActiveCarbs:
                return "No active carbs"
            case .lowGlucose:
                return "Glucose too low"
            case .insufficientDelta:
                return "Insufficient glucose trend"
            case .maxIOBReached:
                return "Maximum IOB reached"
            case let .error(message):
                return "Error: \(message)"
            }
        }
    }
}
