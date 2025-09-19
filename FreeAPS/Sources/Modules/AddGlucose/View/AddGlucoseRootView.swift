import SwiftUI
import Swinject

extension AddGlucose {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var valueFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = state.units == .mmolL ? 1 : 0
            return formatter
        }

        var body: some View {
            Form {
                Section {
                    HStack {
                        Text("Value")
                        Spacer()
                        DecimalTextField("0", value: $state.glucose, formatter: valueFormatter, autofocus: true, cleanInput: true)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                    DatePicker("Date", selection: $state.date)
                }

                Section {
                    Button { state.add() }
                    label: { Text("Add") }
                        .disabled(state.glucose <= 0)
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Add Glucose")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
        }
    }
}
