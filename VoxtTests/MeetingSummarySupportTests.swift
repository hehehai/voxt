import XCTest
@testable import Voxt

final class MeetingSummarySupportTests: XCTestCase {
    func testMeetingSummarySnapshotSupportsJSONRoundTrip() throws {
        let snapshot = MeetingSummarySnapshot(
            title: "Sprint Planning",
            body: "Reviewed blockers.\n\nAligned on release tasks.",
            todoItems: ["Prepare release notes", "Confirm QA coverage"],
            generatedAt: Date(timeIntervalSinceReferenceDate: 1234),
            settingsSnapshot: MeetingSummarySettingsSnapshot(
                autoGenerate: true,
                promptTemplate: "Use a concise summary format.",
                modelSelectionID: "custom-llm:test"
            )
        )

        try XCTAssertJSONRoundTrip(snapshot)
    }

    func testDecodeSummaryParsesStructuredJSONPayload() {
        let settings = MeetingSummarySettingsSnapshot(
            autoGenerate: true,
            promptTemplate: "Summarize decisions and TODOs.",
            modelSelectionID: "remote-llm:openAI"
        )

        let payload = """
        {
          "meeting_summary": {
            "title": "Weekly Sync",
            "content": "Discussed launch timing and partner feedback."
          },
          "todo_list": ["Update the rollout checklist", "Send follow-up to partner team"]
        }
        """

        let decoded = MeetingSummarySupport.decodeSummary(from: payload, settings: settings)

        XCTAssertEqual(decoded?.title, "Weekly Sync")
        XCTAssertEqual(decoded?.body, "Discussed launch timing and partner feedback.")
        XCTAssertEqual(decoded?.todoItems, ["Update the rollout checklist", "Send follow-up to partner team"])
        XCTAssertEqual(decoded?.settingsSnapshot.promptTemplate, "Summarize decisions and TODOs.")
        XCTAssertEqual(decoded?.settingsSnapshot.modelSelectionID, "remote-llm:openAI")
    }

    func testDecodeSummaryExtractsJSONObjectFromWrappedText() {
        let settings = MeetingSummarySettingsSnapshot(
            autoGenerate: true,
            promptTemplate: nil,
            modelSelectionID: "custom-llm:test"
        )

        let payload = """
        Here is the meeting summary:
        {
          "meeting_summary": {
            "title": "发布讨论",
            "content": "团队确认了发布时间，并提出仍需核对 QA 状态。"
          },
          "todo_list": ["Alex：确认 QA 状态，截止周五前"]
        }
        """

        let decoded = MeetingSummarySupport.decodeSummary(from: payload, settings: settings)

        XCTAssertEqual(decoded?.title, "发布讨论")
        XCTAssertEqual(decoded?.body, "团队确认了发布时间，并提出仍需核对 QA 状态。")
        XCTAssertEqual(decoded?.todoItems, ["Alex：确认 QA 状态，截止周五前"])
    }

    func testSummaryPromptReplacesUserMainLanguageTemplateVariable() {
        let settings = MeetingSummarySettingsSnapshot(
            autoGenerate: true,
            promptTemplate: "Use {{USER_MAIN_LANGUAGE}} for the final summary.",
            modelSelectionID: "custom-llm:test"
        )

        let prompt = MeetingSummarySupport.summaryPrompt(
            transcript: "Release sync transcript",
            settings: settings,
            userMainLanguage: "Chinese"
        )

        XCTAssertTrue(prompt.contains("Use Chinese for the final summary."))
        XCTAssertFalse(prompt.contains("{{USER_MAIN_LANGUAGE}}"))
    }

    func testSummaryPromptInjectsMeetingRecordTemplateVariable() {
        let settings = MeetingSummarySettingsSnapshot(
            autoGenerate: true,
            promptTemplate: """
            <user_main_language>{{USER_MAIN_LANGUAGE}}</user_main_language>
            <meeting_record>{{MEETING_RECORD}}</meeting_record>
            """,
            modelSelectionID: "custom-llm:test"
        )

        let prompt = MeetingSummarySupport.summaryPrompt(
            transcript: "Me：Hello\nThem：Ship on Friday",
            settings: settings,
            userMainLanguage: "Chinese"
        )

        XCTAssertTrue(prompt.contains("<user_main_language>Chinese</user_main_language>"))
        XCTAssertTrue(prompt.contains("<meeting_record>Me：Hello\nThem：Ship on Friday</meeting_record>"))
        XCTAssertFalse(prompt.contains("{{MEETING_RECORD}}"))
    }

    func testResolvedPromptTemplateFallsBackToDefault() {
        let resolved = MeetingSummarySupport.resolvedPromptTemplate("   ")

        XCTAssertEqual(resolved, AppPromptDefaults.text(for: .meetingSummary, resolvedFrom: .standard))
    }

    func testDefaultPromptTemplateIncludesJSONLineBreakConstraint() {
        let prompt = MeetingSummarySupport.defaultPromptTemplate()

        XCTAssertTrue(prompt.contains("\"meeting_summary\""))
        XCTAssertTrue(prompt.contains("\"todo_list\""))
        XCTAssertTrue(prompt.contains("only line breaks using \"\\n\""))
    }

    func testDecodeSummaryParsesLegacyXMLPayload() {
        let settings = MeetingSummarySettingsSnapshot(
            autoGenerate: true,
            promptTemplate: nil,
            modelSelectionID: "custom-llm:test"
        )

        let payload = """
        <meeting_summary>
        <title>
        发布讨论
        </title>
        <content>
        团队讨论了发布时间，并确认还需要进一步核对 QA 状态。
        </content>
        </meeting_summary>
        <todo_list>
        Alex：确认 QA 状态，截止周五前
        </todo_list>
        """

        let decoded = MeetingSummarySupport.decodeSummary(from: payload, settings: settings)

        XCTAssertEqual(decoded?.title, "发布讨论")
        XCTAssertEqual(decoded?.body, "团队讨论了发布时间，并确认还需要进一步核对 QA 状态。")
        XCTAssertEqual(decoded?.todoItems, ["Alex：确认 QA 状态，截止周五前"])
    }

