import Foundation
import zlib

@MainActor
struct MeetingRemoteLiveSessionFactory: MeetingLiveSessionFactory {
    let provider: RemoteASRProvider
    let configuration: RemoteProviderConfiguration
    let hintPayload: ResolvedASRHintPayload

    func makeSession(
        for speaker: MeetingSpeaker,
        timelineOffsetSeconds: TimeInterval
    ) throws -> any MeetingLiveTranscribingSession {
        let policy = MeetingLiveSessionPolicy.resolved(
            provider: provider,
            configuration: configuration
        )
        switch provider {
        case .doubaoASR:
            return DoubaoMeetingRemoteLiveSession(
                speaker: speaker,
                configuration: configuration,
                hintPayload: hintPayload,
                timelineOffsetSeconds: timelineOffsetSeconds,
                policy: policy
            )
        case .aliyunBailianASR:
            if MeetingAliyunRemoteSupport.isQwenRealtimeModel(configuration.model) {
                return AliyunQwenMeetingRemoteLiveSession(
                    speaker: speaker,
                    configuration: configuration,
                    hintPayload: hintPayload,
                    timelineOffsetSeconds: timelineOffsetSeconds,
                    policy: policy
                )
            }
            return AliyunFunMeetingRemoteLiveSession(
                speaker: speaker,
                configuration: configuration,
                hintPayload: hintPayload,
                timelineOffsetSeconds: timelineOffsetSeconds,
                policy: policy
            )
        case .openAIWhisper, .glmASR:
            throw NSError(
                domain: "Voxt.Meeting",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "This remote provider does not support live meeting sessions."]
            )
        }
    }
}

@MainActor
private class BaseMeetingRemoteLiveSession: MeetingLiveTranscribingSession {
    let speaker: MeetingSpeaker
    let configuration: RemoteProviderConfiguration
    let hintPayload: ResolvedASRHintPayload
    let speechThreshold: Float
    let policy: MeetingLiveSessionPolicy

    private(set) var eventHandler: ((MeetingTranscriptEvent) -> Void)?
    private(set) var managedSocket: VoxtNetworkSession.ManagedWebSocketTask?
    private(set) var receiveTask: Task<Void, Never>?
    private(set) var isCancelled = false
    private(set) var isStopping = false
    private(set) var isReadyForAudio = false
    private(set) var pendingAudioPackets: [Data] = []
    private(set) var state: MeetingLiveSessionState = .connecting

    private var finishContinuation: CheckedContinuation<Void, Never>?
    private(set) var currentSegmentID: UUID?
    private(set) var currentSegmentStartSeconds: TimeInterval?
    private(set) var currentTranscriptText: String?
    private(set) var totalAudioSecondsSent: TimeInterval = 0
    private var lastSpeechAudioEndSeconds: TimeInterval?
    private var lastTranscriptEventAt: Date?
    private var transcriptState = MeetingLiveTranscriptState()
    private let timelineOffsetSeconds: TimeInterval
    private var hasLoggedFirstAudioPacket = false
    private var hasLoggedFirstServerPacket = false
    private var keepaliveTask: Task<Void, Never>?
    private var lastSpeechAt = Date()
    private var lastKeepaliveAt: Date?
    private var shouldLogNextSpeechAudioPacket = false
    private var hasBegunSpeechStreaming = false
    private var sentAudioPacketCount = 0

    init(
        speaker: MeetingSpeaker,
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload,
        speechThreshold: Float,
        timelineOffsetSeconds: TimeInterval,
        policy: MeetingLiveSessionPolicy
    ) {
        self.speaker = speaker
        self.configuration = configuration
        self.hintPayload = hintPayload
        self.speechThreshold = speechThreshold
        self.timelineOffsetSeconds = timelineOffsetSeconds
        self.policy = policy
    }

    func start(
        timelineOffsetSeconds _: TimeInterval,
        eventHandler: @escaping @MainActor (MeetingTranscriptEvent) -> Void
    ) async throws {
        self.eventHandler = eventHandler
        state = .connecting
        lastSpeechAt = Date()
        totalAudioSecondsSent = 0
        hasBegunSpeechStreaming = false
        transcriptState.resetCurrentItem()
        try await openTransport()
        startKeepaliveLoopIfNeeded()
    }

    func append(samples: [Float], sampleRate: Double) async {
        guard !isCancelled, !samples.isEmpty else { return }

        let normalizedLevel = AudioLevelMeter.normalizedLevel(fromSamples: samples)
        let startSeconds = totalAudioSecondsSent
        let duration = Double(samples.count) / max(sampleRate, 1)
        let isSpeech = normalizedLevel >= speechThreshold
        hasBegunSpeechStreaming = true
        if isSpeech {
            lastSpeechAt = Date()
            lastSpeechAudioEndSeconds = startSeconds + duration
            markSpeechIfNeeded(suggestedStartSeconds: startSeconds)
            shouldLogNextSpeechAudioPacket = true
            hasBegunSpeechStreaming = true
        } else if shouldSplitCurrentSegmentForSilence(at: startSeconds) {
            emitPendingFinalSegmentIfNeeded(endSeconds: timelineOffsetSeconds + startSeconds)
        }
        totalAudioSecondsSent += duration

        guard let pcmData = MeetingRemoteAudioSupport.makePCM16MonoData(from: samples, inputSampleRate: sampleRate) else {
            return
        }
        if isReadyForAudio {
            await sendAudioPacket(pcmData, isLast: false)
        } else {
            pendingAudioPackets.append(pcmData)
        }
    }

    func finish() async {
        guard !isCancelled else { return }
        isStopping = true
        state = .stopping
        stopKeepaliveLoop()
        if isReadyForAudio {
            await sendFinishSignal()
        }
        await waitForFinish(timeoutMilliseconds: 1_800)
        cancelTransport(closeCode: .normalClosure)
    }

    func cancel() async {
        guard !isCancelled else { return }
        isCancelled = true
        state = .failed
        stopKeepaliveLoop()
        signalFinished()
        cancelTransport(closeCode: .goingAway)
    }

    func openTransport() async throws {
        fatalError("Subclasses must override openTransport()")
    }

    func sendAudioPacket(_ pcmData: Data, isLast: Bool) async {
        fatalError("Subclasses must override sendAudioPacket(_:isLast:)")
    }

    func sendFinishSignal() async {
        fatalError("Subclasses must override sendFinishSignal()")
    }

    func flushPendingAudioIfNeeded() async {
        guard isReadyForAudio, !pendingAudioPackets.isEmpty else { return }
        let packets = pendingAudioPackets
        pendingAudioPackets.removeAll()
        for packet in packets {
            await sendAudioPacket(packet, isLast: false)
        }
    }

    func handleReadyForAudio() async {
        guard !isReadyForAudio, !isCancelled else { return }
        isReadyForAudio = true
        state = .active
        await flushPendingAudioIfNeeded()
    }

    func primeTransportForAudio() async {
        guard !isCancelled, !isStopping else { return }
        do {
            try await Task.sleep(for: .milliseconds(180))
        } catch {
            return
        }
        await handleReadyForAudio()
    }

