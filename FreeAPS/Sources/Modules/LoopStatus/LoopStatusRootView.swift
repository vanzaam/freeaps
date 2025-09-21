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

        init(resolver: Resolver) {
            aps = resolver.resolve(APSManager.self)
            storage = resolver.resolve(FileStorage.self)
            carbService = resolver.resolve(CarbAccountingService.self)
            settingsManager = resolver.resolve(SettingsManager.self)
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
                if let iobEntry = storage.retrieve(OpenAPS.Monitor.iob, as: [IOBEntry].self)?.first {
                    iob = iobEntry.iob
                }
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
    }
}
