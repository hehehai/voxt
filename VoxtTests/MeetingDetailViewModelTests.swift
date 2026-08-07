// MeetingDetailViewModelTests.swift
// Provides Meeting Detail View Model Tests for Voxt test coverage.

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
            translationHandler: { text, _ in MeetingTranslationOperation(executionScope: .externalRequest) { text } },
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
            summaryChatPersistence: { _, _ in nil },
            transcriptSegmentsPersistence: { _, _ in nil }
        )

        viewModel.handleViewAppear()
        await fulfillment(of: [persisted], timeout: 1.0)
        viewModel.handleViewAppear()

        XCTAssertEqual(generateCount, 1)
        XCTAssertEqual(viewModel.summary?.title, "Release Check")
    }

    func testSummaryGenerationCannotReplaceSummaryAfterTranscriptMutation() async {
        let generationStarted = expectation(description: "summary generation started")
        var releaseGeneration: CheckedContinuation<MeetingSummarySnapshot, Never>?
        let existingSummary = MeetingSummarySnapshot(
            title: "Existing",
            body: "Saved summary",
            todoItems: [],
            generatedAt: Date(),
            settingsSnapshot: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: "Prompt",
                modelSelectionID: "custom-llm:test"
            )
        )
        let segment = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 0,
            endSeconds: 2,
            text: "Original text"
        )

        let viewModel = MeetingDetailViewModel(
            title: "Meeting Details",
            subtitle: "Today",
            historyEntryID: UUID(),
            initialSummary: existingSummary,
            initialSummaryChatMessages: [],
            initialSummarySettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: "Prompt",
                modelSelectionID: "custom-llm:test"
            ),
            summaryModelOptions: [
                MeetingSummaryModelOption(id: "custom-llm:test", title: "Test", subtitle: "Local")
            ],
            summarySettingsProvider: {
                MeetingSummarySettingsSnapshot(
                    autoGenerate: false,
                    promptTemplate: "Prompt",
                    modelSelectionID: "custom-llm:test"
                )
            },
            summaryModelOptionsProvider: {
                [MeetingSummaryModelOption(id: "custom-llm:test", title: "Test", subtitle: "Local")]
            },
            segments: [segment],
            audioURL: nil,
            translationHandler: { text, _ in
                MeetingTranslationOperation(executionScope: .externalRequest) { text }
            },
            summaryStatusProvider: { _ in
                MeetingSummaryProviderStatus(isAvailable: true, message: "Ready")
            },
            summaryGenerator: { _, settings in
                await withCheckedContinuation { continuation in
                    releaseGeneration = continuation
                    generationStarted.fulfill()
                }
                return MeetingSummarySnapshot(
                    title: "Generated",
                    body: "Generated from the old transcript",
                    todoItems: [],
                    generatedAt: Date(),
                    settingsSnapshot: settings
                )
            },
            summaryPersistence: { _, _ in nil },
            summaryChatAnswerer: { _, _, _, _, _ in "" },
            summaryChatPersistence: { _, _ in nil },
            transcriptSegmentsPersistence: { _, _ in nil }
        )

        viewModel.regenerateSummary()
        await fulfillment(of: [generationStarted], timeout: 1.0)

        viewModel.beginEditingSegment(segment)
        viewModel.editingText = "Updated text"
        viewModel.saveEditingSegment()
        releaseGeneration?.resume(returning: existingSummary)
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.summary?.title, "Existing")
        XCTAssertTrue(viewModel.isSummaryStale)
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
            translationHandler: { text, _ in MeetingTranslationOperation(executionScope: .externalRequest) { text } },
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
            summaryChatPersistence: { _, _ in nil },
            transcriptSegmentsPersistence: { _, _ in nil }
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
            translationHandler: { text, _ in MeetingTranslationOperation(executionScope: .externalRequest) { text } },
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
            },
            transcriptSegmentsPersistence: { _, _ in nil }
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
            translationHandler: { text, _ in MeetingTranslationOperation(executionScope: .externalRequest) { text } },
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
            summaryChatPersistence: { _, _ in nil },
            transcriptSegmentsPersistence: { _, _ in nil }
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

        XCTAssertEqual(viewModel.summaryPromptTemplate, AppPromptDefaults.text(for: .transcriptSummary))
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

    func testHistoryMeetingModeEnablesSpeakerPresentationEvenWithSingleSystemSpeaker() {
        let viewModel = makeHistoryViewModel(
            initialSettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: nil,
                modelSelectionID: "custom-llm:test"
            ),
            modelOptions: [
                MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local")
            ],
            captureMode: .meeting,
            segments: [
                MeetingTranscriptSegment(
                    speaker: .them,
                    audioSource: .systemAudio,
                    startSeconds: 0,
                    endSeconds: 3,
                    text: "A single realtime system speaker should still be treated as meeting mode."
                )
            ]
        )

        XCTAssertEqual(viewModel.captureMode, .meeting)
        XCTAssertTrue(viewModel.showsSpeakerDisplayModePicker)
        XCTAssertTrue(viewModel.availableTranscriptPresentationModes.contains(.speakerMarks))
    }

    func testSummarySettingsPersistThroughFeatureSettingsStore() throws {
        try withRestoredStandardDefaults([
            AppPreferenceKey.featureSettings
        ]) {
            var settings = FeatureSettingsStore.deriveFromLegacy(defaults: .standard)
            settings.meeting.summaryAutoGenerate = true
            settings.meeting.summaryPrompt = "Initial prompt"
            settings.meeting.summaryModelSelectionID = .localLLM("initial-model")
            FeatureSettingsStore.save(settings, defaults: .standard)

            let viewModel = makeHistoryViewModel(
                initialSettings: MeetingSummarySettingsSnapshot(
                    autoGenerate: true,
                    promptTemplate: "Initial prompt",
                    modelSelectionID: "custom-llm:initial-model"
                ),
                modelOptions: [
                    MeetingSummaryModelOption(id: "remote-llm:openAI", title: "OpenAI", subtitle: "Remote")
                ]
            )

            viewModel.setSummaryAutoGenerate(false)
            viewModel.setSummaryPromptTemplate("Persist this prompt")
            viewModel.setSummaryModelSelectionID("remote-llm:openAI")

            let reloaded = FeatureSettingsStore.load(defaults: .standard)
            XCTAssertFalse(reloaded.meeting.summaryAutoGenerate)
            XCTAssertEqual(reloaded.meeting.summaryPrompt, "Persist this prompt")
            XCTAssertEqual(reloaded.meeting.summaryModelSelectionID, .remoteLLM(.openAI))
        }
    }

    func testRenameSpeakerUpdatesMatchingSegmentsAndPersists() {
        let entryID = UUID()
        var persistedSegments: [MeetingTranscriptSegment]?
        let viewModel = MeetingDetailViewModel(
            title: "Meeting Details",
            subtitle: "Today",
            historyEntryID: entryID,
            initialSummary: nil,
            initialSummaryChatMessages: [],
            initialSummarySettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: "Default summary prompt",
                modelSelectionID: "custom-llm:test"
            ),
            summaryModelOptions: [
                MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local")
            ],
            summarySettingsProvider: {
                MeetingSummarySettingsSnapshot(
                    autoGenerate: false,
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
                    speakerID: "S1",
                    speakerDisplayName: "Speaker 1",
                    audioSource: .systemAudio,
                    startSeconds: 0,
                    endSeconds: 1,
                    text: "hello"
                ),
                MeetingTranscriptSegment(
                    speaker: .them,
                    speakerID: "S2",
                    speakerDisplayName: "Speaker 2",
                    audioSource: .systemAudio,
                    startSeconds: 1,
                    endSeconds: 2,
                    text: "world"
                ),
                MeetingTranscriptSegment(
                    speaker: .me,
                    audioSource: .microphone,
                    startSeconds: 2,
                    endSeconds: 3,
                    text: "ack"
                )
            ],
            audioURL: nil,
            translationHandler: { text, _ in MeetingTranslationOperation(executionScope: .externalRequest) { text } },
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
            summaryChatPersistence: { _, _ in nil },
            transcriptSegmentsPersistence: { _, segments in
                persistedSegments = segments
                return nil
            }
        )

        viewModel.renameSpeaker(identityKey: "systemAudio:S1", displayName: "Alice")

        XCTAssertEqual(viewModel.segments[0].speakerDisplayName, "Alice")
        XCTAssertEqual(viewModel.segments[1].speakerDisplayName, "Speaker 2")
        XCTAssertEqual(persistedSegments?.first?.speakerDisplayName, "Alice")
        XCTAssertTrue(viewModel.isSummaryStale)
    }

    func testRenameSpeakerAcceptsLegacyDisplayIdentityKey() {
        let entryID = UUID()
        var persistedSegments: [MeetingTranscriptSegment]?
        let viewModel = MeetingDetailViewModel(
            title: "Meeting Details",
            subtitle: "Today",
            historyEntryID: entryID,
            initialSummary: nil,
            initialSummaryChatMessages: [],
            initialSummarySettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: "Default summary prompt",
                modelSelectionID: "custom-llm:test"
            ),
            summaryModelOptions: [
                MeetingSummaryModelOption(id: "custom-llm:test", title: "Test Model", subtitle: "Local")
            ],
            summarySettingsProvider: {
                MeetingSummarySettingsSnapshot(
                    autoGenerate: false,
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
                    speakerID: "S1",
                    speakerDisplayName: "Speaker 1",
                    audioSource: .systemAudio,
                    startSeconds: 0,
                    endSeconds: 1,
                    text: "hello"
                ),
                MeetingTranscriptSegment(
                    speaker: .them,
                    speakerID: "S2",
                    speakerDisplayName: "Speaker 2",
                    audioSource: .systemAudio,
                    startSeconds: 1,
                    endSeconds: 2,
                    text: "world"
                ),
                MeetingTranscriptSegment(
                    speaker: .me,
                    audioSource: .microphone,
                    startSeconds: 2,
                    endSeconds: 3,
                    text: "ack"
                )
            ],
            audioURL: nil,
            translationHandler: { text, _ in MeetingTranslationOperation(executionScope: .externalRequest) { text } },
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
            summaryChatPersistence: { _, _ in nil },
            transcriptSegmentsPersistence: { _, segments in
                persistedSegments = segments
                return nil
            }
        )

        viewModel.renameSpeaker(identityKey: "display:Speaker 1", displayName: "Alice")

        XCTAssertEqual(viewModel.segments[0].speakerDisplayName, "Alice")
        XCTAssertEqual(viewModel.segments[1].speakerDisplayName, "Speaker 2")
        XCTAssertEqual(persistedSegments?.first?.speakerDisplayName, "Alice")
    }

    func testLiveViewModelTracksFinalizingState() async {
        let liveState = MeetingOverlayState()
        liveState.isPresented = true
        liveState.isRecording = true
        liveState.segments = [
            MeetingTranscriptSegment(
                speaker: .them,
                startSeconds: 0,
                endSeconds: 1,
                text: "Live transcript"
            )
        ]

        let viewModel = MeetingDetailViewModel(
            liveState: liveState,
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
            translationHandler: { text, _ in MeetingTranslationOperation(executionScope: .externalRequest) { text } }
        )
        let localeIdentifiers = ["en", "zh-Hans", "ja"]
        let inProgressSubtitles = localeIdentifiers.map { localeIdentifier in
            String(
                format: "%@ · %@",
                AppLocalization.localizedString("Meeting", localeIdentifier: localeIdentifier),
                AppLocalization.localizedString("Meeting In Progress", localeIdentifier: localeIdentifier)
            )
        }

        XCTAssertFalse(viewModel.isFinalizing)
        XCTAssertTrue(inProgressSubtitles.contains(viewModel.subtitle))

        liveState.isRecording = false
        liveState.isFinalizing = true
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(viewModel.isFinalizing)
        let finalizingSubtitles = localeIdentifiers.map {
            AppLocalization.localizedString("Preparing final meeting details", localeIdentifier: $0)
        }
        XCTAssertTrue(finalizingSubtitles.contains(viewModel.subtitle))
    }

    func testLiveViewModelSplitsLongDisplaySegments() {
        let segments = [
            MeetingTranscriptSegment(
                speaker: .them,
                startSeconds: 0,
                endSeconds: 24,
                text: "第一句介绍当前模型选择和采集链路。第二句继续说明发言人识别的误差来源，以及短暂停顿不应该直接生成新的发言人。第三句讨论会议详情应该保持连续语义，同时实时浮层需要更快地给出可读段落和清晰反馈。第四句补充说明如果文本继续变长，实时显示仍然需要在自然句边界拆开，避免一整块内容压在同一个气泡里。"
            )
        ]

        let displaySegments = MeetingDetailViewModel.liveDisplaySegments(from: segments)

        XCTAssertGreaterThan(displaySegments.count, 1)
        XCTAssertTrue(displaySegments.allSatisfy { $0.text.count <= 130 })
        XCTAssertEqual(
            displaySegments.map(\.text).joined(),
            segments[0].text
        )
    }

    func testLiveViewModelPreservesSpeakerMetadataWhenUpdatingSegments() async {
        let segmentID = UUID()
        let liveState = MeetingOverlayState()
        liveState.isPresented = true
        liveState.isRecording = true
        liveState.captureMode = .meeting
        liveState.segments = [
            MeetingTranscriptSegment(
                id: segmentID,
                speaker: .them,
                speakerID: "sortformer-0",
                speakerDisplayName: "Speaker 1",
                audioSource: .systemAudio,
                speakerConfidence: 0.71,
                startSeconds: 0,
                endSeconds: 2,
                text: "Initial text"
            )
        ]

        let viewModel = MeetingDetailViewModel(
            liveState: liveState,
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
            translationHandler: { text, _ in MeetingTranslationOperation(executionScope: .externalRequest) { text } }
        )

        liveState.segments = [
            MeetingTranscriptSegment(
                id: segmentID,
                speaker: .them,
                speakerID: "sortformer-1",
                speakerDisplayName: "Speaker 2",
                audioSource: .systemAudio,
                speakerConfidence: 0.82,
                startSeconds: 0,
                endSeconds: 2.5,
                text: "Updated text"
            )
        ]
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.segments.first?.speakerID, "sortformer-1")
        XCTAssertEqual(viewModel.segments.first?.speakerDisplayName, "Speaker 2")
        XCTAssertEqual(viewModel.segments.first?.audioSource, .systemAudio)
        XCTAssertEqual(viewModel.segments.first?.speakerConfidence ?? -1, 0.82, accuracy: 0.001)
        XCTAssertEqual(viewModel.segments.first?.displaySpeakerTitle, "Speaker 2")
    }

    func testFailedDetailTranslationDoesNotRetryIndefinitely() async {
        var invocationCount = 0
        let segment = MeetingTranscriptSegment(
            speaker: .them,
            startSeconds: 0,
            endSeconds: 1,
            text: "Translate once"
        )
        let viewModel = makeHistoryViewModel(
            initialSettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: nil,
                modelSelectionID: "custom-llm:test"
            ),
            modelOptions: [],
            segments: [segment],
            translationHandler: { _, _ in
                MeetingTranslationOperation(executionScope: .externalRequest) {
                    invocationCount += 1
                    throw MeetingDetailTranslationTestError.failed
                }
            }
        )

        viewModel.translationDraftLanguageRaw = TranslationTargetLanguage.english.rawValue
        viewModel.confirmTranslationLanguageSelection()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(invocationCount, 1)
        XCTAssertFalse(viewModel.segments[0].isTranslationPending)
    }

    func testEmptyDetailTranslationDoesNotRetryIndefinitely() async {
        var invocationCount = 0
        let viewModel = makeHistoryViewModel(
            initialSettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: nil,
                modelSelectionID: "custom-llm:test"
            ),
            modelOptions: [],
            segments: [MeetingTranscriptSegment(
                speaker: .them,
                startSeconds: 0,
                endSeconds: 1,
                text: "Empty result"
            )],
            translationHandler: { _, _ in
                MeetingTranslationOperation(executionScope: .externalRequest) {
                    invocationCount += 1
                    return "   "
                }
            }
        )

        viewModel.translationDraftLanguageRaw = TranslationTargetLanguage.english.rawValue
        viewModel.confirmTranslationLanguageSelection()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(invocationCount, 1)
        XCTAssertFalse(viewModel.segments[0].isTranslationPending)
    }

    func testUpdatedSegmentTextIsTranslatedAfterActiveRevisionCompletes() async {
        let segmentID = UUID()
        let gate = MeetingDetailTranslationGate()
        var translatedSources: [String] = []
        let liveState = MeetingOverlayState()
        liveState.isPresented = true
        liveState.isRecording = true
        liveState.segments = [MeetingTranscriptSegment(
            id: segmentID,
            speaker: .them,
            startSeconds: 0,
            endSeconds: 1,
            text: "old text"
        )]
        let viewModel = MeetingDetailViewModel(
            liveState: liveState,
            initialSummarySettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: nil,
                modelSelectionID: "custom-llm:test"
            ),
            summaryModelOptions: [],
            summarySettingsProvider: {
                MeetingSummarySettingsSnapshot(autoGenerate: false, promptTemplate: nil, modelSelectionID: "custom-llm:test")
            },
            summaryModelOptionsProvider: { [] },
            translationHandler: { source, _ in
                MeetingTranslationOperation(executionScope: .externalRequest) {
                    translatedSources.append(source)
                    if source == "old text" { await gate.wait() }
                    return "translated: \(source)"
                }
            }
        )

        viewModel.translationDraftLanguageRaw = TranslationTargetLanguage.english.rawValue
        viewModel.confirmTranslationLanguageSelection()
        await gate.waitUntilStarted()
        viewModel.updateLiveSegments([MeetingTranscriptSegment(
            id: segmentID,
            speaker: .them,
            startSeconds: 0,
            endSeconds: 2,
            text: "new text"
        )])
        await gate.open()
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(translatedSources, ["old text", "new text"])
        XCTAssertEqual(viewModel.segments.first?.translatedText, "translated: new text")
        XCTAssertFalse(viewModel.segments.first?.isTranslationPending ?? true)
    }

    func testManualTranscriptEditClearsTranslationAndMarksSummaryStale() {
        let segment = MeetingTranscriptSegment(
            speaker: .me,
            startSeconds: 0,
            endSeconds: 2,
            text: "old text",
            translatedText: "old translation"
        )
        var persisted: [MeetingTranscriptSegment] = []
        let viewModel = makeHistoryViewModel(
            initialSettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: "Prompt",
                modelSelectionID: "custom-llm:test"
            ),
            modelOptions: [MeetingSummaryModelOption(id: "custom-llm:test", title: "Test", subtitle: "Local")],
            segments: [segment],
            transcriptSegmentsPersistence: { _, segments in
                persisted = segments
                return nil
            }
        )

        viewModel.beginEditingSegment(segment)
        viewModel.editingText = "  updated text  "
        viewModel.saveEditingSegment()

        XCTAssertEqual(viewModel.segments.first?.text, "updated text")
        XCTAssertNil(viewModel.segments.first?.translatedText)
        XCTAssertTrue(viewModel.isSummaryStale)
        XCTAssertEqual(persisted.first?.text, "updated text")
        XCTAssertNil(persisted.first?.translatedText)
        XCTAssertNil(viewModel.editingSegmentID)
    }

    func testDeleteAndUndoRestoresSegmentAtOriginalPosition() {
        let first = MeetingTranscriptSegment(speaker: .me, startSeconds: 0, endSeconds: 1, text: "first")
        let second = MeetingTranscriptSegment(speaker: .them, startSeconds: 1, endSeconds: 2, text: "second")
        var persisted: [[MeetingTranscriptSegment]] = []
        let viewModel = makeHistoryViewModel(
            initialSettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: "Prompt",
                modelSelectionID: "custom-llm:test"
            ),
            modelOptions: [MeetingSummaryModelOption(id: "custom-llm:test", title: "Test", subtitle: "Local")],
            segments: [first, second],
            transcriptSegmentsPersistence: { _, segments in
                persisted.append(segments)
                return nil
            }
        )

        viewModel.deleteSegment(first)
        XCTAssertEqual(viewModel.segments.map(\.id), [second.id])
        XCTAssertTrue(viewModel.isUndoDeleteAvailable)

        viewModel.undoDelete()
        XCTAssertEqual(viewModel.segments.map(\.id), [first.id, second.id])
        XCTAssertFalse(viewModel.isUndoDeleteAvailable)
        XCTAssertEqual(persisted.count, 2)
    }

    func testHighlightTogglePersistsOnTranscriptSegment() {
        let segment = MeetingTranscriptSegment(speaker: .them, startSeconds: 2, endSeconds: 4, text: "important")
        var persisted: MeetingTranscriptSegment?
        let viewModel = makeHistoryViewModel(
            initialSettings: MeetingSummarySettingsSnapshot(
                autoGenerate: false,
                promptTemplate: "Prompt",
                modelSelectionID: "custom-llm:test"
            ),
            modelOptions: [MeetingSummaryModelOption(id: "custom-llm:test", title: "Test", subtitle: "Local")],
            segments: [segment],
            transcriptSegmentsPersistence: { _, segments in
                persisted = segments.first
                return nil
            }
        )

        viewModel.toggleHighlight(for: segment)

        XCTAssertTrue(viewModel.segments.first?.isHighlighted == true)
        XCTAssertTrue(persisted?.isHighlighted == true)
    }

    private func makeHistoryViewModel(
        initialSettings: MeetingSummarySettingsSnapshot,
        modelOptions: [MeetingSummaryModelOption],
        captureMode: MeetingCaptureMode? = nil,
        segments: [MeetingTranscriptSegment] = [],
        translationHandler: @escaping MeetingDetailWindowManager.TranslationHandler = { text, _ in
            MeetingTranslationOperation(executionScope: .externalRequest) { text }
        },
        transcriptSegmentsPersistence: @escaping MeetingDetailWindowManager.TranscriptSegmentsPersistence = { _, _ in nil }
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
            segments: segments,
            captureMode: captureMode,
            audioURL: nil,
            translationHandler: translationHandler,
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
            summaryChatPersistence: { _, _ in nil },
            transcriptSegmentsPersistence: transcriptSegmentsPersistence
        )
    }

    private func withRestoredStandardDefaults(
        _ keys: [String],
        _ body: () throws -> Void
    ) rethrows {
        let defaults = UserDefaults.standard
        let savedValues = keys.map { key in
            (key, defaults.object(forKey: key))
        }
        defer {
            for (key, value) in savedValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        try body()
    }
}

private enum MeetingDetailTranslationTestError: Error {
    case failed
}

private actor MeetingDetailTranslationGate {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
