import Combine
import SwiftUI
import Swinject

struct IOBForecastView: View {
    let resolver: Resolver
    @StateObject private var viewModel = IOBForecastViewModel()
    @State private var selectedTimeRange: IOBTimeRange = .oneHour

    enum IOBTimeRange: CaseIterable {
        case oneHour
        case threeHours
        case sixHours

        var hours: Int {
            switch self {
            case .oneHour: return 1
            case .threeHours: return 3
            case .sixHours: return 6
            }
        }

        var title: String {
            switch self {
            case .oneHour: return "1ч"
            case .threeHours: return "3ч"
            case .sixHours: return "6ч"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок с селектором времени
            HStack {
                Text("IOB Прогноз")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Picker("Временной диапазон", selection: $selectedTimeRange) {
                    ForEach(IOBTimeRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 150)
            }

            // Текущий IOB (крупно)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Сейчас")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(formatIOB(viewModel.currentIOB))U")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }

                Spacer()

                // Пик активности
                if let peakPoint = viewModel.peakActivityPoint {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Пик активности")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(peakPoint.timeString)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                }
            }

            // График прогноза
            IOBForecastChartView(
                forecastData: viewModel.forecastForHours(selectedTimeRange.hours),
                timeRange: selectedTimeRange
            )
            .frame(height: 120)

            // Ключевые точки прогноза
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.keyForecastPoints(for: selectedTimeRange.hours)) { point in
                        IOBForecastPointView(point: point)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.all, 16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .onAppear {
            viewModel.configure(resolver: resolver)
        }
        .onChange(of: selectedTimeRange) { _ in
            viewModel.updateKeyPoints()
        }
    }

    private func formatIOB(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.0"
    }
}

// MARK: - IOB Forecast Point View

struct IOBForecastPointView: View {
    let point: IOBForecastPoint

    var body: some View {
        VStack(spacing: 4) {
            Text(point.timeString)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(formatValue(point.iobValue))U")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(colorForIOB(point.iobValue))

            // Маленький индикатор активности
            Rectangle()
                .fill(Color.orange.opacity(activityOpacity(point.activityLevel)))
                .frame(width: 30, height: 3)
                .cornerRadius(1.5)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.8))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    private func formatValue(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "0.0"
    }

    private func colorForIOB(_ iob: Decimal) -> Color {
        let value = iob.doubleValue
        if value > 3.0 { return .red }
        if value > 1.5 { return .orange }
        if value > 0.5 { return .blue }
        return .secondary
    }

    private func activityOpacity(_ activity: Decimal) -> Double {
        let maxActivity = 2.0 // Максимальная ожидаемая активность
        return min(1.0, max(0.1, activity.doubleValue / maxActivity))
    }
}

// MARK: - IOB Forecast Chart View

struct IOBForecastChartView: View {
    let forecastData: [IOBForecastPoint]
    let timeRange: IOBForecastView.IOBTimeRange

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let padding: CGFloat = 20

            ZStack {
                // Фон
                Rectangle()
                    .fill(Color.gray.opacity(0.05))

                // Сетка
                Path { path in
                    // Горизонтальные линии
                    for i in 0 ... 4 {
                        let y = padding + CGFloat(i) * (height - 2 * padding) / 4
                        path.move(to: CGPoint(x: padding, y: y))
                        path.addLine(to: CGPoint(x: width - padding, y: y))
                    }

                    // Вертикальные линии (каждый час)
                    let hoursCount = timeRange.hours
                    for i in 0 ... hoursCount {
                        let x = padding + CGFloat(i) * (width - 2 * padding) / CGFloat(hoursCount)
                        path.move(to: CGPoint(x: x, y: padding))
                        path.addLine(to: CGPoint(x: x, y: height - padding))
                    }
                }
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)

                // IOB линия
                if !forecastData.isEmpty {
                    let maxIOB = max(forecastData.map(\.iobValue).max()?.doubleValue ?? 1.0, 1.0)

                    Path { path in
                        for (index, point) in forecastData.enumerated() {
                            let x = padding + CGFloat(point.minutesFromNow) / CGFloat(timeRange.hours * 60) *
                                (width - 2 * padding)
                            let y = height - padding - CGFloat(point.iobValue.doubleValue / maxIOB) * (height - 2 * padding)

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.blue, lineWidth: 2)

                    // Область под кривой
                    Path { path in
                        if let firstPoint = forecastData.first {
                            let startX = padding
                            let startY = height - padding - CGFloat(firstPoint.iobValue.doubleValue / maxIOB) *
                                (height - 2 * padding)
                            path.move(to: CGPoint(x: startX, y: height - padding))
                            path.addLine(to: CGPoint(x: startX, y: startY))

                            for point in forecastData {
                                let x = padding + CGFloat(point.minutesFromNow) / CGFloat(timeRange.hours * 60) *
                                    (width - 2 * padding)
                                let y = height - padding - CGFloat(point.iobValue.doubleValue / maxIOB) * (height - 2 * padding)
                                path.addLine(to: CGPoint(x: x, y: y))
                            }

                            if let lastPoint = forecastData.last {
                                let endX = padding + CGFloat(lastPoint.minutesFromNow) / CGFloat(timeRange.hours * 60) *
                                    (width - 2 * padding)
                                path.addLine(to: CGPoint(x: endX, y: height - padding))
                            }

                            path.closeSubpath()
                        }
                    }
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)]),
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                }

