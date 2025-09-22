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

                    Section(header: Text("Basal over last 24h (hourly)")) {
                        HourlyBasalChart(rates: state.hourlyRates.map { Double(truncating: $0 as NSDecimalNumber) })
                            .frame(height: 160)
                        HStack {
                            Text("Total SMB (24h)")
                            Spacer()
                            Text("\(Double(truncating: state.totalUnits24h as NSDecimalNumber), specifier: "%.2f") U")
                        }
                    }
                }
            }
            .navigationTitle("SMB-Basal Monitor")
            .onAppear(perform: configureView)
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
                    for i in 0...6 {
                        let y = h - CGFloat(Double(i) / 6.0 * maxRate) * (h - 2) / CGFloat(maxRate)
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)

                // Bars
                ForEach(0..<count, id: \.self) { i in
                    let x = CGFloat(i) * stepX
                    let value = rates[i]
                    let barH = CGFloat(value / maxRate) * (h - 2)
                    Path { p in
                        p.addRoundedRect(in: CGRect(x: x + 2, y: h - barH, width: stepX - 4, height: barH), cornerSize: CGSize(width: 3, height: 3))
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
                        Text("\(Int(24 - (Double(count - 1 - idx))))h ago")
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
