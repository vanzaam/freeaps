import Combine
import Foundation
import LoopKit
import Swinject

/// ViewModel для экрана ввода углеводов в стиле Loop
/// Управляет состоянием UI и интеграцией с CarbAccountingService
@MainActor class AddCarbsLoopViewModel: ObservableObject {
    // MARK: - Published Properties

    /// Количество углеводов в граммах
    @Published var amount: Decimal = 0

    /// Время приёма пищи
    @Published var mealTime = Date()

    /// Скорость абсорбции
    @Published var absorptionSpeed: AbsorptionSpeed = .medium

    /// Тип пищи
    @Published var foodType: String = ""

    /// Текущий COB
    @Published var currentCOB: Decimal = 0

    /// Предварительный расчёт COB
    @Published var estimatedCOB: Decimal = 0

    /// Статус загрузки
    @Published var isLoading: Bool = false

    /// Ошибка
    @Published var lastError: Error?

    // MARK: - Private Properties

    private var carbService: CarbAccountingService?
    private var configService: CarbConfigurationService?
    private var resolver: Resolver?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// Можно ли добавить углеводы
    var canAddCarb: Bool {
        amount > 0 && !isLoading
    }

    // MARK: - Initialization

    init(resolver: Resolver) {
        self.resolver = resolver
        carbService = resolver.resolve(CarbAccountingService.self)
        configService = resolver.resolve(CarbConfigurationService.self)
        setupObservers()
        loadCurrentCOB()
    }

    // MARK: - Public Methods

    /// Загрузить текущий COB
    func loadCurrentCOB() {
        guard let carbService = carbService else {
            warning(.service, "CarbAccountingService not available")
            return
        }

        currentCOB = carbService.cob
        debug(.service, "Loaded current COB: \(currentCOB)g")
    }

    /// Обновить предварительный расчёт COB
    func updateEstimatedCOB() {
        guard amount > 0 else {
            estimatedCOB = 0
            return
        }

        // Рассчитать COB на основе введённых данных
        let absorptionTime = getAbsorptionTime()
        let timeSinceMeal = Date().timeIntervalSince(mealTime)
        let absorptionProgress = min(1.0, max(0, timeSinceMeal / absorptionTime))

        // Оставшийся COB = количество * (1 - прогресс абсорбции)
        let remainingAmount = amount * Decimal(1.0 - absorptionProgress)
        estimatedCOB = max(0, remainingAmount)

        debug(.service, "Updated estimated COB: \(estimatedCOB)g (amount: \(amount)g, progress: \(absorptionProgress))")
    }

    /// Добавить запись углеводов
    func addCarbEntry() async {
        guard let carbService = carbService else {
            error(.service, "CarbAccountingService not available")
            lastError = CarbError.serviceUnavailable
            return
        }

        guard amount > 0 else {
            warning(.service, "Cannot add carb entry with amount 0")
            lastError = CarbError.invalidAmount
            return
        }

        isLoading = true
        lastError = nil

        do {
            let absorptionTime = getAbsorptionTime()
            let foodTypeString = foodType.isEmpty ? nil : foodType

            await carbService.addCarbEntry(
                amount: amount,
                date: mealTime,
                absorptionDuration: absorptionTime,
                foodType: foodTypeString
            )

            info(.service, "Successfully added carb entry: \(amount)g at \(mealTime)")

            // Сбросить форму
            resetForm()

        } catch let err {
            error(.service, "Failed to add carb entry: \(err.localizedDescription)")
            lastError = err
        }

        isLoading = false
    }

    /// Сбросить форму
    func resetForm() {
        amount = 0
        mealTime = Date()
        absorptionSpeed = .medium
        foodType = ""
        estimatedCOB = 0
        lastError = nil
    }

    /// Установить быстрый выбор углеводов
    func setQuickAmount(_ amount: Decimal) {
        self.amount = amount
        updateEstimatedCOB()
    }

    /// Установить тип пищи и автоматически выбрать скорость абсорбции
    func setFoodType(_ foodType: String) {
        self.foodType = foodType

        // Автоматически выбрать скорость абсорбции на основе типа пищи
        switch foodType.lowercased() {
        case "быстро",
             "конфеты",
             "сахар",
             "сок":
            absorptionSpeed = .fast
        case "паста",
             "рис",
             "средне",
             "хлеб":
            absorptionSpeed = .medium
        case "белковое",
             "жирное",
             "медленно",
             "пицца":
            absorptionSpeed = .slow
        default:
            absorptionSpeed = .medium
        }

        updateEstimatedCOB()
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Наблюдать за изменениями в CarbAccountingService
        carbService?.$cob
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newCOB in
                self?.currentCOB = newCOB
            }
            .store(in: &cancellables)
    }

    private func getAbsorptionTime() -> TimeInterval {
        // Если выбран тип пищи, использовать его скорость
        if !foodType.isEmpty {
            return CarbAccountingService.getAbsorptionTime(for: foodType)
        }

        // Иначе использовать выбранную скорость
        return absorptionSpeed.duration
    }
}

// MARK: - Supporting Types

enum CarbError: LocalizedError {
    case serviceUnavailable
    case invalidAmount
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "Сервис углеводов недоступен"
        case .invalidAmount:
            return "Некорректное количество углеводов"
        case let .networkError(error):
            return "Ошибка сети: \(error.localizedDescription)"
        }
    }
}

// MARK: - Extensions

extension AddCarbsLoopViewModel {
    /// Получить описание скорости абсорбции
    func getAbsorptionDescription() -> String {
        if !foodType.isEmpty {
            return CarbAccountingService.getAbsorptionDescription(for: getAbsorptionTime())
        }
        return absorptionSpeed.displayName
    }

    /// Получить рекомендуемую скорость для типа пищи
    func getRecommendedSpeed(for foodType: String) -> AbsorptionSpeed {
        switch foodType.lowercased() {
        case "быстро",
             "конфеты",
             "сахар",
             "сок":
            return .fast
        case "паста",
             "рис",
             "средне",
             "хлеб":
            return .medium
        case "белковое",
             "жирное",
             "медленно",
             "пицца":
            return .slow
        default:
            return .medium
        }
    }
}
