import Foundation
import SwiftUI
import Swinject

extension SmbBasalMonitor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        private var glucoseFormatter: NumberFormatter {
            FormatterCache.numberFormatter(
                style: .decimal,
                minFractionDigits: 1,
                maxFractionDigits: 1
            )
        }

        var body: some View {
            Form {
                statusSection
                recentPulsesSection
                configurationSection
                basalChartSection
                errorCompensationSection
            }
            .navigationTitle("SMB-Basal Monitor")
            .onAppear(perform: configureView)
        }

        private var statusSection: some View {
            Section(header: Text("SMB-Basal Status")) {
                statusRow
                if state.isEnabled {
                    basalIOBRow
                    activePulsesRow
                    oldestPulseRow
                }
            }
        }

        private var statusRow: some View {
            HStack {
                Text("Status")
                Spacer()
                Text(state.isEnabled ? "Enabled" : "Disabled")
                    .foregroundColor(state.isEnabled ? .green : .secondary)
            }
        }

        private var basalIOBRow: some View {
            HStack {
                Text("Current Basal IOB")
                Spacer()
                Text("\(Double(truncating: state.currentBasalIob as NSDecimalNumber), specifier: "%.3f") U")
                    .foregroundColor(.green)
            }
        }

        private var activePulsesRow: some View {
            HStack {
                Text("Active Pulses")
                Spacer()
                Text("\(state.activePulses)")
            }
        }

        @ViewBuilder private var oldestPulseRow: some View {
            if state.oldestPulseAge > 0 {
                HStack {
                    Text("Oldest Pulse")
                    Spacer()
                    Text("\(Int(state.oldestPulseAge)) min ago")
                }
            }
        }

        @ViewBuilder private var recentPulsesSection: some View {
            if state.isEnabled && !state.recentPulses.isEmpty {
                Section(header: Text("Recent Pulses")) {
                    ForEach(state.recentPulses, id: \.id) { pulse in
                        recentPulseRow(pulse: pulse)
                    }
                }
            }
        }

        private func recentPulseRow(pulse: SmbBasalPulse) -> some View {
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

        @ViewBuilder private var configurationSection: some View {
            if state.isEnabled {
                Section(header: Text("Configuration")) {
                    pumpStepRow
                    smbIntervalRow
                    currentBasalRateRow
                    openAPSToggle
                    glucoseThresholdRow
                    glucoseThresholdDescription
                    compensationWindowRow
                    compensationWindowDescription
                }
            }
        }

        private var pumpStepRow: some View {
            HStack {
                Text("Pump Step")
                Spacer()
                Text("\(Double(truncating: state.pumpStep as NSDecimalNumber), specifier: "%.3f") U")
            }
        }

        private var smbIntervalRow: some View {
            HStack {
                Text("SMB Interval")
                Spacer()
                Text("\(Double(truncating: state.smbInterval as NSDecimalNumber), specifier: "%.0f") min")
            }
        }

        private var currentBasalRateRow: some View {
            HStack {
                Text("Current Basal Rate")
                Spacer()
                Text("\(Double(truncating: state.currentBasalRate as NSDecimalNumber), specifier: "%.3f") U/h")
            }
        }

        private var openAPSToggle: some View {
            Toggle(isOn: Binding(
                get: { state.applyOpenAPSTempBasal },
                set: { state.toggleApplyOpenAPSTempBasal($0) }
            )) {
                Text("Apply OpenAPS temp basal suggestions")
            }
        }

        private var glucoseThresholdRow: some View {
            HStack {
                Text("Glucose threshold")
                Spacer()
                DecimalTextField(
                    "4.5",
                    value: Binding(
                        get: { state.glucoseThreshold },
                        set: { state.setGlucoseThreshold($0) }
                    ),
                    formatter: glucoseFormatter,
                    cleanInput: true
                )
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                Text("mmol/L")
            }
        }

        private var glucoseThresholdDescription: some View {
            Text("Suspend basal delivery below this glucose level")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        private var compensationWindowRow: some View {
            HStack {
                Text("Error compensation window")
                Spacer()
                Picker("Minutes", selection: Binding(
                    get: { state.maxCompensationMinutes },
                    set: { state.setMaxCompensationMinutes($0) }
                )) {
                    ForEach([5, 10, 15, 20, 30, 60], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }
        }

        private var compensationWindowDescription: some View {
            Text("Maximum time to accumulate failed pulses for compensation")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        @ViewBuilder private var basalChartSection: some View {
            if state.isEnabled {
                Section(header: Text("Basal over last 24h (hourly)")) {
                    basalChart
                    totalSMBRow
                    totalByChartRow
                }
            }
        }

        private var basalChart: some View {
            HourlyBasalChart(rates: state.hourlyRates.map { Double(truncating: $0 as NSDecimalNumber) })
                .frame(height: 160)
        }

        private var totalSMBRow: some View {
            HStack {
                Text("Total SMB (24h)")
                Spacer()
                Text("\(Double(truncating: state.totalUnits24h as NSDecimalNumber), specifier: "%.2f") U")
            }
        }

        private var totalByChartRow: some View {
            HStack {
                Text("Total by chart")
                Spacer()
                let chartTotal = Double(truncating: state.totalFromRates24h as NSDecimalNumber)
                let smbTotal = Double(truncating: state.totalUnits24h as NSDecimalNumber)
                let ok = abs(chartTotal - smbTotal) < 0.01
                Text(String(format: "%.2f U (%@)", chartTotal, ok ? "OK" : "mismatch"))
                    .foregroundColor(ok ? .green : .red)
            }
        }

        @ViewBuilder private var errorCompensationSection: some View {
            if state.isEnabled && (state.failedPulsesCount > 0 || state.compensationUnits > 0) {
                Section(header: Text("Error Compensation")) {
                    failedPulsesRow
                    compensationUnitsRow
                }
            }
        }

        private var failedPulsesRow: some View {
            HStack {
                Text("Failed pulses")
                Spacer()
                Text("\(state.failedPulsesCount)")
                    .foregroundColor(state.failedPulsesCount > 0 ? .orange : .secondary)
            }
        }

        @ViewBuilder private var compensationUnitsRow: some View {
            if state.compensationUnits > 0 {
                HStack {
                    Text("Compensation units")
                    Spacer()
                    Text("\(Double(truncating: state.compensationUnits as NSDecimalNumber), specifier: "%.3f") U")
                        .foregroundColor(.orange)
                }
                Text("These units will be delivered when conditions improve")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct HourlyBasalChart: View {
    let rates: [Double] // 24 values, oldest -> newest
    @State private var hoverIndex: Int? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = max(rates.count, 1)
            let stepX = w / CGFloat(count)
            let maxRate = max(rates.max() ?? 0.0, 0.01)

            ZStack {
                // Grid
                Path { p in
                    for i in 0 ... 6 {
                        let y = h - CGFloat(Double(i) / 6.0 * maxRate) * (h - 2) / CGFloat(maxRate)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)

                // Bars
                ForEach(0 ..< count, id: \.self) { i in
                    let x = CGFloat(i) * stepX
                    let value = rates[i]
                    let barH = CGFloat(value / maxRate) * (h - 2)
                    Path { p in
                        p.addRoundedRect(
                            in: CGRect(x: x + 2, y: h - barH, width: stepX - 4, height: barH),
                            cornerSize: CGSize(width: 3, height: 3)
                        )
                    }
                    .fill(Color.accentColor.opacity(0.7))
                }

                // Hover overlay
                Rectangle().fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        let idx = min(count - 1, max(0, Int(g.location.x / stepX)))
                        hoverIndex = idx
                    }.onEnded { _ in hoverIndex = nil })

                if let idx = hoverIndex {
                    let value = rates[idx]
                    let x = CGFloat(idx) * stepX + stepX / 2
                    VStack(spacing: 4) {
                        Text("\(Int(24 - Double(count - 1 - idx)))h ago")
                        Text(String(format: "%.3f U/h", value))
                    }
                    .font(.caption2)
                    .padding(6)
                    .background(Color.black.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .position(x: min(max(60, x), w - 60), y: 16)
                }
            }
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
