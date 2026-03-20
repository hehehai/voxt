import Foundation

enum SessionInvocationSource {
    case hotkey
    case mcp
}

enum SessionDeliveryTarget {
    case systemInput
    case mcpResponse
}

enum AgentPromptState: String {
    case idle
    case prompting
    case recording
    case transcribing
    case completed
    case cancelled
    case failed
}

enum AgentPromptErrorCode: String {
    case busy
    case permissionDenied = "permission_denied"
    case cancelled
    case timeout
    case transcriptionFailed = "transcription_failed"
    case serverDisabled = "server_disabled"
    case invalidRequest = "invalid_request"
}

struct AgentPromptRequest: Equatable {
    let id: UUID
    let questions: [String]
    let contextHint: String?
    let timeoutSeconds: TimeInterval

    var questionSummary: String {
        guard let first = questions.first else { return "" }
        if questions.count == 1 {
            return first
        }
        return "\(first) +\(questions.count - 1)"
    }
}

struct AgentPromptToolResponse: Equatable {
    let status: String
    let transcript: String
    let errorCode: AgentPromptErrorCode?
    let errorMessage: String?

    static func answered(_ transcript: String) -> Self {
        Self(status: "answered", transcript: transcript, errorCode: nil, errorMessage: nil)
    }

    static func cancelled(message: String? = nil) -> Self {
        Self(status: "cancelled", transcript: "", errorCode: nil, errorMessage: message)
    }

    static func timedOut(message: String? = nil) -> Self {
        Self(status: "timeout", transcript: "", errorCode: nil, errorMessage: message)
    }

    static func error(_ code: AgentPromptErrorCode, message: String) -> Self {
        Self(status: "error", transcript: "", errorCode: code, errorMessage: message)
    }

    var responsePayload: [String: Any] {
        var payload: [String: Any] = [
            "status": status,
            "transcript": transcript
        ]
        if let errorCode {
            payload["error_code"] = errorCode.rawValue
        }
        if let errorMessage, !errorMessage.isEmpty {
            payload["error_message"] = errorMessage
        }
        return payload
    }
}
