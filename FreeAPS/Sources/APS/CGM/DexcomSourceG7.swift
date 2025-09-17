import Combine
import Foundation
import os.log

/// Dexcom G7 glucose source - currently a stub implementation
// TODO: Implement full G7SensorKit integration when compatibility issues are resolved
final class DexcomSourceG7: GlucoseSource {
    private let processQueue = DispatchQueue(label: "DexcomG7Source.processQueue")

    // G7 tracking data
    private var lastSensorId: String?
    private var lastSensorName: String?
    private var lastGlucoseValue: Int?
    private var lastDataUpdate: Date = .distantPast
    private var cgmHasValidSensorSession: Bool = false

    init() {
        os_log("DexcomSourceG7 initialized - stub implementation", log: .default, type: .info)

        // Initialize lastDataUpdate
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.lastDataUpdate == .distantPast {
                self?.lastDataUpdate = Date().addingTimeInterval(-600) // Set to 10 minutes ago
                os_log("Dexcom G7: initialized lastDataUpdate to 10 minutes ago", log: .default, type: .info)
            }
        }
    }

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        // TODO: Implement actual G7 data fetching when G7SensorKit is compatible
        os_log("DexcomSourceG7.fetch() called - returning empty data (stub)", log: .default, type: .info)
        return Just([])
            .eraseToAnyPublisher()
    }

    // MARK: - SourceInfoProvider

    func sourceInfo() -> [String: Any]? {
        [
            GlucoseSourceKey.description.rawValue: "Dexcom G7 - \(lastSensorName ?? "Stub Implementation")",
            "type": "Dexcom G7",
            "sensorId": lastSensorId ?? "stub",
            "sensorName": lastSensorName ?? "G7 Stub",
            "lastGlucoseValue": lastGlucoseValue ?? 0,
            "lastDataUpdate": lastDataUpdate,
            "hasValidSession": cgmHasValidSensorSession,
            "note": "This is a stub implementation. G7SensorKit integration pending."
        ]
    }
}
