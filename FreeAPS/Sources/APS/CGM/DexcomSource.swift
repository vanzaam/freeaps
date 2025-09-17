import CGMBLEKit
import Combine
import Foundation

final class DexcomSource: GlucoseSource {
    private let processQueue = DispatchQueue(label: "DexcomSource.processQueue")

    private let dexcomManager = TransmitterManager(
        state: TransmitterManagerState(transmitterID: UserDefaults.standard.dexcomTransmitterID ?? "000000")
    )

    private var promise: Future<[BloodGlucose], Error>.Promise?

    init() {
        dexcomManager.addObserver(self, queue: processQueue)
    }

    var transmitterID: String {
        dexcomManager.transmitter.ID
    }

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        dexcomManager.transmitter.resumeScanning()
        return Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    deinit {
        dexcomManager.transmitter.stopScanning()
        dexcomManager.removeObserver(self)
    }
}

extension DexcomSource: TransmitterManagerObserver {
    func transmitterManagerDidUpdateLatestReading(_ manager: TransmitterManager) {
        guard let latestReading = manager.latestReading,
              let quantity = latestReading.glucose
        else {
            return
        }

        let value = Int(quantity.doubleValue(for: .milligramsPerDeciliter))

        let bloodGlucose = BloodGlucose(
            _id: latestReading.syncIdentifier,
            sgv: value,
            direction: .init(trend: latestReading.trend),
            date: Decimal(Int(latestReading.readDate.timeIntervalSince1970 * 1000)),
            dateString: latestReading.readDate,
            unfiltered: nil,
            filtered: nil,
            noise: nil,
            glucose: value,
            type: "sgv"
        )

        promise?(.success([bloodGlucose]))
    }

    func sourceInfo() -> [String: Any]? {
        [GlucoseSourceKey.description.rawValue: "Dexcom tramsmitter ID: \(transmitterID)"]
    }
}

extension BloodGlucose.Direction {
    init(trend: Int) {
        guard trend < Int(Int8.max) else {
            self = .none
            return
        }

        switch trend {
        case let x where x <= -30:
            self = .doubleDown
        case let x where x <= -20:
            self = .singleDown
        case let x where x <= -10:
            self = .fortyFiveDown
        case let x where x < 10:
            self = .flat
        case let x where x < 20:
            self = .fortyFiveUp
        case let x where x < 30:
            self = .singleUp
        default:
            self = .doubleUp
        }
    }
}
