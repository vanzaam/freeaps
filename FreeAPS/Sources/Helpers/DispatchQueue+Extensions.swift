import Combine
import Foundation

extension DispatchQueue {
//    static let reloadQueue = DispatchQueue.markedQueue(label: "reloadQueue", qos: .ui)
}

extension DispatchQueue {
    static var isMain: Bool {
        Thread.isMainThread && OperationQueue.main === OperationQueue.current
    }

    static func safeMainSync<T>(_ block: () throws -> T) rethrows -> T {
        if isMain {
            return try block()
        } else {
            return try DispatchQueue.main.sync {
                try autoreleasepool(invoking: block)
            }
        }
    }

    static func safeMainAsync(_ block: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.default], block: block)
    }

    /// FreeAPS X Performance Enhancement: Non-blocking main queue operations
    static func performOnMainIfNeeded<T>(_ block: @escaping () -> T) -> Future<T, Never> {
        Future { promise in
            if isMain {
                // Already on main thread, execute immediately
                promise(.success(block()))
            } else {
                // Schedule on main thread without blocking
                DispatchQueue.main.async {
                    promise(.success(block()))
                }
            }
        }
    }

    /// FreeAPS X Performance Enhancement: Safe sync with timeout to prevent hangs
    func safeSync<T>(timeout: DispatchTime = .now() + .seconds(5), execute block: @escaping () throws -> T) -> T? {
        var result: T?
        var thrownError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        async {
            do {
                result = try block()
            } catch {
                thrownError = error
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: timeout) == .timedOut {
            debug(.service, "DispatchQueue.safeSync timed out - preventing hang")
            return nil
        }

        if let error = thrownError {
            debug(.service, "DispatchQueue.safeSync error: \(error)")
            return nil
        }

        return result
    }
}

extension DispatchQueue {
    private enum QueueSpecific {
        static let key = DispatchSpecificKey<String>()
        static let value = AssociationKey<String?>("DispatchQueue.Specific.value")
    }

    private(set) var specificValue: String? {
        get { associations.value(forKey: QueueSpecific.value) }
        set { associations.setValue(newValue, forKey: QueueSpecific.value) }
    }

    static func markedQueue(
        label: String = "MarkedQueue",
        qos: DispatchQoS = .default,
        attributes: DispatchQueue.Attributes = [],
        target: DispatchQueue? = nil
    ) -> DispatchQueue {
        let queueLabel = "\(label).\(UUID())"
        let queue = DispatchQueue(
            label: queueLabel,
            qos: qos,
            attributes: attributes,
            autoreleaseFrequency: .workItem,
            target: target
        )
        let specificValue = target?.label ?? queueLabel
        queue.specificValue = specificValue
        queue.setSpecific(key: QueueSpecific.key, value: specificValue)
        return queue
    }

    static var currentLabel: String? { DispatchQueue.getSpecific(key: QueueSpecific.key) }

    var isCurrentQueue: Bool {
        if let staticSpecific = DispatchQueue.currentLabel,
           let instanceSpecific = specificValue,
           staticSpecific == instanceSpecific
        {
            return true
        }
        return false
    }

    func safeSync<T>(execute block: () throws -> T) rethrows -> T {
        try autoreleasepool {
            if self === DispatchQueue.main {
                return try DispatchQueue.safeMainSync(block)
            } else if isCurrentQueue {
                return try block()
            } else {
                return try sync {
                    try autoreleasepool(invoking: block)
                }
            }
        }
    }
}