                // Подписи осей
                VStack {
                    HStack {
                        Text("IOB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, padding / 2)

                    Spacer()

                    HStack {
                        Text("0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(timeRange.hours)ч")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, padding / 2)
                }
                .padding(.horizontal, padding)
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class IOBForecastViewModel: ObservableObject {
    @Published var currentIOB: Decimal = 0
    @Published var forecastData: [IOBForecastPoint] = []
    @Published var peakActivityPoint: IOBForecastPoint?
    @Published var keyPoints: [IOBForecastPoint] = []

    private var iobPredictor: IOBPredictorService?
    private var cancellables = Set<AnyCancellable>()

    func configure(resolver: Resolver) {
        guard let predictor = resolver.resolve(IOBPredictorService.self) else {
            warning(.service, "IOBPredictorService not available")
            return
        }

        iobPredictor = predictor

        // Подписываемся на обновления
        if let publishedPredictor = predictor as? BaseIOBPredictorService {
            publishedPredictor.$currentIOB
                .receive(on: DispatchQueue.main)
                .assign(to: \.currentIOB, on: self)
                .store(in: &cancellables)

            publishedPredictor.$iobForecast
                .receive(on: DispatchQueue.main)
                .sink { [weak self] forecast in
                    self?.forecastData = forecast
                    self?.findPeakActivity()
                    self?.updateKeyPoints()
                }
                .store(in: &cancellables)
        }

        // Обновляем данные каждые 30 секунд
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.iobPredictor?.updateForecast()
            }
            .store(in: &cancellables)
    }

    func forecastForHours(_ hours: Int) -> [IOBForecastPoint] {
        iobPredictor?.forecastForNextHours(hours) ?? []
    }

    func keyForecastPoints(for hours: Int) -> [IOBForecastPoint] {
        let forecast = forecastForHours(hours)
        let stepMinutes = hours <= 1 ? 15 : (hours <= 3 ? 30 : 60)

        return forecast.filter { point in
            point.minutesFromNow % stepMinutes == 0 && point.minutesFromNow > 0
        }.prefix(6).map { $0 }
    }

    private func findPeakActivity() {
        peakActivityPoint = forecastData.max { a, b in
            a.activityLevel < b.activityLevel
        }
    }

    func updateKeyPoints() {
        // Обновляем ключевые точки при изменении временного диапазона
        objectWillChange.send()
    }
}

// MARK: - Supporting Extensions

import Combine

extension IOBForecastViewModel {
    func startPeriodicUpdates() {
        Timer.publish(every: 60, on: .main, in: .common) // Каждую минуту
            .autoconnect()
            .sink { [weak self] _ in
                self?.iobPredictor?.updateForecast()
            }
            .store(in: &cancellables)
    }
}
