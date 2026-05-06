import XCTest
@testable import Voxt

final class TranscriptionHistoryEntryAudioTests: XCTestCase {
    func testDecodingLegacyMeetingAudioPathPopulatesGenericAudioPath() throws {
        let createdAt = Date(timeIntervalSinceReferenceDate: 321)
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "text": "Meeting transcript",
            "createdAt": createdAt.timeIntervalSince1970,
            "transcriptionEngine": "WhisperKit",
            "transcriptionModel": "base",
            "enhancementMode": "Off",
            "enhancementModel": "None",
            "kind": "meeting",
            "isTranslation": false,
            "meetingAudioRelativePath": "meeting/legacy.wav",
            "dictionaryHitTerms": [],
            "dictionaryCorrectedTerms": [],
            "dictionarySuggestedTerms": []
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let entry = try decoder.decode(TranscriptionHistoryEntry.self, from: data)

        XCTAssertEqual(entry.meetingAudioRelativePath, "meeting/legacy.wav")
        XCTAssertEqual(entry.audioRelativePath, "meeting/legacy.wav")
    }

    func testEncodingGenericAudioPathOmitsLegacyFieldWhenUnset() throws {
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
        XCTAssertNil(object["meetingAudioRelativePath"])
    }
}
