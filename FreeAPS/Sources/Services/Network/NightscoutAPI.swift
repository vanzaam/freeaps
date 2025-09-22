import Combine
import CommonCrypto
import Foundation

class NightscoutAPI {
    init(url: URL, secret: String? = nil) {
        self.url = url
        self.secret = secret?.nonEmpty
    }

    private enum Config {
        static let entriesPath = "/api/v1/entries/sgv.json"
        static let uploadEntriesPath = "/api/v1/entries.json"
        static let treatmentsPath = "/api/v1/treatments.json"
        static let statusPath = "/api/v1/devicestatus.json"
        static let profilePath = "/api/v1/profile.json"
        static let retryCount = 1
        static let timeout: TimeInterval = 60
    }

    enum Error: LocalizedError {
        case badStatusCode
        case missingURL
        case notFound
    }

    // Structure for decoding Nightscout treatments for deletion
    private struct NightscoutTreatment: Codable {
        let id: String?
        let created_at: String?
        let eventType: String?
        let enteredBy: String?
        let insulin: Decimal?

        private enum CodingKeys: String, CodingKey {
            case id = "_id"
            case created_at
            case eventType
            case enteredBy
            case insulin
        }
    }

    let url: URL
    let secret: String?

    private let service = NetworkService()
}

extension NightscoutAPI {
    func checkConnection() -> AnyPublisher<Void, Swift.Error> {
        struct Check: Codable, Equatable {
            var eventType = "Note"
            var enteredBy = "openaps-ios"
            var notes = "OpenAPS connected"
        }
        let check = Check()
        var request = URLRequest(url: url.appendingPathComponent(Config.treatmentsPath))

        if let secret = secret {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
            request.httpBody = try! JSONCoding.encoder.encode(check)
        } else {
            request.httpMethod = "GET"
        }

        return service.run(request)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func fetchLastGlucose(sinceDate: Date? = nil) -> AnyPublisher<[BloodGlucose], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.entriesPath
        components.queryItems = [URLQueryItem(name: "count", value: "\(1600)")]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[dateString][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            components.queryItems?.append(dateItem)
        }

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [BloodGlucose].self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<[BloodGlucose], Swift.Error> in
                warning(.nightscout, "Glucose fetching error: \(error.localizedDescription)")
                return Just([]).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .map { glucose in
                glucose
                    .map {
                        var reading = $0
                        reading.glucose = $0.sgv
                        return reading
                    }
            }
            .eraseToAnyPublisher()
    }

