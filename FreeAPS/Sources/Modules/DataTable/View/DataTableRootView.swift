import SwiftUI
import Swinject

extension DataTable {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var isRemoveCarbsAlertPresented = false
        @State private var removeCarbsAlert: Alert?
        @State private var selectedTreatmentId: UUID? = nil
        @State private var selectedGlucoseId: String? = nil

        private var glucoseFormatter: NumberFormatter {
            if state.units == .mmolL {
                return FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 1, maxFractionDigits: 1)
            } else {
                return FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 0)
            }
        }

        private var timeFormatterShort: DateFormatter { FormatterCache.dateFormatter(format: "HH:mm") }

        private var timeFormatterFull: DateFormatter { FormatterCache.dateFormatter(format: "HH:mm:ss") }

        var body: some View {
            Form {
                combinedHistoryList
            }
            .onAppear(perform: configureView)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(
                leading: Button("Close", action: state.hideModal),
                trailing: HStack {
                    Button(action: { state.showModal(for: .addGlucose) }) {
                        Image(systemName: "plus")
                    }
                    EditButton()
                }
            )
        }

        private var combinedHistoryList: some View {
            List {
                ForEach(state.history) { item in
                    if item.isGlucose, let glucose = item.glucose {
                        gluciseView(glucose)
                    } else if item.isTreatment, let treatment = item.treatment {
                        treatmentView(treatment)
                    }
                }
                .onDelete { offsets in
                    // Only delete if the item is glucose
                    let validGlucoseOffsets = offsets.filter { index in
                        guard index < state.history.count else { return false }
                        return state.history[index].isGlucose
                    }
                    
                    if !validGlucoseOffsets.isEmpty {
                        deleteHistoryItem(at: IndexSet(validGlucoseOffsets))
                    }
                }
            }
        }

        private var treatmentsList: some View {
            List {
                ForEach(state.treatments) { item in
                    treatmentView(item)
                }
            }
        }

        private var glucoseList: some View {
            List {
                ForEach(state.glucose) { item in
                    gluciseView(item)
                }.onDelete(perform: deleteGlucose)
            }
        }

        @ViewBuilder private func treatmentView(_ item: Treatment) -> some View {
            HStack {
                Image(systemName: "circle.fill").foregroundColor(item.color)
                Text(
                    (selectedTreatmentId == item.id ? timeFormatterFull : timeFormatterShort)
                        .string(from: item.date)
                )
                .moveDisabled(true)
                Text(item.displayTypeName)
                Text(item.amountText).foregroundColor(.secondary)
                if let duration = item.durationText {
                    Text(duration).foregroundColor(.secondary)
                }

                if item.type == .carbs {
                    Spacer()
                    Image(systemName: "xmark.circle").foregroundColor(.secondary)
                        .contentShape(Rectangle())
                        .padding(.vertical)
                        .onTapGesture {
                            removeCarbsAlert = Alert(
                                title: Text("Delete carbs?"),
                                message: Text(item.amountText),
                                primaryButton: .destructive(
                                    Text("Delete"),
                                    action: { state.deleteCarbs(at: item.date) }
                                ),
                                secondaryButton: .cancel()
                            )
                            isRemoveCarbsAlertPresented = true
                        }
                        .alert(isPresented: $isRemoveCarbsAlertPresented) {
                            removeCarbsAlert!
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedTreatmentId = (selectedTreatmentId == item.id) ? nil : item.id
            }
        }

        @ViewBuilder private func gluciseView(_ item: Glucose) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(
                        (selectedGlucoseId == item.glucose.id ? timeFormatterFull : timeFormatterShort)
                            .string(from: item.glucose.dateString)
                    )
                    Spacer()
                    Text(item.glucose.glucose.map {
                        glucoseFormatter.string(from: Double(
                            state.units == .mmolL ? $0.asMmolL : Decimal($0)
                        ) as NSNumber)!
                    } ?? "--")
                    Text(state.units.rawValue)
                    Text(item.glucose.direction?.symbol ?? "--")
                }
                if selectedGlucoseId == item.glucose.id {
                    Text("ID: " + item.glucose.id).font(.caption2).foregroundColor(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedGlucoseId = (selectedGlucoseId == item.glucose.id) ? nil : item.glucose.id
            }
        }

        private func deleteGlucoseFromHistory(at offsets: IndexSet) {
            // Map history indices to glucose array indices
            let glucoseIndicesToDelete = offsets.compactMap { historyIndex -> Int? in
                guard historyIndex < state.history.count else { return nil }
                let item = state.history[historyIndex]
                
                if item.isGlucose, let glucose = item.glucose {
                    return state.glucose.firstIndex(where: { $0.id == glucose.id })
                }
                return nil
            }
            
            // Delete from glucose array in reverse order to maintain indices
            for glucoseIndex in glucoseIndicesToDelete.sorted(by: >) {
                state.deleteGlucose(at: glucoseIndex)
            }
        }
        
        private func deleteHistoryItem(at offsets: IndexSet) {
            deleteGlucoseFromHistory(at: offsets)
        }

        private func deleteGlucose(at offsets: IndexSet) {
            state.deleteGlucose(at: offsets[offsets.startIndex])
        }
    }
}
