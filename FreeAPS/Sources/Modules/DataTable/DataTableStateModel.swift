import SwiftUI

extension DataTable {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var broadcaster: Broadcaster!
        @Published var mode: Mode = .combined
        @Published var treatments: [Treatment] = []
        @Published var glucose: [Glucose] = []
        @Published var history: [HistoryItem] = []
        @Published var showDeletedItems: Bool = false
        var units: GlucoseUnits = .mmolL
        
        // Persistent storage for deleted items to survive data reloads
        private var deletedTreatmentIds: Set<String> = []
        private var deletedGlucoseIds: Set<String> = []

        override func subscribe() {
            units = settingsManager.settings.units
            loadDeletedItems()
            setupTreatments()
            setupGlucose()
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PumpHistoryObserver.self, observer: self)
            broadcaster.register(TempTargetsObserver.self, observer: self)
            broadcaster.register(CarbsObserver.self, observer: self)
            broadcaster.register(GlucoseObserver.self, observer: self)
        }

        private func setupTreatments() {
            // OpenAPS Performance Enhancement: Async data processing to prevent UI blocking
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                // Use autoreleasepool to manage memory efficiently during heavy data processing
                let finalTreatments = autoreleasepool {
                    let units = self.settingsManager.settings.units

                    // Cache pump history to avoid multiple calls
                    let pumpHistory = self.provider.pumpHistory()

                    let carbs = self.provider.carbs().map {
                        Treatment(units: units, type: .carbs, date: $0.createdAt, amount: $0.carbs)
                    }

                    let boluses = pumpHistory
                        .lazy // Use lazy evaluation for better performance
                        .filter { $0.type == .bolus || $0.type == .smb || $0.type == .smbBasal }
                        .map { event in
                            // Pack type info into secondAmount: nil = manual, 1 = SMB, 2 = SMB-Basal
                            let typeFlag: Decimal? = {
                                switch event.type {
                                case .smb:
                                    return 1
                                case .smbBasal:
                                    return 2
                                case .bolus:
                                    return event.automatic == true ? 1 : nil
                                default:
                                    return nil
                                }
                            }()
                            return Treatment(
                                units: units,
                                type: .bolus,
                                date: event.timestamp,
                                amount: event.amount,
                                secondAmount: typeFlag
                            )
                        }

                    let tempBasals = pumpHistory
                        .lazy
                        .filter { $0.type == .tempBasal || $0.type == .tempBasalDuration }
                        .chunks(ofCount: 2)
                        .compactMap { chunk -> Treatment? in
                            let chunk = Array(chunk)
                            guard chunk.count == 2, chunk[0].type == .tempBasal,
                                  chunk[1].type == .tempBasalDuration else { return nil }
                            return Treatment(
                                units: units,
                                type: .tempBasal,
                                date: chunk[0].timestamp,
                                amount: chunk[0].rate ?? 0,
                                secondAmount: nil,
                                duration: Decimal(chunk[1].durationMin ?? 0)
                            )
                        }

                    let tempTargets = self.provider.tempTargets()
                        .map {
                            Treatment(
                                units: units,
                                type: .tempTarget,
                                date: $0.createdAt,
                                amount: $0.targetBottom ?? 0,
                                secondAmount: $0.targetTop,
                                duration: $0.duration
                            )
                        }

                    let suspend = pumpHistory
                        .lazy
                        .filter { $0.type == .pumpSuspend }
                        .map {
                            Treatment(units: units, type: .suspend, date: $0.timestamp)
                        }

                    let resume = pumpHistory
                        .lazy
                        .filter { $0.type == .pumpResume }
                        .map {
                            Treatment(units: units, type: .resume, date: $0.timestamp)
                        }

                    let allTreatments = [carbs, Array(boluses), Array(tempBasals), tempTargets, Array(suspend), Array(resume)]
                        .flatMap { $0 }
                        .sorted { $0.date > $1.date }
                    
                    // Apply persistent deletion status
                    for treatment in allTreatments {
                        if self.deletedTreatmentIds.contains(treatment.stableId) {
                            treatment.isDeleted = true
                        }
                    }
                    
                    return allTreatments
                }

                // Update UI on main thread without blocking
                DispatchQueue.main.async { [weak self] in
                    self?.treatments = finalTreatments
                    self?.setupHistory() // Update combined history when treatments change
                }
            }
        }

        func setupGlucose() {
            // OpenAPS Performance Enhancement: Async glucose processing to prevent UI blocking
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                let glucoseData = autoreleasepool {
                    let allGlucose = self.provider.glucose().map { Glucose(glucose: $0) }
                    
                    // Apply persistent deletion status
                    for glucoseItem in allGlucose {
                        if self.deletedGlucoseIds.contains(glucoseItem.id) {
                            glucoseItem.isDeleted = true
                        }
                    }
                    
                    return allGlucose
                }

                DispatchQueue.main.async { [weak self] in
                    self?.glucose = glucoseData
                    self?.setupHistory() // Update combined history when glucose changes
                }
            }
        }

        private func setupHistory() {
            // Combine treatments and glucose into one chronologically sorted list
            var combinedItems: [HistoryItem] = []

            // Filter treatments based on showDeletedItems setting
            let visibleTreatments = showDeletedItems ? treatments : treatments.filter { !$0.isDeleted }
            combinedItems.append(contentsOf: visibleTreatments.map { HistoryItem(treatment: $0) })

            // Filter glucose based on showDeletedItems setting
            let visibleGlucose = showDeletedItems ? glucose : glucose.filter { !$0.isDeleted }
            combinedItems.append(contentsOf: visibleGlucose.map { HistoryItem(glucose: $0) })

            // Sort by date (most recent first)
            combinedItems.sort { $0.date > $1.date }

            history = combinedItems
        }

        // Soft delete methods - mark as deleted instead of physically removing
        func softDeleteTreatment(with id: UUID) {
            if let index = treatments.firstIndex(where: { $0.id == id }) {
                let treatment = treatments[index]
                treatments[index].isDeleted = true
                markTreatmentAsDeleted(treatment.stableId)
                setupHistory() // Refresh history display
            }
        }
        
        func softDeleteGlucose(at index: Int) {
            guard index < glucose.count else { return }
            let glucoseItem = glucose[index]
            glucose[index].isDeleted = true
            markGlucoseAsDeleted(glucoseItem.id)
            setupHistory() // Refresh history display
        }
        
        func restoreTreatment(with id: UUID) {
            if let index = treatments.firstIndex(where: { $0.id == id }) {
                let treatment = treatments[index]
                treatments[index].isDeleted = false
                unmarkTreatmentAsDeleted(treatment.stableId)
                setupHistory() // Refresh history display
            }
        }
        
        func restoreGlucose(at index: Int) {
            guard index < glucose.count else { return }
            let glucoseItem = glucose[index]
            glucose[index].isDeleted = false
            unmarkGlucoseAsDeleted(glucoseItem.id)
            setupHistory() // Refresh history display
        }

        func toggleShowDeletedItems() {
            showDeletedItems.toggle()
            setupHistory() // Refresh display based on new setting
        }
        
        // MARK: - Persistent Deleted Items Management
        
        private func loadDeletedItems() {
            // Load deleted treatment IDs from UserDefaults
            if let treatmentIds = UserDefaults.standard.array(forKey: "DeletedTreatmentIds") as? [String] {
                deletedTreatmentIds = Set(treatmentIds)
            }
            
            // Load deleted glucose IDs from UserDefaults  
            if let glucoseIds = UserDefaults.standard.array(forKey: "DeletedGlucoseIds") as? [String] {
                deletedGlucoseIds = Set(glucoseIds)
            }
        }
        
        private func saveDeletedItems() {
            UserDefaults.standard.set(Array(deletedTreatmentIds), forKey: "DeletedTreatmentIds")
            UserDefaults.standard.set(Array(deletedGlucoseIds), forKey: "DeletedGlucoseIds")
        }
        
        private func markTreatmentAsDeleted(_ stableId: String) {
            deletedTreatmentIds.insert(stableId)
            saveDeletedItems()
        }
        
        private func markGlucoseAsDeleted(_ id: String) {
            deletedGlucoseIds.insert(id)
            saveDeletedItems()
        }
        
        private func unmarkTreatmentAsDeleted(_ stableId: String) {
            deletedTreatmentIds.remove(stableId)
            saveDeletedItems()
        }
        
        private func unmarkGlucoseAsDeleted(_ id: String) {
            deletedGlucoseIds.remove(id)
            saveDeletedItems()
        }

        func deleteCarbs(at date: Date) {
            provider.deleteCarbs(at: date)
        }

        func deleteGlucose(at index: Int) {
            let id = glucose[index].id
            provider.deleteGlucose(id: id)
        }
    }
}

extension DataTable.StateModel:
    SettingsObserver,
    PumpHistoryObserver,
    TempTargetsObserver,
    CarbsObserver,
    GlucoseObserver
{
    @MainActor func settingsDidChange(_: FreeAPSSettings) {
        setupTreatments()
    }

    @MainActor func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        setupTreatments()
    }

    @MainActor func tempTargetsDidUpdate(_: [TempTarget]) {
        setupTreatments()
    }

    @MainActor func carbsDidUpdate(_: [CarbsEntry]) {
        setupTreatments()
    }

    @MainActor func glucoseDidUpdate(_: [BloodGlucose]) {
        setupGlucose()
    }
}
