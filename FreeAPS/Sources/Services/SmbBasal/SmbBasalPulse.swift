import Foundation

struct SmbBasalPulse: JSON, Equatable, Hashable {
    let id: String
    let timestamp: Date
    let units: Decimal
}
