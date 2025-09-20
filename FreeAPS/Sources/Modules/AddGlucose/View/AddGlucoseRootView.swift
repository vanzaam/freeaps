import SwiftUI
import Swinject

extension AddGlucose {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var valueFormatter: NumberFormatter {
            state.units == .mmolL
                ? FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 1, maxFractionDigits: 1)
                : FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 0)
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
