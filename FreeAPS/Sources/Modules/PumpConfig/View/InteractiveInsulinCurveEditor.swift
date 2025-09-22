import LoopKit
import LoopKitUI
import SwiftUI
import Swinject

struct InteractiveInsulinCurveEditor: View {
    @Environment(\.presentationMode) private var presentationMode
    let resolver: Resolver

    @State private var selectedCurveType: InsulinCurveType = .rapid
    @State private var customPeakTime: Double = 75
    @State private var customActionDuration: Double = 360
    @State private var customDelay: Double = 10
    @State private var useCustomCurve: Bool = false

    // График данных
    @State private var chartData: [ChartPoint] = []

    enum InsulinCurveType: String, CaseIterable {
        case rapid = "Rapid-Acting"
        case ultraRapid = "Ultra-Rapid (Fiasp)"
        case custom = "Custom"

        var peakTime: Double {
            switch self {
            case .rapid: return 75
            case .ultraRapid: return 55
            case .custom: return 75
            }
        }

        var actionDuration: Double {
            switch self {
            case .rapid,
                 .ultraRapid: return 360
            case .custom: return 360
            }
        }

        var delay: Double {
            10
        }

        var description: String {
            switch self {
            case .rapid:
                return "Подходит для Humalog, Novolog, Novorapid. Пик через 75 минут."
            case .ultraRapid:
                return "Подходит для Fiasp, Lyumjev. Пик через 55 минут."
            case .custom:
                return "Настраиваемая кривая с произвольными параметрами."
            }
        }
    }

    struct ChartPoint {
        let time: Double
        let iobPercent: Double
        let activityLevel: Double
    }

    private var palette: ChartColorPalette {
        ChartColorPalette(
            axisLine: .tertiaryLabel,
            axisLabel: .secondaryLabel,
            grid: .tertiaryLabel,
            glucoseTint: .systemGreen,
            insulinTint: .systemBlue,
            carbTint: .systemOrange
        )
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Заголовок
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Интерактивный редактор кривой инсулина")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Настройте кривую активности инсулина с помощью реальных формул OpenAPS")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    // Выбор типа кривой
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Тип кривой инсулина")
                            .font(.headline)

                        Picker("Тип кривой", selection: $selectedCurveType) {
                            ForEach(InsulinCurveType.allCases, id: \.self) { curveType in
                                Text(curveType.rawValue).tag(curveType)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: selectedCurveType) { newType in
                            updateParametersForCurveType(newType)
                            generateChartData()
                        }

                        Text(selectedCurveType.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    // Параметры кривой
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Параметры кривой")
                            .font(.headline)

                        // Время пика
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Время пика активности")
                                Spacer()
                                Text("\(Int(currentPeakTime)) мин")
                                    .foregroundColor(.blue)
                                    .fontWeight(.medium)
                            }

                            Slider(
                                value: Binding(
                                    get: { currentPeakTime },
                                    set: { newValue in
                                        if selectedCurveType == .custom {
                                            customPeakTime = newValue
                                        }
                                        generateChartData()
                                    }
                                ),
                                in: 35 ... 120,
                                step: 5
                            )
                            .disabled(selectedCurveType != .custom)
                        }

