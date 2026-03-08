import Foundation
import AVFoundation
import Combine
import zlib

@MainActor
class RemoteASRTranscriber: NSObject, ObservableObject, TranscriberProtocol {
    private enum DoubaoProtocol {
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

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false

    var onTranscriptionFinished: ((String) -> Void)?

    private var recorder: AVAudioRecorder?
    private let audioEngine = AVAudioEngine()
    private var doubaoStreamingContext: DoubaoStreamingContext?
    private var meterTimer: Timer?
    private var recordingFileURL: URL?
    private var transcribeTask: Task<Void, Never>?
    private var activeProvider: RemoteASRProvider?
    private let doubaoResourceID = "volc.bigasr.sauc.duration"
    private let streamingFinalWaitTimeout: TimeInterval = 20

    func requestPermissions() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func startRecording() {
        guard !isRecording else { return }
        cleanupActiveUploadTask()
        cleanupDoubaoStreamingState()
        transcribedText = ""
        audioLevel = 0
        let provider = selectedProvider
        let configuration = selectedProviderConfiguration(for: provider)
        activeProvider = provider

        if provider == .doubaoASR {
            do {
                try startDoubaoStreaming(configuration: configuration)
            } catch {
                VoxtLog.error("Doubao streaming setup failed: \(error.localizedDescription)")
                cleanupRecorderState()
                cleanupDoubaoStreamingState()
                activeProvider = nil
            }
            return
        }

        do {
            try startFileRecordingMode()
        } catch {
            VoxtLog.error("Remote ASR recorder setup failed: \(error.localizedDescription)")
            cleanupRecorderState()
            activeProvider = nil
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        if activeProvider == .doubaoASR, let context = doubaoStreamingContext {
            isRecording = false
            stopDoubaoAudioCapture()
            VoxtLog.info("Doubao streaming stop requested. sentAudioPackets=\(context.audioPacketCount)")
            // Doubao expects the terminal negative sequence to mirror the next
            // auto-assigned sequence index, not the last sent positive one.
            let finalSequence = context.audioPacketCount == 0 ? Int32(-1) : -context.nextAudioSequence
            VoxtLog.info(
                "Doubao streaming final packet. lastSequence=\(context.lastAudioSequence), nextSequence=\(context.nextAudioSequence), finalSequence=\(finalSequence)",
                verbose: true
            )
            if !context.isClosed {
                let finalPacket = buildDoubaoPacket(
                    messageType: DoubaoProtocol.messageTypeAudioOnlyClientRequest,
                    messageFlags: DoubaoProtocol.flagNegativeAudioPacket,
                    serialization: DoubaoProtocol.serializationNone,
                    compression: DoubaoProtocol.compressionNone,
                    sequence: finalSequence,
                    payload: Data()
                )
                sendDoubaoPacket(finalPacket, through: context.ws) { error, isBenign in
                    Task { [responseState = context.responseState] in
                        if isBenign {
                            await responseState.markSocketClosed()
                        } else {
                            await responseState.markCompletedWithError(error)
                        }
                    }
                }
            } else {
                VoxtLog.info("Doubao streaming socket already closed before final packet, skip final send.", verbose: true)
            }

            transcribeTask = Task { [weak self] in
                guard let self else { return }
                let finalText: String
                do {
                    finalText = try await context.responseState.waitForFinalResult(timeoutSeconds: streamingFinalWaitTimeout)
                } catch {
                    VoxtLog.warning("Doubao final result wait failed: \(error.localizedDescription)")
                    finalText = await context.responseState.currentText()
                }
                let currentText = await context.responseState.currentText()
                let stabilizedText = finalText.isEmpty ? currentText : finalText
                await MainActor.run {
                    self.transcribedText = stabilizedText
                    self.finish(with: stabilizedText)
                }
            }
            return
        }

        recorder?.stop()
        isRecording = false
        stopMeteringTimer()

        guard let fileURL = recordingFileURL else {
            finish(with: transcribedText)
            return
        }

        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.transcribeRecordedAudio(fileURL: fileURL)
                await MainActor.run {
                    self.transcribedText = result
                    self.finish(with: result)
                }
            } catch {
                await MainActor.run {
                    VoxtLog.error("Remote ASR transcription failed: \(error.localizedDescription)")
                    self.finish(with: self.transcribedText)
                }
            }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func transcribeRecordedAudio(fileURL: URL) async throws -> String {
        let provider = activeProvider ?? selectedProvider
        let configuration = selectedProviderConfiguration(for: provider)

        switch provider {
        case .openAIWhisper:
            return try await transcribeOpenAI(fileURL: fileURL, configuration: configuration)
        case .glmASR:
            return try await transcribeGLM(fileURL: fileURL, configuration: configuration)
        case .doubaoASR:
            return try await transcribeDoubao(fileURL: fileURL, configuration: configuration)
        }
    }

    private func startFileRecordingMode() throws {
        let fileURL = makeTemporaryRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw NSError(domain: "Voxt.RemoteASR", code: -100, userInfo: [NSLocalizedDescriptionKey: "Recorder start failed"])
        }
        self.recorder = recorder
        self.recordingFileURL = fileURL
        self.isRecording = true
        startMeteringTimer()
    }

