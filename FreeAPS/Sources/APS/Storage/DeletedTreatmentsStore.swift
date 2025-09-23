import Foundation

// Lightweight local blacklist for deleted treatments (boluses) to avoid
// showing them in UI and feeding them into IOB. Retains only last 24 hours.
final class DeletedTreatmentsStore {
    static let shared = DeletedTreatmentsStore()

    private struct Entry: Codable, Hashable {
        let key: String
        let timestamp: Date
    }

    private let userDefaultsKey = "DeletedTreatmentsEntries"
    private let queue = DispatchQueue(label: "DeletedTreatmentsStore.queue")
    private let retention: TimeInterval = 24 * 60 * 60

    private init() {}

    // Key is coarse to minute + amount to be robust against seconds rounding
    private func makeKey(date: Date, amount: Decimal?) -> String {
        let minuteBucket = Int(date.timeIntervalSince1970 / 60)
        let amountStr = amount?.description ?? "0"
        return "bolus_\(minuteBucket)_\(amountStr)"
    }

    func addBolus(date: Date, amount: Decimal?) {
        let entry = Entry(key: makeKey(date: date, amount: amount), timestamp: Date())
        queue.async {
            var set = self.load()
            set.insert(entry)
            self.save(set)
            self.pruneLocked()
        }
    }

    func containsBolus(date: Date, amount: Decimal?) -> Bool {
        let key = makeKey(date: date, amount: amount)
        return queue.sync { load().contains { $0.key == key } }
    }

    func prune() {
        queue.async { self.pruneLocked() }
    }

    // MARK: - Private

    private func pruneLocked() {
        let cutoff = Date().addingTimeInterval(-retention)
        var set = load()
        set = Set(set.filter { $0.timestamp > cutoff })
        save(set)
    }

    private func load() -> Set<Entry> {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(Set<Entry>.self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func save(_ set: Set<Entry>) {
        if let data = try? JSONEncoder().encode(set) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
