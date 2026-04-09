import Foundation

enum DoubaoProtocol {
    static let version: UInt8 = 0x1
    static let headerSize: UInt8 = 0x1
    static let messageTypeFullClientRequest: UInt8 = 0x1
    static let messageTypeAudioOnlyClientRequest: UInt8 = 0x2
    static let messageTypeFullServerResponse: UInt8 = 0x9
    static let messageTypeServerAck: UInt8 = 0xB
    static let messageTypeServerErrorResponse: UInt8 = 0xF
    static let flagPositiveSequence: UInt8 = 0x1
    static let flagLastAudioPacket: UInt8 = 0x2
    static let flagNegativeAudioPacket: UInt8 = flagPositiveSequence | flagLastAudioPacket
    static let flagEvent: UInt8 = 0x4
    static let serializationNone: UInt8 = 0x0
    static let serializationJSON: UInt8 = 0x1
    static let compressionNone: UInt8 = 0x0
    static let compressionGzip: UInt8 = 0x1
}

@MainActor
final class DoubaoStreamingContext {
    let session: URLSession
    let ws: URLSessionWebSocketTask
    let responseState: DoubaoResponseState
    var isClosed = false
    var didStartAudioStream = false
    var audioPacketCount = 0
    var serverPacketCount = 0
    var nextAudioSequence: Int32 = 2
    var lastAudioSequence: Int32 = 0
    var pendingPCMData = Data()

    init(session: URLSession, ws: URLSessionWebSocketTask, responseState: DoubaoResponseState) {
        self.session = session
        self.ws = ws
        self.responseState = responseState
    }
}

actor DoubaoResponseState {
    private var text = ""
    private var isFinal = false
    private var completionError: Error?
    private var isSocketClosed = false
    private let onError: @Sendable (Error) -> Void

    init(onError: @escaping @Sendable (Error) -> Void = { _ in }) {
        self.onError = onError
    }

    func replace(text newText: String, isFinal: Bool) -> String {
        text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            self.isFinal = true
        }
        return text
    }

    func markFinal() {
        isFinal = true
    }

    func markCompletedWithError(_ error: Error) {
        if completionError == nil {
            completionError = error
            onError(error)
        }
    }

    func markSocketClosed() {
        isSocketClosed = true
        if completionError == nil {
            completionError = nil
        }
    }

    func waitForFinalResult(timeoutSeconds: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0))
        while !isFinal, !isSocketClosed, completionError == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(120))
        }
        if let completionError {
            throw completionError
        }
        return text
    }

    func currentText() -> String {
        text
    }
}
