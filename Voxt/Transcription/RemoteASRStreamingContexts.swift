import Foundation

actor AsyncGate {
    private var isOpen = false

    func open() {
        isOpen = true
    }

    func wait() async {
        while !isOpen {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }
}

@MainActor
final class AliyunQwenStreamingContext {
    let session: URLSession
    let ws: URLSessionWebSocketTask
    let responseState: AliyunQwenResponseState
    let generationID: UUID
    let kind: AliyunQwenRealtimeSessionKind
    let createdAt = Date()
    var isClosed = false
    var didStartAudioStream = false
    var audioCaptureStartCount = 0
    var pcmCallbackCount = 0
    var audioPacketCount = 0
    var firstPCMCallbackAt: Date?
    var lastPCMCallbackAt: Date?
    var firstAudioPacketSentAt: Date?
    var lastAudioPacketSentAt: Date?
    var lastAudioCaptureStartReason = "not-started"

    init(
        session: URLSession,
        ws: URLSessionWebSocketTask,
        responseState: AliyunQwenResponseState,
        generationID: UUID,
        kind: AliyunQwenRealtimeSessionKind
    ) {
        self.session = session
        self.ws = ws
        self.responseState = responseState
        self.generationID = generationID
        self.kind = kind
    }

    func debugSummary(now: Date = Date()) -> String {
        let age = String(format: "%.2f", now.timeIntervalSince(createdAt))
        let sinceLastPCM = lastPCMCallbackAt.map { String(format: "%.2f", now.timeIntervalSince($0)) } ?? "none"
        let sinceLastSent = lastAudioPacketSentAt.map { String(format: "%.2f", now.timeIntervalSince($0)) } ?? "none"
        return """
        kind=\(kind), ageSec=\(age), captureStarts=\(audioCaptureStartCount), captureReason=\(lastAudioCaptureStartReason), pcmCallbacks=\(pcmCallbackCount), audioPackets=\(audioPacketCount), sinceLastPCM=\(sinceLastPCM), sinceLastSent=\(sinceLastSent), isClosed=\(isClosed)
        """
    }
}

actor AliyunQwenResponseState {
    private var committed: [String] = []
    private var partial = ""
    private var finishRequested = false
    private var sessionFinished = false
    private var completionError: Error?
    private let onError: @Sendable (Error) -> Void

    init(onError: @escaping @Sendable (Error) -> Void = { _ in }) {
        self.onError = onError
    }

    func markFinishRequested() {
        finishRequested = true
    }

    func markSessionFinished() {
        sessionFinished = true
    }

    func markCompletedWithError(_ error: Error) {
        if sessionFinished {
            return
        }
        if completionError == nil {
            completionError = error
            onError(error)
        }
    }

    func setPartial(_ value: String) -> String {
        partial = value
        return mergedText()
    }

    func commit(_ value: String) -> String {
        if committed.last != value {
            committed.append(value)
        }
        partial = ""
        return mergedText()
    }

    func waitForFinalResult(timeoutSeconds: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0))
        while !sessionFinished, completionError == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(120))
        }
        if let completionError {
            throw completionError
        }
        if finishRequested, !partial.isEmpty {
            if committed.last != partial {
                committed.append(partial)
            }
            partial = ""
        }
        return mergedText()
    }

    func currentText() -> String {
        mergedText()
    }

    private func mergedText() -> String {
        var values = committed
        if !partial.isEmpty {
            values.append(partial)
        }
        return values.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class AliyunFunStreamingContext {
    let session: URLSession
    let ws: URLSessionWebSocketTask
    let taskID: String
    let responseState: AliyunFunResponseState
    let generationID: UUID
    let createdAt = Date()
    var isClosed = false
    var didStartAudioStream = false
    var audioCaptureStartCount = 0
    var pcmCallbackCount = 0
    var audioPacketCount = 0
    var firstPCMCallbackAt: Date?
    var lastPCMCallbackAt: Date?
    var firstAudioPacketSentAt: Date?
    var lastAudioPacketSentAt: Date?
    var lastAudioCaptureStartReason = "not-started"

    init(
        session: URLSession,
        ws: URLSessionWebSocketTask,
        taskID: String,
        responseState: AliyunFunResponseState,
        generationID: UUID
    ) {
        self.session = session
        self.ws = ws
        self.taskID = taskID
        self.responseState = responseState
        self.generationID = generationID
    }

    func debugSummary(now: Date = Date()) -> String {
        let age = String(format: "%.2f", now.timeIntervalSince(createdAt))
        let sinceLastPCM = lastPCMCallbackAt.map { String(format: "%.2f", now.timeIntervalSince($0)) } ?? "none"
        let sinceLastSent = lastAudioPacketSentAt.map { String(format: "%.2f", now.timeIntervalSince($0)) } ?? "none"
        return """
        taskID=\(taskID), ageSec=\(age), captureStarts=\(audioCaptureStartCount), captureReason=\(lastAudioCaptureStartReason), pcmCallbacks=\(pcmCallbackCount), audioPackets=\(audioPacketCount), sinceLastPCM=\(sinceLastPCM), sinceLastSent=\(sinceLastSent), isClosed=\(isClosed)
        """
    }
}

actor AliyunFunResponseState {
    private var committedSegments: [String] = []
    private var livePartial = ""
    private var finishRequested = false
    private var taskFinished = false
    private var completionError: Error?
    private let onError: @Sendable (Error) -> Void

    init(onError: @escaping @Sendable (Error) -> Void = { _ in }) {
        self.onError = onError
    }

    func markRunRequested() {}

    func markFinishRequested() {
        finishRequested = true
    }

    func markTaskFinished() {
        taskFinished = true
    }

    func markCompletedWithError(_ error: Error) {
        if completionError == nil {
            completionError = error
            onError(error)
        }
    }

    func updateWithSentence(_ text: String, isSentenceEnd: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return joinedText()
        }
        if isSentenceEnd {
            if committedSegments.last != trimmed {
                committedSegments.append(trimmed)
            }
            livePartial = ""
        } else {
            livePartial = trimmed
        }
        return joinedText()
    }

    func waitForFinalResult(timeoutSeconds: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0))
        while !taskFinished, completionError == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(120))
        }
        if let completionError {
            throw completionError
        }
        if finishRequested, !livePartial.isEmpty {
            if committedSegments.last != livePartial {
                committedSegments.append(livePartial)
            }
            livePartial = ""
        }
        return joinedText()
    }

    func currentText() -> String {
        joinedText()
    }

    private func joinedText() -> String {
        var segments = committedSegments
        if !livePartial.isEmpty {
            segments.append(livePartial)
        }
        return segments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func remoteASRBigEndianData(_ value: UInt32) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

func remoteASRBigEndianData(_ value: Int32) -> Data {
    withUnsafeBytes(of: value.bigEndian) { Data($0) }
}

func remoteASRUInt32(fromBigEndian data: Data) -> UInt32 {
    precondition(data.count == 4)
    return data.reduce(UInt32(0)) { partial, byte in
        (partial << 8) | UInt32(byte)
    }
}

func remoteASRInt32(fromBigEndian data: Data) -> Int32 {
    Int32(bitPattern: remoteASRUInt32(fromBigEndian: data))
}
