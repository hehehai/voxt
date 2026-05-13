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
}
