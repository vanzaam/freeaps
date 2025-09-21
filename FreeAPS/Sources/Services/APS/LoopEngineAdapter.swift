import Combine
import Foundation
import HealthKit
import LoopKit
import Swinject

protocol LoopEngineAdapterProtocol {
    func determine(now: Date) -> AnyPublisher<Suggestion?, Never>
}

final class LoopEngineAdapter: LoopEngineAdapterProtocol, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!

    private let processQueue = DispatchQueue(label: "LoopEngineAdapter.queue")

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func determine(now: Date) -> AnyPublisher<Suggestion?, Never> {
        // TODO: Replace with LoopCore math. For now return nil to keep flow intact.
        return Just<Suggestion?>(nil).eraseToAnyPublisher()
    }
}
