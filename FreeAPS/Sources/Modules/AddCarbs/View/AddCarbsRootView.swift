import SwiftUI
import Swinject

extension AddCarbs {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var formatter: NumberFormatter {
            FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 0) }

        var body: some View {
            Form {
                if let carbsReq = state.carbsRequired {
                    Section {
                        HStack {
                            Text("Carbs required")
                            Spacer()
                            Text(formatter.string(from: carbsReq as NSNumber)! + " g")
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        DecimalTextField("0", value: $state.carbs, formatter: formatter, autofocus: true, cleanInput: true)
                        Text("grams").foregroundColor(.secondary)
                    }
                    DatePicker("Date", selection: $state.date)
                }

                Section {
                    Button { state.add() }
                    label: { Text("Add") }
                        .disabled(state.carbs <= 0)
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Add Carbs")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))
        }
    }
}
