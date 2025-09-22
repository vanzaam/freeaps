import Foundation

protocol DataTableProvider: Provider {
    func pumpHistory() -> [PumpHistoryEvent]
    func tempTargets() -> [TempTarget]
    func carbs() -> [CarbsEntry]
    func deleteCarbs(at date: Date)
    func glucose() -> [BloodGlucose]
    func deleteGlucose(id: String)
    func deleteTreatment(_ treatment: Treatment)
}

extension DataTable {
    final class Provider: BaseProvider, DataTableProvider {
        @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @Injected() var tempTargetsStorage: TempTargetsStorage!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var carbsStorage: CarbsStorage!
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var healthkitManager: HealthKitManager!

        func pumpHistory() -> [PumpHistoryEvent] {
            pumpHistoryStorage.recent()
        }

        func tempTargets() -> [TempTarget] {
            tempTargetsStorage.recent()
        }

        func carbs() -> [CarbsEntry] {
            carbsStorage.recent()
        }

        func deleteCarbs(at date: Date) {
            nightscoutManager.deleteCarbs(at: date)
        }

        func glucose() -> [BloodGlucose] {
            glucoseStorage.recent().sorted { $0.date > $1.date }
        }

        func deleteGlucose(id: String) {
            glucoseStorage.removeGlucose(ids: [id])
            healthkitManager.deleteGlucise(syncID: id)
        }
        
        func deleteTreatment(_ treatment: Treatment) {
            switch treatment.type {
            case .carbs:
                nightscoutManager.deleteCarbs(at: treatment.date)
            case .tempTarget:
                nightscoutManager.deleteTempTarget(at: treatment.date)
            case .bolus:
                if let amount = treatment.amount {
                    nightscoutManager.deleteBolus(at: treatment.date, amount: amount)
                }
            case .tempBasal:
                nightscoutManager.deleteTempBasal(at: treatment.date)
            case .suspend:
                nightscoutManager.deleteSuspend(at: treatment.date)
            case .resume:
                nightscoutManager.deleteResume(at: treatment.date)
            case .fpus:
                break // FPUS is calculated, not stored in Nightscout
            }
        }
    }
}
