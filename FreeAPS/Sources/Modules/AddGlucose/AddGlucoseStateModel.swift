import Combine
import SwiftUI

extension AddGlucose {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var apsManager: APSManager!
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var healthKitManager: HealthKitManager!
        @Published var glucose: Decimal = 0
        @Published var date = Date()
        @Published var units: GlucoseUnits = .mgdL

        override func subscribe() {
            units = settingsManager.settings.units
        }

        func add() {
            debug(.businessLogic, "AddGlucose: start units=\(units.rawValue) input=\(glucose)", printToConsole: true)
            let mgdl: Int = {
                if units == .mmolL {
                    let mmol = NSDecimalNumber(decimal: glucose).doubleValue
                    let converted = (mmol / 0.0555).rounded()
                    return Int(converted)
                } else {
                    let mgdlVal = NSDecimalNumber(decimal: glucose).doubleValue
                    return Int(mgdlVal.rounded())
                }
            }()
            debug(
                .businessLogic,
                "AddGlucose: converted to mg/dL=\(mgdl) at \(date)",
                printToConsole: true
            )

            guard mgdl > 0 else {
                showModal(for: nil)
                return
            }

            let entry = BloodGlucose(
                _id: UUID().uuidString,
                sgv: mgdl,
                direction: nil,
                date: Decimal(Int(date.timeIntervalSince1970 * 1000)),
                dateString: date,
                unfiltered: nil,
                filtered: nil,
                noise: nil,
                glucose: mgdl,
                type: "sgv"
            )

            glucoseStorage.storeGlucose([entry])
            debug(.businessLogic, "AddGlucose: stored locally id=\(entry.id)", printToConsole: true)
            apsManager.heartbeat(date: Date())
            nightscoutManager.uploadManualGlucose(entry: entry, note: "глюкометр")
            debug(.nightscout, "AddGlucose: requested NS upload", printToConsole: true)
            healthKitManager.saveIfNeeded(bloodGlucose: [entry])
            debug(.service, "AddGlucose: requested HealthKit save", printToConsole: true)
            showModal(for: nil)
        }
    }
}