    private var selectedProvider: RemoteASRProvider {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRSelectedProvider) ?? ""
        return RemoteASRProvider(rawValue: raw) ?? .openAIWhisper
    }

    private func selectedProviderConfiguration(for provider: RemoteASRProvider) -> RemoteProviderConfiguration {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
        let all = RemoteModelConfigurationStore.loadConfigurations(from: raw)
        return RemoteModelConfigurationStore.resolvedASRConfiguration(provider: provider, stored: all)
    }

    private func transcribeOpenAI(fileURL: URL, configuration: RemoteProviderConfiguration) async throws -> String {
        let endpoint = URL(string: normalizedEndpoint(configuration.endpoint, defaultValue: "https://api.openai.com/v1/audio/transcriptions"))!
        let token = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key is empty."])
        }
        return try await transcribeViaMultipartStream(
            endpoint: endpoint,
            authorizationValue: "Bearer \(token)",
            fileURL: fileURL,
            model: configuration.model,
            extraFields: ["stream": "true"]
        )
    }

    private func transcribeGLM(fileURL: URL, configuration: RemoteProviderConfiguration) async throws -> String {
        let endpoint = URL(string: normalizedEndpoint(configuration.endpoint, defaultValue: "https://open.bigmodel.cn/api/paas/v4/audio/transcriptions"))!
        let token = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -2, userInfo: [NSLocalizedDescriptionKey: "GLM API key is empty."])
        }
        return try await transcribeViaMultipartStream(
            endpoint: endpoint,
            authorizationValue: "Bearer \(token)",
            fileURL: fileURL,
            model: configuration.model,
            extraFields: ["stream": "true"]
        )
    }

    private func transcribeDoubao(fileURL: URL, configuration: RemoteProviderConfiguration) async throws -> String {
        let accessToken = configuration.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let appID = configuration.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resourceID = resolvedDoubaoResourceID(from: configuration)

        guard !accessToken.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -3, userInfo: [NSLocalizedDescriptionKey: "Doubao Access Token is empty."])
        }
        guard !appID.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -4, userInfo: [NSLocalizedDescriptionKey: "Doubao App ID is empty."])
        }
        return try await transcribeDoubaoWebSocket(
            fileURL: fileURL,
            appID: appID,
            accessToken: accessToken,
            resourceID: resourceID,
            endpoint: normalizedEndpoint(configuration.endpoint, defaultValue: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel")
        )
    }

    private func transcribeDoubaoWebSocket(
        fileURL: URL,
        appID: String,
        accessToken: String,
        resourceID: String,
        endpoint: String
    ) async throws -> String {
        guard let wsURL = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.RemoteASR", code: -5, userInfo: [NSLocalizedDescriptionKey: "Invalid Doubao endpoint URL."])
        }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 45
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")
        VoxtLog.info("Doubao websocket connect. endpoint=\(endpoint), resource=\(resourceID), requestID=\(requestID), appID=\(appID)")

        let ws = VoxtNetworkSession.active.webSocketTask(with: request)
        ws.resume()
        defer {
            ws.cancel(with: .goingAway, reason: nil)
        }

        let reqID = UUID().uuidString.lowercased()
        try await sendDoubaoFullRequest(
            ws: ws,
            reqID: reqID,
            sequence: 1
        )

        let responseState = DoubaoResponseState()
        let receiveTask = Task {
            do {
                while !Task.isCancelled {
                    let message = try await ws.receive()
                    guard case .data(let payloadData) = message else { continue }
                    if let parsed = try self.parseDoubaoServerPacket(payloadData) {
                        if let text = parsed.text, !text.isEmpty {
                            _ = await responseState.replace(text: text, isFinal: parsed.isFinal)
                        } else if parsed.isFinal {
                            await responseState.markFinal()
                        }
                    }
                }
            } catch {
                if let detail = await self.fetchDoubaoHandshakeFailureDetail(
                    error: error,
                    endpoint: endpoint,
                    resourceID: resourceID,
                    appID: appID,
                    accessToken: accessToken
                ) {
                    VoxtLog.warning("Doubao websocket receive failed. detail=\(detail)")
                    let detailedError = NSError(
                        domain: "Voxt.RemoteASR",
                        code: (error as NSError).code,
                        userInfo: [NSLocalizedDescriptionKey: detail]
                    )
                    await responseState.markCompletedWithError(detailedError)
                } else {
                    await responseState.markCompletedWithError(error)
                }
            }
        }

        let fileData = try Data(contentsOf: fileURL)
        let chunkSize = 3200
        var offset = 0
        var sequence: Int32 = 2
        while offset < fileData.count {
            let end = min(offset + chunkSize, fileData.count)
            let chunk = fileData[offset..<end]
            let isLast = end >= fileData.count
            try await sendDoubaoAudioPacket(
                ws: ws,
                payload: Data(chunk),
                isLast: isLast,
                sequence: sequence
            )
            if !isLast {
                sequence += 1
            }
            offset = end
            try? await Task.sleep(for: .milliseconds(24))
        }

        let finalText = try await responseState.waitForFinalResult(timeoutSeconds: 20)
        receiveTask.cancel()
        return finalText
    }

    private func startDoubaoStreaming(configuration: RemoteProviderConfiguration) throws {
        let accessToken = configuration.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let appID = configuration.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resourceID = resolvedDoubaoResourceID(from: configuration)

        guard !accessToken.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -3, userInfo: [NSLocalizedDescriptionKey: "Doubao Access Token is empty."])
        }
        guard !appID.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -4, userInfo: [NSLocalizedDescriptionKey: "Doubao App ID is empty."])
        }

        let endpoint = normalizedEndpoint(configuration.endpoint, defaultValue: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel")
        guard let wsURL = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.RemoteASR", code: -5, userInfo: [NSLocalizedDescriptionKey: "Invalid Doubao endpoint URL."])
        }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 45
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")
        VoxtLog.info("Doubao stream connect. endpoint=\(endpoint), resource=\(resourceID), requestID=\(requestID), appID=\(appID)")

        let ws = VoxtNetworkSession.active.webSocketTask(with: request)
        ws.resume()
        let context = DoubaoStreamingContext(ws: ws, responseState: DoubaoResponseState())
        doubaoStreamingContext = context
        receiveDoubaoMessages(context, endpoint: endpoint, resourceID: resourceID, appID: appID, accessToken: accessToken)

        let reqID = UUID().uuidString.lowercased()
        let payloadObject: [String: Any] = [
            "user": [
                "uid": "voxt"
            ],
            "audio": [
                "format": "pcm",
                "codec": "raw",
                "rate": 16000,
                "bits": 16,
                "channel": 1
            ],
            "request": [
                "reqid": reqID,
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": true,
                "show_utterances": true,
                "enable_nonstream": false
            ]
        ]
        let rawPayload = try JSONSerialization.data(withJSONObject: payloadObject)
        let (initializationCompression, payload) = encodeDoubaoPacketPayload(rawPayload, preferGzip: true)

        let initPacket = buildDoubaoPacket(
            messageType: DoubaoProtocol.messageTypeFullClientRequest,
            messageFlags: DoubaoProtocol.flagPositiveSequence,
            serialization: DoubaoProtocol.serializationJSON,
            compression: initializationCompression,
            sequence: 1,
            payload: payload
        )
        sendDoubaoPacket(initPacket, through: ws) { error, isBenign in
            Task { [responseState = context.responseState] in
                if isBenign {
                    context.isClosed = true
                    await responseState.markSocketClosed()
                } else {
                    await responseState.markCompletedWithError(error)
                }
            }
        }
        isRecording = true
    }

    private func sendDoubaoPacket(
        _ packet: Data,
        through ws: URLSessionWebSocketTask,
        onError: @escaping (Error, Bool) -> Void
    ) {
        ws.send(.data(packet)) { error in
            if let error {
                let nsError = error as NSError
                let isBenign = self.isBenignDoubaoSocketError(nsError)
                onError(error, isBenign)
            }
        }
    }

    private func startDoubaoAudioCapture() throws {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let pcmData = Self.makeDoubaoPCM16MonoData(from: buffer) else { return }
            Task { @MainActor in
                guard self.isRecording,
                      let context = self.doubaoStreamingContext,
                      !context.isClosed
                else { return }
                context.audioPacketCount += 1
                let sequence = context.nextAudioSequence
                context.nextAudioSequence += 1
                context.lastAudioSequence = sequence
                if context.audioPacketCount == 1 {
                    VoxtLog.info("Doubao streaming audio started. inputRate=\(Int(inputFormat.sampleRate))Hz, packetBytes=\(pcmData.count)")
                }
                self.audioLevel = self.audioLevelFromPCM16(pcmData)
                let (audioCompression, audioPayload) = self.encodeDoubaoPacketPayload(pcmData, preferGzip: true)
                let packet = self.buildDoubaoPacket(
                    messageType: DoubaoProtocol.messageTypeAudioOnlyClientRequest,
                    messageFlags: DoubaoProtocol.flagPositiveSequence,
                    serialization: DoubaoProtocol.serializationNone,
                    compression: audioCompression,
                    sequence: sequence,
                    payload: audioPayload
                )
                self.sendDoubaoPacket(packet, through: context.ws) { error, isBenign in
                    Task { [responseState = context.responseState] in
                        if isBenign {
                            context.isClosed = true
                            await responseState.markSocketClosed()
                        } else {
                            await responseState.markCompletedWithError(error)
                        }
                    }
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func stopDoubaoAudioCapture() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioLevel = 0
    }

    private func receiveDoubaoMessages(
        _ context: DoubaoStreamingContext,
        endpoint: String,
        resourceID: String,
        appID: String,
        accessToken: String
    ) {
        context.ws.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        if case .data(let payloadData) = message,
                           let parsed = try self.parseDoubaoServerPacket(payloadData) {
                            context.serverPacketCount += 1
                            if context.serverPacketCount <= 4 {
                                VoxtLog.info("Doubao streaming server packet received. index=\(context.serverPacketCount), bytes=\(payloadData.count), hasText=\(!(parsed.text ?? "").isEmpty), isFinal=\(parsed.isFinal)")
                            }
                            if !context.didStartAudioStream {
                                do {
                                    try self.startDoubaoAudioCapture()
                                    context.didStartAudioStream = true
                                    VoxtLog.info("Doubao streaming handshake confirmed, audio capture started.")
                                } catch {
                                    await context.responseState.markCompletedWithError(error)
                                    self.cleanupDoubaoStreamingState()
                                    self.activeProvider = nil
                                    return
                                }
                            }
                            if let text = parsed.text, !text.isEmpty {
                                let merged = await context.responseState.replace(text: text, isFinal: parsed.isFinal)
                                await MainActor.run {
                                    self.transcribedText = merged
                                }
                            } else if parsed.isFinal {
                                await context.responseState.markFinal()
                            }
                        }
                    } catch {
                        let nsError = error as NSError
                        if self.isBenignDoubaoSocketError(nsError) {
                            context.isClosed = true
                            await context.responseState.markSocketClosed()
                        } else {
                            VoxtLog.warning("Doubao stream receive parse failed. detail=\(error.localizedDescription)")
                            await context.responseState.markCompletedWithError(error)
                        }
                    }
                    if !context.isClosed {
                        self.receiveDoubaoMessages(
                            context,
                            endpoint: endpoint,
                            resourceID: resourceID,
                            appID: appID,
                            accessToken: accessToken
                        )
                    }
                }
            case .failure(let error):
                Task {
                    let nsError = error as NSError
                    if self.isBenignDoubaoSocketError(nsError) {
                        context.isClosed = true
                        await context.responseState.markSocketClosed()
                        return
                    }

                    if let detail = await self.fetchDoubaoHandshakeFailureDetail(
                        error: error,
                        endpoint: endpoint,
                        resourceID: resourceID,
                        appID: appID,
                        accessToken: accessToken
                    ) {
                        await MainActor.run {
                            VoxtLog.warning("Doubao stream receive failed. detail=\(detail)")
                        }
                        let detailedError = NSError(
                            domain: "Voxt.RemoteASR",
                            code: nsError.code,
                            userInfo: [NSLocalizedDescriptionKey: detail]
                        )
                        await context.responseState.markCompletedWithError(detailedError)
                    } else {
                        await context.responseState.markCompletedWithError(error)
                    }
                }
            }
        }
    }

    private func fetchDoubaoHandshakeFailureDetail(
        error: Error,
        endpoint: String,
        resourceID: String,
        appID: String,
        accessToken: String
    ) async -> String? {
        let nsError = error as NSError
        if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorBadServerResponse {
            return nil
        }

        guard var components = URLComponents(string: endpoint) else {
            return nil
        }
        if components.scheme == "wss" {
            components.scheme = "https"
        } else if components.scheme == "ws" {
            components.scheme = "http"
        }
        guard let probeURL = components.url else {
            return nil
        }

        var request = URLRequest(url: probeURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")

        do {
            let (data, response) = try await VoxtNetworkSession.active.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            logHTTPResponse(context: "Doubao handshake probe", response: http, data: data)
            let payload = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if payload.isEmpty {
                return "Doubao handshake failed (HTTP \(http.statusCode))."
            }
            return "Doubao handshake failed (HTTP \(http.statusCode)): \(payload)"
        } catch {
            return nil
        }
    }

    private func logHTTPResponse(context: String, response: HTTPURLResponse, data: Data) {
        let headers = response.allHeaderFields
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let preview = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        VoxtLog.info("[\(context)] status=\(response.statusCode), headers={\(headers)}, body=\(preview)")
    }

    private func isBenignDoubaoSocketError(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain {
            return error.code == 57
        }

        if error.domain == NSURLErrorDomain {
            return [
                NSURLErrorCancelled,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNotConnectedToInternet
            ].contains(error.code)
        }

        return false
    }

    private func sendDoubaoFullRequest(
        ws: URLSessionWebSocketTask,
        reqID: String,
        sequence: Int32
    ) async throws {
        let payloadObject: [String: Any] = [
            "user": [
                "uid": "voxt"
            ],
            "audio": [
                "format": "wav",
                "codec": "raw",
                "rate": 16000,
                "bits": 16,
                "channel": 1,
                "language": "zh-CN"
            ],
            "request": [
                "reqid": reqID,
                "model_name": "bigmodel",
                "enable_itn": true,
                "enable_punc": true,
                "enable_ddc": true,
                "show_utterances": true,
                "enable_nonstream": false
            ]
        ]
        let rawPayload = try JSONSerialization.data(withJSONObject: payloadObject)
        let (payloadCompression, payload) = encodeDoubaoPacketPayload(rawPayload, preferGzip: true)
        let packet = buildDoubaoPacket(
            messageType: DoubaoProtocol.messageTypeFullClientRequest,
            messageFlags: DoubaoProtocol.flagPositiveSequence,
            serialization: DoubaoProtocol.serializationJSON,
            compression: payloadCompression,
            sequence: sequence,
            payload: payload
        )
        try await ws.send(.data(packet))
    }

    private func sendDoubaoAudioPacket(
        ws: URLSessionWebSocketTask,
        payload: Data,
        isLast: Bool,
        sequence: Int32
    ) async throws {
        let (audioCompression, compressedPayload) = encodeDoubaoPacketPayload(payload, preferGzip: true)
        let packet = buildDoubaoPacket(
            messageType: DoubaoProtocol.messageTypeAudioOnlyClientRequest,
            messageFlags: isLast ? DoubaoProtocol.flagNegativeAudioPacket : DoubaoProtocol.flagPositiveSequence,
            serialization: DoubaoProtocol.serializationNone,
            compression: audioCompression,
            sequence: isLast ? -sequence : sequence,
            payload: compressedPayload
        )
        try await ws.send(.data(packet))
    }

    private func encodeDoubaoPacketPayload(
        _ payload: Data,
        preferGzip: Bool
    ) -> (compression: UInt8, payload: Data) {
        guard preferGzip, !payload.isEmpty else {
            return (DoubaoProtocol.compressionNone, payload)
        }

        do {
            return (DoubaoProtocol.compressionGzip, try gzipCompressDoubaoPayload(payload))
        } catch {
            VoxtLog.warning("Doubao gzip compression failed. fallback to plain payload. error=\(error.localizedDescription)")
            return (DoubaoProtocol.compressionNone, payload)
        }
    }

    private func gzipCompressDoubaoPayload(_ data: Data) throws -> Data {
        if data.isEmpty {
            return Data()
        }

        return try data.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return data
            }

            var stream = z_stream()
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
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
                throw NSError(domain: "Voxt.RemoteASR", code: -12, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Doubao GZIP compression."])
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
                throw NSError(
                    domain: "Voxt.RemoteASR",
                    code: -13,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to compress Doubao payload."]
                )
            }
        }
            return output
        }
    }

    private func audioLevelFromPCM16(_ data: Data) -> Float {
        guard data.count >= 2 else { return 0 }
        var sum: Float = 0
        var count: Float = 0
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                let normalized = Float(sample) / Float(Int16.max)
                sum += normalized * normalized
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let rms = sqrt(sum / count)
        return min(max(rms * 2.4, 0), 1)
    }

    private nonisolated static func makeDoubaoPCM16MonoData(from buffer: AVAudioPCMBuffer) -> Data? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        let inputRate = max(buffer.format.sampleRate, 1)
        let targetRate = 16000.0
        let step = max(inputRate / targetRate, 1)
        let outputCount = max(Int(Double(frameCount) / step), 1)
        var output = Data(count: outputCount * MemoryLayout<Int16>.size)

        switch buffer.format.commonFormat {
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData?[0] else { return nil }
            output.withUnsafeMutableBytes { rawBuffer in
                let out = rawBuffer.bindMemory(to: Int16.self)
                for index in 0..<outputCount {
                    let sourceIndex = min(Int(Double(index) * step), frameCount - 1)
                    out[index] = channelData[sourceIndex]
                }
            }
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData?[0] else { return nil }
            output.withUnsafeMutableBytes { rawBuffer in
                let out = rawBuffer.bindMemory(to: Int16.self)
                for index in 0..<outputCount {
                    let sourceIndex = min(Int(Double(index) * step), frameCount - 1)
                    let clamped = max(-1.0, min(1.0, channelData[sourceIndex]))
                    out[index] = Int16(clamped * Float(Int16.max))
                }
            }
        default:
            return nil
        }

        return output
    }

    private func buildDoubaoPacket(
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
        if (messageFlags & DoubaoProtocol.flagPositiveSequence) != 0 || (messageFlags & DoubaoProtocol.flagLastAudioPacket) != 0 {
            data.append(sequence.bigEndianData)
        }
        data.append(UInt32(payload.count).bigEndianData)
        data.append(payload)
        return data
    }

    private func parseDoubaoServerPacket(_ data: Data) throws -> (text: String?, isFinal: Bool)? {
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
            cursor += 4 // server error code
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
            payload = (try? decodeDoubaoGzipPayload(rawPayload)) ?? rawPayload
        default:
            if looksLikeGzip(rawPayload) {
                payload = (try? decodeDoubaoGzipPayload(rawPayload)) ?? rawPayload
            } else {
                throw NSError(
                    domain: "Voxt.RemoteASR",
                    code: -6,
                    userInfo: [NSLocalizedDescriptionKey: "Doubao response compression is unsupported in current client."]
                )
            }
        }

        if messageType == DoubaoProtocol.messageTypeServerErrorResponse {
            let errorText = String(data: payload, encoding: .utf8) ?? "Unknown Doubao server error."
            throw NSError(domain: "Voxt.RemoteASR", code: -7, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        guard !payload.isEmpty else {
            let sequenceFromHeaderOnly = headerSequence
            let isFinal = (messageFlags & DoubaoProtocol.flagLastAudioPacket) != 0
                || (sequenceFromHeaderOnly ?? 1) < 0
            return (nil, isFinal)
        }

        guard let object = try? JSONSerialization.jsonObject(with: payload) else {
            let raw = String(data: payload, encoding: .utf8)
            return (raw, false)
        }

        let sequenceFromJSON = extractSequence(in: object)
        let isFinal = (messageFlags & DoubaoProtocol.flagLastAudioPacket) != 0
            || isLastPackage(in: object) == true
            || (sequenceFromJSON ?? headerSequence ?? 1) < 0
        let fragment = extractDoubaoText(in: object)
        return (fragment, isFinal)
    }

    private func decodeDoubaoGzipPayload(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }

        return try data.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return data
            }

            var stream = z_stream()
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
            stream.next_in = UnsafeMutablePointer<Bytef>(OpaquePointer(input))
            stream.avail_in = uInt(data.count)

            let initStatus = inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initStatus == Z_OK else {
                throw NSError(domain: "Voxt.RemoteASR", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Doubao GZIP decompression."])
            }
            defer { inflateEnd(&stream) }

            var output = Data()
            var decompressStatus: Int32 = Z_OK
            let chunkSize = 16_384
            while decompressStatus == Z_OK {
                var out = [UInt8](repeating: 0, count: chunkSize)
                let outCount = out.count
                let status = out.withUnsafeMutableBytes { outBuffer in
                    stream.next_out = UnsafeMutablePointer<Bytef>(outBuffer.bindMemory(to: UInt8.self).baseAddress)
                    stream.avail_out = uInt(outCount)
                    return inflate(&stream, Z_SYNC_FLUSH)
                }
                let used = outCount - Int(stream.avail_out)
                if used > 0 {
                    output.append(contentsOf: out[0..<used])
                }
                decompressStatus = status
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw NSError(domain: "Voxt.RemoteASR", code: -9, userInfo: [NSLocalizedDescriptionKey: "Failed to decode Doubao GZIP response payload."])
                }
            }
            return output
        }
    }

    private func isLastPackage(in object: Any) -> Bool? {
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

    private func looksLikeGzip(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        return data[0] == 0x1F && data[1] == 0x8B
    }

    private func extractSequence(in object: Any) -> Int32? {
        if let value = object as? Int { return Int32(value) }
        if let value = object as? Int32 { return value }
        if let value = object as? Int64 { return Int32(value) }
        if let dict = object as? [String: Any] {
            if let seq = dict["sequence"] {
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

    private func transcribeViaMultipartStream(
        endpoint: URL,
        authorizationValue: String,
        fileURL: URL,
        model: String,
        extraFields: [String: String]
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let effectiveModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "whisper-1" : model
        let body = try makeMultipartBody(
            fileURL: fileURL,
            boundary: boundary,
            model: effectiveModel,
            extraFields: extraFields
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream, application/json, text/plain", forHTTPHeaderField: "Accept")
        request.setValue(authorizationValue, forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (bytes, response) = try await VoxtNetworkSession.active.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.RemoteASR", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response."])
        }

        if !(200...299).contains(http.statusCode) {
            let payload = try await collectText(from: bytes)
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(payload)"]
            )
        }

        var aggregate = ""
        for try await rawLine in bytes.lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let line: String
            if trimmed.hasPrefix("data:") {
                line = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                line = trimmed
            }

            if line == "[DONE]" {
                break
            }

            if let fragment = extractTextFragment(fromLine: line), !fragment.isEmpty {
                aggregate = mergeStreamFragment(current: aggregate, incoming: fragment)
                await MainActor.run {
                    self.transcribedText = aggregate
                }
            }
        }

        if aggregate.isEmpty {
            return transcribedText
        }
        return aggregate
    }

    private func extractTextFragment(fromLine line: String) -> String? {
        guard let data = line.data(using: .utf8) else {
            return line
        }

        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let value = extractText(in: object), !value.isEmpty {
                return value
            }
            return nil
        }

        return line
    }

    private func extractDoubaoText(in object: Any) -> String? {
        if let dict = object as? [String: Any],
           let result = dict["result"] as? [String: Any],
           let text = result["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        var candidates: [String] = []

        func appendCandidate(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
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

                for (_, value) in dict {
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
        return candidates.max(by: { $0.count < $1.count })
    }

    private func extractText(in object: Any) -> String? {
        if let text = object as? String {
            return text
        }
        if let dict = object as? [String: Any] {
            let preferredKeys = ["delta", "text", "transcript", "result_text", "result", "content", "utterance"]
            for key in preferredKeys {
                if let value = dict[key], let text = extractText(in: value), !text.isEmpty {
                    return text
                }
            }
            for value in dict.values {
                if let text = extractText(in: value), !text.isEmpty {
                    return text
                }
            }
        }
        if let array = object as? [Any] {
            for item in array {
                if let text = extractText(in: item), !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private func mergeStreamFragment(current: String, incoming: String) -> String {
        let fragment = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else { return current }
        if current.isEmpty { return fragment }
        if fragment == current { return current }
        if fragment.hasPrefix(current) { return fragment }
        if current.hasPrefix(fragment) { return current }
        if fragment.contains(current) { return fragment }
        if current.contains(fragment) { return current }

        let maxOverlap = min(current.count, fragment.count)
        if maxOverlap > 0 {
            for length in stride(from: maxOverlap, through: 1, by: -1) {
                let currentSuffix = String(current.suffix(length))
                let incomingPrefix = String(fragment.prefix(length))
                if currentSuffix == incomingPrefix {
                    return current + fragment.dropFirst(length)
                }
            }
        }
        return current + fragment
    }

    private func makeMultipartBody(
        fileURL: URL,
        boundary: String,
        model: String,
        extraFields: [String: String]
    ) throws -> Data {
        var body = Data()

        func appendField(name: String, value: String) {
            guard !value.isEmpty else { return }
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: model)
        for (name, value) in extraFields where !value.isEmpty {
            appendField(name: name, value: value)
        }

        let filename = fileURL.lastPathComponent
        let mimeType = "audio/wav"
        let fileData = try Data(contentsOf: fileURL)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func collectText(from bytes: URLSession.AsyncBytes) async throws -> String {
        var chunks: [String] = []
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
            if chunks.count >= 6 { break }
        }
        return chunks.joined(separator: " | ")
    }

    private func normalizedEndpoint(_ value: String, defaultValue: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }

    private func resolvedDoubaoResourceID(from configuration: RemoteProviderConfiguration) -> String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty || model == "volc.seedasr.sauc.duration" {
            return doubaoResourceID
        }
        return model
    }

    private func startMeteringTimer() {
        stopMeteringTimer()
        meterTimer = Timer.scheduledTimer(
            timeInterval: 0.05,
            target: self,
            selector: #selector(updateAudioMeter),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopMeteringTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
        audioLevel = 0
    }

    @objc private func updateAudioMeter() {
        guard let recorder else { return }
        recorder.updateMeters()
        let avgPower = recorder.averagePower(forChannel: 0)
        let linear = pow(10, avgPower / 20)
        audioLevel = min(max(linear, 0), 1)
    }

    private func makeTemporaryRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voxt-remote-asr-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }

    private func cleanupRecorderState() {
        recorder?.stop()
        recorder = nil
        recordingFileURL = nil
        isRecording = false
        stopMeteringTimer()
    }

    private func cleanupDoubaoStreamingState() {
        if let context = doubaoStreamingContext {
            context.isClosed = true
            context.ws.cancel(with: .normalClosure, reason: nil)
        }
        doubaoStreamingContext = nil
        stopDoubaoAudioCapture()
    }

    private func cleanupActiveUploadTask() {
        transcribeTask?.cancel()
        transcribeTask = nil
    }

    private func finish(with text: String) {
        cleanupActiveUploadTask()
        cleanupRecorderState()
        cleanupDoubaoStreamingState()
        activeProvider = nil
        onTranscriptionFinished?(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

    @MainActor
private final class DoubaoStreamingContext {
    let ws: URLSessionWebSocketTask
    let responseState: DoubaoResponseState
    var isClosed = false
    var didStartAudioStream = false
    var audioPacketCount = 0
    var serverPacketCount = 0
    var nextAudioSequence: Int32 = 2
    var lastAudioSequence: Int32 = 0

    init(ws: URLSessionWebSocketTask, responseState: DoubaoResponseState) {
        self.ws = ws
        self.responseState = responseState
    }
}

private actor DoubaoResponseState {
    private var text = ""
    private var isFinal = false
    private var completionError: Error?
    private var isSocketClosed = false

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
        }
    }

    func markSocketClosed() {
        isSocketClosed = true
        if completionError == nil {
            // WebSocket close is expected after server final package; keep existing text and exit wait loop.
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
