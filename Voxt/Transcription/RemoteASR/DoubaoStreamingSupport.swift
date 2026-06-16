// DoubaoStreamingSupport.swift
// Provides Doubao Streaming Support for remote ASR adapters.

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
    let generationID: UUID
    let createdAt = Date()
    var isClosed = false
    var didStartAudioStream = false
    var audioCaptureStartCount = 0
    var audioPacketCount = 0
    var serverPacketCount = 0
    var pcmCallbackCount = 0
    var nextAudioSequence: Int32 = 2
    var lastAudioSequence: Int32 = 0
    var pendingPCMData = Data()
    var firstPCMCallbackAt: Date?
    var lastPCMCallbackAt: Date?
    var firstAudioPacketSentAt: Date?
    var lastAudioPacketSentAt: Date?
    var firstServerPacketAt: Date?
    var lastServerPacketAt: Date?
    var lastAudioCaptureStartReason = "not-started"

    init(
        session: URLSession,
        ws: URLSessionWebSocketTask,
        responseState: DoubaoResponseState,
        generationID: UUID
    ) {
        self.session = session
        self.ws = ws
        self.responseState = responseState
        self.generationID = generationID
    }

    func debugSummary(now: Date = Date()) -> String {
        let age = String(format: "%.2f", now.timeIntervalSince(createdAt))
        let sinceLastPCM = lastPCMCallbackAt.map { String(format: "%.2f", now.timeIntervalSince($0)) } ?? "none"
        let sinceLastSent = lastAudioPacketSentAt.map { String(format: "%.2f", now.timeIntervalSince($0)) } ?? "none"
        let sinceLastServer = lastServerPacketAt.map { String(format: "%.2f", now.timeIntervalSince($0)) } ?? "none"
        return """
        ageSec=\(age), captureStarts=\(audioCaptureStartCount), captureReason=\(lastAudioCaptureStartReason), pcmCallbacks=\(pcmCallbackCount), audioPackets=\(audioPacketCount), serverPackets=\(serverPacketCount), pendingPCMBytes=\(pendingPCMData.count), lastSeq=\(lastAudioSequence), nextSeq=\(nextAudioSequence), sinceLastPCM=\(sinceLastPCM), sinceLastSent=\(sinceLastSent), sinceLastServer=\(sinceLastServer), isClosed=\(isClosed)
        """
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
