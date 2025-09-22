import Foundation

struct SmbBasalIob: JSON, Equatable {
    let iob: Decimal
    let timestamp: Date
    let activePulses: Int
    let oldestPulseAge: TimeInterval // in minutes
}