    func emitTranscript(text: String, isFinal: Bool) {
        if shouldSplitCurrentSegmentForTextOutputGap() {
            emitPendingFinalSegmentIfNeeded()
        }
        let normalizedText = transcriptState.normalizedVisibleText(for: text)
        guard !normalizedText.isEmpty else {
            if isFinal {
                transcriptState.resetCurrentItem()
                resetCurrentSegment()
            }
            return
        }

        if currentSegmentID == nil {
            currentSegmentID = UUID()
            currentSegmentStartSeconds = max(timelineOffsetSeconds + totalAudioSecondsSent - 0.4, 0)
        }
        currentTranscriptText = normalizedText

        let segment = MeetingTranscriptSegment(
            id: currentSegmentID ?? UUID(),
            speaker: speaker,
            startSeconds: currentSegmentStartSeconds ?? max(timelineOffsetSeconds + totalAudioSecondsSent - 0.4, 0),
            endSeconds: max(timelineOffsetSeconds + totalAudioSecondsSent, currentSegmentStartSeconds ?? 0),
            text: normalizedText,
            preventsAdjacentMerge: true
        )
        eventHandler?(isFinal ? .final(segment) : .partial(segment))
        lastTranscriptEventAt = Date()

        if isFinal {
            resetCurrentSegment()
        }
    }

    func emitProviderPacket(_ packet: MeetingLiveProviderPacket) {
        if !packet.units.isEmpty {
            if let activeUnit = packet.units.last {
                emitProviderUnit(activeUnit, forceFinal: false)
            }
            if packet.isFinal {
                signalFinished()
            }
            return
        }

        if let fallbackText = packet.fallbackText,
           !fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emitTranscript(text: fallbackText, isFinal: packet.isFinal)
            return
        }

        if packet.isFinal {
            signalFinished()
        }
    }

    private func emitProviderUnit(_ unit: MeetingLiveProviderTranscriptUnit, forceFinal: Bool) {
        let text = unit.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if shouldSplitCurrentSegmentForTextOutputGap() {
            emitPendingFinalSegmentIfNeeded()
        }

        let normalizedText = transcriptState.normalizedVisibleText(for: text)
        guard !normalizedText.isEmpty else {
            if forceFinal {
                transcriptState.resetCurrentItem()
                resetCurrentSegment()
            }
            return
        }

        if currentSegmentID == nil {
            currentSegmentID = UUID()
            currentSegmentStartSeconds = resolvedProviderSegmentStartSeconds(for: unit)
        }
        currentTranscriptText = normalizedText

        let segment = MeetingTranscriptSegment(
            id: currentSegmentID ?? UUID(),
            speaker: speaker,
            startSeconds: currentSegmentStartSeconds ?? resolvedProviderSegmentStartSeconds(for: unit),
            endSeconds: resolvedProviderSegmentEndSeconds(
                for: unit,
                startSeconds: currentSegmentStartSeconds ?? resolvedProviderSegmentStartSeconds(for: unit)
            ),
            text: normalizedText,
            preventsAdjacentMerge: true
        )
        let shouldFinalizeNow = forceFinal
        eventHandler?(shouldFinalizeNow ? .final(segment) : .partial(segment))
        lastTranscriptEventAt = Date()

        if shouldFinalizeNow {
            resetCurrentSegment()
        }
    }

    func emitFailure(_ error: Error) {
        guard !isCancelled, !isStopping else {
            signalFinished()
            return
        }
        state = .failed
        let nsError = error as NSError
        let message = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        eventHandler?(.failed(speaker: speaker, message: message.isEmpty ? "Unknown live meeting ASR error." : message))
        signalFinished()
    }

    func finishReceiveLoop(_ task: Task<Void, Never>) {
        receiveTask = task
    }

    func registerSocket(_ socket: VoxtNetworkSession.ManagedWebSocketTask) {
        managedSocket = socket
    }

    func socketTask() -> URLSessionWebSocketTask? {
        managedSocket?.task
    }

    func cancelTransport(closeCode: URLSessionWebSocketTask.CloseCode) {
        stopKeepaliveLoop()
        receiveTask?.cancel()
        receiveTask = nil
        if let task = managedSocket?.task {
            task.cancel(with: closeCode, reason: nil)
        }
        managedSocket?.session.invalidateAndCancel()
        managedSocket = nil
    }

    private func markSpeechIfNeeded(suggestedStartSeconds: TimeInterval) {
        guard currentSegmentID == nil else { return }
        currentSegmentID = UUID()
        currentSegmentStartSeconds = timelineOffsetSeconds + suggestedStartSeconds
    }

    private func resetCurrentSegment() {
        currentSegmentID = nil
        currentSegmentStartSeconds = nil
        currentTranscriptText = nil
        lastTranscriptEventAt = nil
        transcriptState.resetCurrentItem()
    }

    private func waitForFinish(timeoutMilliseconds: UInt64) async {
        if finishContinuation == nil {
            await withCheckedContinuation { continuation in
                finishContinuation = continuation
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: timeoutMilliseconds * 1_000_000)
                    self?.signalFinished()
                }
            }
        }
    }

    func signalFinished() {
        stopKeepaliveLoop()
        emitPendingFinalSegmentIfNeeded()
        finishContinuation?.resume()
        finishContinuation = nil
        eventHandler?(.finished(speaker: speaker))
    }

    private func emitPendingFinalSegmentIfNeeded(endSeconds explicitEndSeconds: TimeInterval? = nil) {
        guard let currentSegmentID,
              let currentSegmentStartSeconds,
              let text = currentTranscriptText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return
        }

        let segment = MeetingTranscriptSegment(
            id: currentSegmentID,
            speaker: speaker,
            startSeconds: currentSegmentStartSeconds,
            endSeconds: max(
                explicitEndSeconds ?? timelineOffsetSeconds + totalAudioSecondsSent,
                currentSegmentStartSeconds
            ),
            text: text,
            preventsAdjacentMerge: true
        )
        transcriptState.freezeCurrentItem(text: text)
        eventHandler?(.final(segment))
        resetCurrentSegment()
    }

    private func shouldSplitCurrentSegmentForSilence(at currentAudioSeconds: TimeInterval) -> Bool {
        guard policy.segmentSilenceSplitThreshold > 0,
              currentSegmentID != nil,
              currentTranscriptText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let lastSpeechAudioEndSeconds
        else {
            return false
        }
        return currentAudioSeconds - lastSpeechAudioEndSeconds >= policy.segmentSilenceSplitThreshold
    }

    private func shouldSplitCurrentSegmentForTextOutputGap() -> Bool {
        guard policy.segmentSilenceSplitThreshold > 0,
              currentSegmentID != nil,
              currentTranscriptText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let lastTranscriptEventAt
        else {
            return false
        }
        return Date().timeIntervalSince(lastTranscriptEventAt) >= policy.segmentSilenceSplitThreshold
    }

    func logFirstAudioPacketIfNeeded(kind: String) {
        guard !hasLoggedFirstAudioPacket else { return }
        hasLoggedFirstAudioPacket = true
        VoxtLog.info("Meeting live audio started. provider=\(kind), speaker=\(speaker.rawValue)")
    }

    func logOutgoingAudioPacketIfNeeded(kind: String, sequence: Int32, payloadBytes: Int) {
        guard sentAudioPacketCount < 5 else { return }
        sentAudioPacketCount += 1
        VoxtLog.info(
            "Meeting live audio packet sent. provider=\(kind), speaker=\(speaker.rawValue), sequence=\(sequence), payloadBytes=\(payloadBytes)"
        )
    }

    func consumeShouldLogNextSpeechAudioPacket() -> Bool {
        defer { shouldLogNextSpeechAudioPacket = false }
        return shouldLogNextSpeechAudioPacket
    }

    func logServerPacketIfNeeded(kind: String, parsed: (text: String?, isFinal: Bool, sequence: Int32?)?) {
        let textCount = parsed?.text?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0
        if !hasLoggedFirstServerPacket {
            hasLoggedFirstServerPacket = true
            VoxtLog.info(
                "Meeting live server packet received. provider=\(kind), speaker=\(speaker.rawValue), textChars=\(textCount), isFinal=\(parsed?.isFinal == true), sequence=\(parsed?.sequence.map(String.init) ?? "nil")"
            )
            return
        }
        if textCount > 0 || parsed?.isFinal == true {
            VoxtLog.info(
                "Meeting live transcript event. provider=\(kind), speaker=\(speaker.rawValue), textChars=\(textCount), isFinal=\(parsed?.isFinal == true), sequence=\(parsed?.sequence.map(String.init) ?? "nil")",
                verbose: true
            )
        }
    }

    private func startKeepaliveLoopIfNeeded() {
        guard policy.idleKeepaliveEnabled, keepaliveTask == nil else { return }
        keepaliveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !self.isCancelled, !self.isStopping {
                do {
                    try await Task.sleep(for: .milliseconds(800))
                } catch {
                    return
                }
                await self.sendKeepaliveIfNeeded()
            }
        }
    }

    private func stopKeepaliveLoop() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
    }

    private func sendKeepaliveIfNeeded() async {
        guard policy.idleKeepaliveEnabled,
              isReadyForAudio,
              state == .active,
              !isCancelled,
              !isStopping,
              hasBegunSpeechStreaming
        else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastSpeechAt) >= policy.idleKeepaliveInterval else { return }
        if let lastKeepaliveAt,
           now.timeIntervalSince(lastKeepaliveAt) < max(policy.idleKeepaliveInterval - 0.5, 0.5) {
            return
        }

        let sampleCount = max(Int(16_000 * policy.idleKeepaliveFrameDuration), 1)
        let silenceSamples = [Float](repeating: 0, count: sampleCount)
        guard let silenceData = MeetingRemoteAudioSupport.makePCM16MonoData(from: silenceSamples, inputSampleRate: 16_000) else {
            return
        }
        lastKeepaliveAt = now
        await sendAudioPacket(silenceData, isLast: false)
    }

    private func resolvedProviderSegmentStartSeconds(
        for unit: MeetingLiveProviderTranscriptUnit
    ) -> TimeInterval {
        let relativeStart = unit.startSeconds ?? max(totalAudioSecondsSent - 0.4, 0)
        return max(timelineOffsetSeconds + relativeStart, 0)
    }

    private func resolvedProviderSegmentEndSeconds(
        for unit: MeetingLiveProviderTranscriptUnit,
        startSeconds: TimeInterval
    ) -> TimeInterval {
        let relativeEnd = unit.endSeconds ?? totalAudioSecondsSent
        return max(timelineOffsetSeconds + relativeEnd, startSeconds)
    }
}

