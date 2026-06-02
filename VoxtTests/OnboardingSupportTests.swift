import XCTest
@testable import Voxt

final class OnboardingSupportTests: XCTestCase {
    func testTranscriptionPermissionsIncludeSpeechRecognitionForDictation() {
        let permissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .transcription,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .dictation,
                muteSystemAudioWhileRecording: false
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .speechRecognition]
        )
    }

    func testTranscriptionPermissionsIncludeSystemAudioWhenMuteEnabled() {
        let permissions = OnboardingPermissionRequirementResolver.requiredPermissions(
            for: .transcription,
            context: OnboardingPermissionRequirementContext(
                selectedEngine: .mlxAudio,
                muteSystemAudioWhileRecording: true
            )
        )

        XCTAssertEqual(
            permissions,
            [.microphone, .accessibility, .inputMonitoring, .systemAudioCapture]
        )
    }

    func testNonRecordingStepsDoNotRequirePermissions() {
        let context = OnboardingPermissionRequirementContext(
            selectedEngine: .mlxAudio,
            muteSystemAudioWhileRecording: true
        )

        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .language, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .model, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .translation, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .rewrite, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .appEnhancement, context: context).isEmpty)
        XCTAssertTrue(OnboardingPermissionRequirementResolver.requiredPermissions(for: .finish, context: context).isEmpty)
    }

    func testRewritePermissionsIncludeScreenCaptureWhenRewriteScreenshotContextIsEnabled() {
        let context = OnboardingPermissionRequirementContext(
            selectedEngine: .mlxAudio,
            muteSystemAudioWhileRecording: false,
            rewriteScreenshotContextEnabled: true
        )

        XCTAssertEqual(
            OnboardingPermissionRequirementResolver.requiredPermissions(for: .rewrite, context: context),
            [.screenCapture]
        )
    }

    func testFeatureSelectionResolverMapsASRSelections() {
        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.asrSelectionID(
                selectedEngine: .mlxAudio,
                mlxModelRepo: "mlx-community/whisper-large-v3-turbo-4bit",
                whisperModelID: "openai_whisper-tiny",
                remoteASRProvider: .doubaoASR
            ),
            .mlx("mlx-community/whisper-large-v3-turbo-4bit")
        )

        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.asrSelectionID(
                selectedEngine: .remote,
                mlxModelRepo: "",
                whisperModelID: "",
                remoteASRProvider: .doubaoASR
            ),
            .remoteASR(.doubaoASR)
        )
    }

    func testFeatureSelectionResolverMapsLLMSelections() {
        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.llmSelectionID(
                choice: .local,
                localLLMRepo: "mlx-community/Qwen3-4B-4bit",
                remoteLLMProvider: .openAI
            ),
            .localLLM("mlx-community/Qwen3-4B-4bit")
        )

        XCTAssertEqual(
            OnboardingFeatureSelectionResolver.llmSelectionID(
                choice: .system,
                localLLMRepo: "",
                remoteLLMProvider: .openAI
            ),
            .appleIntelligence
        )
    }

    func testFeatureSelectionResolverUsesWhisperDirectTranslateForAppleIntelligencePlusWhisper() {
        let selection = OnboardingFeatureSelectionResolver.translationSelectionID(
            llmSelection: .appleIntelligence,
            asrSelection: .whisper("openai_whisper-large-v3"),
            existingSelection: .remoteLLM(.openAI),
            fallbackLocalLLMRepo: "mlx-community/Qwen3-4B-4bit"
        )

        XCTAssertEqual(selection, .whisperDirectTranslate)
    }

    func testFeatureSelectionResolverPreservesExistingTranslationSelectionWhenCompatible() {
        let selection = OnboardingFeatureSelectionResolver.translationSelectionID(
            llmSelection: .appleIntelligence,
            asrSelection: .mlx("mlx-community/whisper-large-v3-turbo-4bit"),
            existingSelection: .remoteLLM(.openAI),
            fallbackLocalLLMRepo: "mlx-community/Qwen3-4B-4bit"
        )

        XCTAssertEqual(selection, .remoteLLM(.openAI))
    }
}