    func fetchCarbs(sinceDate: Date? = nil) -> AnyPublisher<[CarbsEntry], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[carbs][$exists]", value: "true"),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: CarbsEntry.manual.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NigtscoutTreatment.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            )
        ]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[created_at][$gt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            components.queryItems?.append(dateItem)
        }

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [CarbsEntry].self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<[CarbsEntry], Swift.Error> in
                warning(.nightscout, "Carbs fetching error: \(error.localizedDescription)")
                return Just([]).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func deleteCarbs(at date: Date) -> AnyPublisher<Void, Swift.Error> {
        let queryItems = [
            URLQueryItem(name: "find[carbs][$exists]", value: "true"),
            URLQueryItem(name: "find[eventType]", value: "Carbs"),
            URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(-300))
            ),
            URLQueryItem(
                name: "find[created_at][$lte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(300))
            ),
            URLQueryItem(name: "find[enteredBy]", value: "freeaps-x")
        ]

        return deleteTreatmentsSafely(queryItems: queryItems, logName: "Carbs")
    }

    // Safe DELETE implementation: GET treatments first, then DELETE by _id individually
    // This prevents Nightscout server crashes from unsupported bulk DELETE operations
    private func deleteTreatmentsSafely(queryItems: [URLQueryItem], logName: String) -> AnyPublisher<Void, Swift.Error> {
        // Step 1: Try primary fetch, then fallback with widened time window and without strict filters
        performFetch(queryItems: queryItems, logName: logName)
            .flatMap { [weak self] treatments -> AnyPublisher<Void, Swift.Error> in
                guard let self = self else { return Fail(error: Error.missingURL).eraseToAnyPublisher() }
                if !treatments.isEmpty {
                    return self.deleteTreatmentsByIds(treatments, logName: logName)
                }
                // Fallback attempt: remove enteredBy/insulin filters and widen time window
                let fallbackItems = self.fallbackQueryItems(from: queryItems)
                return self.performFetch(queryItems: fallbackItems, logName: logName + " (fallback)")
                    .flatMap { [weak self] fallbackTreatments -> AnyPublisher<Void, Swift.Error> in
                        guard let self = self else { return Fail(error: Error.missingURL).eraseToAnyPublisher() }
                        guard !fallbackTreatments.isEmpty else {
                            return Fail(error: Error.notFound).eraseToAnyPublisher()
                        }
                        return self.deleteTreatmentsByIds(fallbackTreatments, logName: logName)
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    // Build a safer, broader query: drop strict filters and widen time window
    private func fallbackQueryItems(from original: [URLQueryItem]) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        var gteIndex: Int?
        var lteIndex: Int?

        for (idx, item) in original.enumerated() {
            switch item.name {
            case "find[enteredBy]",
                 "find[insulin]":
                // drop strict filters in fallback
                continue
            case "find[created_at][$gte]":
                gteIndex = items.count
                items.append(item)
            case "find[created_at][$lte]":
                lteIndex = items.count
                items.append(item)
            default:
                items.append(item)
            }
        }

        // widen time window to ±10 minutes if present
        if let gi = gteIndex, let value = items[gi].value, let date = Formatter.iso8601withFractionalSeconds.date(from: value) {
            let widened = Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(-600))
            items[gi] = URLQueryItem(name: "find[created_at][$gte]", value: widened)
        }
        if let li = lteIndex, let value = items[li].value, let date = Formatter.iso8601withFractionalSeconds.date(from: value) {
            let widened = Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(600))
            items[li] = URLQueryItem(name: "find[created_at][$lte]", value: widened)
        }

        return items
    }

    // Perform GET fetch of treatments with common headers and logging
    private func performFetch(queryItems: [URLQueryItem], logName: String) -> AnyPublisher<[NightscoutTreatment], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = queryItems + [URLQueryItem(name: "count", value: "100")]

        var fetchRequest = URLRequest(url: components.url!)
        fetchRequest.allowsConstrainedNetworkAccess = false
        fetchRequest.timeoutInterval = Config.timeout
        fetchRequest.httpMethod = "GET"

        if let secret = secret {
            fetchRequest.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        debug(.nightscout, "Fetching \(logName) to delete: \(components.url?.absoluteString ?? "invalid URL")")

        return service.run(fetchRequest)
            .decode(type: [NightscoutTreatment].self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<[NightscoutTreatment], Swift.Error> in
                // If server returned non-JSON (e.g., 502 Bad Gateway), treat as no matches
                warning(.nightscout, "Fetch decode failed for \(logName): \(error.localizedDescription)")
                return Just([]).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    // Delete the single treatment closest to the targetDate (and optionally closest by amount)
    private func deleteSingleTreatmentSafely(
        queryItems: [URLQueryItem],
        targetDate: Date,
        preferredAmount: Decimal?,
        logName: String
    ) -> AnyPublisher<Void, Swift.Error> {
        performFetch(queryItems: queryItems, logName: logName)
            .flatMap { treatments -> AnyPublisher<Void, Swift.Error> in
                if let best = self.selectNearestTreatment(
                    from: treatments,
                    targetDate: targetDate,
                    preferredAmount: preferredAmount
                ) {
                    return self.deleteTreatmentsByIds([best], logName: logName)
                }
                // fallback: widen and drop strict filters
                let fallbackItems = self.fallbackQueryItems(from: queryItems)
                return self.performFetch(queryItems: fallbackItems, logName: logName + " (fallback)")
                    .flatMap { fallbackTreatments -> AnyPublisher<Void, Swift.Error> in
                        if let best = self.selectNearestTreatment(
                            from: fallbackTreatments,
                            targetDate: targetDate,
                            preferredAmount: preferredAmount
                        ) {
                            return self.deleteTreatmentsByIds([best], logName: logName)
                        }
                        return Fail(error: Error.notFound).eraseToAnyPublisher()
                    }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private func selectNearestTreatment(
        from treatments: [NightscoutTreatment],
        targetDate: Date,
        preferredAmount: Decimal?
    ) -> NightscoutTreatment? {
        guard !treatments.isEmpty else { return nil }
        func date(of t: NightscoutTreatment) -> Date? {
            guard let s = t.created_at else { return nil }
            return Formatter.iso8601withFractionalSeconds.date(from: s)
        }
        let withDates = treatments.compactMap { t -> (NightscoutTreatment, Date) in
            (t, date(of: t) ?? Date.distantPast)
        }
        let sortedByTime = withDates.sorted { abs($0.1.timeIntervalSince(targetDate)) < abs($1.1.timeIntervalSince(targetDate)) }
        if let preferredAmount = preferredAmount {
            // Choose among top 3 closest by time the one closest by insulin amount
            let top = Array(sortedByTime.prefix(3)).map(\.0)
            let best = top.min { a, b in
                let da = (a.insulin ?? -999) - preferredAmount
                let db = (b.insulin ?? -999) - preferredAmount
                return abs((da as NSDecimalNumber).doubleValue) < abs((db as NSDecimalNumber).doubleValue)
            }
            return best ?? sortedByTime.first?.0
        }
        return sortedByTime.first?.0
    }

    // Helper method to delete treatments by their _id - prevents server crashes
    private func deleteTreatmentsByIds(_ treatments: [NightscoutTreatment], logName: String) -> AnyPublisher<Void, Swift.Error> {
        let publishers = treatments.compactMap { treatment -> AnyPublisher<Void, Swift.Error>? in
            guard let treatmentId = treatment.id else {
                debug(.nightscout, "Skipping \(logName) without _id")
                return nil
            }

            // Step 2: DELETE each treatment by _id using correct endpoint
            var deleteComponents = URLComponents()
            deleteComponents.scheme = url.scheme
            deleteComponents.host = url.host
            deleteComponents.port = url.port
            deleteComponents.path = "/api/v1/treatments/\(treatmentId)"

            var deleteRequest = URLRequest(url: deleteComponents.url!)
            deleteRequest.allowsConstrainedNetworkAccess = false
            deleteRequest.timeoutInterval = Config.timeout
            deleteRequest.httpMethod = "DELETE"

            if let secret = secret {
                deleteRequest.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
            }

            debug(.nightscout, "DELETE \(logName) by _id: \(treatmentId)")

            return service.run(deleteRequest)
                .map { _ in () }
                .eraseToAnyPublisher()
        }

        guard !publishers.isEmpty else {
            debug(.nightscout, "No matching \(logName) found to delete")
            return Fail(error: Error.notFound).eraseToAnyPublisher()
        }

        return Publishers.MergeMany(publishers).eraseToAnyPublisher()
    }

    func deleteTempTarget(at date: Date) -> AnyPublisher<Void, Swift.Error> {
        let queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Temporary Target"),
            URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(-600))
            ),
            URLQueryItem(
                name: "find[created_at][$lte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(600))
            ),
            URLQueryItem(name: "find[enteredBy]", value: "freeaps-x")
        ]

        // Pick the nearest temp target by time and delete by _id
        return deleteSingleTreatmentSafely(queryItems: queryItems, targetDate: date, preferredAmount: nil, logName: "Temp Target")
    }

    func deleteBolus(at date: Date, amount: Decimal) -> AnyPublisher<Void, Swift.Error> {
        // Do not filter by exact insulin amount in query (server-side rounding varies)
        let queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Bolus"),
            URLQueryItem(name: "find[insulin][$exists]", value: "true"),
            URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(-600))
            ),
            URLQueryItem(
                name: "find[created_at][$lte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(600))
            ),
            URLQueryItem(name: "find[enteredBy]", value: "freeaps-x")
        ]

        return deleteSingleTreatmentSafely(queryItems: queryItems, targetDate: date, preferredAmount: amount, logName: "Bolus")
    }

    func deleteTempBasal(at date: Date) -> AnyPublisher<Void, Swift.Error> {
        let queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Temp Basal"),
            URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(-300))
            ),
            URLQueryItem(
                name: "find[created_at][$lte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(300))
            ),
            URLQueryItem(name: "find[enteredBy]", value: "freeaps-x")
        ]

        return deleteTreatmentsSafely(queryItems: queryItems, logName: "Temp Basal")
    }

    func deleteSuspend(at date: Date) -> AnyPublisher<Void, Swift.Error> {
        deleteTreatment(eventType: "Pump Suspend", at: date)
    }

    func deleteResume(at date: Date) -> AnyPublisher<Void, Swift.Error> {
        deleteTreatment(eventType: "Pump Resume", at: date)
    }

    private func deleteTreatment(eventType: String, at date: Date) -> AnyPublisher<Void, Swift.Error> {
        let queryItems = [
            URLQueryItem(name: "find[eventType]", value: eventType),
            URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(-300))
            ),
            URLQueryItem(
                name: "find[created_at][$lte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date.addingTimeInterval(300))
            ),
            URLQueryItem(name: "find[enteredBy]", value: "freeaps-x")
        ]

        return deleteTreatmentsSafely(queryItems: queryItems, logName: eventType)
    }

    func fetchTempTargets(sinceDate: Date? = nil) -> AnyPublisher<[TempTarget], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Temporary+Target"),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: TempTarget.manual.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(
                name: "find[enteredBy][$ne]",
                value: NigtscoutTreatment.local.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            ),
            URLQueryItem(name: "find[duration][$exists]", value: "true")
        ]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[created_at][$gt]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            components.queryItems?.append(dateItem)
        }

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [TempTarget].self, decoder: JSONCoding.decoder)
            .catch { error -> AnyPublisher<[TempTarget], Swift.Error> in
                warning(.nightscout, "TempTarget fetching error: \(error.localizedDescription)")
                return Just([]).setFailureType(to: Swift.Error.self).eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    func fetchAnnouncement(sinceDate: Date? = nil) -> AnyPublisher<[Announcement], Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath
        components.queryItems = [
            URLQueryItem(name: "find[eventType]", value: "Announcement"),
            URLQueryItem(
                name: "find[enteredBy]",
                value: Announcement.remote.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            )
        ]
        if let date = sinceDate {
            let dateItem = URLQueryItem(
                name: "find[created_at][$gte]",
                value: Formatter.iso8601withFractionalSeconds.string(from: date)
            )
            components.queryItems?.append(dateItem)
        }

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }

        return service.run(request)
            .retry(Config.retryCount)
            .decode(type: [Announcement].self, decoder: JSONCoding.decoder)
            .eraseToAnyPublisher()
    }

    func uploadTreatments(_ treatments: [NigtscoutTreatment]) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.treatmentsPath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        request.httpBody = try! JSONCoding.encoder.encode(treatments)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadGlucose(_ glucose: [BloodGlucose]) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.uploadEntriesPath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        request.httpBody = try! JSONCoding.encoder.encode(glucose)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadStatus(_ status: NightscoutStatus) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.statusPath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        request.httpBody = try! JSONCoding.encoder.encode(status)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    func uploadProfile(_ profile: NightscoutProfileStore) -> AnyPublisher<Void, Swift.Error> {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = Config.profilePath

        var request = URLRequest(url: components.url!)
        request.allowsConstrainedNetworkAccess = false
        request.timeoutInterval = Config.timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        if let secret = secret {
            request.addValue(secret.sha1(), forHTTPHeaderField: "api-secret")
        }
        request.httpBody = try! JSONCoding.encoder.encode(profile)
        request.httpMethod = "POST"

        return service.run(request)
            .retry(Config.retryCount)
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}

private extension String {
    func sha1() -> String {
        let data = Data(utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }
}