@MainActor
private final class DoubaoMeetingRemoteLiveSession: BaseMeetingRemoteLiveSession {
    private let resourceID: String
    private let endpoint: String
    private let appID: String
    private let accessToken: String

    init(
        speaker: MeetingSpeaker,
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload,
        timelineOffsetSeconds: TimeInterval,
        policy: MeetingLiveSessionPolicy
    ) {
        self.resourceID = DoubaoASRConfiguration.resolvedResourceID(configuration.model)
        self.endpoint = DoubaoASRConfiguration.resolvedStreamingEndpoint(configuration.endpoint, model: configuration.model)
        self.appID = configuration.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessToken = configuration.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        super.init(
            speaker: speaker,
            configuration: configuration,
            hintPayload: hintPayload,
            speechThreshold: speaker == .me ? 0.015 : 0.025,
            timelineOffsetSeconds: timelineOffsetSeconds,
            policy: policy
        )
    }

    override func openTransport() async throws {
        guard !accessToken.isEmpty else {
            throw NSError(domain: "Voxt.Meeting", code: -10, userInfo: [NSLocalizedDescriptionKey: "Doubao Access Token is empty."])
        }
        guard !appID.isEmpty else {
            throw NSError(domain: "Voxt.Meeting", code: -11, userInfo: [NSLocalizedDescriptionKey: "Doubao App ID is empty."])
        }
        guard let wsURL = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Meeting", code: -12, userInfo: [NSLocalizedDescriptionKey: "Invalid Doubao WebSocket endpoint URL."])
        }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 45
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")
        VoxtLog.info(
            "Meeting Doubao live connect. endpoint=\(endpoint), resource=\(resourceID), speaker=\(speaker.rawValue), proxyMode=\(VoxtNetworkSession.modeDescription)"
        )

        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        registerSocket(managedSocket)
        managedSocket.task.resume()
        startReceiveLoop()
        try await sendDoubaoFullRequest(on: managedSocket.task)
    }

    override func sendAudioPacket(_ pcmData: Data, isLast: Bool) async {
        guard let ws = socketTask() else { return }
        do {
            let (audioCompression, audioPayload) = try MeetingRemoteAudioSupport.encodeDoubaoPayload(pcmData)
            let packet = MeetingRemoteAudioSupport.buildDoubaoPacket(
                messageType: MeetingRemoteAudioSupport.DoubaoProtocol.messageTypeAudioOnlyClientRequest,
                messageFlags: isLast
                    ? MeetingRemoteAudioSupport.DoubaoProtocol.flagLastAudioPacket
                    : MeetingRemoteAudioSupport.DoubaoProtocol.flagNoSequence,
                serialization: MeetingRemoteAudioSupport.DoubaoProtocol.serializationNone,
                compression: audioCompression,
                sequence: 0,
                payload: audioPayload
            )
            try await ws.send(.data(packet))
            if !isLast {
                logOutgoingAudioPacketIfNeeded(kind: "doubao", sequence: 0, payloadBytes: audioPayload.count)
            }
            if !isLast, consumeShouldLogNextSpeechAudioPacket() {
                logFirstAudioPacketIfNeeded(kind: "doubao")
            }
        } catch {
            emitFailure(error)
            await cancel()
        }
    }

    override func sendFinishSignal() async {
        await sendAudioPacket(Data(), isLast: true)
    }

    private func sendDoubaoFullRequest(on ws: URLSessionWebSocketTask) async throws {
        let reqID = UUID().uuidString.lowercased()
        let streamingHintPayload = ResolvedASRHintPayload(
            language: nil,
            languageHints: hintPayload.languageHints,
            chineseOutputVariant: hintPayload.chineseOutputVariant,
            prompt: hintPayload.prompt
        )
        let packet = try MeetingRemoteAudioSupport.buildDoubaoFullRequestPacket(
            reqID: reqID,
            sequence: 1,
            hintPayload: streamingHintPayload,
            audioFormat: DoubaoASRConfiguration.streamingAudioFormat
        )
        try await ws.send(.data(packet))
    }

    private func startReceiveLoop() {
        guard let ws = socketTask() else { return }
        finishReceiveLoop(
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    while !Task.isCancelled {
                        let message = try await ws.receive()
                        guard case .data(let payloadData) = message else { continue }
                        if let packet = try MeetingRemoteAudioSupport.parseDoubaoServerPacket(payloadData) {
                            self.logServerPacketIfNeeded(
                                kind: "doubao",
                                parsed: (
                                    text: packet.units.last?.text ?? packet.fallbackText,
                                    isFinal: packet.isFinal,
                                    sequence: packet.sequence
                                )
                            )
                            await self.handleReadyForAudio()
                            self.emitProviderPacket(packet)
                        }
                    }
                } catch {
                    if self.isStopping || self.isCancelled || self.shouldTreatAsBenignSocketClosure(error) {
                        self.signalFinished()
                    } else {
                        self.emitFailure(error)
                    }
                }
            }
        )
    }

    private func shouldTreatAsBenignSocketClosure(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == 57 {
            return true
        }
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorCancelled,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNotConnectedToInternet
            ].contains(nsError.code)
        }
        return false
    }
}

