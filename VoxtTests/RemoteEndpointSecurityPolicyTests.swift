// RemoteEndpointSecurityPolicyTests.swift

import XCTest
@testable import Voxt

final class RemoteEndpointSecurityPolicyTests: XCTestCase {
    func testCredentialDetectionIncludesCodexOAuthSource() {
        let codex = RemoteProviderConfiguration(
            providerID: RemoteLLMProvider.codex.rawValue,
            model: "gpt-5-codex",
            endpoint: "http://api.example.com/responses",
            apiKey: ""
        )
        let openAIWithoutKey = RemoteProviderConfiguration(
            providerID: RemoteLLMProvider.openAI.rawValue,
            model: "gpt-5",
            endpoint: "http://api.example.com/v1",
            apiKey: ""
        )

        XCTAssertTrue(RemoteEndpointSecurityPolicy.hasLLMCredentials(provider: .codex, configuration: codex))
        XCTAssertFalse(RemoteEndpointSecurityPolicy.hasLLMCredentials(provider: .openAI, configuration: openAIWithoutKey))
        XCTAssertNotNil(RemoteEndpointSecurityPolicy.validationMessage(
            endpoint: codex.endpoint,
            hasCredentials: RemoteEndpointSecurityPolicy.hasLLMCredentials(provider: .codex, configuration: codex)
        ))
    }

    @MainActor
    func testCodexAuthorizationRejectsRemoteHTTPBeforeReadingCredentials() async {
        let configuration = RemoteProviderConfiguration(
            providerID: RemoteLLMProvider.codex.rawValue,
            model: "gpt-5-codex",
            endpoint: "http://api.example.com/responses",
            apiKey: "",
            codexAuthFilePath: "/path/that/does/not/exist"
        )

        do {
            _ = try await RemoteLLMRuntimeClient().authorizationHeaders(
                provider: .codex,
                configuration: configuration
            )
            XCTFail("Expected insecure endpoint validation to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                AppLocalization.localizedString(
                    "Insecure endpoints can receive credentials only on this Mac. Use HTTPS or WSS for remote hosts."
                )
            )
        }
    }

    @MainActor
    func testConnectivityTesterRejectsRemoteHTTPBeforeSendingAPIKey() async {
        let configuration = RemoteProviderConfiguration(
            providerID: RemoteLLMProvider.deepseek.rawValue,
            model: "deepseek-chat",
            endpoint: "http://api.example.com/v1",
            apiKey: "secret"
        )

        do {
            _ = try await RemoteProviderConnectivityTester(testTarget: .llm(.deepseek))
                .run(configuration: configuration)
            XCTFail("Expected insecure endpoint validation to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                AppLocalization.localizedString(
                    "Insecure endpoints can receive credentials only on this Mac. Use HTTPS or WSS for remote hosts."
                )
            )
        }
    }

    @MainActor
    func testRemoteASRFileTranscriptionRejectsRemoteHTTPBeforeUploadingAPIKey() async {
        let configuration = RemoteProviderConfiguration(
            providerID: RemoteASRProvider.openAIWhisper.rawValue,
            model: RemoteASRProvider.openAIWhisper.suggestedModel,
            endpoint: "http://api.example.com/v1/audio/transcriptions",
            apiKey: "secret"
        )

        do {
            _ = try await RemoteASRTranscriber().transcribeDebugAudioFile(
                URL(fileURLWithPath: "/path/that/does/not/exist.wav"),
                provider: .openAIWhisper,
                configuration: configuration
            )
            XCTFail("Expected insecure endpoint validation to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                AppLocalization.localizedString(
                    "Insecure endpoints can receive credentials only on this Mac. Use HTTPS or WSS for remote hosts."
                )
            )
        }
    }

    func testAllowsHTTPSCredentialsAndLoopbackHTTP() {
        XCTAssertNil(RemoteEndpointSecurityPolicy.validationMessage(endpoint: "https://api.example.com/v1", hasCredentials: true))
        XCTAssertNil(RemoteEndpointSecurityPolicy.validationMessage(endpoint: "http://127.0.0.1:11434/v1", hasCredentials: true))
        XCTAssertNil(RemoteEndpointSecurityPolicy.validationMessage(endpoint: "http://192.168.1.10:11434/v1", hasCredentials: false))
        XCTAssertNil(RemoteEndpointSecurityPolicy.validationMessage(
            endpoint: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime",
            hasCredentials: true,
            allowsWebSocket: true
        ))
    }

    func testRejectsCredentialsSentToRemoteHTTPAndURLUserInfo() {
        XCTAssertNotNil(RemoteEndpointSecurityPolicy.validationMessage(endpoint: "http://api.example.com/v1", hasCredentials: true))
        XCTAssertNotNil(RemoteEndpointSecurityPolicy.validationMessage(endpoint: "https://user:secret@example.com/v1", hasCredentials: false))
        XCTAssertNotNil(RemoteEndpointSecurityPolicy.validationMessage(
            endpoint: "ws://api.example.com/realtime",
            hasCredentials: true,
            allowsWebSocket: true
        ))
        XCTAssertNotNil(RemoteEndpointSecurityPolicy.validationMessage(
            endpoint: "wss://api.example.com/realtime",
            hasCredentials: true
        ))
    }

    func testSanitizedLogEndpointRemovesCredentialsQueryAndFragment() {
        XCTAssertEqual(
            RemoteEndpointSecurityPolicy.sanitizedForLog("https://user:secret@example.com:8443/v1?token=secret&region=cn#fragment"),
            "https://example.com:8443/v1"
        )
    }
}
