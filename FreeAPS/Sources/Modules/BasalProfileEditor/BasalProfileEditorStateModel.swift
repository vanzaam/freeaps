import SwiftUI

extension BasalProfileEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Published var syncInProgress = false
        @Published var items: [Item] = []

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        private(set) var rateValues: [Decimal] = []

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        override func subscribe() {
            // Build selectable rates, clamped to app's maxBasal and device-supported steps if available
            let appMaxBasal = provider.pumpSettings().maxBasal
            let maxDouble = Double(truncating: appMaxBasal as NSNumber)
            if let supported = provider.supportedBasalRates {
                rateValues = supported.filter { $0 <= appMaxBasal }
            } else {
                // 0.00 ... up to appMaxBasal with 0.01 steps (rounded from 5/100)
                let upper = max(0.0, maxDouble)
                rateValues = stride(from: 0.0, through: upper * 100.0, by: 5.0)
                    .map { ($0.decimal ?? .zero) / 100 }
            }
            items = provider.profile.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.minutes * 60)) ?? 0
                // Clamp each profile entry to allowed rates list
                let rateClamped = rateValues.last(where: { $0 <= value.rate }) ?? (rateValues.first ?? 0)
                let rateIndex = rateValues.firstIndex(of: rateClamped) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }
        }

        func add() {
            var time = 0
            var rate = 0
            if let last = items.last {
                time = last.timeIndex + 1
                rate = last.rateIndex
            }

            let newItem = Item(rateIndex: rate, timeIndex: time)

            items.append(newItem)
        }

        func save() {
            syncInProgress = true
            let profile = items.map { item -> BasalProfileEntry in
                let fotmatter = DateFormatter()
                fotmatter.timeZone = TimeZone(secondsFromGMT: 0)
                fotmatter.dateFormat = "HH:mm:ss"
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return BasalProfileEntry(start: fotmatter.string(from: date), minutes: minutes, rate: rate)
            }
            provider.saveProfile(profile)
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    self.syncInProgress = false
                } receiveValue: {}
                .store(in: &lifetime)
        }

        func validate() {
            DispatchQueue.main.async {
                let uniq = Array(Set(self.items))
                let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
                sorted.first?.timeIndex = 0
                self.items = sorted
            }
        }
    }
}