    func testHistoryEntryDecodeRemainsCompatibleWithoutMeetingSummaryField() throws {
        let entry = TranscriptionHistoryEntry(
            id: UUID(),
            text: "Meeting text",
            createdAt: Date(timeIntervalSinceReferenceDate: 456),
            transcriptionEngine: "WhisperKit",
            transcriptionModel: "small",
            enhancementMode: "Remote LLM",
            enhancementModel: "model-x",
            kind: .meeting,
            isTranslation: false,
            audioDurationSeconds: 32,
            transcriptionProcessingDurationSeconds: nil,
            llmDurationSeconds: nil,
            focusedAppName: "Calendar",
            matchedGroupID: nil,
            matchedAppGroupName: nil,
            matchedURLGroupName: nil,
            remoteASRProvider: nil,
            remoteASRModel: nil,
            remoteASREndpoint: nil,
            remoteLLMProvider: nil,
            remoteLLMModel: nil,
            remoteLLMEndpoint: nil,
            whisperWordTimings: nil,
            meetingSegments: [
                MeetingTranscriptSegment(
                    speaker: .them,
                    startSeconds: 0,
                    endSeconds: 2,
                    text: "Let's ship on Friday."
                )
            ],
            meetingAudioRelativePath: "meeting/demo.wav",
            meetingSummary: MeetingSummarySnapshot(
                title: "Ship Friday",
                body: "The team agreed on the Friday ship date.",
                todoItems: ["Finalize checklist"],
                generatedAt: Date(timeIntervalSinceReferenceDate: 789),
                settingsSnapshot: MeetingSummarySettingsSnapshot(
                    autoGenerate: true,
                    promptTemplate: "Use a meeting-minute style summary.",
                    modelSelectionID: "custom-llm:test"
                )
            ),
            dictionaryHitTerms: [],
            dictionaryCorrectedTerms: [],
            dictionarySuggestedTerms: []
        )

        let encoded = try JSONEncoder().encode(entry)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "meetingSummary")
        let strippedData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(TranscriptionHistoryEntry.self, from: strippedData)

        XCTAssertNil(decoded.meetingSummary)
        XCTAssertEqual(decoded.meetingSegments?.count, 1)
        XCTAssertEqual(decoded.kind, .meeting)
    }

    func testHistoryEntryRoundTripPersistsMeetingSummaryChatMessages() throws {
        let entry = TranscriptionHistoryEntry(
            id: UUID(),
            text: "Meeting text",
            createdAt: Date(timeIntervalSinceReferenceDate: 456),
            transcriptionEngine: "WhisperKit",
            transcriptionModel: "small",
            enhancementMode: "Remote LLM",
            enhancementModel: "model-x",
            kind: .meeting,
            isTranslation: false,
            audioDurationSeconds: 32,
            transcriptionProcessingDurationSeconds: nil,
            llmDurationSeconds: nil,
            focusedAppName: "Calendar",
            matchedGroupID: nil,
            matchedAppGroupName: nil,
            matchedURLGroupName: nil,
            remoteASRProvider: nil,
            remoteASRModel: nil,
            remoteASREndpoint: nil,
            remoteLLMProvider: nil,
            remoteLLMModel: nil,
            remoteLLMEndpoint: nil,
            whisperWordTimings: nil,
            meetingSegments: nil,
            meetingAudioRelativePath: nil,
            meetingSummary: nil,
            meetingSummaryChatMessages: [
                MeetingSummaryChatMessage(role: .user, content: "Who owns the release checklist?"),
                MeetingSummaryChatMessage(role: .assistant, content: "The meeting record does not name an owner.")
            ],
            dictionaryHitTerms: [],
            dictionaryCorrectedTerms: [],
            dictionarySuggestedTerms: []
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TranscriptionHistoryEntry.self, from: data)

        XCTAssertEqual(decoded.meetingSummaryChatMessages?.count, 2)
        XCTAssertEqual(decoded.meetingSummaryChatMessages?.first?.role, .user)
        XCTAssertEqual(decoded.meetingSummaryChatMessages?.last?.role, .assistant)
    }

    func testMeetingSummarySnapshotDecodeIgnoresLegacyLengthAndStyleFields() throws {
        let payload = """
        {
          "title": "Sprint Planning",
          "body": "Aligned on release scope.",
          "todoItems": ["Confirm QA coverage"],
          "generatedAt": 1234,
          "settingsSnapshot": {
            "autoGenerate": true,
            "promptTemplate": "Summarize decisions and TODOs.",
            "modelSelectionID": "remote-llm:openAI",
            "length": "medium",
            "style": "minutes"
          }
        }
        """

        let decoded = try JSONDecoder().decode(
            MeetingSummarySnapshot.self,
            from: XCTUnwrap(payload.data(using: .utf8))
        )

        XCTAssertEqual(decoded.title, "Sprint Planning")
        XCTAssertEqual(decoded.body, "Aligned on release scope.")
        XCTAssertEqual(decoded.todoItems, ["Confirm QA coverage"])
        XCTAssertEqual(decoded.settingsSnapshot.promptTemplate, "Summarize decisions and TODOs.")
        XCTAssertEqual(decoded.settingsSnapshot.modelSelectionID, "remote-llm:openAI")
    }
}
