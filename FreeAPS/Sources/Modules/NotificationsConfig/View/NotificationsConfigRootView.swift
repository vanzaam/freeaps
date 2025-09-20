import SwiftUI
import Swinject

extension NotificationsConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var glucoseFormatter: NumberFormatter {
            state.units == .mmolL
                ? FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 1)
                : FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 0)
        }

        private var carbsFormatter: NumberFormatter {
            FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 0) }

        var body: some View {
            Form {
                Section(header: Text("Glucose")) {
                    Toggle("Show glucose on the app badge", isOn: $state.glucoseBadge)
                    Toggle("Always Notify Glucose", isOn: $state.glucoseNotificationsAlways)
                    Toggle("Also play alert sound", isOn: $state.useAlarmSound)
                    Toggle("Also add source info", isOn: $state.addSourceInfoToGlucoseNotifications)

                    HStack {
                        Text("Low")
                        Spacer()
                        DecimalTextField("0", value: $state.lowGlucose, formatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }

                    HStack {
                        Text("High")
                        Spacer()
                        DecimalTextField("0", value: $state.highGlucose, formatter: glucoseFormatter)
                        Text(state.units.rawValue).foregroundColor(.secondary)
                    }
                }

                Section(header: Text("Other")) {
                    HStack {
                        Text("Carbs Required Threshold")
                        Spacer()
                        DecimalTextField("0", value: $state.carbsRequiredThreshold, formatter: carbsFormatter)
                        Text("g").foregroundColor(.secondary)
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationBarTitle("Notifications")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
