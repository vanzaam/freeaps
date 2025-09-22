import Foundation
import SwiftUI

enum DataTable {
    enum Config {}

    enum Mode: String, Hashable, Identifiable, CaseIterable {
        case treatments
        case glucose
        case combined // New combined mode

        var id: String { rawValue }

        var name: String {
            var name: String = ""
            switch self {
            case .treatments:
                name = "Treatments"
            case .glucose:
                name = "Glucose"
            case .combined:
                name = "History"
            }
            return NSLocalizedString(name, comment: "History Mode")
        }
    }

    // Combined history item that can be either treatment or glucose
    class HistoryItem: Identifiable, Hashable, Equatable {
        let id = UUID()
        let date: Date
        let treatment: Treatment?
        let glucose: Glucose?

        init(treatment: Treatment) {
            self.treatment = treatment
            glucose = nil
            date = treatment.date
        }

        init(glucose: Glucose) {
            treatment = nil
            self.glucose = glucose
            date = glucose.glucose.dateString
        }

        var isGlucose: Bool {
            glucose != nil
        }

        var isTreatment: Bool {
            treatment != nil
        }

        var isDeleted: Bool {
            treatment?.isDeleted == true || glucose?.isDeleted == true
        }

        static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    enum DataType: String, Equatable {
        case carbs
        case bolus
        case tempBasal
        case tempTarget
        case suspend
        case resume

        var name: String {
            var name: String = ""
            switch self {
            case .carbs:
                name = "Carbs"
            case .bolus:
                name = "Bolus"
            case .tempBasal:
                name = "Temp Basal"
            case .tempTarget:
                name = "Temp Target"
            case .suspend:
                name = "Suspend"
            case .resume:
                name = "Resume"
            }

            return NSLocalizedString(name, comment: "Treatment type")
        }
    }

    class Treatment: Identifiable, Hashable, Equatable {
        let id = UUID()
        let units: GlucoseUnits
        let type: DataType
        let date: Date
        let amount: Decimal?
        let secondAmount: Decimal?
        let duration: Decimal?
        var isDeleted: Bool = false

        // Stable identifier for persistence - based on content, not random UUID
        var stableId: String {
            let timestamp = Int(date.timeIntervalSince1970)
            let amountStr = amount?.description ?? "0"
            let secondAmountStr = secondAmount?.description ?? "0"
            let durationStr = duration?.description ?? "0"
            return "\(type.rawValue)_\(timestamp)_\(amountStr)_\(secondAmountStr)_\(durationStr)"
        }

        private var numberFormater: NumberFormatter {
            FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 2) }

        init(
            units: GlucoseUnits,
            type: DataType,
            date: Date,
            amount: Decimal? = nil,
            secondAmount: Decimal? = nil,
            duration: Decimal? = nil,
            isDeleted: Bool = false
        ) {
            self.units = units
            self.type = type
            self.date = date
            self.amount = amount
            self.secondAmount = secondAmount
            self.duration = duration
            self.isDeleted = isDeleted
        }

        static func == (lhs: Treatment, rhs: Treatment) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        var amountText: String {
            guard let amount = amount else {
                return ""
            }

            if amount == 0, duration == 0 {
                return "Cancel temp"
            }

            switch type {
            case .carbs:
                return numberFormater.string(from: amount as NSNumber)! + NSLocalizedString(" g", comment: "gram of carbs")
            case .bolus:
                return numberFormater.string(from: amount as NSNumber)! + NSLocalizedString(" U", comment: "Insulin unit")
            case .tempBasal:
                return numberFormater
                    .string(from: amount as NSNumber)! + NSLocalizedString(" U/hr", comment: "Unit insulin per hour")
            case .tempTarget:
                var converted = amount
                if units == .mmolL {
                    converted = converted.asMmolL
                }

                guard var secondAmount = secondAmount else {
                    return numberFormater.string(from: converted as NSNumber)! + " \(units.rawValue)"
                }
                if units == .mmolL {
                    secondAmount = secondAmount.asMmolL
                }

                return numberFormater.string(from: converted as NSNumber)! + " - " + numberFormater
                    .string(from: secondAmount as NSNumber)! + " \(units.rawValue)"
            case .resume,
                 .suspend:
                return type.name
            }
        }

        var color: Color {
            // Show deleted items in light gray
            if isDeleted {
                return .secondary.opacity(0.5)
            }

            switch type {
            case .carbs:
                return .loopYellow
            case .bolus:
                return .insulin
            case .tempBasal:
                return Color.insulin.opacity(0.5)
            case .resume,
                 .suspend,
                 .tempTarget:
                return .loopGray
            }
        }

        var durationText: String? {
            guard let duration = duration, duration > 0 else {
                return nil
            }
            return numberFormater.string(from: duration as NSNumber)! + " min"
        }

        var displayTypeName: String {
            switch type {
            case .bolus:
                if let flag = secondAmount {
                    switch flag {
                    case 1:
                        return "SMB"
                    case 2:
                        return "SMB-Basal"
                    default:
                        return "Ручной болюс"
                    }
                }
                return "Ручной болюс"
            case .tempBasal:
                return "ВБС"
            default:
                return type.name
            }
        }
    }

    class Glucose: Identifiable, Hashable, Equatable {
        static func == (lhs: DataTable.Glucose, rhs: DataTable.Glucose) -> Bool {
            lhs.glucose == rhs.glucose
        }

        let glucose: BloodGlucose
        var isDeleted: Bool = false

        init(glucose: BloodGlucose, isDeleted: Bool = false) {
            self.glucose = glucose
            self.isDeleted = isDeleted
        }

        var id: String { glucose.id }

        func hash(into hasher: inout Hasher) {
            hasher.combine(glucose.id)
        }
    }
}

protocol DataTableProvider: Provider {
    func pumpHistory() -> [PumpHistoryEvent]
    func tempTargets() -> [TempTarget]
    func carbs() -> [CarbsEntry]
    func glucose() -> [BloodGlucose]
    func deleteCarbs(at date: Date)
    func deleteGlucose(id: String)
    func deleteTreatment(_ treatment: DataTable.Treatment)
}
