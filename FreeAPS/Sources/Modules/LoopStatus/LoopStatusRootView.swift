import LoopKit
import SwiftUI
import Swinject

enum LoopStatus {}

extension LoopStatus {
    struct RootView: View {
        let resolver: Resolver
        @StateObject private var state: StateModel

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("Loop")) {
                        HStack {
                            Text("Status").foregroundColor(.secondary)
                            Spacer()
                            Text(state.closedLoop ? (state.isLooping ? "Running" : "Closed loop") : "Open loop")
                                .foregroundColor(state.closedLoop ? .green : (state.isLooping ? .green : .orange))
                        }
                        HStack {
                            Text("Last run").foregroundColor(.secondary)
                            Spacer()
                            Text(state.lastLoopString)
                        }
                        if let err = state.lastErrorString {
                            HStack(alignment: .top) {
                                Text("Error").foregroundColor(.secondary)
                                Spacer()
                                Text(err).foregroundColor(.red)
                            }
                        }
                        Button("Run loop now") { state.runLoop() }
                    }

                    Section(header: Text("Suggested")) {
                        if let s = state.suggested {
                            KeyValueRow(key: "Reason", value: s.reason)
                            KeyValueRow(key: "Bolus", value: s.units.map { "\($0) U" } ?? "—")
                            KeyValueRow(key: "Rate", value: s.rate.map { "\($0) U/h" } ?? "—")
                            KeyValueRow(key: "Duration", value: s.duration.map { "\($0) min" } ?? "—")
                        } else {
                            Text("No data").foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text("Enacted")) {
                        if let e = state.enacted {
                            KeyValueRow(key: "Reason", value: e.reason)
                            KeyValueRow(key: "Bolus", value: e.units.map { "\($0) U" } ?? "—")
                            KeyValueRow(key: "Rate", value: e.rate.map { "\($0) U/h" } ?? "—")
                            KeyValueRow(key: "Duration", value: e.duration.map { "\($0) min" } ?? "—")
                            KeyValueRow(key: "Received", value: (e.recieved ?? false) ? "Yes" : "No")
                        } else {
                            Text("No data").foregroundColor(.secondary)
                        }
                    }

                    Section(header: Text("IOB/COB")) {
                        KeyValueRow(key: "IOB", value: "\(state.iob) U")
                        KeyValueRow(key: "COB", value: "\(state.cob) g")
                    }
                }
                .navigationTitle("Loop Status")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Refresh") { state.load() } } }
                .onAppear { state.load() }
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }
}

private struct KeyValueRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack {
            Text(key).foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - StateModel

extension LoopStatus {
    @MainActor final class StateModel: ObservableObject {
        @Published var isLooping: Bool = false
        @Published var lastLoop: Date = .distantPast
        @Published var suggested: Suggestion?
        @Published var enacted: Suggestion?
        @Published var iob: Decimal = 0
        @Published var cob: Decimal = 0
        @Published var lastErrorString: String?
        @Published var closedLoop: Bool = false

        private let aps: APSManager?
        private let storage: FileStorage?
        private let carbService: CarbAccountingService?
        private let settingsManager: SettingsManager?
        private let pumpHistoryStorage: PumpHistoryStorage?

        init(resolver: Resolver) {
            aps = resolver.resolve(APSManager.self)
            storage = resolver.resolve(FileStorage.self)
            carbService = resolver.resolve(CarbAccountingService.self)
            settingsManager = resolver.resolve(SettingsManager.self)
            pumpHistoryStorage = resolver.resolve(PumpHistoryStorage.self)
        }

        var lastLoopString: String {
            if lastLoop == .distantPast { return "—" }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"
            return df.string(from: lastLoop)
        }

        func load() {
            if let aps = aps {
                isLooping = aps.isLooping.value
                lastLoop = aps.lastLoopDate
                lastErrorString = aps.lastError.value?.localizedDescription
            }

            if let storage = storage {
                // Рассчитываем свежий IOB (как в Dashboard)
                iob = calculateFreshIOB()

                suggested = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
                enacted = storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)
            }

            if let carbService = carbService {
                cob = carbService.cob
            }

            closedLoop = settingsManager?.settings.closedLoop ?? false
        }

        func runLoop() {
            guard let aps = aps else { return }
            _ = aps.determineBasal().sink { _ in } receiveValue: { _ in }
        }

        /// Рассчитать свежий IOB из pump history (как в Dashboard)
        private func calculateFreshIOB() -> Decimal {
            guard let pumpHistoryStorage = pumpHistoryStorage,
                  let storage = storage
            else {
                debug(.service, "LoopStatus: pumpHistoryStorage or storage not available")
                return 0
            }

            let pumpHistory = pumpHistoryStorage.recent()
            debug(.service, "LoopStatus: Loaded \(pumpHistory.count) pump events for IOB calculation")

            // Используем ту же логику конвертации что и в Dashboard
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
            debug(.service, "LoopStatus: Converted \(doseEntries.count) pump events to DoseEntry")

            // IOB временной ряд с шагом 5 минут (как в Dashboard)
            let insulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: nil)
            let now = Date()
            let iobSeries = doseEntries.insulinOnBoard(
                insulinModelProvider: insulinModelProvider,
                longestEffectDuration: InsulinMath.defaultInsulinActivityDuration,
                from: now.addingTimeInterval(-6 * 3600),
                to: now,
                delta: 5 * 60
            )

            let lastIOBValue = iobSeries.last?.value ?? 0
            debug(.service, "LoopStatus: Calculated fresh IOB=\(lastIOBValue), from \(doseEntries.count) doses")

            if lastIOBValue.isNaN || lastIOBValue.isInfinite {
                debug(.service, "LoopStatus: Invalid IOB value: \(lastIOBValue), using 0")
                return 0
            }

            let freshIOB = Decimal(lastIOBValue)
            debug(.service, "LoopStatus: Fresh IOB calculated successfully: \(freshIOB)")
            return freshIOB
        }
    }
}
