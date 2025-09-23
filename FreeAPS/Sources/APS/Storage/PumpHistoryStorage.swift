import Foundation
import LoopKit
import SwiftDate
import Swinject

protocol PumpHistoryObserver {
    func pumpHistoryDidUpdate(_ events: [PumpHistoryEvent])
}

protocol PumpHistoryStorage {
    func storePumpEvents(_ events: [NewPumpEvent])
    func storeEvents(_ events: [PumpHistoryEvent])
    func storeJournalCarbs(_ carbs: Int)
    func recent() -> [PumpHistoryEvent]
    func nightscoutTretmentsNotUploaded() -> [NigtscoutTreatment]
    func saveCancelTempEvents()
}

final class BasePumpHistoryStorage: PumpHistoryStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BasePumpHistoryStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storePumpEvents(_ events: [NewPumpEvent]) {
        processQueue.async {
            let eventsToStore = events.flatMap { event -> [PumpHistoryEvent] in
                let id = event.raw.md5String
                switch event.type {
                case .bolus:
                    guard let dose = event.dose else { return [] }
                    let amount = Decimal(string: dose.unitsInDeliverableIncrements.description)
                    let deliveredUnits = dose.deliveredUnits.map { Decimal($0) }
                    let minutes = Int((dose.endDate - dose.startDate).timeInterval / 60)

                    // Create temporary event to check if it's SMB-Basal
                    let tempEvent = PumpHistoryEvent(
                        id: id,
                        type: .bolus,
                        timestamp: event.date,
                        amount: amount,
                        deliveredUnits: deliveredUnits,
                        duration: minutes,
                        durationMin: nil,
                        rate: nil,
                        temp: nil,
                        carbInput: nil,
                        automatic: dose.automatic
                    )

                    // Determine correct event type
                    let eventType: EventType = {
                        if dose.automatic == true {
                            let isSmbBasal = self.isSmbBasalPulse(event: tempEvent)
                            let finalType: EventType = isSmbBasal ? .smbBasal : .smb
                            print(
                                "PumpHistoryStorage: Automatic bolus \(amount ?? 0)U -> \(finalType.rawValue) (isSmbBasal: \(isSmbBasal))"
                            )
                            return finalType
                        } else {
                            print("PumpHistoryStorage: Manual bolus \(amount ?? 0)U -> Bolus")
                            return .bolus
                        }
                    }()

                    return [PumpHistoryEvent(
                        id: id,
                        type: eventType,
                        timestamp: event.date,
                        amount: amount,
                        deliveredUnits: deliveredUnits,
                        duration: minutes,
                        durationMin: nil,
                        rate: nil,
                        temp: nil,
                        carbInput: nil,
                        automatic: dose.automatic
                    )]
                case .tempBasal:
                    guard let dose = event.dose else { return [] }

                    let rate = Decimal(dose.unitsPerHour)
                    let minutes = (dose.endDate - dose.startDate).timeInterval / 60
                    let delivered = dose.deliveredUnits
                    let date = event.date

                    // Treat finalized temp basals with delivered units as cancel markers in our storage model
                    let isCancel = (event.dose?.isMutable == false) && delivered != nil
                    guard !isCancel else { return [] }

                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .tempBasalDuration,
                            timestamp: date,
                            amount: nil,
                            deliveredUnits: nil,
                            duration: nil,
                            durationMin: Int(round(minutes)),
                            rate: nil,
                            temp: nil,
                            carbInput: nil,
                            automatic: nil
                        ),
                        PumpHistoryEvent(
                            id: "_" + id,
                            type: .tempBasal,
                            timestamp: date,
                            amount: nil,
                            deliveredUnits: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: rate,
                            temp: .absolute,
                            carbInput: nil,
                            automatic: nil
                        )
                    ]
                case .suspend:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpSuspend,
                            timestamp: event.date,
                            amount: nil,
                            deliveredUnits: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil,
                            automatic: nil
                        )
                    ]
                case .resume:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpResume,
                            timestamp: event.date,
                            amount: nil,
                            deliveredUnits: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil,
                            automatic: nil
                        )
                    ]
                case .rewind:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .rewind,
                            timestamp: event.date,
                            amount: nil,
                            deliveredUnits: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil,
                            automatic: nil
                        )
                    ]
                case .prime:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .prime,
                            timestamp: event.date,
                            amount: nil,
                            deliveredUnits: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil,
                            automatic: nil
                        )
                    ]
                default:
                    return []
                }
            }

            self.storeEvents(eventsToStore)
        }
    }

    func storeJournalCarbs(_ carbs: Int) {
        processQueue.async {
            let eventsToStore = [
                PumpHistoryEvent(
                    id: UUID().uuidString,
                    type: .journalCarbs,
                    timestamp: Date(),
                    amount: nil,
                    deliveredUnits: nil,
                    duration: nil,
                    durationMin: nil,
                    rate: nil,
                    temp: nil,
                    carbInput: carbs,
                    automatic: nil
                )
            ]
            self.storeEvents(eventsToStore)
        }
    }

    func storeEvents(_ events: [PumpHistoryEvent]) {
        processQueue.async {
            let file = OpenAPS.Monitor.pumpHistory
            var uniqEvents: [PumpHistoryEvent] = []
            self.storage.transaction { storage in
                storage.append(events, to: file, uniqBy: \.id)
                uniqEvents = storage.retrieve(file, as: [PumpHistoryEvent].self)?
                    .filter { $0.timestamp.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.timestamp > $1.timestamp } ?? []
                storage.save(Array(uniqEvents), as: file)
            }
            self.broadcaster.notify(PumpHistoryObserver.self, on: self.processQueue) {
                $0.pumpHistoryDidUpdate(uniqEvents)
            }
        }
    }

    func recent() -> [PumpHistoryEvent] {
        storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self)?.reversed() ?? []
    }

    func nightscoutTretmentsNotUploaded() -> [NigtscoutTreatment] {
        let events = recent()
        guard !events.isEmpty else { return [] }

        let temps: [NigtscoutTreatment] = events.reduce([]) { result, event in
            var result = result
            switch event.type {
            case .tempBasal:
                result.append(NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: event,
                    absolute: event.rate,
                    rate: event.rate,
                    eventType: .nsTempBasal,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: nil,
                    targetTop: nil,
                    targetBottom: nil
                ))
            case .tempBasalDuration:
                if var last = result.popLast(), last.eventType == .nsTempBasal, last.createdAt == event.timestamp {
                    last.duration = event.durationMin
                    last.rawDuration = event
                    result.append(last)
                }
            default: break
            }
            return result
        }

        // Deduplicate events by timestamp and amount to prevent SMB/SMB-Basal duplicates
        let uniqueEvents = events.reduce([PumpHistoryEvent]()) { result, event in
            var result = result
            let isDuplicate = result.contains { existing in
                existing.type == event.type &&
                    abs(existing.timestamp.timeIntervalSince(event.timestamp)) < 30 && // within 30 seconds
                    existing.amount == event.amount &&
                    existing.automatic == event.automatic
            }
            if !isDuplicate {
                result.append(event)
            }
            return result
        }

        let bolusesAndCarbs = uniqueEvents.compactMap { event -> NigtscoutTreatment? in
            switch event.type {
            case .bolus,
                 .smb,
                 .smbBasal:
                // Determine if this is a regular SMB or SMB-Basal
                let eventType: EventType = {
                    switch event.type {
                    case .smb,
                         .smbBasal:
                        return event.type
                    default:
                        if event.automatic == true {
                            return self.isSmbBasalPulse(event: event) ? .smbBasal : .smb
                        } else {
                            return .bolus
                        }
                    }
                }()
                return NigtscoutTreatment(
                    duration: event.duration,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: eventType,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: event,
                    insulin: event.effectiveInsulinAmount,
                    notes: nil,
                    carbs: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            case .journalCarbs:
                return NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: Decimal(event.carbInput ?? 0),
                    targetTop: nil,
                    targetBottom: nil
                )
            default: return nil
            }
        }

        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedPumphistory, as: [NigtscoutTreatment].self) ?? []

        let treatments = Array(Set([bolusesAndCarbs, temps].flatMap { $0 }).subtracting(Set(uploaded)))

        return treatments.sorted { $0.createdAt! > $1.createdAt! }
    }

    func saveCancelTempEvents() {
        let basalID = UUID().uuidString
        let date = Date()

        let events = [
            PumpHistoryEvent(
                id: basalID,
                type: .tempBasalDuration,
                timestamp: date,
                amount: nil,
                deliveredUnits: nil,
                duration: nil,
                durationMin: 0,
                rate: nil,
                temp: nil,
                carbInput: nil,
                automatic: nil
            ),
            PumpHistoryEvent(
                id: "_" + basalID,
                type: .tempBasal,
                timestamp: date,
                amount: nil,
                deliveredUnits: nil,
                duration: nil,
                durationMin: nil,
                rate: 0,
                temp: .absolute,
                carbInput: nil,
                automatic: nil
            )
        ]

        storeEvents(events)
    }

    // MARK: - SMB-Basal Detection

    private func isSmbBasalPulse(event: PumpHistoryEvent) -> Bool {
        // Only check if SMB-basal is enabled
        guard settingsManager.settings.smbBasalEnabled else {
            return false
        }

        // Get stored SMB-basal pulses
        let pulses = storage.retrieve(OpenAPS.Monitor.smbBasalPulses, as: [SmbBasalPulse].self) ?? []

        // Look for matching pulse within 30 seconds and same amount
        return pulses.contains { pulse in
            let timeDifference = abs(event.timestamp.timeIntervalSince(pulse.timestamp))
            let amountMatch = abs((event.amount ?? 0) - pulse.units) < 0.001
            return timeDifference < 30 && amountMatch
        }
    }
}
