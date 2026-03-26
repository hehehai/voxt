import XCTest
@testable import Voxt

@MainActor
final class MeetingDetailViewModelTests: XCTestCase {
    func testHistoryViewModelAutoGeneratesSummaryOnlyOnce() async {
        let persisted = expectation(description: "summary persisted")
        var generateCount = 0

        let viewModel = MeetingDetailViewModel(
            title: "Meeting Details",
            subtitle: "Today",
            historyEntryID: UUID(),
            initialSummary: nil,
            initialSummaryChatMessages: [],
            initialSummarySettings: MeetingSummarySettingsSnapshot(
                autoGenerate: true,
                promptTemplate: "Default summary prompt",
                modelSelectionID: "custom-llm:test"
            ),
            summaryModelOptions: [
                MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local")
            ],
            summarySettingsProvider: {
                MeetingSummarySettingsSnapshot(
                    autoGenerate: true,
                    promptTemplate: "Default summary prompt",
                    modelSelectionID: "custom-llm:test"
                )
            },
            summaryModelOptionsProvider: {
                [MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local")]
            },
            segments: [
                MeetingTranscriptSegment(
                    speaker: .them,
                    startSeconds: 0,
                    endSeconds: 4,
                    text: "Let's finish the release checklist today."
                )
            ],
            audioURL: nil,
            translationHandler: { text, _ in text },
            summaryStatusProvider: { _ in
                MeetingSummaryProviderStatus(isAvailable: true, message: "Ready")
            },
            summaryGenerator: { _, settings in
                generateCount += 1
                return MeetingSummarySnapshot(
                    title: "Release Check",
                    body: "The team agreed to finish the release checklist today.",
                    todoItems: ["Finish release checklist"],
                    generatedAt: Date(),
                    settingsSnapshot: settings
                )
            },
            summaryPersistence: { _, _ in
                persisted.fulfill()
                return nil
            },
            summaryChatAnswerer: { _, _, _, _, _ in "" },
            summaryChatPersistence: { _, _ in nil }
        )

        viewModel.handleViewAppear()
        await fulfillment(of: [persisted], timeout: 1.0)
        viewModel.handleViewAppear()

        XCTAssertEqual(generateCount, 1)
        XCTAssertEqual(viewModel.summary?.title, "Release Check")
    }

    func testHistoryViewModelDoesNotAutoGenerateWhenSummaryAlreadyExists() async {
        var generateCount = 0

        let existing = MeetingSummarySnapshot(
            title: "Existing",
            body: "Saved summary",
            todoItems: [],
            generatedAt: Date(),
            settingsSnapshot: MeetingSummarySettingsSnapshot(
                autoGenerate: true,
                promptTemplate: "Default summary prompt",
                modelSelectionID: "custom-llm:test"
            )
        )

        let viewModel = MeetingDetailViewModel(
            title: "Meeting Details",
            subtitle: "Today",
            historyEntryID: UUID(),
            initialSummary: existing,
            initialSummaryChatMessages: [],
            initialSummarySettings: MeetingSummarySettingsSnapshot(
                autoGenerate: true,
                promptTemplate: "Default summary prompt",
                modelSelectionID: "custom-llm:test"
            ),
            summaryModelOptions: [
                MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local")
            ],
            summarySettingsProvider: {
                MeetingSummarySettingsSnapshot(
                    autoGenerate: true,
                    promptTemplate: "Default summary prompt",
                    modelSelectionID: "custom-llm:test"
                )
            },
            summaryModelOptionsProvider: {
                [MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local")]
            },
            segments: [
                MeetingTranscriptSegment(
                    speaker: .them,
                    startSeconds: 0,
                    endSeconds: 4,
                    text: "Already summarized."
                )
            ],
            audioURL: nil,
            translationHandler: { text, _ in text },
            summaryStatusProvider: { _ in
                MeetingSummaryProviderStatus(isAvailable: true, message: "Ready")
            },
            summaryGenerator: { _, settings in
                generateCount += 1
                return MeetingSummarySnapshot(
                    title: "New",
                    body: "Should not run",
                    todoItems: [],
                    generatedAt: Date(),
                    settingsSnapshot: settings
                )
            },
            summaryPersistence: { _, _ in nil },
            summaryChatAnswerer: { _, _, _, _, _ in "" },
            summaryChatPersistence: { _, _ in nil }
        )

        viewModel.handleViewAppear()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(generateCount, 0)
        XCTAssertEqual(viewModel.summary?.title, "Existing")
    }

    func testHistoryViewModelSendsAndPersistsSummaryChatMessages() async {
        let persisted = expectation(description: "chat persisted")
        persisted.expectedFulfillmentCount = 2
        var answerInvocationCount = 0

        let viewModel = MeetingDetailViewModel(
            title: "Meeting Details",
            subtitle: "Today",
            historyEntryID: UUID(),
            initialSummary: MeetingSummarySnapshot(
                title: "Existing",
                body: "Saved summary",
                todoItems: ["Prepare release notes"],
                generatedAt: Date(),
                settingsSnapshot: MeetingSummarySettingsSnapshot(
                    autoGenerate: true,
                    promptTemplate: "Default summary prompt",
                    modelSelectionID: "custom-llm:test"
                )
            ),
            initialSummaryChatMessages: [],
            initialSummarySettings: MeetingSummarySettingsSnapshot(
                autoGenerate: true,
                promptTemplate: "Default summary prompt",
                modelSelectionID: "custom-llm:test"
            ),
            summaryModelOptions: [
                MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local")
            ],
            summarySettingsProvider: {
                MeetingSummarySettingsSnapshot(
                    autoGenerate: true,
                    promptTemplate: "Default summary prompt",
                    modelSelectionID: "custom-llm:test"
                )
            },
            summaryModelOptionsProvider: {
                [MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local")]
            },
            segments: [
                MeetingTranscriptSegment(
                    speaker: .them,
                    startSeconds: 0,
                    endSeconds: 4,
                    text: "Alex will finish the release notes."
                )
            ],
            audioURL: nil,
            translationHandler: { text, _ in text },
            summaryStatusProvider: { _ in
                MeetingSummaryProviderStatus(isAvailable: true, message: "Ready")
            },
            summaryGenerator: { _, settings in
                MeetingSummarySnapshot(
                    title: "Existing",
                    body: "Saved summary",
                    todoItems: ["Prepare release notes"],
                    generatedAt: Date(),
                    settingsSnapshot: settings
                )
            },
            summaryPersistence: { _, _ in nil },
            summaryChatAnswerer: { _, _, history, question, _ in
                answerInvocationCount += 1
                XCTAssertEqual(history.count, 1)
                XCTAssertEqual(history.first?.role, .user)
                XCTAssertEqual(question, "Who owns the release notes?")
                return "Alex owns the release notes."
            },
            summaryChatPersistence: { _, messages in
                persisted.fulfill()
                XCTAssertLessThanOrEqual(messages.count, 2)
                return nil
            }
        )

        viewModel.summaryChatDraft = "Who owns the release notes?"
        viewModel.sendSummaryChat()
        await fulfillment(of: [persisted], timeout: 1.0)

        XCTAssertEqual(answerInvocationCount, 1)
        XCTAssertEqual(viewModel.summaryChatMessages.count, 2)
        XCTAssertEqual(viewModel.summaryChatMessages.first?.role, .user)
        XCTAssertEqual(viewModel.summaryChatMessages.last?.role, .assistant)
    }

    func testHistoryViewModelUsesResolvedInitialSummarySettings() {
        let viewModel = MeetingDetailViewModel(
            title: "Meeting Details",
            subtitle: "Today",
            historyEntryID: UUID(),
            initialSummary: nil,
            initialSummaryChatMessages: [],
            initialSummarySettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: "Focus on decisions and owners.",
                modelSelectionID: "remote-llm:openAI"
            ),
            summaryModelOptions: [
                MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local"),
                MeetingSummaryModelOption(id: "remote-llm:openAI", title: "OpenAI · gpt-5.4", subtitle: "Configured Remote LLM")
            ],
            summarySettingsProvider: {
                MeetingSummarySettingsSnapshot(
                    autoGenerate: false,
                    promptTemplate: "Focus on decisions and owners.",
                    modelSelectionID: "remote-llm:openAI"
                )
            },
            summaryModelOptionsProvider: {
                [
                    MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local"),
                    MeetingSummaryModelOption(id: "remote-llm:openAI", title: "OpenAI · gpt-5.4", subtitle: "Configured Remote LLM")
                ]
            },
            segments: [],
            audioURL: nil,
            translationHandler: { text, _ in text },
            summaryStatusProvider: { _ in
                MeetingSummaryProviderStatus(isAvailable: true, message: "Ready")
            },
            summaryGenerator: { _, settings in
                MeetingSummarySnapshot(
                    title: "Existing",
                    body: "Saved summary",
                    todoItems: [],
                    generatedAt: Date(),
                    settingsSnapshot: settings
                )
            },
            summaryPersistence: { _, _ in nil },
            summaryChatAnswerer: { _, _, _, _, _ in "" },
            summaryChatPersistence: { _, _ in nil }
        )

        XCTAssertFalse(viewModel.summaryAutoGenerate)
        XCTAssertEqual(viewModel.summaryPromptTemplate, "Focus on decisions and owners.")
        XCTAssertEqual(viewModel.resolvedSummaryModelSelectionID, "remote-llm:openAI")
    }

    func testResetSummaryPromptTemplateRestoresDefaultPrompt() {
        let viewModel = makeHistoryViewModel(
            initialSettings: MeetingSummarySettingsSnapshot(
                autoGenerate: true,
                promptTemplate: "Custom prompt",
                modelSelectionID: "custom-llm:test"
            ),
            modelOptions: [
                MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local")
            ]
        )

        viewModel.resetSummaryPromptTemplate()

        XCTAssertEqual(viewModel.summaryPromptTemplate, AppPreferenceKey.defaultMeetingSummaryPrompt)
    }

    func testRefreshSummaryConfigurationFallsBackToFirstAvailableModel() {
        let viewModel = makeHistoryViewModel(
            initialSettings: MeetingSummarySettingsSnapshot(
                autoGenerate: true,
                promptTemplate: nil,
                modelSelectionID: "remote-llm:missing"
            ),
            modelOptions: [
                MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local")
            ]
        )

        viewModel.refreshSummaryConfiguration(
            settings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: "Refreshed prompt",
                modelSelectionID: "remote-llm:missing"
            ),
            modelOptions: [
                MeetingSummaryModelOption(id: "remote-llm:available", title: "Remote Model", subtitle: "Configured")
            ]
        )

        XCTAssertFalse(viewModel.summaryAutoGenerate)
        XCTAssertEqual(viewModel.summaryPromptTemplate, "Refreshed prompt")
        XCTAssertEqual(viewModel.resolvedSummaryModelSelectionID, "remote-llm:available")
    }

    func testHistoryTranslationIncludesRemoteSpeakerSegments() async {
        let viewModel = MeetingDetailViewModel(
            title: "Meeting Details",
            subtitle: "Today",
            historyEntryID: UUID(),
            initialSummary: nil,
            initialSummaryChatMessages: [],
            initialSummarySettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: "Default summary prompt",
                modelSelectionID: "custom-llm:test"
            ),
            summaryModelOptions: [],
            summarySettingsProvider: {
                MeetingSummarySettingsSnapshot(
                    autoGenerate: false,
                    promptTemplate: "Default summary prompt",
                    modelSelectionID: "custom-llm:test"
                )
            },
            summaryModelOptionsProvider: { [] },
            segments: [
                MeetingTranscriptSegment(
                    speaker: .me,
                    startSeconds: 0,
                    endSeconds: 1,
                    text: "local segment"
                ),
                MeetingTranscriptSegment(
                    speaker: .remote(1),
                    startSeconds: 1,
                    endSeconds: 2,
                    text: "remote segment"
                )
            ],
            audioURL: nil,
            translationHandler: { text, _ in "translated: \(text)" },
            summaryStatusProvider: { _ in
                MeetingSummaryProviderStatus(isAvailable: false, message: "Unavailable")
            },
            summaryGenerator: { _, settings in
                MeetingSummarySnapshot(
                    title: "Unused",
                    body: "Unused",
                    todoItems: [],
                    generatedAt: Date(),
                    settingsSnapshot: settings
                )
            },
            summaryPersistence: { _, _ in nil },
            summaryChatAnswerer: { _, _, _, _, _ in "" },
            summaryChatPersistence: { _, _ in nil }
        )

        viewModel.setTranslationEnabled(true)
        viewModel.confirmTranslationLanguageSelection()
        try? await Task.sleep(for: .milliseconds(150))

        XCTAssertNil(viewModel.segments.first(where: { $0.speaker == .me })?.translatedText)
        XCTAssertEqual(
            viewModel.segments.first(where: { $0.speaker == .remote(1) })?.translatedText,
            "translated: remote segment"
        )
    }

    private func makeHistoryViewModel(
        initialSettings: MeetingSummarySettingsSnapshot,
        modelOptions: [MeetingSummaryModelOption]
    ) -> MeetingDetailViewModel {
        MeetingDetailViewModel(
            title: "Meeting Details",
            subtitle: "Today",
            historyEntryID: UUID(),
            initialSummary: nil,
            initialSummaryChatMessages: [],
            initialSummarySettings: initialSettings,
            summaryModelOptions: modelOptions,
            summarySettingsProvider: { initialSettings },
            summaryModelOptionsProvider: { modelOptions },
            segments: [],
            audioURL: nil,
            translationHandler: { text, _ in text },
            summaryStatusProvider: { _ in
                MeetingSummaryProviderStatus(isAvailable: true, message: "Ready")
            },
            summaryGenerator: { _, settings in
                MeetingSummarySnapshot(
                    title: "Generated",
                    body: "Body",
                    todoItems: [],
                    generatedAt: Date(),
                    settingsSnapshot: settings
                )
            },
            summaryPersistence: { _, _ in nil },
            summaryChatAnswerer: { _, _, _, _, _ in "" },
            summaryChatPersistence: { _, _ in nil }
        )
    }
}
