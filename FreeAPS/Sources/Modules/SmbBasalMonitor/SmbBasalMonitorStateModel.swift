import Foundation
import SwiftUI

extension SmbBasalMonitor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var smbBasalManager: SmbBasalManager!
        @Injected() var storage: FileStorage!

        @Published var isEnabled = false
        @Published var currentBasalIob: Decimal = 0
        @Published var activePulses: Int = 0
        @Published var oldestPulseAge: TimeInterval = 0
        @Published var recentPulses: [SmbBasalPulse] = []
        @Published var pumpStep: Decimal = 0.05
        @Published var smbInterval: Decimal = 3
        @Published var currentBasalRate: Decimal = 0
        @Published var applyOpenAPSTempBasal: Bool = true

        private var timer: Timer?

        override func subscribe() {
            updateStatus()
            startTimer()
        }

        deinit {
            timer?.invalidate()
        }

        private func startTimer() {
            timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatus()
                }
            }
        }

        private func updateStatus() {
            isEnabled = smbBasalManager.isEnabled

            guard isEnabled else {
                currentBasalIob = 0
                activePulses = 0
                oldestPulseAge = 0
                recentPulses = []
                return
            }

            let basalIob = smbBasalManager.currentBasalIob()
            currentBasalIob = basalIob.iob
            activePulses = basalIob.activePulses
            oldestPulseAge = basalIob.oldestPulseAge

            // Получаем последние пульсы
            let allPulses = storage.retrieve(OpenAPS.Monitor.smbBasalPulses, as: [SmbBasalPulse].self) ?? []
            recentPulses = Array(allPulses.suffix(10)) // Последние 10 пульсов

            // Получаем текущие настройки
            let preferences = settingsManager.preferences
            smbInterval = preferences.smbInterval
            applyOpenAPSTempBasal = settingsManager.settings.useOpenAPSForTempBasalWhenSmbBasal

            // Получаем текущую базальную скорость
            let currentProfile = provider.basalProfile
            let now = Date()
            let calendar = Calendar.current
            let minutesFromMidnight = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

            if let currentEntry = currentProfile.first(where: { entry in
                let startMinutes = entry.minutes
                let endMinutes = currentProfile.first(where: { $0.minutes > startMinutes })?.minutes ?? 1440
                return minutesFromMidnight >= startMinutes && minutesFromMidnight < endMinutes
            }) {
                currentBasalRate = currentEntry.rate
            }
        }

        func toggleApplyOpenAPSTempBasal(_ value: Bool) {
            settingsManager.updateSettings { s in
                s.useOpenAPSForTempBasalWhenSmbBasal = value
            }
            applyOpenAPSTempBasal = value
        }
    }
}
