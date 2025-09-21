import Foundation

struct Suggestion: JSON, Equatable {
    let reason: String
    let units: Decimal?
    let insulinReq: Decimal?
    let eventualBG: Int?
    let sensitivityRatio: Decimal?
    let rate: Decimal?
    let duration: Int?
    let iob: Decimal?
    let cob: Decimal?
    var predictions: Predictions?
    let deliverAt: Date?
    let carbsReq: Decimal?
    let temp: TempType?
    let bg: Decimal?
    let reservoir: Decimal?
    var timestamp: Date?
    var recieved: Bool?
}

struct Predictions: JSON, Equatable {
    let iob: [Int]?
    let zt: [Int]?
    let cob: [Int]?
    let uam: [Int]?
}

extension Suggestion {
    private enum CodingKeys: String, CodingKey {
        case reason
        case units
        case insulinReq
        case eventualBG
        case sensitivityRatio
        case rate
        case duration
        case iob = "IOB"
        case cob = "COB"
        case predictions = "predBGs"
        case deliverAt
        case carbsReq
        case temp
        case bg
        case reservoir
        case timestamp
        case recieved
    }
}

extension Predictions {
    private enum CodingKeys: String, CodingKey {
        case iob = "IOB"
        case zt = "ZT"
        case cob = "COB"
        case uam = "UAM"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func decodeIntArray(for key: CodingKeys) -> [Int]? {
            if let strict = try? container.decode([Int].self, forKey: key) {
                return strict
            }
            if let loose = try? container.decode([Int?].self, forKey: key) {
                let filtered = loose.compactMap { $0 }
                return filtered.isEmpty ? nil : filtered
            }
            return nil
        }

        iob = decodeIntArray(for: .iob)
        zt = decodeIntArray(for: .zt)
        cob = decodeIntArray(for: .cob)
        uam = decodeIntArray(for: .uam)
    }
}

protocol SuggestionObserver {
    func suggestionDidUpdate(_ suggestion: Suggestion)
}

protocol EnactedSuggestionObserver {
    func enactedSuggestionDidUpdate(_ suggestion: Suggestion)
}

extension Suggestion {
    var reasonParts: [String] {
        reason.components(separatedBy: "; ").first?.components(separatedBy: ", ") ?? []
    }

    var reasonConclusion: String {
        reason.components(separatedBy: "; ").last ?? ""
    }
}