@MainActor
private final class AliyunFunMeetingRemoteLiveSession: BaseMeetingRemoteLiveSession {
    private let endpoint: String
    private let token: String
    private let model: String
    private let taskID = UUID().uuidString.lowercased()

    init(
        speaker: MeetingSpeaker,
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload,
        timelineOffsetSeconds: TimeInterval,
        policy: MeetingLiveSessionPolicy
    ) {
        self.token = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? RemoteASRProvider.aliyunBailianASR.suggestedModel
            : configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = MeetingAliyunRemoteSupport.resolvedFunRealtimeEndpoint(configuration.endpoint)
        super.init(
            speaker: speaker,
            configuration: configuration,
            hintPayload: hintPayload,
            speechThreshold: speaker == .me ? 0.015 : 0.025,
            timelineOffsetSeconds: timelineOffsetSeconds,
            policy: policy
        )
    }

    override func openTransport() async throws {
        guard !token.isEmpty else {
            throw NSError(domain: "Voxt.Meeting", code: -20, userInfo: [NSLocalizedDescriptionKey: "Aliyun Bailian API key is empty."])
        }
        guard let wsURL = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Meeting", code: -21, userInfo: [NSLocalizedDescriptionKey: "Invalid Aliyun realtime WebSocket endpoint URL."])
        }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        VoxtLog.info(
            "Meeting Aliyun Fun live connect. endpoint=\(endpoint), model=\(model), speaker=\(speaker.rawValue), proxyMode=\(VoxtNetworkSession.modeDescription)"
        )

        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        registerSocket(managedSocket)
        managedSocket.task.resume()
        startReceiveLoop()
        try await sendRunTask(on: managedSocket.task)
        await primeTransportForAudio()
    }

    override func sendAudioPacket(_ pcmData: Data, isLast: Bool) async {
        guard !isLast, let ws = socketTask() else { return }
        do {
            try await ws.send(.data(pcmData))
            if consumeShouldLogNextSpeechAudioPacket() {
                logFirstAudioPacketIfNeeded(kind: "aliyunFun")
            }
        } catch {
            emitFailure(error)
            await cancel()
        }
    }

    override func sendFinishSignal() async {
        guard let ws = socketTask() else { return }
        do {
            try await sendControl(action: "finish-task", on: ws)
        } catch {
            emitFailure(error)
        }
    }

    private func sendRunTask(on ws: URLSessionWebSocketTask) async throws {
        var parameters: [String: Any] = [
            "sample_rate": 16000,
            "format": "pcm"
        ]
        if !hintPayload.languageHints.isEmpty {
            parameters["language_hints"] = hintPayload.languageHints
        }
        let payload: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": taskID
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": model,
                "parameters": parameters,
                "input": [:]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Voxt.Meeting", code: -22, userInfo: [NSLocalizedDescriptionKey: "Failed to encode Aliyun run-task payload."])
        }
        try await ws.send(.string(text))
    }

    private func sendControl(action: String, on ws: URLSessionWebSocketTask) async throws {
        let payload: [String: Any] = [
            "header": [
                "action": action,
                "task_id": taskID
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Voxt.Meeting", code: -23, userInfo: [NSLocalizedDescriptionKey: "Failed to encode Aliyun control payload."])
        }
        try await ws.send(.string(text))
    }

    private func startReceiveLoop() {
        guard let ws = socketTask() else { return }
        finishReceiveLoop(
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    while !Task.isCancelled {
                        let message = try await ws.receive()
                        let text: String?
                        switch message {
                        case .string(let string):
                            text = string
                        case .data(let data):
                            text = String(data: data, encoding: .utf8)
                        @unknown default:
                            text = nil
                        }
                        guard let text,
                              let data = text.data(using: .utf8),
                              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else {
                            continue
                        }
                        let event = (object["event"] as? String ?? "").lowercased()
                        let payload = object["payload"] as? [String: Any] ?? [:]

                        if event == "task-started" {
                            self.logServerPacketIfNeeded(kind: "aliyunFun", parsed: nil)
                            await self.handleReadyForAudio()
                            continue
                        }
                        if event == "task-finished" {
                            self.signalFinished()
                            break
                        }
                        if event == "task-failed" || event == "error" {
                            let detail = (payload["message"] as? String)
                                ?? (object["message"] as? String)
                                ?? "Aliyun fun ASR task failed."
                            self.emitFailure(NSError(domain: "Voxt.Meeting", code: -24, userInfo: [NSLocalizedDescriptionKey: detail]))
                            break
                        }
                        if event == "result-generated" {
                            let sentence = (payload["output"] as? [String: Any]).flatMap { output in
                                output["sentence"] as? [String: Any]
                            } ?? [:]
                            let partialText = (sentence["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            let isSentenceEnd = sentence["sentence_end"] as? Bool ?? false
                            if !partialText.isEmpty {
                                let unit = MeetingRemoteAudioSupport.makeAliyunSentenceUnit(
                                    sentence: sentence,
                                    fallbackText: partialText,
                                    isFinal: isSentenceEnd
                                )
                                self.logServerPacketIfNeeded(
                                    kind: "aliyunFun",
                                    parsed: (text: partialText, isFinal: isSentenceEnd, sequence: nil)
                                )
                                if let unit {
                                    self.emitProviderPacket(
                                        MeetingLiveProviderPacket(
                                            units: [unit],
                                            fallbackText: nil,
                                            isFinal: false,
                                            sequence: nil
                                        )
                                    )
                                } else {
                                    self.emitTranscript(text: partialText, isFinal: isSentenceEnd)
                                }
                            }
                        }
                    }
                } catch {
                    if self.isStopping || self.isCancelled || self.shouldTreatAsBenignSocketClosure(error) {
                        self.signalFinished()
                    } else {
                        self.emitFailure(error)
                    }
                }
            }
        )
    }

    private func shouldTreatAsBenignSocketClosure(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [NSURLErrorCancelled, NSURLErrorNetworkConnectionLost].contains(nsError.code)
        }
        return false
    }
}

@MainActor
private final class AliyunQwenMeetingRemoteLiveSession: BaseMeetingRemoteLiveSession {
    private let endpoint: String
    private let token: String

