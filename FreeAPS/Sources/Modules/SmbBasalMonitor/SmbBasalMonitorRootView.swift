import Foundation
import SwiftUI
import Swinject

extension SmbBasalMonitor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        var body: some View {
            Form {
                Section(header: Text("SMB-Basal Status")) {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(state.isEnabled ? "Enabled" : "Disabled")
                            .foregroundColor(state.isEnabled ? .green : .secondary)
                    }

                    if state.isEnabled {
                        HStack {
                            Text("Current Basal IOB")
                            Spacer()
                            Text("\(Double(truncating: state.currentBasalIob as NSDecimalNumber), specifier: "%.3f") U")
                                .foregroundColor(.green)
                        }

                        HStack {
                            Text("Active Pulses")
                            Spacer()
                            Text("\(state.activePulses)")
                        }

                        if state.oldestPulseAge > 0 {
                            HStack {
                                Text("Oldest Pulse")
                                Spacer()
                                Text("\(Int(state.oldestPulseAge)) min ago")
                            }
                        }
                    }
                }

                if state.isEnabled && !state.recentPulses.isEmpty {
                    Section(header: Text("Recent Pulses")) {
                        ForEach(state.recentPulses, id: \.id) { pulse in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(Double(truncating: pulse.units as NSDecimalNumber), specifier: "%.3f") U")
                                        .font(.system(size: 14, weight: .medium))
                                    Text(DateFormatter.timeOnly.string(from: pulse.timestamp))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(Int(Date().timeIntervalSince(pulse.timestamp) / 60)) min ago")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if state.isEnabled {
                    Section(header: Text("Configuration")) {
                        HStack {
                            Text("Pump Step")
                            Spacer()
                            Text("\(Double(truncating: state.pumpStep as NSDecimalNumber), specifier: "%.3f") U")
                        }

                        HStack {
                            Text("SMB Interval")
                            Spacer()
                            Text("\(Double(truncating: state.smbInterval as NSDecimalNumber), specifier: "%.0f") min")
                        }

                        HStack {
                            Text("Current Basal Rate")
                            Spacer()
                            Text("\(Double(truncating: state.currentBasalRate as NSDecimalNumber), specifier: "%.3f") U/h")
                        }

                        Toggle(isOn: Binding(
                            get: { state.applyOpenAPSTempBasal },
                            set: { state.toggleApplyOpenAPSTempBasal($0) }
                        )) {
                            Text("Apply OpenAPS temp basal suggestions")
                        }
                    }
                }
            }
            .navigationTitle("SMB-Basal Monitor")
            .onAppear(perform: configureView)
        }
    }
}

extension DateFormatter {
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
}
