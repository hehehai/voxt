// RemoteModelConfigurationTests.swift
// Provides Remote Model Configuration Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class RemoteModelConfigurationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        VoxtSecureStorage.clearAllForTesting()
    }

    override func tearDown() {
        VoxtSecureStorage.clearAllForTesting()
        super.tearDown()
    }

    func testDoubaoConfigurationUsesExpectedDefaults() {
        XCTAssertEqual(DoubaoASRConfiguration.resolvedEndpoint("", model: ""), DoubaoASRConfiguration.defaultNostreamEndpoint)
        XCTAssertEqual(
            DoubaoASRConfiguration.resolvedStreamingEndpoint("", model: DoubaoASRConfiguration.modelV1),
            DoubaoASRConfiguration.defaultStreamingEndpointV1
        )
        XCTAssertEqual(
            DoubaoASRConfiguration.resolvedStreamingEndpoint("", model: ""),
            DoubaoASRConfiguration.defaultStreamingEndpointV2
        )
    }

    func testDoubaoFullRequestPayloadIncludesLanguageAndVariant() {
        let payload = DoubaoASRConfiguration.fullRequestPayload(
            requestID: "req-1",
            userID: "user-1",
            language: "zh-CN",
            chineseOutputVariant: "zh-Hans",
            enableNonstream: true
        )

        let audio = payload["audio"] as? [String: Any]
        let request = payload["request"] as? [String: Any]
        XCTAssertEqual(audio?["language"] as? String, "zh-CN")
        XCTAssertEqual(request?["output_zh_variant"] as? String, "zh-Hans")
        XCTAssertEqual(request?["enable_nonstream"] as? Bool, true)
    }

    func testDoubaoFullRequestPayloadIncludesDictionaryContextAndCorpus() throws {
        let payload = DoubaoASRConfiguration.fullRequestPayload(
            requestID: "req-1",
            userID: "user-1",
            language: "zh-CN",
            chineseOutputVariant: "zh-Hans",
            dictionaryPayload: DoubaoDictionaryRequestPayload(
                hotwords: ["OpenAI"],
                correctWords: ["open ai": "OpenAI"]
            )
        )

        let request = try XCTUnwrap(payload["request"] as? [String: Any])
        let corpus = try XCTUnwrap(request["corpus"] as? [String: Any])

        let contextString = try XCTUnwrap(corpus["context"] as? String)
        let contextData = try XCTUnwrap(contextString.data(using: .utf8))
        let context = try XCTUnwrap(try JSONSerialization.jsonObject(with: contextData) as? [String: Any])
        XCTAssertEqual((context["hotwords"] as? [[String: String]])?.first?["word"], "OpenAI")
        XCTAssertEqual((context["correct_words"] as? [String: String])?["open ai"], "OpenAI")
    }

    func testDoubaoRecommendedStreamingChunkSplitsAndFlushesTrailingPartial() {
        let packetBytes = DoubaoASRConfiguration.recommendedStreamingPacketBytes
        var buffer = Data(repeating: 1, count: packetBytes * 2 + 123)

        let first = DoubaoASRConfiguration.popRecommendedStreamingChunk(from: &buffer, includeTrailingPartial: false)
        let second = DoubaoASRConfiguration.popRecommendedStreamingChunk(from: &buffer, includeTrailingPartial: false)
        let noneYet = DoubaoASRConfiguration.popRecommendedStreamingChunk(from: &buffer, includeTrailingPartial: false)
        let trailing = DoubaoASRConfiguration.popRecommendedStreamingChunk(from: &buffer, includeTrailingPartial: true)

        XCTAssertEqual(first?.count, packetBytes)
        XCTAssertEqual(second?.count, packetBytes)
        XCTAssertNil(noneYet)
        XCTAssertEqual(trailing?.count, 123)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDoubaoFinalStreamingSequenceUsesNextSequence() {
        XCTAssertEqual(DoubaoASRConfiguration.finalStreamingSequence(nextAudioSequence: 2), -2)
        XCTAssertEqual(DoubaoASRConfiguration.finalStreamingSequence(nextAudioSequence: 16), -16)
    }

    func testDoubaoParserRejectsOversizedCompressedPayload() {
        let oversizedPayload = Data(
            repeating: 0,
            count: MeetingRemoteAudioSupport.maxDoubaoCompressedPayloadBytes + 1
        )
        let packet = MeetingRemoteAudioSupport.buildDoubaoPacket(
            messageType: MeetingRemoteAudioSupport.DoubaoProtocol.messageTypeFullServerResponse,
            messageFlags: MeetingRemoteAudioSupport.DoubaoProtocol.flagPositiveSequence,
            serialization: MeetingRemoteAudioSupport.DoubaoProtocol.serializationJSON,
            compression: MeetingRemoteAudioSupport.DoubaoProtocol.compressionGzip,
            sequence: 1,
            payload: oversizedPayload
        )

        XCTAssertThrowsError(try MeetingRemoteAudioSupport.parseDoubaoServerPacket(packet))
    }

    func testDoubaoParserRejectsHighExpansionGzipPayload() throws {
        let largePlaintext = Data(repeating: 65, count: 1_048_577)
        let encoded = try MeetingRemoteAudioSupport.encodeDoubaoPayload(largePlaintext)
        XCTAssertEqual(encoded.compression, MeetingRemoteAudioSupport.DoubaoProtocol.compressionGzip)
        let packet = MeetingRemoteAudioSupport.buildDoubaoPacket(
            messageType: MeetingRemoteAudioSupport.DoubaoProtocol.messageTypeFullServerResponse,
            messageFlags: MeetingRemoteAudioSupport.DoubaoProtocol.flagPositiveSequence,
            serialization: MeetingRemoteAudioSupport.DoubaoProtocol.serializationJSON,
            compression: encoded.compression,
            sequence: 1,
            payload: encoded.payload
        )

        XCTAssertThrowsError(try MeetingRemoteAudioSupport.parseDoubaoServerPacket(packet))
    }

    func testAliyunASRModelOptionsIncludeOmniRealtimeModels() {
        let ids = Set(RemoteASRProvider.aliyunBailianASR.modelOptions.map(\.id))
        XCTAssertTrue(ids.contains("qwen3.5-omni-flash-realtime"))
        XCTAssertTrue(ids.contains("qwen3.5-omni-plus-realtime"))
        XCTAssertTrue(ids.contains("qwen-omni-turbo-realtime"))
    }

    func testAliyunRealtimeModelFamilyDetectionSeparatesQwenAndOmni() {
        XCTAssertEqual(
            RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: "qwen3-asr-flash-realtime"),
            .qwenASR
        )
        XCTAssertEqual(
            RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: "qwen3.5-omni-flash-realtime"),
            .omniASR
        )
        XCTAssertEqual(
            RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: "qwen3.5-omni-plus-realtime"),
            .omniASR
        )
        XCTAssertEqual(
            RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: "qwen-omni-turbo-realtime"),
            .omniASR
        )
        XCTAssertNil(RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: "fun-asr-realtime"))
    }

    func testAliyunOmniSessionUpdatePayloadUsesExplicitInputTranscriptionModel() throws {
        let payload = AliyunQwenRealtimePayloadSupport.sessionUpdatePayload(
            kind: .omniASR,
            hintPayload: ResolvedASRHintPayload(language: "zh", languageHints: ["zh"])
        )

        let session = try XCTUnwrap(payload["session"] as? [String: Any])
        let transcription = try XCTUnwrap(session["input_audio_transcription"] as? [String: Any])
        let turnDetection = try XCTUnwrap(session["turn_detection"] as? [String: Any])

        XCTAssertEqual(payload["type"] as? String, "session.update")
        XCTAssertEqual(session["modalities"] as? [String], ["text"])
        XCTAssertEqual(session["input_audio_format"] as? String, "pcm")
        XCTAssertEqual(session["sample_rate"] as? Int, 16000)
        XCTAssertEqual(transcription["model"] as? String, "qwen3-asr-flash-realtime")
        XCTAssertEqual(transcription["language"] as? String, "zh")
        XCTAssertEqual(turnDetection["type"] as? String, "server_vad")
        XCTAssertEqual(turnDetection["threshold"] as? Double, 0.35)
        XCTAssertEqual(turnDetection["silence_duration_ms"] as? Int, 800)
    }

    func testAliyunOmniRealtimeDoesNotRequireManualCommitWhenUsingServerVAD() {
        XCTAssertFalse(AliyunQwenRealtimeSessionKind.omniASR.shouldCommitBeforeFinish)
    }

    func testAliyunQwenSessionUpdatePayloadLeavesTranscriptionModelUnset() throws {
        let payload = AliyunQwenRealtimePayloadSupport.sessionUpdatePayload(
            kind: .qwenASR,
            hintPayload: ResolvedASRHintPayload(language: nil, languageHints: [])
        )

        let session = try XCTUnwrap(payload["session"] as? [String: Any])
        let transcription = try XCTUnwrap(session["input_audio_transcription"] as? [String: Any])

        XCTAssertNil(transcription["model"])
        XCTAssertNil(transcription["language"])
    }

    func testAliyunQwenSessionUpdatePayloadCanDisableTurnDetectionForMeeting() throws {
        let payload = AliyunQwenRealtimePayloadSupport.sessionUpdatePayload(
            kind: .qwenASR,
            hintPayload: ResolvedASRHintPayload(language: nil, languageHints: []),
            includesTurnDetection: false
        )

        let session = try XCTUnwrap(payload["session"] as? [String: Any])

        XCTAssertNil(session["turn_detection"])
    }

    func testLoadSaveRoundTripPreservesConfigurations() {
        let stored: [String: RemoteProviderConfiguration] = [
            RemoteASRProvider.openAIWhisper.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.openAIWhisper.rawValue,
                model: "whisper-1",
                endpoint: "https://example.com/asr",
                apiKey: "secret"
            ),
            RemoteASRProvider.doubaoASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: DoubaoASRConfiguration.modelV2,
                appID: "app-id",
                accessToken: "token",
                doubaoDictionaryMode: DoubaoDictionaryMode.off.rawValue,
                doubaoEnableRequestHotwords: false,
                doubaoEnableRequestCorrections: false
            ),
            RemoteLLMProvider.openAI.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5.2",
                endpoint: "https://example.com/llm",
                apiKey: "secret",
                openAIReasoningEffort: OpenAIReasoningEffort.high.rawValue,
                openAITextVerbosity: OpenAITextVerbosity.low.rawValue,
                openAIMaxOutputTokens: 4096
            )
        ]

        let raw = RemoteModelConfigurationStore.saveConfigurations(stored)
        VoxtSecureStorage.clearCacheForTesting()
        let roundTrip = RemoteModelConfigurationStore.loadConfigurations(from: raw)

        XCTAssertFalse(raw.contains("secret"))
        XCTAssertFalse(raw.contains("app-id"))
        XCTAssertFalse(raw.contains("token"))
        XCTAssertEqual(roundTrip, stored)
    }

    func testMetadataOnlyLoadDoesNotResolveStoredSensitiveValues() {
        let stored: [String: RemoteProviderConfiguration] = [
            RemoteLLMProvider.openAI.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.openAI.rawValue,
                model: "gpt-5.2",
                endpoint: "https://example.com/llm",
                apiKey: "secret"
            )
        ]

        let raw = RemoteModelConfigurationStore.saveConfigurations(stored)
        let metadataOnly = RemoteModelConfigurationStore.loadConfigurations(
            from: raw,
            sensitiveValueLoading: .metadataOnly
        )

        XCTAssertEqual(metadataOnly[RemoteLLMProvider.openAI.rawValue]?.model, "gpt-5.2")
        XCTAssertEqual(metadataOnly[RemoteLLMProvider.openAI.rawValue]?.endpoint, "https://example.com/llm")
        XCTAssertTrue(metadataOnly[RemoteLLMProvider.openAI.rawValue]?.apiKey.isEmpty ?? false)
        XCTAssertFalse(raw.contains("__stored__"))
        XCTAssertTrue(metadataOnly[RemoteLLMProvider.openAI.rawValue]?.isConfigured ?? false)
    }

    func testSavingMetadataOnlyConfigurationPreservesUneditedStoredCredential() throws {
        let provider = RemoteLLMProvider.openAI
        let stored = TestFactories.makeRemoteConfiguration(
            providerID: provider.rawValue,
            model: "gpt-5.2",
            apiKey: "stored-secret"
        )
        let raw = RemoteModelConfigurationStore.saveConfigurations([provider.rawValue: stored])
        var metadata = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: provider.rawValue,
                from: raw,
                sensitiveValueLoading: .metadataOnly
            )
        )
        metadata.model = "gpt-5.3"

        let updatedRaw = try RemoteModelConfigurationStore.saveConfiguration(
            metadata,
            updating: raw
        ).get()
        let reloaded = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: provider.rawValue,
                from: updatedRaw
            )
        )

        XCTAssertEqual(reloaded.model, "gpt-5.3")
        XCTAssertEqual(reloaded.apiKey, "stored-secret")
        XCTAssertFalse(updatedRaw.contains("stored-secret"))
    }

    func testCredentialEditIntentCanExplicitlyClearStoredCredential() throws {
        let provider = RemoteLLMProvider.openAI
        let stored = TestFactories.makeRemoteConfiguration(
            providerID: provider.rawValue,
            model: "gpt-5.2",
            apiKey: "stored-secret"
        )
        let raw = RemoteModelConfigurationStore.saveConfigurations([provider.rawValue: stored])
        let metadata = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: provider.rawValue,
                from: raw,
                sensitiveValueLoading: .metadataOnly
            )
        )
        let cleared = metadata.applyingCredentialEditIntent(
            from: metadata,
            editedFields: [.apiKey]
        )

        let updatedRaw = try RemoteModelConfigurationStore.saveConfiguration(
            cleared,
            updating: raw
        ).get()
        let reloaded = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: provider.rawValue,
                from: updatedRaw
            )
        )

        XCTAssertTrue(reloaded.apiKey.isEmpty)
        XCTAssertFalse(reloaded.isConfigured)
        XCTAssertFalse(
            VoxtSecureStorage.hasProtectedValueForTesting(
                for: "remote-provider.\(provider.rawValue).credentials"
            )
        )
    }

    func testReplacingOneCredentialFieldPreservesOtherStoredFields() throws {
        let providerID = RemoteASRProvider.doubaoASR.rawValue
        let stored = TestFactories.makeRemoteConfiguration(
            providerID: providerID,
            model: DoubaoASRConfiguration.modelV2,
            appID: "stored-app-id",
            accessToken: "old-token"
        )
        let raw = RemoteModelConfigurationStore.saveConfigurations([providerID: stored])
        let metadata = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: providerID,
                from: raw,
                sensitiveValueLoading: .metadataOnly
            )
        )
        var draft = metadata
        draft.accessToken = "new-token"
        draft = draft.applyingCredentialEditIntent(
            from: metadata,
            editedFields: [.accessToken]
        )

        let runtimeDraft = try RemoteModelConfigurationStore.runtimeConfiguration(for: draft).value
        XCTAssertEqual(runtimeDraft.appID, "stored-app-id")
        XCTAssertEqual(runtimeDraft.accessToken, "new-token")

        let updatedRaw = try RemoteModelConfigurationStore.saveConfiguration(
            draft,
            updating: raw
        ).get()
        let reloaded = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(providerID: providerID, from: updatedRaw)
        )

        XCTAssertEqual(reloaded.appID, "stored-app-id")
        XCTAssertEqual(reloaded.accessToken, "new-token")
    }

    func testSavingPreservedCredentialFailsClosedWhenStoredValueIsMissing() throws {
        let provider = RemoteLLMProvider.openAI
        let account = "remote-provider.\(provider.rawValue).credentials"
        let stored = TestFactories.makeRemoteConfiguration(
            providerID: provider.rawValue,
            model: "gpt-5.2",
            apiKey: "stored-secret"
        )
        let raw = RemoteModelConfigurationStore.saveConfigurations([provider.rawValue: stored])
        var metadata = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: provider.rawValue,
                from: raw,
                sensitiveValueLoading: .metadataOnly
            )
        )
        metadata.model = "gpt-5.3"
        VoxtSecureStorage.removeProtectedValueForTesting(for: account)

        let result = RemoteModelConfigurationStore.saveConfiguration(metadata, updating: raw)

        XCTAssertEqual(result, .failure(.secureStorageUnavailable))
        XCTAssertFalse(VoxtSecureStorage.hasProtectedValueForTesting(for: account))
    }

    func testResponsesRequestResolvesMetadataOnlyCredentialAtNetworkBoundary() throws {
        let provider = RemoteLLMProvider.volcengine
        let stored = TestFactories.makeRemoteConfiguration(
            providerID: provider.rawValue,
            model: "doubao-seed-2-0-mini-260215",
            endpoint: "https://ark.cn-beijing.volces.com/api/v3/responses",
            apiKey: "runtime-secret"
        )
        let raw = RemoteModelConfigurationStore.saveConfigurations([provider.rawValue: stored])
        let metadataOnly = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: provider.rawValue,
                from: raw,
                sensitiveValueLoading: .metadataOnly
            )
        )
        XCTAssertTrue(metadataOnly.apiKey.isEmpty)

        let request = try RemoteLLMRuntimeClient().makeResponsesRequest(
            provider: provider,
            endpointValue: stored.endpoint,
            model: stored.model,
            systemPrompt: "Answer the user.",
            inputPayload: "Hello",
            configuration: metadataOnly,
            previousResponseID: nil,
            tuning: .init(maxTokens: 128, temperature: 0.1, topP: 0.3),
            textFormat: nil,
            streamingEnabled: false
        )

        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer runtime-secret"
        )
    }

    func testRuntimeRequestRejectsMetadataWhenStoredCredentialIsMissing() throws {
        let provider = RemoteLLMProvider.volcengine
        let stored = TestFactories.makeRemoteConfiguration(
            providerID: provider.rawValue,
            model: "doubao-seed-2-0-mini-260215",
            apiKey: "runtime-secret"
        )
        let raw = RemoteModelConfigurationStore.saveConfigurations([provider.rawValue: stored])
        let metadataOnly = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: provider.rawValue,
                from: raw,
                sensitiveValueLoading: .metadataOnly
            )
        )
        VoxtSecureStorage.removeProtectedValueForTesting(
            for: "remote-provider.\(provider.rawValue).credentials"
        )

        XCTAssertThrowsError(
            try RemoteModelConfigurationStore.runtimeConfiguration(for: metadataOnly)
        ) { error in
            XCTAssertEqual(
                error as? RemoteModelConfigurationStore.RuntimeCredentialError,
                .missing
            )
        }
    }

    func testRuntimeRequestRejectsCorruptedBundledCredential() throws {
        let provider = RemoteLLMProvider.volcengine
        let stored = TestFactories.makeRemoteConfiguration(
            providerID: provider.rawValue,
            model: "doubao-seed-2-0-mini-260215",
            apiKey: "runtime-secret"
        )
        let raw = RemoteModelConfigurationStore.saveConfigurations([provider.rawValue: stored])
        let metadataOnly = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: provider.rawValue,
                from: raw,
                sensitiveValueLoading: .metadataOnly
            )
        )
        try VoxtSecureStorage.setProtectedString(
            "not-json",
            for: "remote-provider.\(provider.rawValue).credentials"
        )

        XCTAssertThrowsError(
            try RemoteModelConfigurationStore.runtimeConfiguration(for: metadataOnly)
        ) { error in
            XCTAssertEqual(
                error as? RemoteModelConfigurationStore.RuntimeCredentialError,
                .corrupted
            )
        }
    }

    func testTargetedLoadResolvesOnlyRequestedProviderConfiguration() {
        let stored: [String: RemoteProviderConfiguration] = [
            RemoteASRProvider.doubaoASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: DoubaoASRConfiguration.modelV2,
                appID: "doubao-app",
                accessToken: "doubao-token"
            ),
            RemoteASRProvider.aliyunBailianASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
                model: "fun-asr-realtime",
                apiKey: "aliyun-key"
            )
        ]

        let raw = RemoteModelConfigurationStore.saveConfigurations(stored)
        let doubao = RemoteModelConfigurationStore.loadConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            from: raw
        )

        XCTAssertEqual(doubao?.providerID, RemoteASRProvider.doubaoASR.rawValue)
        XCTAssertEqual(doubao?.appID, "doubao-app")
        XCTAssertEqual(doubao?.accessToken, "doubao-token")
    }

    func testTargetedMetadataLoadDoesNotReturnStoredCredential() {
        let stored = TestFactories.makeRemoteConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            model: DoubaoASRConfiguration.modelV2,
            appID: "doubao-app",
            accessToken: "doubao-token"
        )

        let raw = RemoteModelConfigurationStore.saveConfigurations([stored.providerID: stored])
        let metadata = RemoteModelConfigurationStore.loadConfiguration(
            providerID: stored.providerID,
            from: raw,
            sensitiveValueLoading: .metadataOnly
        )

        XCTAssertTrue(metadata?.appID.isEmpty ?? false)
        XCTAssertTrue(metadata?.accessToken.isEmpty ?? false)
        XCTAssertTrue(metadata?.isConfigured ?? false)
    }

    func testMetadataOnlyLoadPreservesExactBundledCredentialFieldPresence() {
        let stored = TestFactories.makeRemoteConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            model: DoubaoASRConfiguration.modelV2,
            appID: "doubao-app",
            accessToken: ""
        )

        let raw = RemoteModelConfigurationStore.saveConfigurations([stored.providerID: stored])
        let metadata = RemoteModelConfigurationStore.loadConfiguration(
            providerID: stored.providerID,
            from: raw,
            sensitiveValueLoading: .metadataOnly
        )

        XCTAssertTrue(raw.contains("storedCredentialPresence"))
        XCTAssertTrue(metadata?.appID.isEmpty ?? false)
        XCTAssertTrue(metadata?.apiKey.isEmpty ?? false)
        XCTAssertTrue(metadata?.accessToken.isEmpty ?? false)
        XCTAssertFalse(metadata?.isConfigured ?? true)
    }

    func testMetadataOnlyLoadDerivesExactPresenceFromLegacyBundleWithoutMask() throws {
        let bundledValues = """
        {"apiKey":"","appID":"legacy-app","accessToken":""}
        """
        XCTAssertTrue(
            VoxtSecureStorage.set(
                bundledValues,
                for: "remote-provider.doubaoASR.credentials"
            )
        )

        let legacyRaw = """
        [
          {
            "providerID": "doubaoASR",
            "model": "\(DoubaoASRConfiguration.modelV2)",
            "endpoint": "",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let metadata = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                from: legacyRaw,
                sensitiveValueLoading: .metadataOnly
            )
        )

        XCTAssertTrue(metadata.appID.isEmpty)
        XCTAssertTrue(metadata.apiKey.isEmpty)
        XCTAssertTrue(metadata.accessToken.isEmpty)
        XCTAssertFalse(metadata.isConfigured)
    }

    func testLegacyBundleMigrationPersistsCredentialPresenceMetadata() {
        let suiteName = "RemoteModelConfigurationTests.credentialPresence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(
            VoxtSecureStorage.set(
                "{\"apiKey\":\"\",\"appID\":\"legacy-app\",\"accessToken\":\"\"}",
                for: "remote-provider.doubaoASR.credentials"
            )
        )
        defaults.set(
            """
            [{"providerID":"doubaoASR","model":"\(DoubaoASRConfiguration.modelV2)","apiKey":"","appID":"","accessToken":""}]
            """,
            forKey: AppPreferenceKey.remoteASRProviderConfigurations
        )

        RemoteModelConfigurationStore.migrateLegacyStoredSecrets(defaults: defaults)

        let migratedRaw = defaults.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
        let metadata = RemoteModelConfigurationStore.loadConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            from: migratedRaw,
            sensitiveValueLoading: .metadataOnly
        )
        XCTAssertTrue(migratedRaw.contains("storedCredentialPresence"))
        XCTAssertTrue(metadata?.appID.isEmpty ?? false)
        XCTAssertTrue(metadata?.apiKey.isEmpty ?? false)
        XCTAssertTrue(metadata?.accessToken.isEmpty ?? false)
    }

    func testLegacyBundleProtectedWriteFailureKeepsCredentialAvailableAndRetriesLater() {
        let suiteName = "RemoteModelConfigurationTests.credentialPresenceRetry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let account = "remote-provider.doubaoASR.credentials"
        let legacyRaw = """
        [{"providerID":"doubaoASR","model":"\(DoubaoASRConfiguration.modelV2)","apiKey":"","appID":"","accessToken":""}]
        """
        VoxtSecureStorage.setLegacyValueForTesting(
            "{\"apiKey\":\"\",\"appID\":\"legacy-app\",\"accessToken\":\"legacy-token\"}",
            for: account
        )
        VoxtSecureStorage.setProtectedWritesFailForTesting(true)
        defaults.set(legacyRaw, forKey: AppPreferenceKey.remoteASRProviderConfigurations)

        RemoteModelConfigurationStore.migrateLegacyStoredSecrets(defaults: defaults)

        let migratedRaw = defaults.string(
            forKey: AppPreferenceKey.remoteASRProviderConfigurations
        ) ?? ""
        XCTAssertEqual(migratedRaw, legacyRaw)
        XCTAssertEqual(defaults.integer(forKey: AppPreferenceKey.remoteCredentialMigrationVersion), 0)
        XCTAssertTrue(VoxtSecureStorage.hasLegacyValueForTesting(for: account))
        XCTAssertFalse(VoxtSecureStorage.hasProtectedValueForTesting(for: account))

        VoxtSecureStorage.setProtectedWritesFailForTesting(false)
        VoxtSecureStorage.clearCacheForTesting()
        RemoteModelConfigurationStore.migrateLegacyStoredSecrets(defaults: defaults)

        let retriedRaw = defaults.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
        let retried = RemoteModelConfigurationStore.loadConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            from: retriedRaw
        )
        XCTAssertTrue(retriedRaw.contains("storedCredentialPresence"))
        XCTAssertEqual(retried?.appID, "legacy-app")
        XCTAssertEqual(retried?.accessToken, "legacy-token")
        XCTAssertFalse(VoxtSecureStorage.hasLegacyValueForTesting(for: account))
        XCTAssertTrue(VoxtSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertEqual(defaults.integer(forKey: AppPreferenceKey.remoteCredentialMigrationVersion), 1)
    }

    func testStaleCredentialPresenceIsCorrectedOnceAndOneSaveRestoresStableStorage() throws {
        let suiteName = "RemoteModelConfigurationTests.staleCredentialPresence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let providerID = RemoteASRProvider.doubaoASR.rawValue
        let account = "remote-provider.\(providerID).credentials"
        let configured = TestFactories.makeRemoteConfiguration(
            providerID: providerID,
            model: DoubaoASRConfiguration.modelV2,
            appID: "doubao-app",
            accessToken: "doubao-token"
        )
        let staleRaw = RemoteModelConfigurationStore.saveConfigurations([providerID: configured])
        // Reproduce the old failure mode: the item is gone but a process-local
        // cache still contains the value. Migration must trust Keychain state.
        VoxtSecureStorage.removeProtectedValueForTesting(for: account, preservingCache: true)
        defaults.set(staleRaw, forKey: AppPreferenceKey.remoteASRProviderConfigurations)

        RemoteModelConfigurationStore.migrateLegacyStoredSecrets(defaults: defaults)

        let correctedRaw = defaults.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
        let corrected = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: providerID,
                from: correctedRaw,
                sensitiveValueLoading: .metadataOnly
            )
        )
        XCTAssertFalse(corrected.isConfigured)
        XCTAssertEqual(defaults.integer(forKey: AppPreferenceKey.remoteCredentialMigrationVersion), 1)

        let savedRaw = try RemoteModelConfigurationStore.saveConfiguration(
            configured,
            updating: correctedRaw
        ).get()
        VoxtSecureStorage.clearCacheForTesting()
        RemoteModelConfigurationStore.migrateLegacyStoredSecrets(defaults: defaults)
        let reloaded = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(providerID: providerID, from: savedRaw)
        )

        XCTAssertEqual(reloaded.appID, "doubao-app")
        XCTAssertEqual(reloaded.accessToken, "doubao-token")
        XCTAssertTrue(VoxtSecureStorage.hasProtectedValueForTesting(for: account))
    }

    func testLegacyBundleCleanupFailureDoesNotHideCredentialOnFirstLoad() throws {
        let account = "remote-provider.doubaoASR.credentials"
        let raw = """
        [{"providerID":"doubaoASR","model":"\(DoubaoASRConfiguration.modelV2)","apiKey":"","appID":"","accessToken":""}]
        """
        VoxtSecureStorage.setLegacyValueForTesting(
            "{\"apiKey\":\"\",\"appID\":\"legacy-app\",\"accessToken\":\"legacy-token\"}",
            for: account
        )
        VoxtSecureStorage.setDeletesFailForTesting(true)

        let firstLoad = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                from: raw
            )
        )

        XCTAssertEqual(firstLoad.appID, "legacy-app")
        XCTAssertEqual(firstLoad.accessToken, "legacy-token")
        XCTAssertTrue(VoxtSecureStorage.hasProtectedValueForTesting(for: account))
        XCTAssertTrue(VoxtSecureStorage.hasLegacyValueForTesting(for: account))

        VoxtSecureStorage.setDeletesFailForTesting(false)
        VoxtSecureStorage.clearCacheForTesting()

        let retriedLoad = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                from: raw
            )
        )
        XCTAssertEqual(retriedLoad.appID, "legacy-app")
        XCTAssertEqual(retriedLoad.accessToken, "legacy-token")
        XCTAssertFalse(VoxtSecureStorage.hasLegacyValueForTesting(for: account))
    }

    func testSaveConfigurationFailurePreservesPreviousMetadata() {
        let existingRaw = RemoteModelConfigurationStore.saveConfigurations([:])
        let updated = TestFactories.makeRemoteConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            model: DoubaoASRConfiguration.modelV2,
            appID: "doubao-app",
            accessToken: "doubao-token"
        )
        VoxtSecureStorage.setProtectedWritesFailForTesting(true)

        let result = RemoteModelConfigurationStore.saveConfiguration(
            updated,
            updating: existingRaw
        )

        XCTAssertEqual(result, .failure(.secureStorageUnavailable))
        XCTAssertFalse(
            VoxtSecureStorage.hasProtectedValueForTesting(
                for: "remote-provider.doubaoASR.credentials"
            )
        )
    }

    func testMetadataEncodingFailureDoesNotCommitCredential() {
        let existingRaw = RemoteModelConfigurationStore.saveConfigurations([:])
        let updated = TestFactories.makeRemoteConfiguration(
            providerID: RemoteLLMProvider.openAI.rawValue,
            model: "gpt-5.2",
            apiKey: "new-secret",
            generationSettings: LLMGenerationSettings(temperature: .nan)
        )

        let result = RemoteModelConfigurationStore.saveConfiguration(
            updated,
            updating: existingRaw
        )

        XCTAssertEqual(result, .failure(.metadataEncodingFailed))
        XCTAssertFalse(
            VoxtSecureStorage.hasProtectedValueForTesting(
                for: "remote-provider.openAI.credentials"
            )
        )
    }

    func testLegacyCredentialCleanupFailureKeepsBundledSaveConsistent() throws {
        let stored = TestFactories.makeRemoteConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            model: DoubaoASRConfiguration.modelV2,
            appID: "doubao-app",
            accessToken: "doubao-token"
        )
        let existingRaw = RemoteModelConfigurationStore.saveConfigurations([stored.providerID: stored])
        let cleared = TestFactories.makeRemoteConfiguration(
            providerID: stored.providerID,
            model: stored.model
        )
        VoxtSecureStorage.setLegacyValueForTesting(
            "legacy-app",
            for: "remote-provider.doubaoASR.appID"
        )
        VoxtSecureStorage.setLegacyValueForTesting(
            "legacy-token",
            for: "remote-provider.doubaoASR.accessToken"
        )
        VoxtSecureStorage.setDeletesFailForTesting(true)

        let clearedRaw = try RemoteModelConfigurationStore.saveConfiguration(
            cleared,
            updating: existingRaw
        ).get()

        XCTAssertNotEqual(clearedRaw, existingRaw)
        let resolved = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(providerID: stored.providerID, from: clearedRaw)
        )
        XCTAssertTrue(resolved.appID.isEmpty)
        XCTAssertTrue(resolved.accessToken.isEmpty)
        XCTAssertFalse(resolved.isConfigured)
        XCTAssertTrue(
            VoxtSecureStorage.hasLegacyValueForTesting(
                for: "remote-provider.doubaoASR.appID"
            )
        )
        XCTAssertTrue(
            VoxtSecureStorage.hasLegacyValueForTesting(
                for: "remote-provider.doubaoASR.accessToken"
            )
        )

        VoxtSecureStorage.setDeletesFailForTesting(false)
        let cleanedRaw = try RemoteModelConfigurationStore.saveConfiguration(
            cleared,
            updating: clearedRaw
        ).get()
        let cleaned = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(providerID: stored.providerID, from: cleanedRaw)
        )

        XCTAssertTrue(cleaned.appID.isEmpty)
        XCTAssertTrue(cleaned.accessToken.isEmpty)
        XCTAssertFalse(
            VoxtSecureStorage.hasString(
                for: "remote-provider.doubaoASR.credentials"
            )
        )
        XCTAssertFalse(
            VoxtSecureStorage.hasLegacyValueForTesting(
                for: "remote-provider.doubaoASR.appID"
            )
        )
        XCTAssertFalse(
            VoxtSecureStorage.hasLegacyValueForTesting(
                for: "remote-provider.doubaoASR.accessToken"
            )
        )
    }

    func testLegacyCleanupFailureDoesNotPairNewCredentialWithOldMetadata() throws {
        let providerID = RemoteASRProvider.aliyunBailianASR.rawValue
        let initial = TestFactories.makeRemoteConfiguration(
            providerID: providerID,
            model: "fun-asr-realtime",
            endpoint: "wss://old.example.com/realtime",
            apiKey: "old-key"
        )
        let existingRaw = RemoteModelConfigurationStore.saveConfigurations([providerID: initial])
        let updated = TestFactories.makeRemoteConfiguration(
            providerID: providerID,
            model: "qwen3-asr-flash-realtime",
            endpoint: "wss://new.example.com/realtime",
            apiKey: "new-key"
        )
        VoxtSecureStorage.setLegacyValueForTesting(
            "old-key",
            for: "remote-provider.\(providerID).apiKey"
        )
        VoxtSecureStorage.setDeletesFailForTesting(true)

        let updatedRaw = try RemoteModelConfigurationStore.saveConfiguration(
            updated,
            updating: existingRaw
        ).get()
        let resolved = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(providerID: providerID, from: updatedRaw)
        )

        XCTAssertEqual(resolved.model, "qwen3-asr-flash-realtime")
        XCTAssertEqual(resolved.endpoint, "wss://new.example.com/realtime")
        XCTAssertEqual(resolved.apiKey, "new-key")
    }

    func testProviderCredentialsUseSingleBundledKeychainItem() {
        let stored = TestFactories.makeRemoteConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            model: DoubaoASRConfiguration.modelV2,
            appID: "doubao-app",
            accessToken: "doubao-token"
        )

        _ = RemoteModelConfigurationStore.saveConfigurations([stored.providerID: stored])
        VoxtSecureStorage.clearCacheForTesting()

        XCTAssertTrue(
            VoxtSecureStorage.hasString(for: "remote-provider.doubaoASR.credentials")
        )
        XCTAssertFalse(
            VoxtSecureStorage.hasString(for: "remote-provider.doubaoASR.appID")
        )
        XCTAssertFalse(
            VoxtSecureStorage.hasString(for: "remote-provider.doubaoASR.accessToken")
        )
    }

    func testLegacyPerFieldCredentialsMigrateToBundledItemOnFirstRead() throws {
        VoxtSecureStorage.set("legacy-app", for: "remote-provider.doubaoASR.appID")
        VoxtSecureStorage.set("legacy-token", for: "remote-provider.doubaoASR.accessToken")
        VoxtSecureStorage.clearCacheForTesting()

        let raw = """
        [
          {
            "providerID": "doubaoASR",
            "model": "\(DoubaoASRConfiguration.modelV2)",
            "endpoint": "",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let migrated = try XCTUnwrap(
            RemoteModelConfigurationStore.loadConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                from: raw
            )
        )
        VoxtSecureStorage.clearCacheForTesting()

        XCTAssertEqual(migrated.appID, "legacy-app")
        XCTAssertEqual(migrated.accessToken, "legacy-token")
        XCTAssertTrue(
            VoxtSecureStorage.hasString(for: "remote-provider.doubaoASR.credentials")
        )
        XCTAssertFalse(
            VoxtSecureStorage.hasString(for: "remote-provider.doubaoASR.appID")
        )
        XCTAssertFalse(
            VoxtSecureStorage.hasString(for: "remote-provider.doubaoASR.accessToken")
        )
    }

    func testOllamaConfigurationIsConfiguredWithoutAPIKeyWhenModelExists() {
        let configuration = TestFactories.makeRemoteConfiguration(
            providerID: RemoteLLMProvider.ollama.rawValue,
            model: "qwen3"
        )

        XCTAssertTrue(configuration.isConfigured)
    }

    func testOMLXConfigurationIsConfiguredWithoutAPIKeyWhenModelExists() {
        let configuration = TestFactories.makeRemoteConfiguration(
            providerID: RemoteLLMProvider.omlx.rawValue,
            model: "qwen3"
        )

        XCTAssertTrue(configuration.isConfigured)
    }

    func testOpenAIConfigurationStillRequiresCredential() {
        let configuration = TestFactories.makeRemoteConfiguration(
            providerID: RemoteLLMProvider.openAI.rawValue,
            model: "gpt-5.2"
        )

        XCTAssertFalse(configuration.isConfigured)
    }

    func testDoubaoConfigurationRequiresBothAppIDAndAccessToken() {
        let onlyAppID = TestFactories.makeRemoteConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            model: DoubaoASRConfiguration.modelV2,
            appID: "doubao-app"
        )
        let onlyAccessToken = TestFactories.makeRemoteConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            model: DoubaoASRConfiguration.modelV2,
            accessToken: "doubao-token"
        )
        let complete = TestFactories.makeRemoteConfiguration(
            providerID: RemoteASRProvider.doubaoASR.rawValue,
            model: DoubaoASRConfiguration.modelV2,
            appID: "doubao-app",
            accessToken: "doubao-token"
        )

        XCTAssertFalse(onlyAppID.isConfigured)
        XCTAssertFalse(onlyAccessToken.isConfigured)
        XCTAssertTrue(complete.isConfigured)
    }

    func testCodexConfigurationUsesLocalLoginAndDoesNotRequireAPIKey() {
        let configuration = TestFactories.makeRemoteConfiguration(
            providerID: RemoteLLMProvider.codex.rawValue,
            model: "gpt-5.4-mini"
        )

        XCTAssertTrue(configuration.isConfigured)
        XCTAssertTrue(RemoteLLMProvider.codex.apiKeyIsOptional)
        XCTAssertTrue(RemoteLLMProvider.codex.usesResponsesAPI)
    }

    func testCodexCredentialProviderReadsLocalAuthFile() async throws {
        let directory = try TemporaryDirectory()
        let token = try makeTestJWT(payload: [
            "exp": Date().addingTimeInterval(3600).timeIntervalSince1970,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "acct_test"
            ]
        ])
        let authURL = directory.url.appendingPathComponent("auth.json")
        let authData = try JSONSerialization.data(withJSONObject: [
            "auth_mode": "chatgpt",
            "tokens": [
                "access_token": token,
                "refresh_token": "refresh-token"
            ]
        ])
        try authData.write(to: authURL)

        let headers = try await CodexOAuthCredentialProvider(
            environment: ["CODEX_HOME": directory.url.path]
        ).authorizationHeaders()

        XCTAssertEqual(headers["Authorization"], "Bearer \(token)")
        XCTAssertEqual(headers["ChatGPT-Account-ID"], "acct_test")
        XCTAssertEqual(headers["originator"], "codex_cli_rs")
    }

    func testCodexCredentialProviderReadsSelectedAuthFilePath() async throws {
        let directory = try TemporaryDirectory()
        let token = try makeTestJWT(payload: [
            "exp": Date().addingTimeInterval(3600).timeIntervalSince1970
        ])
        let authURL = directory.url.appendingPathComponent("selected-auth.json")
        let authData = try JSONSerialization.data(withJSONObject: [
            "auth_mode": "chatgpt",
            "tokens": [
                "access_token": token,
                "refresh_token": "refresh-token",
                "account_id": "acct_selected"
            ]
        ])
        try authData.write(to: authURL)

        let headers = try await CodexOAuthCredentialProvider(
            environment: ["CODEX_HOME": "/missing-codex-home"],
            authFilePath: authURL.path
        ).authorizationHeaders()

        XCTAssertEqual(headers["Authorization"], "Bearer \(token)")
        XCTAssertEqual(headers["ChatGPT-Account-ID"], "acct_selected")
    }

    func testCodexCredentialProviderReportsAuthFilePermissionDenied() async throws {
        let directory = try TemporaryDirectory()
        let authURL = directory.url.appendingPathComponent("auth.json")
        try Data("{}".utf8).write(to: authURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: authURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: authURL.path)
        }

        do {
            _ = try await CodexOAuthCredentialProvider(authFilePath: authURL.path).authorizationHeaders()
            XCTFail("Expected auth file permission error")
        } catch CodexOAuthCredentialProvider.CredentialError.authFilePermissionDenied(let path) {
            XCTAssertEqual(path, authURL.path)
        } catch {
            XCTFail("Expected auth file permission error, got \(error)")
        }
    }

    func testCodexConfigurationRoundTripPreservesAuthFileSelection() {
        let bookmark = Data([1, 2, 3, 4])
        let stored: [String: RemoteProviderConfiguration] = [
            RemoteLLMProvider.codex.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.codex.rawValue,
                model: "gpt-5.3-codex-spark",
                codexAuthFilePath: "/Users/test/.config/codex/auth.json",
                codexAuthFileBookmark: bookmark,
                codexFastModeEnabled: true
            )
        ]

        let raw = RemoteModelConfigurationStore.saveConfigurations(stored)
        let roundTrip = RemoteModelConfigurationStore.loadConfigurations(from: raw)
        let restored = roundTrip[RemoteLLMProvider.codex.rawValue]

        XCTAssertEqual(restored?.codexAuthFilePath, "/Users/test/.config/codex/auth.json")
        XCTAssertEqual(restored?.codexAuthFileBookmark, bookmark)
        XCTAssertEqual(restored?.codexFastModeEnabled, true)
    }

    func testDecodeLegacyCodexConfigurationDefaultsFastModeToOff() throws {
        let legacyJSON = """
        [
          {
            "providerID": "\(RemoteLLMProvider.codex.rawValue)",
            "model": "gpt-5.4",
            "endpoint": "",
            "apiKey": ""
          }
        ]
        """

        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: legacyJSON)

        XCTAssertEqual(loaded[RemoteLLMProvider.codex.rawValue]?.codexFastModeEnabled, false)
    }

    func testCodexCredentialProviderUsesUserHomeOutsideAppContainer() {
        let provider = CodexOAuthCredentialProvider(
            environment: [
                "HOME": "/Users/test/Library/Containers/com.voxt.Voxt/Data"
            ],
            userHomeDirectory: "/Users/test"
        )

        XCTAssertEqual(provider.authFilePath(), "/Users/test/.codex/auth.json")
    }

    func testCodexCredentialProviderExpandsCodexHomeWithUserHome() {
        let provider = CodexOAuthCredentialProvider(
            environment: [
                "CODEX_HOME": "~/.config/codex",
                "HOME": "/Users/test/Library/Containers/com.voxt.Voxt/Data"
            ],
            userHomeDirectory: "/Users/test"
        )

        XCTAssertEqual(provider.authFilePath(), "/Users/test/.config/codex/auth.json")
    }

    func testOpenAIModelCatalogUsesOfficialModelIDs() {
        XCTAssertEqual(RemoteLLMProvider.openAI.suggestedModel, "gpt-5.2")

        let ids = RemoteLLMProvider.openAI.modelOptions.map(\.id)
        XCTAssertTrue(ids.contains("gpt-5.2"))
        XCTAssertTrue(ids.contains("gpt-5.2-pro"))
        XCTAssertTrue(ids.contains("gpt-5.1"))
        XCTAssertFalse(ids.contains("gpt-5.5"))
        XCTAssertFalse(ids.contains("gpt-5.4"))
    }

    func testCodexModelCatalogDefaultsToCurrentModel() {
        XCTAssertEqual(RemoteLLMProvider.codex.suggestedModel, "gpt-5.4")

        let ids = RemoteLLMProvider.codex.modelOptions.map(\.id)
        XCTAssertEqual(ids.first, "gpt-5.4")
        XCTAssertTrue(ids.contains("gpt-5.3-codex-spark"))
        XCTAssertTrue(ids.contains("gpt-5.4-mini"))
    }

    func testOpenAIReasoningEffortOptionsFollowModelSupport() {
        XCTAssertEqual(
            OpenAIReasoningEffort.supportedCases(forModel: "gpt-5.2"),
            [.automatic, .none, .low, .medium, .high, .xhigh]
        )
        XCTAssertEqual(
            OpenAIReasoningEffort.supportedCases(forModel: "gpt-5.2-pro"),
            [.automatic, .medium, .high, .xhigh]
        )
        XCTAssertEqual(
            OpenAIReasoningEffort.supportedCases(forModel: "gpt-5.1"),
            [.automatic, .none, .low, .medium, .high]
        )
        XCTAssertEqual(
            OpenAIReasoningEffort.supportedCases(forModel: "gpt-5"),
            [.automatic, .minimal, .low, .medium, .high]
        )
    }

    private func makeTestJWT(payload: [String: Any]) throws -> String {
        let headerData = try JSONSerialization.data(withJSONObject: ["alg": "none", "typ": "JWT"])
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        return "\(base64URLEncoded(headerData)).\(base64URLEncoded(payloadData)).signature"
    }

    private func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func testLoadSaveRoundTripPreservesOllamaConfigurationFields() {
        let stored: [String: RemoteProviderConfiguration] = [
            RemoteLLMProvider.ollama.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteLLMProvider.ollama.rawValue,
                model: "qwen3",
                endpoint: "http://127.0.0.1:11434/api/chat",
                ollamaResponseFormat: OllamaResponseFormat.jsonSchema.rawValue,
                ollamaJSONSchema: #"{"type":"object","properties":{"answer":{"type":"string"}}}"#,
                ollamaThinkMode: OllamaThinkMode.low.rawValue,
                ollamaKeepAlive: "5m",
                ollamaLogprobsEnabled: true,
                ollamaTopLogprobs: 7,
                ollamaOptionsJSON: #"{"num_ctx":8192,"repeat_penalty":1.05}"#
            )
        ]

        let raw = RemoteModelConfigurationStore.saveConfigurations(stored)
        let roundTrip = RemoteModelConfigurationStore.loadConfigurations(from: raw)
        let restored = roundTrip[RemoteLLMProvider.ollama.rawValue]

        XCTAssertEqual(restored?.ollamaResponseFormat, OllamaResponseFormat.jsonSchema.rawValue)
        XCTAssertEqual(restored?.ollamaJSONSchema, #"{"type":"object","properties":{"answer":{"type":"string"}}}"#)
        XCTAssertEqual(restored?.ollamaThinkMode, OllamaThinkMode.low.rawValue)
        XCTAssertEqual(restored?.ollamaKeepAlive, "5m")
        XCTAssertEqual(restored?.ollamaLogprobsEnabled, true)
        XCTAssertEqual(restored?.ollamaTopLogprobs, 7)
        XCTAssertEqual(restored?.ollamaOptionsJSON, #"{"num_ctx":8192,"repeat_penalty":1.05}"#)
        XCTAssertEqual(restored?.generationSettings.responseFormat, .jsonSchema)
        XCTAssertEqual(restored?.generationSettings.thinking.mode, .effort)
        XCTAssertEqual(restored?.generationSettings.thinking.effort, OllamaThinkMode.low.rawValue)
        XCTAssertEqual(restored?.generationSettings.logprobs, true)
        XCTAssertEqual(restored?.generationSettings.topLogprobs, 7)
        XCTAssertEqual(restored?.generationSettings.extraOptionsJSON, #"{"num_ctx":8192,"repeat_penalty":1.05}"#)
    }

    func testLegacyOpenAIConfigurationMigratesToUnifiedGenerationSettings() {
        let configuration = TestFactories.makeRemoteConfiguration(
            providerID: RemoteLLMProvider.openAI.rawValue,
            model: "gpt-5.2",
            openAIReasoningEffort: OpenAIReasoningEffort.high.rawValue,
            openAIMaxOutputTokens: 4096
        )

        XCTAssertEqual(configuration.generationSettings.maxOutputTokens, 4096)
        XCTAssertEqual(configuration.generationSettings.thinking.mode, .effort)
        XCTAssertEqual(configuration.generationSettings.thinking.effort, OpenAIReasoningEffort.high.rawValue)
    }

    func testResolvedASRConfigurationFallsBackToSuggestedModelAndClearsRealtimeFlag() {
        let stored: [String: RemoteProviderConfiguration] = [
            RemoteASRProvider.doubaoASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: "invalid-model",
                accessToken: "token",
                openAIChunkPseudoRealtimeEnabled: true
            )
        ]

        let resolved = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: .doubaoASR,
            stored: stored
        )

        XCTAssertEqual(resolved.model, RemoteASRProvider.doubaoASR.suggestedModel)
        XCTAssertFalse(resolved.openAIChunkPseudoRealtimeEnabled)
    }

    func testResolvedLLMConfigurationDefaultsWhenMissing() {
        let resolved = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: .anthropic,
            stored: [:]
        )

        XCTAssertEqual(resolved.providerID, RemoteLLMProvider.anthropic.rawValue)
        XCTAssertEqual(resolved.model, RemoteLLMProvider.anthropic.suggestedModel)
        XCTAssertEqual(resolved.endpoint, "")
        XCTAssertFalse(resolved.searchEnabled)
    }

    func testResponsesProviderCapabilitiesAreConfiguredPerProvider() {
        XCTAssertTrue(RemoteLLMProvider.openAI.usesResponsesAPI)
        XCTAssertTrue(RemoteLLMProvider.codex.usesResponsesAPI)
        XCTAssertTrue(RemoteLLMProvider.aliyunBailian.usesResponsesAPI)
        XCTAssertTrue(RemoteLLMProvider.volcengine.usesResponsesAPI)
        XCTAssertTrue(RemoteLLMProvider.aliyunBailian.supportsHostedSearch)
        XCTAssertTrue(RemoteLLMProvider.volcengine.supportsHostedSearch)
        XCTAssertTrue(RemoteLLMProvider.aliyunBailian.defaultSearchEnabled)
        XCTAssertFalse(RemoteLLMProvider.volcengine.defaultSearchEnabled)
        XCTAssertTrue(RemoteLLMProvider.omlx.apiKeyIsOptional)
        XCTAssertTrue(RemoteLLMProvider.codex.apiKeyIsOptional)
        XCTAssertFalse(RemoteLLMProvider.omlx.usesResponsesAPI)
    }

    func testCodexModelCatalogUsesCurrentFallbackPresets() {
        XCTAssertEqual(RemoteLLMProvider.codex.suggestedModel, "gpt-5.4")

        let latestIDs = RemoteLLMProvider.codex.latestModelOptions.map(\.id)
        XCTAssertEqual(latestIDs.first, "gpt-5.4")
        XCTAssertTrue(latestIDs.contains("gpt-5.5"))
        XCTAssertTrue(latestIDs.contains("gpt-5.3-codex"))
        XCTAssertTrue(latestIDs.contains("gpt-5-codex-mini"))
        XCTAssertTrue(latestIDs.contains("gpt-oss-120b"))
    }

    func testCodexGenerationCapabilitiesMatchCodexBackend() {
        let capabilities = LLMProviderCapabilityRegistry.capabilities(for: .codex)

        XCTAssertFalse(capabilities.supportsThinkingEffort)
        XCTAssertFalse(capabilities.supportsResponseFormat)
        XCTAssertFalse(capabilities.supportsMaxOutputTokens)
        XCTAssertFalse(capabilities.supportsTemperature)
        XCTAssertFalse(capabilities.supportsTopP)
        XCTAssertFalse(capabilities.supportsLogprobs)
        XCTAssertFalse(capabilities.supportsStopSequences)
        XCTAssertFalse(capabilities.supportsExtraBody)
    }

    func testDeepSeekUsesCurrentSuggestedModelAndKeepsLegacyAliases() {
        XCTAssertEqual(RemoteLLMProvider.deepseek.suggestedModel, "deepseek-v4-flash")

        let latestIDs = RemoteLLMProvider.deepseek.latestModelOptions.map(\.id)
        XCTAssertTrue(latestIDs.contains("deepseek-v4-flash"))
        XCTAssertTrue(latestIDs.contains("deepseek-v4-pro"))

        let allIDs = RemoteLLMProvider.deepseek.modelOptions.map(\.id)
        XCTAssertTrue(allIDs.contains("deepseek-chat"))
        XCTAssertTrue(allIDs.contains("deepseek-reasoner"))
    }

    func testStepFunUsesChatCompletionModelCatalogAndCapabilities() {
        XCTAssertEqual(RemoteLLMProvider.stepFun.suggestedModel, "step-3.5-flash")
        XCTAssertFalse(RemoteLLMProvider.stepFun.usesResponsesAPI)
        XCTAssertFalse(RemoteLLMProvider.stepFun.supportsHostedSearch)

        let ids = RemoteLLMProvider.stepFun.modelOptions.map(\.id)
        XCTAssertTrue(ids.contains("step-3.5-flash"))
        XCTAssertTrue(ids.contains("step-3.5-flash-2603"))
        XCTAssertTrue(ids.contains("step-2-mini"))
        XCTAssertTrue(ids.contains("step-1-32k"))
        XCTAssertTrue(ids.contains("step-router-v1"))

        let capabilities = LLMProviderCapabilityRegistry.capabilities(for: .stepFun)
        XCTAssertTrue(capabilities.supportsThinkingEffort)
        XCTAssertFalse(capabilities.supportsThinkingBudget)
        XCTAssertTrue(capabilities.supportsResponseFormat)
    }

    func testXiaomiMiMoUsesChatCompletionModelCatalogAndCapabilities() {
        XCTAssertEqual(RemoteASRProvider.xiaomiMiMoASR.suggestedModel, "mimo-v2.5-asr")
        XCTAssertEqual(RemoteASRProvider.xiaomiMiMoASR.modelOptions.map(\.id), ["mimo-v2.5-asr"])

        XCTAssertEqual(RemoteLLMProvider.xiaomiMiMo.suggestedModel, "mimo-v2.5-pro")
        XCTAssertFalse(RemoteLLMProvider.xiaomiMiMo.usesResponsesAPI)
        XCTAssertFalse(RemoteLLMProvider.xiaomiMiMo.supportsHostedSearch)

        let ids = RemoteLLMProvider.xiaomiMiMo.modelOptions.map(\.id)
        XCTAssertTrue(ids.contains("mimo-v2.5-pro"))
        XCTAssertTrue(ids.contains("mimo-v2.5"))

        let capabilities = LLMProviderCapabilityRegistry.capabilities(for: .xiaomiMiMo)
        XCTAssertTrue(capabilities.supportsThinkingToggle)
        XCTAssertFalse(capabilities.supportsThinkingEffort)
        XCTAssertFalse(capabilities.supportsThinkingBudget)
        XCTAssertTrue(capabilities.supportsPenalties)
        XCTAssertFalse(capabilities.supportsLogprobs)
        XCTAssertTrue(capabilities.supportsResponseFormat)
    }

    func testStepFunLLMConfigurationDefaultsThinkingToOff() {
        let resolved = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: .stepFun,
            stored: [:]
        )

        XCTAssertEqual(resolved.generationSettings.thinking.mode, .off)
        XCTAssertEqual(resolved.effectiveGenerationSettings(provider: .stepFun).thinking.mode, .off)
    }

    func testStepFunLegacyConfigurationDoesNotInheritOpenAIReasoningEffort() {
        let configuration = TestFactories.makeRemoteConfiguration(
            providerID: RemoteLLMProvider.stepFun.rawValue,
            model: "step-3.5-flash-2603",
            openAIReasoningEffort: OpenAIReasoningEffort.high.rawValue
        )

        XCTAssertEqual(configuration.generationSettings.thinking.mode, .off)
        XCTAssertNil(configuration.generationSettings.thinking.effort)
    }

    func testResolvedAliyunLLMConfigurationDefaultsSearchToEnabled() {
        let resolved = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: .aliyunBailian,
            stored: [:]
        )

        XCTAssertTrue(resolved.searchEnabled)
    }

    func testResolvedVolcengineLLMConfigurationDefaultsSearchToDisabled() {
        let resolved = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: .volcengine,
            stored: [:]
        )

        XCTAssertFalse(resolved.searchEnabled)
    }

    func testDecodeLegacyAliyunLLMConfigurationDefaultsSearchToEnabled() throws {
        let legacyJSON = """
        [
          {
            "providerID": "aliyunBailian",
            "model": "qwen-plus-latest",
            "endpoint": "",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: legacyJSON)

        XCTAssertEqual(loaded["aliyunBailian"]?.searchEnabled, true)
    }

    func testDecodeLegacyVolcengineLLMConfigurationDefaultsSearchToDisabled() throws {
        let legacyJSON = """
        [
          {
            "providerID": "volcengine",
            "model": "doubao-1-5-pro",
            "endpoint": "",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: legacyJSON)

        XCTAssertEqual(loaded["volcengine"]?.searchEnabled, false)
    }

    func testDecodeLegacyAliyunEndpointMigratesToResponsesURL() {
        let legacyJSON = """
        [
          {
            "providerID": "aliyunBailian",
            "model": "qwen-plus-latest",
            "endpoint": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: legacyJSON)

        XCTAssertEqual(
            loaded["aliyunBailian"]?.endpoint,
            "https://dashscope.aliyuncs.com/compatible-mode/v1/responses"
        )
    }

    func testDecodeLegacyVolcengineEndpointMigratesToResponsesURL() {
        let legacyJSON = """
        [
          {
            "providerID": "volcengine",
            "model": "doubao-1-5-pro",
            "endpoint": "https://ark.cn-beijing.volces.com/api/v3/models",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: legacyJSON)

        XCTAssertEqual(
            loaded["volcengine"]?.endpoint,
            "https://ark.cn-beijing.volces.com/api/v3/responses"
        )
    }

    func testDecodeLegacyOpenAIEndpointMigratesToResponsesURL() {
        let legacyJSON = """
        [
          {
            "providerID": "openAI",
            "model": "gpt-5.2",
            "endpoint": "https://api.openai.com/v1/chat/completions",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: legacyJSON)

        XCTAssertEqual(
            loaded["openAI"]?.endpoint,
            "https://api.openai.com/v1/responses"
        )
    }

    func testMigrateLegacyLLMEndpointsRewritesPersistedLegacyURLs() {
        let suiteName = "RemoteModelConfigurationTests.migrateLegacyLLMEndpoints.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            """
            [
              {
                "providerID": "openAI",
                "model": "gpt-5.2",
                "endpoint": "https://api.openai.com/v1/models",
                "apiKey": "",
                "appID": "",
                "accessToken": ""
              },
              {
                "providerID": "aliyunBailian",
                "model": "qwen-plus-latest",
                "endpoint": "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                "apiKey": "",
                "appID": "",
                "accessToken": ""
              },
              {
                "providerID": "volcengine",
                "model": "doubao-1-5-pro",
                "endpoint": "https://ark.cn-beijing.volces.com/api/v3/models",
                "apiKey": "",
                "appID": "",
                "accessToken": ""
              }
            ]
            """,
            forKey: AppPreferenceKey.remoteLLMProviderConfigurations
        )

        RemoteModelConfigurationStore.migrateLegacyLLMEndpoints(defaults: defaults)

        let migrated = RemoteModelConfigurationStore.loadConfigurations(
            from: defaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? ""
        )

        XCTAssertEqual(
            migrated["openAI"]?.endpoint,
            "https://api.openai.com/v1/responses"
        )
        XCTAssertEqual(
            migrated["aliyunBailian"]?.endpoint,
            "https://dashscope.aliyuncs.com/compatible-mode/v1/responses"
        )
        XCTAssertEqual(
            migrated["volcengine"]?.endpoint,
            "https://ark.cn-beijing.volces.com/api/v3/responses"
        )
    }

    func testMigrateLegacyStoredSecretsSkipsAlreadySanitizedPayloads() {
        let suiteName = "RemoteModelConfigurationTests.migrateLegacyStoredSecrets.skip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let raw = """
        [
          {
            "providerID": "openAI",
            "model": "gpt-5.2",
            "endpoint": "https://example.com/responses",
            "apiKey": "",
            "appID": "",
            "accessToken": ""
          }
        ]
        """

        defaults.set(raw, forKey: AppPreferenceKey.remoteLLMProviderConfigurations)

        RemoteModelConfigurationStore.migrateLegacyStoredSecrets(defaults: defaults)

        XCTAssertEqual(
            defaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations),
            raw
        )
        XCTAssertNil(
            VoxtSecureStorage.string(
                for: "remote-provider.openAI.apiKey"
            )
        )
        XCTAssertNil(
            VoxtSecureStorage.string(
                for: "remote-provider.openAI.credentials"
            )
        )
        XCTAssertEqual(defaults.integer(forKey: AppPreferenceKey.remoteCredentialMigrationVersion), 1)
    }

    func testSavingOneRemoteASRProviderPreservesOtherProviderSecrets() throws {
        let initial: [String: RemoteProviderConfiguration] = [
            RemoteASRProvider.doubaoASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.doubaoASR.rawValue,
                model: DoubaoASRConfiguration.modelV2,
                appID: "doubao-app",
                accessToken: "doubao-token"
            ),
            RemoteASRProvider.aliyunBailianASR.rawValue: TestFactories.makeRemoteConfiguration(
                providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
                model: "fun-asr-realtime",
                endpoint: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
                apiKey: "aliyun-key"
            )
        ]

        let raw = RemoteModelConfigurationStore.saveConfigurations(initial)
        let updatedAliyun = TestFactories.makeRemoteConfiguration(
            providerID: RemoteASRProvider.aliyunBailianASR.rawValue,
            model: "qwen3-asr-flash-realtime",
            endpoint: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
            apiKey: "aliyun-key-updated"
        )

        let mergedRaw = try RemoteModelConfigurationStore.saveConfiguration(
            updatedAliyun,
            updating: raw
        ).get()
        let loaded = RemoteModelConfigurationStore.loadConfigurations(from: mergedRaw)

        XCTAssertEqual(loaded[RemoteASRProvider.aliyunBailianASR.rawValue]?.apiKey, "aliyun-key-updated")
        XCTAssertEqual(loaded[RemoteASRProvider.doubaoASR.rawValue]?.appID, "doubao-app")
        XCTAssertEqual(loaded[RemoteASRProvider.doubaoASR.rawValue]?.accessToken, "doubao-token")
    }

    func testRemoteASRTextSanitizerRejectsIdentifierLikeStrings() {
        XCTAssertTrue(RemoteASRTextSanitizer.isLikelyIdentifierText("9ff6a1a4-f758-4a87-b761-11508533c499"))
        XCTAssertTrue(RemoteASRTextSanitizer.isLikelyIdentifierText("abc123ef456789ab_cdef1234567890"))
        XCTAssertTrue(RemoteASRTextSanitizer.isLikelyIdentifierText("9ff6a1a4f7584a87b76111508533c499"))
    }

    func testRemoteASRTextSanitizerAllowsNaturalLanguageText() {
        XCTAssertFalse(RemoteASRTextSanitizer.isLikelyIdentifierText("你好"))
        XCTAssertFalse(RemoteASRTextSanitizer.isLikelyIdentifierText("我们今天继续开会"))
        XCTAssertFalse(RemoteASRTextSanitizer.isLikelyIdentifierText("hello world 2026"))
    }

}