    init(
        speaker: MeetingSpeaker,
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload,
        timelineOffsetSeconds: TimeInterval,
        policy: MeetingLiveSessionPolicy
    ) {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "qwen3-asr-flash-realtime"
            : configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = MeetingAliyunRemoteSupport.resolvedQwenRealtimeEndpoint(configuration.endpoint, model: model)
        super.init(
            speaker: speaker,
            configuration: configuration,
            hintPayload: hintPayload,
            speechThreshold: speaker == .me ? 0.015 : 0.025,
            timelineOffsetSeconds: timelineOffsetSeconds,
            policy: policy
        )
    }

    override func openTransport() async throws {
        guard !token.isEmpty else {
            throw NSError(domain: "Voxt.Meeting", code: -30, userInfo: [NSLocalizedDescriptionKey: "Aliyun Bailian API key is empty."])
        }
        guard let wsURL = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.Meeting", code: -31, userInfo: [NSLocalizedDescriptionKey: "Invalid Aliyun Qwen realtime WebSocket endpoint URL."])
        }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        VoxtLog.info(
            "Meeting Aliyun Qwen live connect. endpoint=\(endpoint), speaker=\(speaker.rawValue), proxyMode=\(VoxtNetworkSession.modeDescription)"
        )

        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        registerSocket(managedSocket)
        managedSocket.task.resume()
        startReceiveLoop()
        try await sendSessionUpdate(on: managedSocket.task)
        await primeTransportForAudio()
    }

    override func sendAudioPacket(_ pcmData: Data, isLast: Bool) async {
        guard !isLast, let ws = socketTask() else { return }
        let payload: [String: Any] = [
            "event_id": UUID().uuidString.lowercased(),
            "type": "input_audio_buffer.append",
            "audio": pcmData.base64EncodedString()
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "Voxt.Meeting", code: -32, userInfo: [NSLocalizedDescriptionKey: "Failed to encode Aliyun Qwen audio event."])
            }
            try await ws.send(.string(text))
            if consumeShouldLogNextSpeechAudioPacket() {
                logFirstAudioPacketIfNeeded(kind: "aliyunQwen")
            }
        } catch {
            emitFailure(error)
            await cancel()
        }
    }

    override func sendFinishSignal() async {
        guard let ws = socketTask() else { return }
        let payload: [String: Any] = [
            "event_id": UUID().uuidString.lowercased(),
            "type": "session.finish"
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "Voxt.Meeting", code: -33, userInfo: [NSLocalizedDescriptionKey: "Failed to encode Aliyun Qwen finish event."])
            }
            try await ws.send(.string(text))
        } catch {
            emitFailure(error)
        }
    }

    private func sendSessionUpdate(on ws: URLSessionWebSocketTask) async throws {
        var transcriptionPayload: [String: Any] = [:]
        if let language = hintPayload.language?.trimmingCharacters(in: .whitespacesAndNewlines),
           !language.isEmpty {
            transcriptionPayload["language"] = language
        }
        let payload: [String: Any] = [
            "event_id": UUID().uuidString.lowercased(),
            "type": "session.update",
            "session": [
                "modalities": ["text"],
                "input_audio_format": "pcm",
                "sample_rate": 16000,
                "input_audio_transcription": transcriptionPayload,
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.0,
                    "silence_duration_ms": 400
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "Voxt.Meeting", code: -34, userInfo: [NSLocalizedDescriptionKey: "Failed to encode Aliyun Qwen session update."])
        }
        try await ws.send(.string(text))
    }

    private func startReceiveLoop() {
        guard let ws = socketTask() else { return }
        finishReceiveLoop(
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    while !Task.isCancelled {
                        let message = try await ws.receive()
                        let text: String?
                        switch message {
                        case .string(let string):
                            text = string
                        case .data(let data):
                            text = String(data: data, encoding: .utf8)
                        @unknown default:
                            text = nil
                        }
                        guard let text,
                              let data = text.data(using: .utf8),
                              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else {
                            continue
                        }
                        let type = (object["type"] as? String ?? "").lowercased()
                        if type == "session.updated" {
                            self.logServerPacketIfNeeded(kind: "aliyunQwen", parsed: nil)
                            await self.handleReadyForAudio()
                            continue
                        }
                        if type == "conversation.item.input_audio_transcription.text" {
                            let partial = (object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !partial.isEmpty {
                                self.logServerPacketIfNeeded(kind: "aliyunQwen", parsed: (text: partial, isFinal: false, sequence: nil))
                                if let unit = MeetingRemoteAudioSupport.makeAliyunQwenUnit(
                                    object: object,
                                    fallbackText: partial,
                                    isFinal: false
                                ) {
                                    self.emitProviderPacket(
                                        MeetingLiveProviderPacket(
                                            units: [unit],
                                            fallbackText: nil,
                                            isFinal: false,
                                            sequence: nil
                                        )
                                    )
                                } else {
                                    self.emitTranscript(text: partial, isFinal: false)
                                }
                            }
                            continue
                        }
                        if type == "conversation.item.input_audio_transcription.completed" {
                            let final = (object["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !final.isEmpty {
                                self.logServerPacketIfNeeded(kind: "aliyunQwen", parsed: (text: final, isFinal: true, sequence: nil))
                                if let unit = MeetingRemoteAudioSupport.makeAliyunQwenUnit(
                                    object: object,
                                    fallbackText: final,
                                    isFinal: true
                                ) {
                                    self.emitProviderPacket(
                                        MeetingLiveProviderPacket(
                                            units: [unit],
                                            fallbackText: nil,
                                            isFinal: false,
                                            sequence: nil
                                        )
                                    )
                                } else {
                                    self.emitTranscript(text: final, isFinal: true)
                                }
                            }
                            continue
                        }
                        if type == "session.finished" {
                            self.signalFinished()
                            break
                        }
                        if type == "error" {
                            let detail = (object["message"] as? String) ?? "Aliyun Qwen realtime ASR task failed."
                            self.emitFailure(NSError(domain: "Voxt.Meeting", code: -35, userInfo: [NSLocalizedDescriptionKey: detail]))
                            break
                        }
                    }
                } catch {
                    if self.isStopping || self.isCancelled || self.shouldTreatAsBenignSocketClosure(error) {
                        self.signalFinished()
                    } else {
                        self.emitFailure(error)
                    }
                }
            }
        )
    }

    private func shouldTreatAsBenignSocketClosure(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [NSURLErrorCancelled, NSURLErrorNetworkConnectionLost].contains(nsError.code)
        }
        return false
    }
}

