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
        @Published var hourlyRates: [Decimal] = Array(repeating: 0, count: 24)
        @Published var totalUnits24h: Decimal = 0
        @Published var totalFromRates24h: Decimal = 0

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
            computeHourly(from: allPulses)

            // Получаем текущие настройки
            let preferences = settingsManager.preferences
            smbInterval = preferences.smbInterval
            applyOpenAPSTempBasal = settingsManager.settings.useOpenAPSForTempBasalWhenSmbBasal

            // Получаем текущую базальную скорость
            let currentProfile = provider.basalProfile
            let now = Date()
            let calendar = Calendar.current
            let minutesFromMidnight = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

            if applyOpenAPSTempBasal,
               let enacted = storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self),
               let enactedRate = enacted.rate,
               let enactedTs = enacted.timestamp,
               now.timeIntervalSince(enactedTs) <= 20 * 60
            {
                // Показываем фактически применённый OpenAPS temp basal (свежий)
                currentBasalRate = enactedRate
            } else if applyOpenAPSTempBasal,
                      let suggested = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self),
                      let suggestedRate = suggested.rate,
                      let sugTs = suggested.timestamp,
                      now.timeIntervalSince(sugTs) <= 20 * 60
            {
                // Или свежее предложение
                currentBasalRate = suggestedRate
            } else if let currentEntry = currentProfile.first(where: { entry in
                let startMinutes = entry.minutes
                let endMinutes = currentProfile.first(where: { $0.minutes > startMinutes })?.minutes ?? 1440
                return minutesFromMidnight >= startMinutes && minutesFromMidnight < endMinutes
            }) {
                currentBasalRate = currentEntry.rate
            }
        }

        func toggleApplyOpenAPSTempBasal(_ value: Bool) {
            settingsManager.settings.useOpenAPSForTempBasalWhenSmbBasal = value
            applyOpenAPSTempBasal = value
        }

        private func computeHourly(from pulses: [SmbBasalPulse]) {
            let now = Date()
            let start = now.addingTimeInterval(-24 * 3600)
            var bins = Array(repeating: Decimal(0), count: 24)
            var total: Decimal = 0
            for p in pulses {
                guard p.timestamp >= start else { continue }
                let idx = min(23, max(0, Int(p.timestamp.timeIntervalSince(start) / 3600)))
                bins[idx] += p.units
                total += p.units
            }
            hourlyRates = bins
            totalUnits24h = total
            totalFromRates24h = bins.reduce(0, +)
        }
    }
}
