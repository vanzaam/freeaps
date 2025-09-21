import SwiftUI

/// HUD компонент для отображения статуса Loop в стиле оригинального Loop
struct LoopStatusHUDView: View {
    let currentGlucose: Decimal?
    let trend: String?
    let loopStatus: LoopHUDStatus
    let pumpStatus: PumpHUDStatus
    let lastUpdate: Date?

    // Callbacks для действий
    var onGlucoseTapped: (() -> Void)?
    var onLoopTapped: (() -> Void)?
    var onPumpTapped: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // Левая секция: Глюкоза и тренд
            glucoseSection
                .frame(maxWidth: .infinity, alignment: .leading)

            // Центральная секция: Статус Loop
            loopStatusSection
                .frame(maxWidth: .infinity, alignment: .center)

            // Правая секция: Статус помпы
            pumpStatusSection
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }

    // MARK: - Glucose Section

    private var glucoseSection: some View {
        Button(action: { onGlucoseTapped?() }) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatGlucose(currentGlucose))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundColor(glucoseColor)

                    if let trend = trend {
                        Text(trend)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                if let lastUpdate = lastUpdate {
                    Text(timeAgoString(from: lastUpdate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Loop Status Section

    private var loopStatusSection: some View {
        Button(action: {
            onLoopTapped?()
        }) {
            VStack(spacing: 4) {
                // Loop символ с анимацией
                Image(systemName: loopStatus.systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(loopStatus.color)
                    .rotationEffect(.degrees(loopStatus.isRunning ? 360 : 0))
                    .animation(
                        loopStatus.isRunning ?
                            Animation.linear(duration: 2).repeatForever(autoreverses: false) :
                            .default,
                        value: loopStatus.isRunning
                    )

                Text(loopStatus.title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Pump Status Section

    private var pumpStatusSection: some View {
        Button(action: {
            onPumpTapped?()
        }) {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: pumpStatus.systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(pumpStatus.color)

                    Text("\(pumpStatus.batteryLevel)%")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }

                if let reservoir = pumpStatus.reservoirLevel {
                    Text("\(Int(reservoir))U")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(pumpStatus.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Computed Properties

    private var glucoseColor: Color {
        guard let glucose = currentGlucose else { return .secondary }
        let value = glucose.doubleValue

        if value < 70 { return .red }
        if value > 180 { return .red }
        if value < 80 || value > 160 { return .orange }
        return .green
    }

    // MARK: - Helper Methods

    private func formatGlucose(_ glucose: Decimal?) -> String {
        guard let glucose = glucose else { return "---" }
        // Если значение выглядит как mmol/L, показываем с одной цифрой после запятой
        if glucose.doubleValue < 40 { // 40 mmol/L заведомо выше любых реальных значений
            return String(format: "%.1f", glucose.doubleValue)
        }
        return String(format: "%.0f", glucose.doubleValue)
    }

    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "сейчас"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)м назад"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours)ч назад"
        }
    }
}

// MARK: - Supporting Types

struct LoopHUDStatus {
    let title: String
    let systemImage: String
    let color: Color
    let isRunning: Bool

    static let running = LoopHUDStatus(
        title: "Закрытый цикл",
        systemImage: "arrow.triangle.2.circlepath",
        color: .green,
        isRunning: true
    )

    static let openLoop = LoopHUDStatus(
        title: "Открытый цикл",
        systemImage: "arrow.triangle.2.circlepath",
        color: .orange,
        isRunning: false
    )

    // Закрытый цикл включён, но цикл сейчас не выполняется
    static let closed = LoopHUDStatus(
        title: "Закрытый цикл",
        systemImage: "arrow.triangle.2.circlepath",
        color: .green,
        isRunning: false
    )

    static let error = LoopHUDStatus(
        title: "Ошибка цикла",
        systemImage: "exclamationmark.triangle",
        color: .red,
        isRunning: false
    )

    static let disabled = LoopHUDStatus(
        title: "Цикл отключен",
        systemImage: "pause.circle",
        color: .gray,
        isRunning: false
    )
}

struct PumpHUDStatus {
    let name: String
    let batteryLevel: Int
    let reservoirLevel: Double?
    let systemImage: String
    let color: Color

    var isConnected: Bool {
        color != .red
    }

    static let connected = PumpHUDStatus(
        name: "Omnipod",
        batteryLevel: 85,
        reservoirLevel: 156.5,
        systemImage: "antenna.radiowaves.left.and.right",
        color: .green
    )

    static let disconnected = PumpHUDStatus(
        name: "Omnipod",
        batteryLevel: 0,
        reservoirLevel: nil,
        systemImage: "antenna.radiowaves.left.and.right.slash",
        color: .red
    )
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        LoopStatusHUDView(
            currentGlucose: 142,
            trend: "→",
            loopStatus: .running,
            pumpStatus: .connected,
            lastUpdate: Date().addingTimeInterval(-120)
        )

        Rectangle()
            .fill(Color(.systemGray6))
            .frame(height: 200)
    }
    .background(Color(.systemBackground))
}
