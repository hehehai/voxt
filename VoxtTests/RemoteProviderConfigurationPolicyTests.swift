import XCTest
@testable import Voxt

final class RemoteProviderConfigurationPolicyTests: XCTestCase {
    func testResolvedSelectionPrefersKnownSelectionThenConfiguredValue() {
        let target = RemoteProviderTestTarget.llm(.openAI)

        XCTAssertEqual(
            RemoteProviderConfigurationPolicy.resolvedSelection(
                target: target,
                selectedProviderModel: "gpt-5.2",
                configuredModel: "custom-model"
            ),
            "gpt-5.2"
        )

        XCTAssertEqual(
            RemoteProviderConfigurationPolicy.resolvedSelection(
                target: target,
                selectedProviderModel: "unknown",
                configuredModel: "gpt-5.2"
            ),
            "gpt-5.2"
        )
    }

    func testInitialSelectionFallsBackToCustomForUnknownLLMModel() {
        let selection = RemoteProviderConfigurationPolicy.initialSelection(
            target: .llm(.openAI),
            configuredModel: "my-custom-model"
        )

        XCTAssertEqual(selection, RemoteProviderConfigurationPolicy.customModelOptionID)
    }

    func testResolvedModelValueUsesSuggestedModelWhenCustomValueEmpty() {
        let resolved = RemoteProviderConfigurationPolicy.resolvedModelValue(
            target: .llm(.anthropic),
            resolvedSelection: RemoteProviderConfigurationPolicy.customModelOptionID,
            customModelID: "   "
        )

        XCTAssertEqual(resolved, RemoteLLMProvider.anthropic.suggestedModel)
    }

    func testAliyunEndpointPresetsDependOnModelType() {
        let qwenPresets = RemoteProviderConfigurationPolicy.endpointPresets(
            target: .asr(.aliyunBailianASR),
            resolvedModel: "qwen3-asr-flash-realtime"
        )
        let funPresets = RemoteProviderConfigurationPolicy.endpointPresets(
            target: .asr(.aliyunBailianASR),
            resolvedModel: "fun-asr-realtime"
        )

        XCTAssertTrue(qwenPresets.allSatisfy { $0.url.contains("/realtime") })
        XCTAssertTrue(funPresets.allSatisfy { $0.url.contains("/inference") })
    }
}

