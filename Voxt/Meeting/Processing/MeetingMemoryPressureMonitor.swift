// MeetingMemoryPressureMonitor.swift
// Converts macOS memory-pressure notifications into a bounded-inference safety signal.

import Dispatch
import Foundation

nonisolated final class MeetingMemoryPressureMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var source: DispatchSourceMemoryPressure?

    func start(handler: @escaping @Sendable (Bool) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard source == nil else { return }

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler {
            let event = source.data
            handler(event.contains(.warning) || event.contains(.critical))
        }
        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }
}