private enum MeetingAliyunRemoteSupport {
    static func isQwenRealtimeModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("qwen3-asr-flash-realtime")
    }

    static func resolvedFunRealtimeEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
        }
        if let url = URL(string: trimmed) {
            let normalizedPath = url.path.lowercased()
            if normalizedPath.hasSuffix("/api-ws/v1/inference") {
                return trimmed
            }
            if normalizedPath.hasSuffix("/models") {
                return replacingPathSuffix(in: trimmed, oldSuffix: "/models", newSuffix: "/api-ws/v1/inference")
            }
            if normalizedPath.hasSuffix("/chat/completions") {
                return replacingPathSuffix(in: trimmed, oldSuffix: "/chat/completions", newSuffix: "/api-ws/v1/inference")
            }
            if normalizedPath.hasSuffix("/v1") {
                return appendingPath(trimmed, suffix: "/inference")
            }
        }
        return trimmed
    }

    static func resolvedQwenRealtimeEndpoint(_ endpoint: String, model: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? model

        guard !trimmed.isEmpty else {
            return "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=\(encodedModel)"
        }
        guard var components = URLComponents(string: trimmed) else {
            return trimmed
        }
        let normalizedPath = components.path.lowercased()
        if normalizedPath.hasSuffix("/api-ws/v1/realtime") {
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "model" }) {
                items.append(URLQueryItem(name: "model", value: model))
                components.queryItems = items
            }
            return components.string ?? trimmed
        }
        if normalizedPath.hasSuffix("/api-ws/v1/inference") {
            components.path = components.path.replacingOccurrences(of: "/api-ws/v1/inference", with: "/api-ws/v1/realtime")
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "model" }) {
                items.append(URLQueryItem(name: "model", value: model))
            }
            components.queryItems = items
            return components.string ?? trimmed
        }
        if normalizedPath.hasSuffix("/chat/completions") {
            let base = replacingPathSuffix(in: trimmed, oldSuffix: "/chat/completions", newSuffix: "/api-ws/v1/realtime")
            return base.contains("?") ? base : "\(base)?model=\(encodedModel)"
        }
        return trimmed
    }

    private static func appendingPath(_ value: String, suffix: String) -> String {
        value.hasSuffix("/") ? value + suffix.dropFirst() : value + suffix
    }

    private static func replacingPathSuffix(in value: String, oldSuffix: String, newSuffix: String) -> String {
        guard value.lowercased().hasSuffix(oldSuffix) else { return value }
        return String(value.dropLast(oldSuffix.count)) + newSuffix
    }
}

private enum MeetingRemoteAudioSupport {
    enum DoubaoProtocol {
        static let version: UInt8 = 0x1
        static let headerSize: UInt8 = 0x1
        static let messageTypeFullClientRequest: UInt8 = 0x1
        static let messageTypeAudioOnlyClientRequest: UInt8 = 0x2
        static let messageTypeFullServerResponse: UInt8 = 0x9
        static let messageTypeServerAck: UInt8 = 0xB
        static let messageTypeServerErrorResponse: UInt8 = 0xF
        static let flagNoSequence: UInt8 = 0x0
        static let flagPositiveSequence: UInt8 = 0x1
        static let flagLastAudioPacket: UInt8 = 0x2
        static let flagNegativeAudioPacket: UInt8 = flagPositiveSequence | flagLastAudioPacket
        static let flagEvent: UInt8 = 0x4
        static let serializationNone: UInt8 = 0x0
        static let serializationJSON: UInt8 = 0x1
        static let compressionNone: UInt8 = 0x0
        static let compressionGzip: UInt8 = 0x1
    }

    static func makePCM16MonoData(from samples: [Float], inputSampleRate: Double) -> Data? {
        guard !samples.isEmpty, inputSampleRate > 0 else { return nil }
        let targetRate = 16000.0
        let ratio = targetRate / inputSampleRate
        let outputCount = max(Int(Double(samples.count) * ratio), 1)
        var data = Data(count: outputCount * MemoryLayout<Int16>.size)
        data.withUnsafeMutableBytes { rawBuffer in
            let out = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<outputCount {
                let sourcePosition = Double(index) / ratio
                let sourceIndex = min(Int(sourcePosition.rounded(.down)), samples.count - 1)
                let clamped = max(-1.0, min(1.0, samples[sourceIndex]))
                out[index] = Int16(clamped * Float(Int16.max))
            }
        }
        return data
    }

    static func buildDoubaoFullRequestPacket(
        reqID: String,
        sequence: Int32,
        hintPayload: ResolvedASRHintPayload,
        audioFormat: String
    ) throws -> Data {
        let payloadObject = DoubaoASRConfiguration.fullRequestPayload(
            requestID: reqID,
            userID: "voxt-meeting",
            language: hintPayload.language,
            chineseOutputVariant: hintPayload.chineseOutputVariant,
            audioFormat: audioFormat
        )
        let rawPayload = try JSONSerialization.data(withJSONObject: payloadObject)
        let (compression, payload) = try encodeDoubaoPayload(rawPayload)
        return buildDoubaoPacket(
            messageType: DoubaoProtocol.messageTypeFullClientRequest,
            messageFlags: DoubaoProtocol.flagPositiveSequence,
            serialization: DoubaoProtocol.serializationJSON,
            compression: compression,
            sequence: sequence,
            payload: payload
        )
    }

    static func encodeDoubaoPayload(_ payload: Data) throws -> (compression: UInt8, payload: Data) {
        guard !payload.isEmpty else {
            return (DoubaoProtocol.compressionNone, payload)
        }
        return (DoubaoProtocol.compressionGzip, try gzipCompress(payload))
    }

    static func buildDoubaoPacket(
        messageType: UInt8,
        messageFlags: UInt8,
        serialization: UInt8,
        compression: UInt8,
        sequence: Int32,
        payload: Data
    ) -> Data {
        var data = Data()
        data.append((DoubaoProtocol.version << 4) | DoubaoProtocol.headerSize)
        data.append((messageType << 4) | messageFlags)
        data.append((serialization << 4) | compression)
        data.append(0x00)
        if (messageFlags & DoubaoProtocol.flagPositiveSequence) != 0 {
            data.append(sequence.bigEndianData)
        }
        data.append(UInt32(payload.count).bigEndianData)
        data.append(payload)
        return data
    }

