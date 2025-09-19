import Combine
import Foundation
import LibreTransmitter
import LoopKit
import Swinject

protocol LibreTransmitterSource: GlucoseSource {
    var manager: LibreTransmitterManagerV3? { get set }
}

final class BaseLibreTransmitterSource: LibreTransmitterSource, Injectable {
    private let processQueue = DispatchQueue(label: "BaseLibreTransmitterSource.processQueue")

    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var calibrationService: CalibrationService!

    private var promise: Future<[BloodGlucose], Error>.Promise?

    var manager: LibreTransmitterManagerV3? {
        didSet {
            configured = manager != nil
            manager?.cgmManagerDelegate = self
        }
    }

    @Persisted(key: "LibreTransmitterManager.configured") private(set) var configured = false

    init(resolver: Resolver) {
        if configured {
            manager = LibreTransmitterManagerV3()
            manager?.cgmManagerDelegate = self
        }

        injectServices(resolver)
    }

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        Future<[BloodGlucose], Error> { [weak self] promise in
            self?.promise = promise
        }
        .timeout(60, scheduler: processQueue, options: nil, customError: nil)
        .replaceError(with: [])
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    func sourceInfo() -> [String: Any]? {
        if let battery = manager?.batteryLevel {
            return ["transmitterBattery": battery]
        }
        return nil
    }
}

extension BaseLibreTransmitterSource: CGMManagerDelegate {
    var queue: DispatchQueue { processQueue }

    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        glucoseStorage.syncDate()
    }

    func cgmManager(_: CGMManager, hasNew readingResult: CGMReadingResult) {
        switch readingResult {
        case .noData,
             .unreliableData:
            promise?(.success([]))
        case let .error(error):
            warning(.service, "LibreTransmitter error:", error: error)
            promise?(.failure(error))
        case let .newData(samples):
            let glucose: [BloodGlucose] = samples.map { s in
                let trendMapped: BloodGlucose.Direction? = s.trend.map { BloodGlucose.Direction.fromLoopKitTrend($0) }
                return BloodGlucose(
                    _id: s.syncIdentifier,
                    sgv: Int(s.quantity.doubleValue(for: .milligramsPerDeciliter)),
                    direction: trendMapped,
                    date: Decimal(Int(s.date.timeIntervalSince1970 * 1000)),
                    dateString: s.date,
                    unfiltered: nil,
                    filtered: nil,
                    noise: nil,
                    glucose: Int(s.quantity.doubleValue(for: .milligramsPerDeciliter)),
                    type: "sgv"
                )
            }
            promise?(.success(glucose))
        }
    }

    func cgmManager(_: CGMManager, didUpdate _: CGMManagerStatus) {}

    func cgmManagerWantsDeletion(_: CGMManager) {}

    func cgmManagerDidUpdateState(_: CGMManager) {}

    func credentialStoragePrefix(for _: CGMManager) -> String { "freeaps" }

    // New event notifications are not used in FreeAPS; ignore safely
    func cgmManager(_: CGMManager, hasNew _: [PersistedCgmEvent]) {}

    // DeviceManagerDelegate (via CGMManagerDelegate)
    func deviceManager(
        _: DeviceManager,
        logEventForDeviceIdentifier _: String?,
        type _: DeviceLogEntryType,
        message _: String,
        completion: ((Error?) -> Void)?
    ) {
        completion?(nil)
    }

    // AlertIssuer (via DeviceManagerDelegate)
    func issueAlert(_ alert: Alert) {
        // No-op fallback; FreeAPS handles notifications elsewhere
        _ = alert
    }

    func retractAlert(identifier _: Alert.Identifier) {}

    // PersistedAlertStore (via DeviceManagerDelegate)
    func doesIssuedAlertExist(identifier _: Alert.Identifier, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false))
    }

    func lookupAllUnretracted(managerIdentifier _: String, completion: @escaping (Result<[PersistedAlert], Error>) -> Void) {
        completion(.success([]))
    }

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion: @escaping (Result<[PersistedAlert], Error>) -> Void
    ) {
        completion(.success([]))
    }

    func recordRetractedAlert(_ _: Alert, at _: Date) {}
}

extension BloodGlucose.Direction {
    static func fromLoopKitTrend(_ trendType: GlucoseTrend) -> BloodGlucose.Direction {
        switch trendType {
        case .upUpUp:
            return .doubleUp
        case .upUp:
            return .singleUp
        case .up:
            return .fortyFiveUp
        case .flat:
            return .flat
        case .down:
            return .fortyFiveDown
        case .downDown:
            return .singleDown
        case .downDownDown:
            return .doubleDown
        }
    }
}
