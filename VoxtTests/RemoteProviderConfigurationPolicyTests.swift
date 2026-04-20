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

    func testAliyunLLMEndpointPresetsUseResponsesAPI() {
        let presets = RemoteProviderConfigurationPolicy.endpointPresets(
            target: .llm(.aliyunBailian),
            resolvedModel: "qwen-plus"
        )

        XCTAssertEqual(
            presets.map(\.url),
            [
                "https://dashscope.aliyuncs.com/compatible-mode/v1/responses",
                "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/responses",
                "https://dashscope-us.aliyuncs.com/compatible-mode/v1/responses"
            ]
        )
    }

    func testVolcengineLLMEndpointPresetsUseResponsesAPI() {
        let presets = RemoteProviderConfigurationPolicy.endpointPresets(
            target: .llm(.volcengine),
            resolvedModel: "doubao-1-5-pro"
        )

        XCTAssertEqual(
            presets.map(\.url),
            [
                "https://ark.cn-beijing.volces.com/api/v3/responses"
            ]
        )
    }

    func testAliyunASREndpointRemapsRegionWhenSwitchingModelFamilies() {
        let endpoint = RemoteProviderConfigurationPolicy.remappedEndpointOnModelChange(
            target: .asr(.aliyunBailianASR),
            previousModel: "qwen3-asr-flash-realtime",
            newModel: "fun-asr-realtime",
            currentEndpoint: "wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime"
        )

        XCTAssertEqual(endpoint, "wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference")
    }

    func testAliyunASREndpointLeavesCustomHostUntouchedWhenSwitchingModels() {
        let endpoint = RemoteProviderConfigurationPolicy.remappedEndpointOnModelChange(
            target: .asr(.aliyunBailianASR),
            previousModel: "qwen3-asr-flash-realtime",
            newModel: "fun-asr-realtime",
            currentEndpoint: "wss://example.com/custom-realtime"
        )

        XCTAssertEqual(endpoint, "wss://example.com/custom-realtime")
    }

    func testAliyunASREndpointFillsDefaultPresetWhenEmptyAndModelChanges() {
        let endpoint = RemoteProviderConfigurationPolicy.remappedEndpointOnModelChange(
            target: .asr(.aliyunBailianASR),
            previousModel: "qwen3-asr-flash-realtime",
            newModel: "fun-asr-realtime",
            currentEndpoint: ""
        )

        XCTAssertEqual(endpoint, "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
    }
}