    static func parseDoubaoServerPacket(_ data: Data) throws -> MeetingLiveProviderPacket? {
        guard data.count >= 8 else { return nil }

        let byte0 = data[0]
        let byte1 = data[1]
        let byte2 = data[2]
        let headerSizeWords = Int(byte0 & 0x0F)
        let headerSizeBytes = max(4, headerSizeWords * 4)
        guard data.count >= headerSizeBytes else { return nil }

        let messageType = (byte1 >> 4) & 0x0F
        let messageFlags = byte1 & 0x0F
        let compression = byte2 & 0x0F
        guard messageType == DoubaoProtocol.messageTypeFullServerResponse ||
                messageType == DoubaoProtocol.messageTypeServerAck ||
                messageType == DoubaoProtocol.messageTypeServerErrorResponse else {
            return nil
        }

        let hasSequence = (messageFlags & 0x1) != 0 || (messageFlags & 0x2) != 0
        let hasEvent = (messageFlags & DoubaoProtocol.flagEvent) != 0
        var cursor = headerSizeBytes

        var headerSequence: Int32?
        if hasSequence {
            guard data.count >= cursor + 4 else { return nil }
            headerSequence = Int32(bigEndianData: data.subdata(in: cursor..<(cursor + 4)))
            cursor += 4
        }
        if hasEvent {
            guard data.count >= cursor + 4 else { return nil }
            cursor += 4
        }

        let rawPayload: Data
        switch messageType {
        case DoubaoProtocol.messageTypeFullServerResponse:
            guard data.count >= cursor + 4 else { return nil }
            let payloadSize = Int(UInt32(bigEndianData: data.subdata(in: cursor..<(cursor + 4))))
            cursor += 4
            guard payloadSize >= 0, data.count >= cursor + payloadSize else { return nil }
            rawPayload = data.subdata(in: cursor..<(cursor + payloadSize))
        case DoubaoProtocol.messageTypeServerErrorResponse:
            guard data.count >= cursor + 8 else { return nil }
            cursor += 4
            let payloadSize = Int(UInt32(bigEndianData: data.subdata(in: cursor..<(cursor + 4))))
            cursor += 4
            guard payloadSize >= 0, data.count >= cursor + payloadSize else { return nil }
            rawPayload = data.subdata(in: cursor..<(cursor + payloadSize))
        case DoubaoProtocol.messageTypeServerAck:
            rawPayload = data.count > cursor ? data.subdata(in: cursor..<data.count) : Data()
        default:
            return nil
        }

        let payload: Data
        switch compression {
        case DoubaoProtocol.compressionNone:
            payload = rawPayload
        case DoubaoProtocol.compressionGzip:
            payload = (try? gunzip(rawPayload)) ?? rawPayload
        default:
            payload = rawPayload
        }

        if messageType == DoubaoProtocol.messageTypeServerErrorResponse {
            let errorText = String(data: payload, encoding: .utf8) ?? "Unknown Doubao server error."
            throw NSError(domain: "Voxt.Meeting", code: -40, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        guard !payload.isEmpty else {
            let isFinal = (messageFlags & DoubaoProtocol.flagLastAudioPacket) != 0 || (headerSequence ?? 1) < 0
            return MeetingLiveProviderPacket(units: [], fallbackText: nil, isFinal: isFinal, sequence: headerSequence)
        }
        guard let object = try? JSONSerialization.jsonObject(with: payload) else {
            let raw = String(data: payload, encoding: .utf8)
            return MeetingLiveProviderPacket(units: [], fallbackText: raw, isFinal: false, sequence: headerSequence)
        }
        let sequenceFromJSON = extractSequence(in: object)
        let isFinal = (messageFlags & DoubaoProtocol.flagLastAudioPacket) != 0
            || isLastPackage(in: object) == true
            || (sequenceFromJSON ?? headerSequence ?? 1) < 0
        let fragment = extractDoubaoText(in: object)
        let units = extractDoubaoUtteranceUnits(in: object, defaultIsFinal: isFinal)
        let hasUtteranceContainers = containsRecursiveKey("utterances", in: object)
        return MeetingLiveProviderPacket(
            units: units,
            fallbackText: hasUtteranceContainers ? nil : fragment,
            isFinal: isFinal,
            sequence: sequenceFromJSON ?? headerSequence
        )
    }

    private static func gzipCompress(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }
        return try data.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return data
            }

            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(OpaquePointer(input))
            stream.avail_in = uInt(data.count)

            let initStatus = deflateInit2_(
                &stream,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                MAX_WBITS + 16,
                MAX_MEM_LEVEL,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            guard initStatus == Z_OK else {
                throw NSError(domain: "Voxt.Meeting", code: -41, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Doubao GZIP compression."])
            }
            defer { deflateEnd(&stream) }

            var output = Data()
            var status: Int32 = Z_OK
            while status == Z_OK {
                var out = [UInt8](repeating: 0, count: 16_384)
                let statusCode = out.withUnsafeMutableBytes { outBuffer in
                    stream.next_out = UnsafeMutablePointer<Bytef>(outBuffer.bindMemory(to: UInt8.self).baseAddress)
                    stream.avail_out = uInt(outBuffer.count)
                    return deflate(&stream, Z_FINISH)
                }
                let used = out.count - Int(stream.avail_out)
                if used > 0 {
                    output.append(contentsOf: out[0..<used])
                }
                status = statusCode
                if status != Z_OK && status != Z_STREAM_END {
                    throw NSError(domain: "Voxt.Meeting", code: -42, userInfo: [NSLocalizedDescriptionKey: "Failed to compress Doubao payload."])
                }
            }
            return output
        }
    }

    private static func gunzip(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }
        return try data.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return data
            }
            var stream = z_stream()
            stream.next_in = UnsafeMutablePointer<Bytef>(OpaquePointer(input))
            stream.avail_in = uInt(data.count)