                        // Продолжительность действия
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Продолжительность действия")
                                Spacer()
                                Text("\(Int(currentActionDuration)) мин (\(currentActionDuration / 60, specifier: "%.1f")ч)")
                                    .foregroundColor(.blue)
                                    .fontWeight(.medium)
                            }

                            Slider(
                                value: Binding(
                                    get: { currentActionDuration },
                                    set: { newValue in
                                        if selectedCurveType == .custom {
                                            customActionDuration = newValue
                                        }
                                        generateChartData()
                                    }
                                ),
                                in: 180 ... 480,
                                step: 30
                            )
                            .disabled(selectedCurveType != .custom)
                        }

                        // Задержка
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Задержка начала действия")
                                Spacer()
                                Text("\(Int(currentDelay)) мин")
                                    .foregroundColor(.blue)
                                    .fontWeight(.medium)
                            }

                            Slider(
                                value: Binding(
                                    get: { currentDelay },
                                    set: { newValue in
                                        if selectedCurveType == .custom {
                                            customDelay = newValue
                                        }
                                        generateChartData()
                                    }
                                ),
                                in: 0 ... 20,
                                step: 2
                            )
                            .disabled(selectedCurveType != .custom)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // График кривой
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Визуализация кривой")
                            .font(.headline)
                            .padding(.horizontal)

                        InsulinCurveChartView(
                            chartData: chartData,
                            peakTime: currentPeakTime,
                            actionDuration: currentActionDuration
                        )
                        .frame(height: 300)
                        .padding(.horizontal)
                    }

                    // Информация о формуле
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Формула OpenAPS (Экспоненциальная модель)")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Используемые параметры:")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("• τ = \(currentTau, specifier: "%.1f")")
                            Text("• a = \(currentA, specifier: "%.3f")")
                            Text("• S = \(currentS, specifier: "%.3f")")
                        }
                        .font(.caption)
                        .padding(.all, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)

                        Text("IOB(t) = 1 - S × (1-a) × ((t²/(τ×DIA×(1-a)) - t/τ - 1) × e^(-t/τ) + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.all, 8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)

                    // Кнопки действий
                    HStack(spacing: 16) {
                        Button("Отмена") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)

                        Button("Применить") {
                            saveInsulinCurve()
                            presentationMode.wrappedValue.dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            updateParametersForCurveType(selectedCurveType)
            generateChartData()
        }
    }

    // MARK: - Computed Properties

    private var currentPeakTime: Double {
        selectedCurveType == .custom ? customPeakTime : selectedCurveType.peakTime
    }

    private var currentActionDuration: Double {
        selectedCurveType == .custom ? customActionDuration : selectedCurveType.actionDuration
    }

    private var currentDelay: Double {
        selectedCurveType == .custom ? customDelay : selectedCurveType.delay
    }

    // Расчет параметров формулы OpenAPS
    private var currentTau: Double {
        let peak = currentPeakTime
        let duration = currentActionDuration
        return peak * (1 - peak / duration) / (1 - 2 * peak / duration)
    }

    private var currentA: Double {
        2 * currentTau / currentActionDuration
    }

    private var currentS: Double {
        let a = currentA
        let duration = currentActionDuration
        let tau = currentTau
        return 1 / (1 - a + (1 + a) * exp(-duration / tau))
    }

    // MARK: - Methods

    private func updateParametersForCurveType(_ curveType: InsulinCurveType) {
        if curveType != .custom {
            customPeakTime = curveType.peakTime
            customActionDuration = curveType.actionDuration
            customDelay = curveType.delay
        }
    }

    private func generateChartData() {
        var data: [ChartPoint] = []
        let duration = currentActionDuration + currentDelay
        let stepMinutes = 5.0

        for minute in stride(from: 0, through: duration, by: stepMinutes) {
            let iob = calculateIOB(at: minute)
            let activity = calculateActivity(at: minute)

            data.append(ChartPoint(
                time: minute,
                iobPercent: iob * 100,
                activityLevel: activity * 100
            ))
        }

        chartData = data
    }

    private func calculateIOB(at time: Double) -> Double {
        let timeAfterDelay = time - currentDelay
        let duration = currentActionDuration

        guard timeAfterDelay > 0 else { return 1.0 }
        guard timeAfterDelay < duration else { return 0.0 }

        let t = timeAfterDelay
        let tau = currentTau
        let a = currentA
        let s = currentS

        let iob = 1 - s * (1 - a) * ((pow(t, 2) / (tau * duration * (1 - a)) - t / tau - 1) * exp(-t / tau) + 1)

        return max(0, min(1, iob))
    }

    private func calculateActivity(at time: Double) -> Double {
        // Производная IOB для получения активности
        let timeAfterDelay = time - currentDelay
        let duration = currentActionDuration

        guard timeAfterDelay > 0 else { return 0.0 }
        guard timeAfterDelay < duration else { return 0.0 }

        // Приближенная активность через разность IOB
        let dt = 1.0
        let iob1 = calculateIOB(at: time)
        let iob2 = calculateIOB(at: time + dt)

        return abs(iob1 - iob2) / dt
    }

    private func saveInsulinCurve() {
        guard let storage = resolver.resolve(FileStorage.self) else { return }

        // Сохраняем настройки кривой
        let settings = InsulinCurveSettings(
            curveType: selectedCurveType.rawValue,
            peakTime: currentPeakTime,
            actionDuration: currentActionDuration,
            delay: currentDelay,
            useCustom: selectedCurveType == .custom
        )

        // Сохраняем настройки кривой как JSON объект
        storage.save(settings, as: OpenAPS.Settings.insulinCurve)

        // Также сохраняем для совместимости
        storage.save(String(describing: selectedCurveType), as: OpenAPS.Settings.model)
    }
}

