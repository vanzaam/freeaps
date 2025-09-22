import LoopKit
import LoopKitUI
import SwiftUI
import Swinject

/// Главный экран OpenAPS в точном стиле Loop
/// Верхняя панель: глюкоза, статус Loop, помпа
/// Центр: графики SwiftCharts как в Loop
/// Низ: кнопки действий как в Loop
struct DashboardRootView: View {
    let resolver: Resolver
    @StateObject private var viewModel: DashboardStateModel
    @State private var selectedTimeRange: TimeRange = .sixHours
    @State private var showingAddCarbs = false
    @State private var showingAddBolus = false
    @State private var showingTempTarget = false
    @State private var showingSettings = false
    @State private var showingPumpSettings = false
    @State private var showingLoopStatus = false
    @State private var showingGlucoseHistory = false
    @State private var showingCarbEntry = false
    @State private var hoverX: CGFloat? = nil
    @State private var hoverDate: Date? = nil

    init(resolver: Resolver) {
        self.resolver = resolver
        _viewModel = StateObject(wrappedValue: DashboardStateModel(resolver: resolver))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let percent = viewModel.bolusPercent {
                HStack {
                    ProgressView(value: percent)
                        .progressViewStyle(BolusProgressViewStyle())
                    Text(String(format: "%.0f%%", percent * 100))
                        .font(.caption)
                        .foregroundColor(.insulin)
                    Spacer()
                    Button(action: { cancelBolus() }) {
                        Text("Stop")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            // Верхняя панель в стиле Loop: глюкоза, статус Loop, помпа
            LoopStatusHUDView(
                currentGlucose: viewModel.currentGlucose,
                trend: viewModel.trend,
                loopStatus: getLoopStatus(),
                pumpStatus: getPumpStatus(),
                lastUpdate: viewModel.lastUpdate,
                onGlucoseTapped: {
                    showingGlucoseHistory = true
                },
                onLoopTapped: {
                    // Открыть экран статуса петли
                    showingLoopStatus = true
                },
                onPumpTapped: {
                    // Открыть настройки помпы (как раньше в Home):
                    // если есть pumpManager → сразу нативные настройки;
                    // иначе → экран настройки помпы
                    showingPumpSettings = true
                }
            )

            // Глюкозный график + общая линия наведения и всплывающая строка
            ZStack(alignment: .topLeading) {
                LoopUIKitGlucoseChartView(
                    glucose: viewModel.glucose,
                    predicted: viewModel.predictedGlucose,
                    timeRangeHours: selectedTimeRange.hours,
                    useMmolL: viewModel.units == .mmolL,
                    lowThreshold: viewModel.lowThreshold,
                    highThreshold: viewModel.highThreshold
                )
                .frame(height: 280)

                GeometryReader { geo in
                    if let x = hoverX {
                        Rectangle()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: 1)
                            .position(x: min(max(1, x), geo.size.width - 1), y: geo.size.height / 2)
                    }

                    if let date = hoverDate {
                        let g = nearestGlucose(at: date)
                        let i = nearestIOB(at: date)
                        let c = nearestCOB(at: date)
                        let b = nearestBolus(at: date)
                        Text(
                            "\(date, formatter: hoverTimeFormatter)  BG: \(formatNumber(g, units: viewModel.units))  IOB: \(formatNumber(i))U  COB: \(formatNumber(c))g  Bolus: \(formatNumber(b))U"
                        )
                        .font(.caption2)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(6)
                        .foregroundColor(.white)
                        .padding(.top, 4)
                        .padding(.leading, 6)
                    }
                }
                .allowsHitTesting(false)
            }
            .padding(.horizontal, 8)

            // Вторичные графики + общая линия наведения
            ZStack {
                VStack(spacing: 8) {
                    LoopUIKitIOBChartView(
                        iob: viewModel.iobData,
                        iobForecast: viewModel.iobForecastData,
                        timeRangeHours: selectedTimeRange.hours
                    )
                    .frame(height: 110)
                    LoopUIKitDoseChartView(delivery: viewModel.delivery, timeRangeHours: selectedTimeRange.hours)
                        .frame(height: 130)
                    LoopUIKitCOBChartView(
                        cob: viewModel.cobData,
                        timeRangeHours: selectedTimeRange.hours,
                        onTap: { showingCarbEntry = true }
                    )
                    .frame(height: 110)
                }
                GeometryReader { geo in
                    if let x = hoverX {
                        Rectangle()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: 1)
                            .position(x: min(max(1, x), geo.size.width - 1), y: geo.size.height / 2)
                    }
                }
                .allowsHitTesting(false)
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 8)

            // Нижняя панель с кнопками в стиле Loop
            LoopActionButtonsView(
                onCarbsAction: { showingAddCarbs = true },
                onPreBolusAction: { handlePreBolus() },
                onBolusAction: { showingAddBolus = true },
                onTempTargetAction: { showingTempTarget = true },
                onSettingsAction: { showingSettings = true }
            )
        }
        .background(Color(.systemGray6))
        .sheet(isPresented: $showingAddCarbs) {
            AddCarbsLoopView(resolver: resolver)
        }
        .sheet(isPresented: $showingAddBolus) {
            Bolus.RootView(resolver: resolver, waitForSuggestion: false)
        }
        .sheet(isPresented: $showingTempTarget) {
            // TODO: Создать TempTargetView или использовать существующий
            Text("Временные цели - в разработке")
        }
        .sheet(isPresented: $showingSettings) {
            NavigationView {
                Settings.RootView(resolver: resolver)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
        .fullScreenCover(isPresented: $showingPumpSettings, onDismiss: { viewModel.refreshData() }) {
            if let aps = resolver.resolve(APSManager.self), let pumpManager = aps.pumpManager {
                // Открываем сразу нативные настройки помпы
                PumpConfig.PumpSettingsView(
                    pumpManager: pumpManager,
                    completionDelegate: PumpConfig.PumpSettingsCompletion { showingPumpSettings = false }
                )
            } else {
                // Нет настроенной помпы – показать мастер настройки
                NavigationView {
                    PumpConfig.RootView(resolver: resolver)
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
        .sheet(isPresented: $showingLoopStatus) {
            LoopStatus.RootView(resolver: resolver)
        }
        .sheet(isPresented: $showingGlucoseHistory) {
            NavigationView {
                DataTable.RootView(resolver: resolver)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
        .sheet(isPresented: $showingCarbEntry) {
            AddCarbsLoopView(resolver: resolver)
        }
        .onAppear { viewModel.loadData() }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    hoverX = value.location.x
                    let now = Date()
                    let startDate = now.addingTimeInterval(-6 * 3600) // 6 часов назад
                    let endDate = now.addingTimeInterval(6 * 3600) // 6 часов вперед
                    // Приблизительная ширина области графиков с учётом паддингов
                    let width = UIScreen.main.bounds.width - 16
                    let ratio = max(0, min(1, (hoverX ?? 0) / max(1, width)))
                    hoverDate = Date(timeInterval: TimeInterval(ratio) * endDate.timeIntervalSince(startDate), since: startDate)
                }
                .onEnded { _ in
                    hoverX = nil
                    hoverDate = nil
                }
        )
    }

    // MARK: - Helper Methods

    private func getLoopStatus() -> LoopHUDStatus {
        // Если включён закрытый цикл – показываем "Closed loop" даже когда цикл не в процессе
        if viewModel.closedLoop {
            return viewModel.isLooping ? .running : .closed
        } else {
            return .openLoop
        }
    }

    private func getPumpStatus() -> PumpHUDStatus {
        // Получить реальный статус помпы из viewModel
        PumpHUDStatus(
            name: viewModel.pumpName ?? "Помпа",
            batteryLevel: viewModel.pumpBattery ?? 0,
            reservoirLevel: viewModel.pumpReservoir,
            systemImage: viewModel
                .pumpConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
            color: viewModel.pumpConnected ? .green : .red
        )
    }

    private func handlePreBolus() {
        // Логика пре-болюса - открыть болюс с предустановленным временем
        showingAddBolus = true
        // TODO: Реализовать логику пре-болюса с задержкой
    }

    private func cancelBolus() {
        if let aps = resolver.resolve(APSManager.self) {
            aps.cancelBolus()
        }
    }
}

// MARK: - Hover helpers

private let hoverTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    return f
}()

private func formatNumber(_ value: Decimal?, units: GlucoseUnits? = nil) -> String {
    guard let v = value else { return "—" }
    if let units = units, units == .mmolL {
        return String(format: "%.1f", NSDecimalNumber(decimal: v).doubleValue)
    }
    return String(format: "%.0f", NSDecimalNumber(decimal: v).doubleValue)
}

private extension DashboardRootView {
    func nearestGlucose(at date: Date) -> Decimal? {
        viewModel.glucose.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })?.value
    }

    func nearestIOB(at date: Date) -> Decimal? {
        viewModel.iobData.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })?.value
    }

    func nearestCOB(at date: Date) -> Decimal? {
        viewModel.cobData.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })?.value
    }

    func nearestBolus(at date: Date) -> Decimal? {
        let window: TimeInterval = 5 * 60
        return viewModel.delivery
            .filter { $0.type == .bolus && abs($0.date.timeIntervalSince(date)) <= window }
            .sorted(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
            .first?.amount
    }
}

// MARK: - Time Range Picker

enum TimeRange: CaseIterable {
    case threeHours
    case sixHours
    case twelveHours
    case twentyFourHours

    var title: String {
        switch self {
        case .threeHours: return "3ч"
        case .sixHours: return "6ч"
        case .twelveHours: return "12ч"
        case .twentyFourHours: return "24ч"
        }
    }

    var hours: Int {
        switch self {
        case .threeHours: return 3
        case .sixHours: return 6
        case .twelveHours: return 12
        case .twentyFourHours: return 24
        }
    }
}

// MARK: - Preview

#Preview {
    let container = Container()
    DashboardRootView(resolver: container.synchronize())
}
