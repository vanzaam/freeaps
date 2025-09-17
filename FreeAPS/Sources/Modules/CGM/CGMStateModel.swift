import Combine
import SwiftUI

extension CGM {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var libreSource: LibreTransmitterSource!
        @Injected() var calendarManager: CalendarManager!
        @Injected() var fetchGlucoseManager: FetchGlucoseManager!

        @Published var cgm: CGMType = .nightscout
        @Published var transmitterID = ""
        @Published var uploadGlucose = false
        @Published var createCalendarEvents = false
        @Published var calendarIDs: [String] = []
        @Published var currentCalendarID: String = ""
        @Persisted(key: "CalendarManager.currentCalendarID") var storedCalendarID: String? = nil

        // Dexcom G7 status
        @Published var g7SensorFound: Bool = false
        @Published var g7SensorId: String = ""

        override func subscribe() {
            cgm = settingsManager.settings.cgm
            transmitterID = UserDefaults.standard.dexcomTransmitterID ?? ""
            currentCalendarID = storedCalendarID ?? ""
            calendarIDs = calendarManager.calendarIDs()

            subscribeSetting(\.useCalendar, on: $createCalendarEvents) { createCalendarEvents = $0 }
            subscribeSetting(\.uploadGlucose, on: $uploadGlucose) { uploadGlucose = $0 }

            $cgm
                .removeDuplicates()
                .sink { [weak self] value in
                    guard let self = self else { return }
                    self.settingsManager.settings.cgm = value
                    if value != .dexcomG7 {
                        self.g7SensorFound = false
                        self.g7SensorId = ""
                    }
                }
                .store(in: &lifetime)

            $createCalendarEvents
                .removeDuplicates()
                .flatMap { [weak self] ok -> AnyPublisher<Bool, Never> in
                    guard ok, let self = self else { return Just(false).eraseToAnyPublisher() }
                    return self.calendarManager.requestAccessIfNeeded()
                }
                .map { [weak self] ok -> [String] in
                    guard ok, let self = self else { return [] }
                    return self.calendarManager.calendarIDs()
                }
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.calendarIDs, on: self)
                .store(in: &lifetime)

            $currentCalendarID
                .removeDuplicates()
                .sink { [weak self] id in
                    guard id.isNotEmpty else {
                        self?.calendarManager.currentCalendarID = nil
                        return
                    }
                    self?.calendarManager.currentCalendarID = id
                }
                .store(in: &lifetime)

            // Poll G7 source info periodically to update sensor status (lightweight)
            Timer.publish(every: 5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self = self, self.cgm == .dexcomG7 else { return }
                    let info = self.fetchGlucoseManager.sourceInfo()
                    let found = (info?["sensorFound"] as? Bool) ?? false
                    let sid = (info?["sensorId"] as? String) ?? ""
                    if self.g7SensorFound != found { self.g7SensorFound = found }
                    if self.g7SensorId != sid { self.g7SensorId = sid }
                }
                .store(in: &lifetime)
        }

        func onChangeID() {
            UserDefaults.standard.dexcomTransmitterID = transmitterID
        }
    }
}