// MARK: - Supporting Types

struct InsulinCurveSettings: JSON {
    let curveType: String
    let peakTime: Double
    let actionDuration: Double
    let delay: Double
    let useCustom: Bool
}

// MARK: - Chart View

struct InsulinCurveChartView: View {
    let chartData: [InteractiveInsulinCurveEditor.ChartPoint]
    let peakTime: Double
    let actionDuration: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let maxTime = actionDuration + 10
            let padding: CGFloat = 40

            ZStack {
                // Фон
                Rectangle()
                    .fill(Color.gray.opacity(0.05))

                // Сетка
                Path { path in
                    // Вертикальные линии (время)
                    for hour in 0 ... Int(maxTime / 60) {
                        let x = padding + CGFloat(hour * 60) / CGFloat(maxTime) * (width - 2 * padding)
                        path.move(to: CGPoint(x: x, y: padding))
                        path.addLine(to: CGPoint(x: x, y: height - padding))
                    }

                    // Горизонтальные линии (проценты)
                    for percent in stride(from: 0, through: 100, by: 25) {
                        let y = height - padding - CGFloat(percent) / 100 * (height - 2 * padding)
                        path.move(to: CGPoint(x: padding, y: y))
                        path.addLine(to: CGPoint(x: width - padding, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)

                // Кривая IOB (% оставшегося инсулина)
                Path { path in
                    for (index, point) in chartData.enumerated() {
                        let x = padding + CGFloat(point.time) / CGFloat(maxTime) * (width - 2 * padding)
                        let y = height - padding - CGFloat(point.iobPercent) / 100 * (height - 2 * padding)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.blue, lineWidth: 3)

                // Кривая активности (нормализованная)
                Path { path in
                    let maxActivity = chartData.map(\.activityLevel).max() ?? 1

                    for (index, point) in chartData.enumerated() {
                        let x = padding + CGFloat(point.time) / CGFloat(maxTime) * (width - 2 * padding)
                        let normalizedActivity = CGFloat(point.activityLevel) / CGFloat(maxActivity) * 100
                        let y = height - padding - normalizedActivity / 100 * (height - 2 * padding)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.orange, lineWidth: 2)

                // Линия пика
                Path { path in
                    let x = padding + CGFloat(peakTime) / CGFloat(maxTime) * (width - 2 * padding)
                    path.move(to: CGPoint(x: x, y: padding))
                    path.addLine(to: CGPoint(x: x, y: height - padding))
                }
                .stroke(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))

                // Подписи осей
                VStack {
                    Spacer()
                    HStack {
                        Text("0")
                            .font(.caption)
                            .offset(x: padding)
                        Spacer()
                        Text("\(Int(maxTime / 60))ч")
                            .font(.caption)
                            .offset(x: -padding)
                    }
                }

                HStack {
                    VStack {
                        Text("100%")
                            .font(.caption)
                        Spacer()
                        Text("0%")
                            .font(.caption)
                    }
                    .offset(x: padding / 2)
                    Spacer()
                }

                // Легенда
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Rectangle()
                                    .fill(Color.blue)
                                    .frame(width: 20, height: 3)
                                Text("IOB (%)")
                                    .font(.caption)
                            }
                            HStack {
                                Rectangle()
                                    .fill(Color.orange)
                                    .frame(width: 20, height: 2)
                                Text("Активность")
                                    .font(.caption)
                            }
                            HStack {
                                Rectangle()
                                    .fill(Color.red.opacity(0.7))
                                    .frame(width: 20, height: 2)
                                Text("Пик (\(Int(peakTime))м)")
                                    .font(.caption)
                            }
                        }
                        .padding(8)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(8)
                        .shadow(radius: 2)
                    }
                    .padding(.top, padding)
                    Spacer()
                }
            }
        }
    }
}
