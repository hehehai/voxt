import Foundation

extension AppDelegate {
    @discardableResult
    func beginLLMRequest() -> UUID {
        let requestID = UUID()
        activeLLMRequestID = requestID
        return requestID
    }

    func isCurrentLLMRequest(_ requestID: UUID) -> Bool {
        activeLLMRequestID == requestID && !isSessionCancellationRequested
    }

    func invalidateActiveLLMRequest() {
        activeLLMRequestID = UUID()
    }
}
