// LLMRequestLifecycle.swift
// Provides LLMRequest Lifecycle for app lifecycle and routing.

import Foundation

extension AppDelegate {
    @discardableResult
    func beginLLMRequest() -> UUID {
        for task in llmTasksByRequestID.values {
            task.cancel()
        }
        let requestID = UUID()
        activeLLMRequestID = requestID
        return requestID
    }

    func isCurrentLLMRequest(_ requestID: UUID) -> Bool {
        activeLLMRequestID == requestID && !isSessionCancellationRequested
    }

    func invalidateActiveLLMRequest() {
        _ = cancelActiveLLMRequest()
    }

    func runTrackedLLMRequest(
        _ requestID: UUID,
        operation: @escaping @MainActor () async -> Void
    ) {
        guard !isApplicationTerminating else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.llmTasksByRequestID[requestID] = nil }
            await operation()
        }
        llmTasksByRequestID[requestID] = task
    }

    @discardableResult
    func cancelActiveLLMRequest() -> [Task<Void, Never>] {
        let tasks = Array(llmTasksByRequestID.values)
        llmTasksByRequestID.removeAll()
        activeLLMRequestID = UUID()
        for task in tasks {
            task.cancel()
        }
        return tasks
    }
}
