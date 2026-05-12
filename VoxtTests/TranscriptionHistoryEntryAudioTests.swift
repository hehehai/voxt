import XCTest
@testable import Voxt

@MainActor
final class TranscriptionHistoryEntryAudioTests: XCTestCase {
    func testDecodingTranscriptAudioPathPopulatesGenericAudioPath() throws {
        let createdAt = Date(timeIntervalSinceReferenceDate: 321)
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "text": "Transcript",
            "createdAt": createdAt.timeIntervalSince1970,
            "transcriptionEngine": "WhisperKit",
            "transcriptionModel": "base",
            "enhancementMode": "Off",
            "enhancementModel": "None",
            "kind": "transcript",
            "isTranslation": false,
            "transcriptAudioRelativePath": "transcript/clip.wav",
            "dictionaryHitTerms": [],
            "dictionaryCorrectedTerms": [],
            "dictionarySuggestedTerms": []
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let entry = try decoder.decode(TranscriptionHistoryEntry.self, from: data)

        XCTAssertEqual(entry.kind, .transcript)
        XCTAssertEqual(entry.transcriptAudioRelativePath, "transcript/clip.wav")
        XCTAssertEqual(entry.audioRelativePath, "transcript/clip.wav")
        XCTAssertTrue(entry.dictionaryCorrectionSnapshots.isEmpty)
    }

    func testEncodingGenericAudioPathOmitsTranscriptSpecificFieldWhenUnset() throws {
        let entry = TranscriptionHistoryEntry(
            id: UUID(),
            text: "Transcript",
            createdAt: Date(timeIntervalSinceReferenceDate: 456),
            transcriptionEngine: "WhisperKit",
            transcriptionModel: "large-v3",
            enhancementMode: "Off",
            enhancementModel: "None",
            kind: .normal,
            isTranslation: false,
            audioDurationSeconds: 2,
            transcriptionProcessingDurationSeconds: 1,
            llmDurationSeconds: nil,
            focusedAppName: nil,
            focusedAppBundleID: nil,
            matchedGroupID: nil,
            matchedGroupName: nil,
            matchedAppGroupName: nil,
            matchedURLGroupName: nil,
            remoteASRProvider: nil,
            remoteASRModel: nil,
            remoteASREndpoint: nil,
            remoteLLMProvider: nil,
            remoteLLMModel: nil,
            remoteLLMEndpoint: nil,
            audioRelativePath: "transcription/sample.wav",
            whisperWordTimings: nil,
            dictionaryHitTerms: [],
            dictionaryCorrectedTerms: [],
            dictionarySuggestedTerms: []
        )

        let data = try JSONEncoder().encode(entry)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["audioRelativePath"] as? String, "transcription/sample.wav")
        XCTAssertNil(object["transcriptAudioRelativePath"])
        XCTAssertTrue((object["dictionaryCorrectionSnapshots"] as? [Any])?.isEmpty == true)
    }
}