            let initStatus = inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initStatus == Z_OK else {
                throw NSError(domain: "Voxt.Meeting", code: -43, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Doubao GZIP decompression."])
            }
            defer { inflateEnd(&stream) }

            var output = Data()
            var status: Int32 = Z_OK
            while status == Z_OK {
                var out = [UInt8](repeating: 0, count: 16_384)
                let statusCode = out.withUnsafeMutableBytes { outBuffer in
                    stream.next_out = UnsafeMutablePointer<Bytef>(outBuffer.bindMemory(to: UInt8.self).baseAddress)
                    stream.avail_out = uInt(outBuffer.count)
                    return inflate(&stream, Z_SYNC_FLUSH)
                }
                let used = out.count - Int(stream.avail_out)
                if used > 0 {
                    output.append(contentsOf: out[0..<used])
                }
                status = statusCode
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw NSError(domain: "Voxt.Meeting", code: -44, userInfo: [NSLocalizedDescriptionKey: "Failed to decode Doubao response payload."])
                }
            }
            return output
        }
    }

    private static func isLastPackage(in object: Any) -> Bool? {
        if let dict = object as? [String: Any] {
            if let value = dict["is_last_package"] {
                return value as? Bool ?? (value as? NSNumber)?.boolValue
            }
            for nested in dict.values {
                if let result = isLastPackage(in: nested) {
                    return result
                }
            }
            return nil
        }
        if let array = object as? [Any] {
            for item in array {
                if let result = isLastPackage(in: item) {
                    return result
                }
            }
        }
        return nil
    }

    private static func extractSequence(in object: Any) -> Int32? {
        if let value = object as? Int { return Int32(value) }
        if let value = object as? Int32 { return value }
        if let value = object as? Int64 { return Int32(value) }
        if let value = object as? NSNumber { return value.int32Value }
        if let dict = object as? [String: Any] {
            if let seq = dict["sequence"] {
                return extractSequence(in: seq)
            }
            if let seq = dict["seq"] {
                return extractSequence(in: seq)
            }
            if let seq = dict["autoAssignedSequence"] {
                return extractSequence(in: seq)
            }
            if let seq = dict["auto_assigned_sequence"] {
                return extractSequence(in: seq)
            }
            for nested in dict.values {
                if let seq = extractSequence(in: nested) {
                    return seq
                }
            }
        }
        if let array = object as? [Any] {
            for item in array {
                if let seq = extractSequence(in: item) {
                    return seq
                }
            }
        }
        return nil
    }

    private static func extractDoubaoText(in object: Any) -> String? {
        if let dict = object as? [String: Any],
           let result = dict["result"] as? [String: Any],
           let text = result["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !isLikelyIdentifierText(trimmed) {
                return trimmed
            }
        }

        var candidates: [String] = []
        func appendCandidate(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isLikelyIdentifierText(trimmed) else { return }
            candidates.append(trimmed)
        }

        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                let directTextKeys = ["text", "transcript", "utterance", "utterance_text", "result_text"]
                for key in directTextKeys {
                    if let value = dict[key] as? String {
                        appendCandidate(value)
                    }
                }
                let containerKeys = ["result", "results", "utterances", "payload_msg", "payload", "data", "nbest", "alternatives"]
                for key in containerKeys {
                    if let value = dict[key] {
                        walk(value)
                    }
                }
                for (_, value) in dict where value is [String: Any] || value is [Any] {
                    walk(value)
                }
                return
            }
            if let array = node as? [Any] {
                for item in array {
                    walk(item)
                }
            }
        }

        walk(object)
        return candidates.max(by: { $0.count < $1.count })
    }

    private static func extractDoubaoUtteranceUnits(
        in object: Any,
        defaultIsFinal: Bool
    ) -> [MeetingLiveProviderTranscriptUnit] {
        var units: [MeetingLiveProviderTranscriptUnit] = []

        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let utterances = dict["utterances"] as? [[String: Any]] {
                    for (index, utterance) in utterances.enumerated() {
                        if let unit = makeDoubaoUtteranceUnit(
                            utterance,
                            fallbackIndex: index,
                            defaultIsFinal: defaultIsFinal
                        ) {
                            units.append(unit)
                        }
                    }
                }
                for value in dict.values {
                    if value is [String: Any] || value is [Any] {
                        walk(value)
                    }
                }
                return
            }
            if let array = node as? [Any] {
                for item in array {
                    walk(item)
                }
            }
        }

        walk(object)
        units.sort { lhs, rhs in
            let lhsStart = lhs.startSeconds ?? 0
            let rhsStart = rhs.startSeconds ?? 0
            if lhsStart == rhsStart {
                return (lhs.key ?? lhs.text) < (rhs.key ?? rhs.text)
            }
            return lhsStart < rhsStart
        }
        return units
    }

    private static func containsRecursiveKey(_ targetKey: String, in object: Any) -> Bool {
        if let dict = object as? [String: Any] {
            if dict[targetKey] != nil {
                return true
            }
            for value in dict.values {
                if containsRecursiveKey(targetKey, in: value) {
                    return true
                }
            }
        }
        if let array = object as? [Any] {
            for item in array where containsRecursiveKey(targetKey, in: item) {
                return true
            }
        }
        return false
    }

    private static func makeDoubaoUtteranceUnit(
        _ utterance: [String: Any],
        fallbackIndex: Int,
        defaultIsFinal: Bool
    ) -> MeetingLiveProviderTranscriptUnit? {
        let text = extractDoubaoText(in: utterance)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty, !isLikelyIdentifierText(text) else { return nil }

        let startMs = extractTimeMilliseconds(
            in: utterance,
            keys: ["start_time", "begin_time", "start_ms", "begin_ms", "start", "begin"]
        )
        let endMs = extractTimeMilliseconds(
            in: utterance,
            keys: ["end_time", "end_ms", "end"]
        )
        let key = extractString(
            in: utterance,
            keys: ["utterance_id", "id", "uid", "segment_id"]
        ) ?? {
            if let startMs, let endMs {
                return "\(startMs)-\(endMs)"
            }
            return "utterance-\(fallbackIndex)-\(text)"
        }()

        let isFinal = extractBool(
            in: utterance,
            keys: ["is_final", "final", "sentence_end", "definite"]
        ) ?? defaultIsFinal

        return MeetingLiveProviderTranscriptUnit(
            key: key,
            startSeconds: startMs.map { Double($0) / 1000 },
            endSeconds: endMs.map { Double($0) / 1000 },
            text: text,
            isFinal: isFinal
        )
    }

    static func makeAliyunSentenceUnit(
        sentence: [String: Any],
        fallbackText: String,
        isFinal: Bool
    ) -> MeetingLiveProviderTranscriptUnit? {
        let text = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let key = extractString(in: sentence, keys: ["sentence_id", "id", "index"])
        let startMs = extractTimeMilliseconds(in: sentence, keys: ["begin_time", "start_time", "start_ms", "begin_ms"])
        let endMs = extractTimeMilliseconds(in: sentence, keys: ["end_time", "end_ms"])
        guard key != nil || startMs != nil || endMs != nil else { return nil }
        return MeetingLiveProviderTranscriptUnit(
            key: key ?? [startMs, endMs].compactMap { $0 }.map(String.init).joined(separator: "-"),
            startSeconds: startMs.map { Double($0) / 1000 },
            endSeconds: endMs.map { Double($0) / 1000 },
            text: text,
            isFinal: isFinal
        )
    }

    static func makeAliyunQwenUnit(
        object: [String: Any],
        fallbackText: String,
        isFinal: Bool
    ) -> MeetingLiveProviderTranscriptUnit? {
        let text = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let key = extractString(in: object, keys: ["item_id", "itemId", "id"])
            ?? ((object["item"] as? [String: Any]).flatMap { extractString(in: $0, keys: ["id", "item_id"]) })
        let startMs = extractTimeMilliseconds(in: object, keys: ["audio_start_ms", "start_ms", "begin_ms"])
        let endMs = extractTimeMilliseconds(in: object, keys: ["audio_end_ms", "end_ms"])
        guard key != nil || startMs != nil || endMs != nil else { return nil }
        return MeetingLiveProviderTranscriptUnit(
            key: key ?? [startMs, endMs].compactMap { $0 }.map(String.init).joined(separator: "-"),
            startSeconds: startMs.map { Double($0) / 1000 },
            endSeconds: endMs.map { Double($0) / 1000 },
            text: text,
            isFinal: isFinal
        )
    }

    private static func extractTimeMilliseconds(
        in object: Any,
        keys: [String]
    ) -> Int? {
        if let dict = object as? [String: Any] {
            for key in keys {
                if let value = dict[key], let parsed = extractInt(in: value) {
                    return parsed
                }
            }
        }
        return nil
    }

    private static func extractString(
        in object: Any,
        keys: [String]
    ) -> String? {
        guard let dict = object as? [String: Any] else { return nil }
        for key in keys {
            if let value = dict[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            if let value = dict[key] {
                if let intValue = extractInt(in: value) {
                    return String(intValue)
                }
            }
        }
        return nil
    }

    private static func extractBool(
        in object: Any,
        keys: [String]
    ) -> Bool? {
        guard let dict = object as? [String: Any] else { return nil }
        for key in keys {
            if let value = dict[key] as? Bool {
                return value
            }
            if let value = dict[key] as? NSNumber {
                return value.boolValue
            }
        }
        return nil
    }

    private static func extractInt(in object: Any) -> Int? {
        if let value = object as? Int {
            return value
        }
        if let value = object as? Int64 {
            return Int(value)
        }
        if let value = object as? Int32 {
            return Int(value)
        }
        if let value = object as? Double {
            return Int(value.rounded())
        }
        if let value = object as? NSNumber {
            return value.intValue
        }
        if let value = object as? String,
           let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return nil
    }

    private static func isLikelyIdentifierText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let uuidPattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"#
        if trimmed.range(of: uuidPattern, options: .regularExpression) != nil {
            return true
        }
        let compactIDPattern = #"^[0-9a-fA-F_-]{16,}$"#
        if trimmed.range(of: compactIDPattern, options: .regularExpression) != nil,
           trimmed.rangeOfCharacter(from: .letters) != nil,
           trimmed.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }
        return false
    }
}

private extension UInt32 {
    var bigEndianData: Data {
        withUnsafeBytes(of: self.bigEndian) { Data($0) }
    }

    init(bigEndianData data: Data) {
        precondition(data.count == 4)
        self = data.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}

private extension Int32 {
    var bigEndianData: Data {
        withUnsafeBytes(of: self.bigEndian) { Data($0) }
    }

    init(bigEndianData data: Data) {
        precondition(data.count == 4)
        let value = data.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        self = Int32(bitPattern: value)
    }
}
