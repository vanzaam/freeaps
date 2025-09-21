import LoopKit
import SwiftUI
import Swinject

/// Главный экран для ввода углеводов в стиле Loop
/// Предоставляет красивый и интуитивный интерфейс для добавления углеводов
struct AddCarbsLoopView: View {
    let resolver: Resolver
    @StateObject private var viewModel: AddCarbsLoopViewModel
    @Environment(\.dismiss) private var dismiss

    init(resolver: Resolver) {
        self.resolver = resolver
        _viewModel = StateObject(wrappedValue: AddCarbsLoopViewModel(resolver: resolver))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header с текущим COB
                COBHeaderView(currentCOB: viewModel.currentCOB)

                // Основной контент
                ScrollView {
                    VStack(spacing: 20) {
                        // Ввод количества углеводов
                        CarbQuantityInputView(
                            amount: $viewModel.amount,
                            onAmountChanged: viewModel.updateEstimatedCOB
                        )

                        // Выбор времени приёма пищи
                        MealTimeInputView(
                            mealTime: $viewModel.mealTime,
                            onTimeChanged: viewModel.updateEstimatedCOB
                        )

                        // Выбор скорости абсорбции
                        AbsorptionSpeedPickerView(
                            selectedSpeed: $viewModel.absorptionSpeed,
                            onSpeedChanged: viewModel.updateEstimatedCOB
                        )

                        // Тип пищи (опционально)
                        FoodTypeRowView(
                            foodType: $viewModel.foodType,
                            onFoodTypeChanged: viewModel.updateEstimatedCOB
                        )

                        // Предварительный расчёт COB
                        COBPreviewView(
                            estimatedCOB: viewModel.estimatedCOB,
                            currentCOB: viewModel.currentCOB
                        )

                        // Быстрые кнопки для популярных значений
                        QuickAmountButtonsView(
                            onAmountSelected: { amount in
                                viewModel.amount = amount
                                viewModel.updateEstimatedCOB()
                            }
                        )
                    }
                    .padding()
                }

                // Кнопка добавления
                AddCarbButtonView(
                    isEnabled: viewModel.canAddCarb,
                    isLoading: viewModel.isLoading,
                    onAdd: {
                        Task {
                            await viewModel.addCarbEntry()
                            dismiss()
                        }
                    }
                )
            }
            .navigationTitle("Добавить углеводы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadCurrentCOB()
        }
    }
}

// MARK: - Header View

struct COBHeaderView: View {
    let currentCOB: Decimal

    var body: some View {
        VStack(spacing: 8) {
            Text("Текущий COB")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(formatDecimal(currentCOB, min: 1, max: 1)) г")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

private func formatDecimal(_ value: Decimal, min: Int, max: Int) -> String {
    let formatter = FormatterCache.numberFormatter(style: .decimal, minFractionDigits: min, maxFractionDigits: max)
    return formatter.string(from: NSDecimalNumber(decimal: value)) ?? String(describing: value)
}

// MARK: - Quantity Input View

struct CarbQuantityInputView: View {
    @Binding var amount: Decimal
    let onAmountChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Количество углеводов")
                .font(.headline)
                .foregroundColor(.primary)

            HStack {
                TextField("0", value: $amount, format: .number)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.decimalPad)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .onChange(of: amount) { _ in
                        onAmountChanged()
                    }

                Text("грамм")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Meal Time Input View

struct MealTimeInputView: View {
    @Binding var mealTime: Date
    let onTimeChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Время приёма пищи")
                .font(.headline)
                .foregroundColor(.primary)

            DatePicker(
                "Время",
                selection: $mealTime,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(CompactDatePickerStyle())
            .onChange(of: mealTime) { _ in
                onTimeChanged()
            }
        }
    }
}

// MARK: - Absorption Speed Picker View

struct AbsorptionSpeedPickerView: View {
    @Binding var selectedSpeed: AbsorptionSpeed
    let onSpeedChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Скорость абсорбции")
                .font(.headline)
                .foregroundColor(.primary)

            Picker("Скорость", selection: $selectedSpeed) {
                ForEach(AbsorptionSpeed.allCases, id: \.self) { speed in
                    Text(speed.displayName)
                        .tag(speed)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedSpeed) { _ in
                onSpeedChanged()
            }
        }
    }
}

// MARK: - Food Type Row View

struct FoodTypeRowView: View {
    @Binding var foodType: String
    let onFoodTypeChanged: () -> Void

    private let foodTypes = ["Быстро", "Средне", "Медленно", "Пицца", "Жирное", "Белковое"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Тип пищи (опционально)")
                .font(.headline)
                .foregroundColor(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(foodTypes, id: \.self) { type in
                        Button(action: {
                            foodType = type
                            onFoodTypeChanged()
                        }) {
                            Text(type)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    foodType == type ? Color.blue : Color(.systemGray5)
                                )
                                .foregroundColor(
                                    foodType == type ? .white : .primary
                                )
                                .cornerRadius(16)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - COB Preview View

struct COBPreviewView: View {
    let estimatedCOB: Decimal
    let currentCOB: Decimal

    private var totalCOB: Decimal {
        currentCOB + estimatedCOB
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Предварительный расчёт")
                .font(.headline)
                .foregroundColor(.primary)

            HStack(spacing: 20) {
                VStack {
                    Text("Текущий COB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(formatDecimal(currentCOB, min: 1, max: 1)) г")
                        .font(.title3)
                        .fontWeight(.medium)
                }

                Image(systemName: "plus")
                    .foregroundColor(.secondary)

                VStack {
                    Text("Новый COB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(formatDecimal(estimatedCOB, min: 1, max: 1)) г")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }

                Image(systemName: "equal")
                    .foregroundColor(.secondary)

                VStack {
                    Text("Итого COB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(formatDecimal(totalCOB, min: 1, max: 1)) г")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Quick Amount Buttons View

struct QuickAmountButtonsView: View {
    let onAmountSelected: (Decimal) -> Void

    private let quickAmounts: [Decimal] = [5, 10, 15, 20, 25, 30, 40, 50]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Быстрый выбор")
                .font(.headline)
                .foregroundColor(.primary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(quickAmounts, id: \.self) { amount in
                    Button(action: {
                        onAmountSelected(amount)
                    }) {
                        Text(formatDecimal(amount, min: 0, max: 0))
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
}

// MARK: - Add Carb Button View

struct AddCarbButtonView: View {
    let isEnabled: Bool
    let isLoading: Bool
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }

                Text("Добавить углеводы")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                isEnabled ? Color.blue : Color(.systemGray4)
            )
            .cornerRadius(12)
        }
        .disabled(!isEnabled || isLoading)
        .padding()
    }
}

// MARK: - Supporting Types

enum AbsorptionSpeed: String, CaseIterable {
    case fast
    case medium
    case slow

    var displayName: String {
        switch self {
        case .fast: return "Быстро (15 мин)"
        case .medium: return "Средне (30 мин)"
        case .slow: return "Медленно (60 мин)"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .fast: return 15 * 60
        case .medium: return 30 * 60
        case .slow: return 60 * 60
        }
    }
}

#Preview {
    let container = Container()
    // Минимальная настройка для preview
    return AddCarbsLoopView(resolver: container.synchronize())
}
