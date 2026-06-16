// AsyncJSONPersistenceCoordinator.swift
// Provides Async JSONPersistence Coordinator for shared utilities.

import Foundation

final class AsyncJSONPersistenceCoordinator {
    private let queue: DispatchQueue
    private let writeDebounceInterval: DispatchTimeInterval = .milliseconds(250)
    private var pendingWriteWorkItem: DispatchWorkItem?
    private var pendingWriteGeneration: UInt64 = 0

    init(label: String) {
        self.queue = DispatchQueue(label: label, qos: .utility)
    }

    func scheduleWrite<Value: Encodable>(_ value: Value, to url: URL) {
        queue.async {
            self.pendingWriteWorkItem?.cancel()
            self.pendingWriteGeneration &+= 1
            let generation = self.pendingWriteGeneration

            let workItem = DispatchWorkItem {
                guard generation == self.pendingWriteGeneration else { return }
                do {
                    let data = try JSONEncoder().encode(value)
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try data.write(to: url, options: [.atomic])
                } catch {
                    // Keep UI responsive even if persistence fails.
                }

                if generation == self.pendingWriteGeneration {
                    self.pendingWriteWorkItem = nil
                }
            }

            self.pendingWriteWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + self.writeDebounceInterval, execute: workItem)
        }
    }
}
