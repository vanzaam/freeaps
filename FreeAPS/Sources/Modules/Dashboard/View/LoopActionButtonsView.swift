import SwiftUI

/// Нижняя панель с кнопками действий в стиле Loop
struct LoopActionButtonsView: View {
    let onCarbsAction: () -> Void
    let onPreBolusAction: () -> Void
    let onBolusAction: () -> Void
    let onTempTargetAction: () -> Void
    let onSettingsAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Основные кнопки действий
            HStack(spacing: 12) {
                // Углеводы
                ActionButton(
                    title: "Углеводы",
                    systemImage: "fork.knife",
                    color: .green,
                    action: onCarbsAction
                )

                // Пре-болюс
                ActionButton(
                    title: "До еды",
                    systemImage: "clock.arrow.circlepath",
                    color: .orange,
                    action: onPreBolusAction
                )

                // Болюс (центральная кнопка, больше размер)
                BolusButton(action: onBolusAction)

                // Временный профиль
                ActionButton(
                    title: "Профиль",
                    systemImage: "target",
                    color: .purple,
                    action: onTempTargetAction
                )

                // Настройки
                ActionButton(
                    title: "Настройки",
                    systemImage: "gearshape",
                    color: .gray,
                    action: onSettingsAction
                )
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 16)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: -1)
        )
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Иконка в круглом фоне как в Loop
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(color)
                }

                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Bolus Button (центральная)

private struct BolusButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Большая центральная кнопка как в Loop
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 54, height: 54)

                    Circle()
                        .stroke(Color.blue, lineWidth: 2)
                        .frame(width: 54, height: 54)

                    Image(systemName: "drop.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.blue)
                }

                Text("Болюс")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        LoopActionButtonsView(
            onCarbsAction: { print("Углеводы") },
            onPreBolusAction: { print("До еды") },
            onBolusAction: { print("Болюс") },
            onTempTargetAction: { print("Профиль") },
            onSettingsAction: { print("Настройки") }
        )
    }
    .background(Color(.systemGray6))
}
