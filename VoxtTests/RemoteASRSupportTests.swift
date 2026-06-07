import XCTest
@testable import Voxt

final class RemoteASRSupportTests: XCTestCase {
    func testOpenAITranscriptionMultipartFieldsOmitStreamForFileTranscription() {
        let fields = RemoteASRTextSupport.openAITranscriptionMultipartFields(
            model: "gpt-4o-mini-transcribe",
            hintPayload: ResolvedASRHintPayload(
                language: "zh",
                languageHints: ["zh"],
                prompt: "Prefer product names."
            )
        )

        XCTAssertEqual(fields["response_format"], "json")
        XCTAssertEqual(fields["language"], "zh")
        XCTAssertEqual(fields["prompt"], "Prefer product names.")
        XCTAssertNil(fields["stream"])
    }

    func testOpenAITranscriptionMultipartFieldsOmitPromptForDiarizeModel() {
        let fields = RemoteASRTextSupport.openAITranscriptionMultipartFields(
            model: "gpt-4o-transcribe-diarize",
            hintPayload: ResolvedASRHintPayload(
                language: "en",
                languageHints: ["en"],
                prompt: "Ignore for diarize."
            )
        )

        XCTAssertEqual(fields["response_format"], "json")
        XCTAssertEqual(fields["language"], "en")
        XCTAssertNil(fields["prompt"])
        XCTAssertNil(fields["stream"])
    }

    func testExtractStreamErrorMessageReadsNestedErrorPayload() {
        let message = RemoteASRTextSupport.extractStreamErrorMessage(
            fromLine: #"{"error":{"code":"invalid_api_key","message":"API key is invalid"}}"#
        )

        XCTAssertEqual(message, "API key is invalid")
    }

    func testExtractStreamErrorMessageReadsErrorEventPayload() {
        let message = RemoteASRTextSupport.extractStreamErrorMessage(
            fromLine: #"{"event":"error","message":"model is required"}"#
        )

        XCTAssertEqual(message, "model is required")
    }

    func testExtractStreamErrorMessageIgnoresNormalTextPayload() {
        let message = RemoteASRTextSupport.extractStreamErrorMessage(
            fromLine: #"{"text":"hello world"}"#
        )

        XCTAssertNil(message)
    }

    func testStepFunTranscriptionPayloadIncludesLanguageAndHotwords() {
        let payload = StepFunPayloadSupport.transcriptionPayload(
            model: "stepaudio-2.5-asr",
            hintPayload: ResolvedASRHintPayload(
                language: "zh",
                contextualPhrases: ["Voxt", "FireRed"]
            )
        )

        XCTAssertEqual(payload["model"] as? String, "stepaudio-2.5-asr")
        XCTAssertEqual(payload["language"] as? String, "zh")
        XCTAssertEqual(payload["enable_itn"] as? Bool, true)
        XCTAssertEqual(payload["hotwords"] as? [String], ["Voxt", "FireRed"])
        XCTAssertNil(payload["enable_timestamp"])
        XCTAssertNil(payload["prompt"])
        XCTAssertFalse(StepFunPayloadSupport.supportsSSEPrompt(model: "stepaudio-2.5-asr"))
    }

    func testAliyunFunRealtimeParametersIncludeLanguageHintsAndHotwords() {
        let parameters = AliyunFunRealtimePayloadSupport.parameters(
            hintPayload: ResolvedASRHintPayload(
                languageHints: ["zh", "en"],
                contextualPhrases: ["Voxt", "FireRed"]
            )
        )

        XCTAssertEqual(parameters["sample_rate"] as? Int, 16000)
        XCTAssertEqual(parameters["format"] as? String, "pcm")
        XCTAssertEqual(parameters["language_hints"] as? [String], ["zh", "en"])
        XCTAssertEqual(parameters["hotwords"] as? [String], ["Voxt", "FireRed"])
    }

    func testAliyunFunRealtimeParametersOmitEmptyHotwords() {
        let parameters = AliyunFunRealtimePayloadSupport.parameters(
            hintPayload: ResolvedASRHintPayload(languageHints: ["zh"])
        )

        XCTAssertEqual(parameters["language_hints"] as? [String], ["zh"])
        XCTAssertNil(parameters["hotwords"])
    }

    func testStepFunProTranscriptionPayloadCanIncludePrompt() {
        let payload = StepFunPayloadSupport.transcriptionPayload(
            model: "stepaudio-2-asr-pro",
            hintPayload: ResolvedASRHintPayload(
                language: "zh",
                prompt: "Prefer these terms.\nVoxt",
                contextualPhrases: ["Voxt"]
            ),
            includePrompt: StepFunPayloadSupport.supportsSSEPrompt(model: "stepaudio-2-asr-pro")
        )

        XCTAssertEqual(payload["model"] as? String, "stepaudio-2-asr-pro")
        XCTAssertEqual(payload["prompt"] as? String, "Prefer these terms.\nVoxt")
        XCTAssertEqual(payload["hotwords"] as? [String], ["Voxt"])
        XCTAssertTrue(StepFunPayloadSupport.supportsSSEPrompt(model: "stepaudio-2-asr-pro"))
    }

    func testStepFunSSEDoneTextIsParsedAsCompletedResult() {
        let delta = StepFunPayloadSupport.parseSSEDataLine(
            #"{"type":"transcript.text.delta","delta":"一二三四五。"}"#
        )
        let completed = StepFunPayloadSupport.parseSSEDataLine(
            #"{"type":"transcript.text.done","text":"12345。"}"#
        )

        XCTAssertEqual(delta, .delta("一二三四五。"))
        XCTAssertEqual(completed, .completed("12345。"))
    }

    func testStepFunRealtimeSessionUpdateUsesWebSocketShape() throws {
        let payload = StepFunPayloadSupport.sessionUpdatePayload(
            model: "step-asr-1.1-stream",
            hintPayload: ResolvedASRHintPayload(
                language: "zh",
                prompt: "Prefer these terms.\nVoxt",
                contextualPhrases: ["Voxt"]
            ),
            useServerVAD: true
        )

        XCTAssertEqual(payload["type"] as? String, "session.update")
        let session = try XCTUnwrap(payload["session"] as? [String: Any])
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])

        XCTAssertEqual(transcription["model"] as? String, "step-asr-1.1-stream")
        XCTAssertEqual(transcription["prompt"] as? String, "Prefer these terms.\nVoxt")
        XCTAssertNil(transcription["hotwords"])
        XCTAssertEqual(transcription["full_rerun_on_commit"] as? Bool, true)
        XCTAssertEqual(format["codec"] as? String, "pcm_s16le")
        XCTAssertNotNil(input["turn_detection"])
    }

    func testStepFunRealtimeEndpointRemapsSSEEndpoint() {
        XCTAssertEqual(
            RemoteASREndpointSupport.resolvedStepFunRealtimeEndpoint("https://api.stepfun.com/v1/audio/asr/sse"),
            "wss://api.stepfun.com/v1/realtime/asr/stream"
        )
    }
}
