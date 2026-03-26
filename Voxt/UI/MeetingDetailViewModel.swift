import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
enum MeetingSummaryLoadState: Equatable {
    case idle
    case loading
    case unavailable(String)
    case failed(String)
}

@MainActor
final class MeetingDetailViewModel: ObservableObject {
    enum TranscriptPresentationMode: String, CaseIterable, Identifiable {
        case timeline
        case speakerMarks

        var id: String { rawValue }
    }

    enum Mode {
        case history
        case live
    }

    @Published private(set) var title: String
    @Published private(set) var subtitle: String
    @Published private(set) var segments: [MeetingTranscriptSegment]
    @Published private(set) var isPaused = false
    @Published var translationEnabled: Bool
    @Published var isTranslationLanguagePickerPresented = false
    @Published var translationDraftLanguageRaw: String

    @Published private(set) var summary: MeetingSummarySnapshot?
    @Published private(set) var summaryChatMessages: [MeetingSummaryChatMessage]
    @Published private(set) var summaryState: MeetingSummaryLoadState = .idle
    @Published private(set) var isSummaryChatLoading = false
    @Published private(set) var summaryChatErrorMessage: String?
    @Published var isSummarySettingsPresented = false
    @Published var summaryAutoGenerate: Bool
    @Published var summaryPromptTemplate: String
    @Published var summaryModelSelectionID: String
    @Published var summaryChatDraft = ""
    @Published var transcriptPresentationModeRaw = TranscriptPresentationMode.timeline.rawValue
    @Published var isSearchPresented = false
    @Published var searchQuery = ""
    @Published var isSummaryCollapsed = false

    let mode: Mode
    let audioURL: URL?
    @Published private(set) var summaryModelOptions: [MeetingSummaryModelOption]

    private let historyEntryID: UUID?
    private let translationHandler: MeetingDetailWindowManager.TranslationHandler
    private let summarySettingsProvider: MeetingDetailWindowManager.SummarySettingsProvider?
    private let summaryModelOptionsProvider: MeetingDetailWindowManager.SummaryModelOptionsProvider?
    private let summaryStatusProvider: MeetingDetailWindowManager.SummaryStatusProvider?
    private let summaryGenerator: MeetingDetailWindowManager.SummaryGenerator?
    private let summaryPersistence: MeetingDetailWindowManager.SummaryPersistence?
    private let summaryChatAnswerer: MeetingDetailWindowManager.SummaryChatAnswerer?
    private let summaryChatPersistence: MeetingDetailWindowManager.SummaryChatPersistence?

    private var cancellables = Set<AnyCancellable>()
    private var translationTasks: [UUID: Task<Void, Never>] = [:]
    private var summaryTask: Task<Void, Never>?
    private var summaryChatTask: Task<Void, Never>?
    private var hasHandledInitialAppearance = false

    init(
        title: String,
        subtitle: String,
        historyEntryID: UUID,
        initialSummary: MeetingSummarySnapshot?,
        initialSummaryChatMessages: [MeetingSummaryChatMessage],
        initialSummarySettings: MeetingSummarySettingsSnapshot,
        summaryModelOptions: [MeetingSummaryModelOption],
        summarySettingsProvider: @escaping MeetingDetailWindowManager.SummarySettingsProvider,
        summaryModelOptionsProvider: @escaping MeetingDetailWindowManager.SummaryModelOptionsProvider,
        segments: [MeetingTranscriptSegment],
        audioURL: URL?,
        translationHandler: @escaping MeetingDetailWindowManager.TranslationHandler,
        summaryStatusProvider: @escaping MeetingDetailWindowManager.SummaryStatusProvider,
        summaryGenerator: @escaping MeetingDetailWindowManager.SummaryGenerator,
        summaryPersistence: @escaping MeetingDetailWindowManager.SummaryPersistence,
        summaryChatAnswerer: @escaping MeetingDetailWindowManager.SummaryChatAnswerer,
        summaryChatPersistence: @escaping MeetingDetailWindowManager.SummaryChatPersistence
    ) {
        self.mode = .history
        self.title = title
        self.subtitle = subtitle
        self.historyEntryID = historyEntryID
        self.summary = initialSummary
        self.summaryChatMessages = initialSummaryChatMessages
        self.summaryModelOptions = summaryModelOptions
        self.segments = segments
        self.audioURL = audioURL
        self.isPaused = true
        self.translationHandler = translationHandler
        self.summarySettingsProvider = summarySettingsProvider
        self.summaryModelOptionsProvider = summaryModelOptionsProvider
        self.summaryStatusProvider = summaryStatusProvider
        self.summaryGenerator = summaryGenerator
        self.summaryPersistence = summaryPersistence
        self.summaryChatAnswerer = summaryChatAnswerer
        self.summaryChatPersistence = summaryChatPersistence

        self.translationDraftLanguageRaw = Self.initialTranslationLanguageRaw()
        self.translationEnabled = Self.segmentsContainTranslations(segments)

        let resolvedConfiguration = Self.resolveSummaryConfiguration(
            settings: initialSummarySettings,
            modelOptions: summaryModelOptions,
            currentSelectionID: nil
        )
        self.summaryAutoGenerate = resolvedConfiguration.autoGenerate
        self.summaryPromptTemplate = resolvedConfiguration.promptTemplate
        self.summaryModelSelectionID = resolvedConfiguration.modelSelectionID

        if initialSummary != nil {
            summaryState = .idle
        }
    }

    init(
        liveState: MeetingOverlayState,
        initialSummarySettings: MeetingSummarySettingsSnapshot,
        summaryModelOptions: [MeetingSummaryModelOption],
        summarySettingsProvider: @escaping MeetingDetailWindowManager.SummarySettingsProvider,
        summaryModelOptionsProvider: @escaping MeetingDetailWindowManager.SummaryModelOptionsProvider,
        translationHandler: @escaping MeetingDetailWindowManager.TranslationHandler
    ) {
        self.mode = .live
        self.title = String(localized: "Meeting Details")
        self.subtitle = liveState.isPaused
            ? String(localized: "Meeting Paused")
            : String(localized: "Meeting In Progress")
        self.historyEntryID = nil
        self.summary = nil
        self.summaryChatMessages = []
        self.summaryModelOptions = summaryModelOptions
        self.segments = liveState.segments
        self.audioURL = nil
        self.isPaused = liveState.isPaused
        self.translationHandler = translationHandler
        self.summarySettingsProvider = summarySettingsProvider
        self.summaryModelOptionsProvider = summaryModelOptionsProvider
        self.summaryStatusProvider = nil
        self.summaryGenerator = nil
        self.summaryPersistence = nil
        self.summaryChatAnswerer = nil
        self.summaryChatPersistence = nil

        self.translationDraftLanguageRaw = Self.initialTranslationLanguageRaw()
        self.translationEnabled = liveState.realtimeTranslateEnabled || Self.segmentsContainTranslations(liveState.segments)

        let resolvedConfiguration = Self.resolveSummaryConfiguration(
            settings: initialSummarySettings,
            modelOptions: summaryModelOptions,
            currentSelectionID: nil
        )
        self.summaryAutoGenerate = resolvedConfiguration.autoGenerate
        self.summaryPromptTemplate = resolvedConfiguration.promptTemplate
        self.summaryModelSelectionID = resolvedConfiguration.modelSelectionID

        liveState.$segments
            .receive(on: RunLoop.main)
            .sink { [weak self] segments in
                self?.updateLiveSegments(segments)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(liveState.$isPaused, liveState.$isRecording)
            .receive(on: RunLoop.main)
            .sink { [weak self] isPaused, isRecording in
                self?.isPaused = isPaused
                self?.subtitle = isPaused
                    ? String(localized: "Meeting Paused")
                    : (isRecording ? String(localized: "Meeting In Progress") : String(localized: "Meeting Ended"))
            }
            .store(in: &cancellables)

        liveState.$realtimeTranslateEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if isEnabled {
                    self.translationEnabled = true
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        translationTasks.values.forEach { $0.cancel() }
        summaryTask?.cancel()
        summaryChatTask?.cancel()
    }

    var canExport: Bool {
        switch mode {
        case .history:
            return !segments.isEmpty
        case .live:
            return isPaused && !segments.isEmpty
        }
    }

    var canRegenerateSummary: Bool {
        mode == .history && historyEntryID != nil
    }

    var canSendSummaryChat: Bool {
        mode == .history
            && historyEntryID != nil
            && summary != nil
            && !segments.isEmpty
            && hasSummaryModelOptions
            && !isSummaryChatLoading
            && !summaryChatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSummaryModelOptions: Bool {
        !summaryModelOptions.isEmpty
    }

    var resolvedSummaryModelSelectionID: String {
        if summaryModelOptions.contains(where: { $0.id == summaryModelSelectionID }) {
            return summaryModelSelectionID
        }
        return summaryModelOptions.first?.id ?? summaryModelSelectionID
    }

    var summaryProviderMessage: String {
        summaryProviderStatus.message
    }

    var summaryProviderStatus: MeetingSummaryProviderStatus {
        switch mode {
        case .history:
            return summaryStatusProvider?(summarySettingsSnapshot)
                ?? MeetingSummaryProviderStatus(
                    isAvailable: false,
                    message: AppLocalization.localizedString("Meeting summary is unavailable.")
                )
        case .live:
            return MeetingSummaryProviderStatus(
                isAvailable: false,
                message: AppLocalization.localizedString("Meeting summary is generated after the meeting is saved.")
            )
        }
    }

    var transcriptPresentationMode: TranscriptPresentationMode {
        TranscriptPresentationMode(rawValue: transcriptPresentationModeRaw) ?? .timeline
    }

    func export() throws {
        try MeetingTranscriptExporter.export(
            segments: segments,
            defaultFilename: MeetingTranscriptExporter.defaultFilename(prefix: "Voxt-Meeting")
        )
    }

    func handleViewAppear() {
        guard !hasHandledInitialAppearance else { return }
        hasHandledInitialAppearance = true
        refreshSummaryConfigurationFromProviders()

        switch mode {
        case .history:
            if summary != nil {
                summaryState = .idle
                return
            }
            guard summaryAutoGenerate else {
                summaryState = .idle
                return
            }
            regenerateSummary(isAutomatic: true)
        case .live:
            summaryState = .idle
        }
    }

    func setTranslationEnabled(_ isEnabled: Bool) {
        guard isEnabled else {
            isTranslationLanguagePickerPresented = false
            translationEnabled = false
            cancelTranslationTasks()
            clearPendingTranslationState()
            return
        }

        if Self.segmentsContainTranslations(segments) {
            translationEnabled = true
            return
        }

        translationDraftLanguageRaw = resolvedStoredTranslationLanguage().rawValue
        isTranslationLanguagePickerPresented = true
        translationEnabled = false
    }

    func confirmTranslationLanguageSelection() {
        guard let language = TranslationTargetLanguage(rawValue: translationDraftLanguageRaw) else {
            cancelTranslationLanguageSelection()
            return
        }

        UserDefaults.standard.set(
            language.rawValue,
            forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage
        )
        isTranslationLanguagePickerPresented = false
        translationEnabled = true
        translateEligibleSegmentsIfNeeded(targetLanguage: language)
    }

    func cancelTranslationLanguageSelection() {
        isTranslationLanguagePickerPresented = false
        translationEnabled = false
    }

    func toggleTranslation() {
        setTranslationEnabled(!translationEnabled)
    }

    func setTranscriptPresentationMode(_ mode: TranscriptPresentationMode) {
        transcriptPresentationModeRaw = mode.rawValue
    }

    func toggleSearchPresentation() {
        isSearchPresented.toggle()
        if !isSearchPresented {
            searchQuery = ""
        }
    }

    func toggleSummaryCollapsed() {
        isSummaryCollapsed.toggle()
    }

    func presentSummarySettings() {
        refreshSummaryConfigurationFromProviders()
        isSummarySettingsPresented = true
    }

    func setSummaryAutoGenerate(_ isEnabled: Bool) {
        summaryAutoGenerate = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: AppPreferenceKey.meetingSummaryAutoGenerate)
        if !isEnabled && summary == nil {
            summaryState = .idle
        }
    }

    func setSummaryPromptTemplate(_ promptTemplate: String) {
        summaryPromptTemplate = promptTemplate
        UserDefaults.standard.set(promptTemplate, forKey: AppPreferenceKey.meetingSummaryPromptTemplate)
    }

    func resetSummaryPromptTemplate() {
        setSummaryPromptTemplate(AppPreferenceKey.defaultMeetingSummaryPrompt)
    }

    func setSummaryModelSelectionID(_ selectionID: String) {
        summaryModelSelectionID = selectionID
        UserDefaults.standard.set(selectionID, forKey: AppPreferenceKey.meetingSummaryModelSelection)
    }

    func regenerateSummary(isAutomatic: Bool = false) {
        guard mode == .history, let historyEntryID, let summaryGenerator else {
            summaryState = .unavailable(summaryProviderMessage)
            return
        }

        let providerStatus = summaryProviderStatus
        guard providerStatus.isAvailable else {
            summaryState = .unavailable(providerStatus.message)
            return
        }
        let settings = summarySettingsSnapshot
        let segmentsSnapshot = segments

        if !isAutomatic || summary == nil {
            summaryState = .loading
        }

        summaryTask?.cancel()
        summaryTask = Task { [weak self] in
            guard let self else { return }
            do {
                if isAutomatic {
                    try await Task.sleep(for: .milliseconds(220))
                }
                let transcript = await Task.detached(priority: .userInitiated) {
                    MeetingTranscriptFormatter.llmInputText(for: segmentsSnapshot)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }.value
                guard !transcript.isEmpty else {
                    await MainActor.run {
                        self.summaryState = .failed(AppLocalization.localizedString("No meeting transcript is available yet."))
                    }
                    return
                }
                let generated = try await summaryGenerator(transcript, settings)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.summary = generated
                    self.summaryState = .idle
                    _ = self.summaryPersistence?(historyEntryID, generated)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.summaryState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func sendSummaryChat() {
        guard mode == .history,
              let historyEntryID,
              let summaryChatAnswerer
        else {
            return
        }

        let question = summaryChatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        summaryChatDraft = ""
        summaryChatErrorMessage = nil
        let userMessage = MeetingSummaryChatMessage(role: .user, content: question)
        summaryChatMessages.append(userMessage)
        _ = summaryChatPersistence?(historyEntryID, summaryChatMessages)
        isSummaryChatLoading = true

        let settings = summarySettingsSnapshot
        let existingHistory = summaryChatMessages
        let currentSummary = summary
        let segmentsSnapshot = segments

        summaryChatTask?.cancel()
        summaryChatTask = Task { [weak self] in
            guard let self else { return }
            do {
                let transcript = await Task.detached(priority: .userInitiated) {
                    MeetingTranscriptFormatter.llmInputText(for: segmentsSnapshot)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }.value
                let answer = try await summaryChatAnswerer(
                    transcript,
                    currentSummary,
                    existingHistory,
                    question,
                    settings
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let assistantMessage = MeetingSummaryChatMessage(role: .assistant, content: answer)
                    self.summaryChatMessages.append(assistantMessage)
                    self.isSummaryChatLoading = false
                    self.summaryChatErrorMessage = nil
                    _ = self.summaryChatPersistence?(historyEntryID, self.summaryChatMessages)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isSummaryChatLoading = false
                    self.summaryChatErrorMessage = error.localizedDescription
                    _ = self.summaryChatPersistence?(historyEntryID, self.summaryChatMessages)
                }
            }
        }
    }

    func updateLiveSegments(_ incomingSegments: [MeetingTranscriptSegment]) {
        segments = mergeSegmentsPreservingTranslationState(incomingSegments)
        if translationEnabled {
            translateEligibleSegmentsIfNeeded(targetLanguage: resolvedStoredTranslationLanguage())
        }
    }

    func refreshSummaryConfiguration(
        settings: MeetingSummarySettingsSnapshot,
        modelOptions: [MeetingSummaryModelOption]
    ) {
        summaryModelOptions = modelOptions
        let resolvedConfiguration = Self.resolveSummaryConfiguration(
            settings: settings,
            modelOptions: modelOptions,
            currentSelectionID: summaryModelSelectionID
        )
        summaryAutoGenerate = resolvedConfiguration.autoGenerate
        summaryPromptTemplate = resolvedConfiguration.promptTemplate
        summaryModelSelectionID = resolvedConfiguration.modelSelectionID
    }

    private func mergeSegmentsPreservingTranslationState(_ incomingSegments: [MeetingTranscriptSegment]) -> [MeetingTranscriptSegment] {
        let existingByID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        return incomingSegments.map { incoming in
            guard let existing = existingByID[incoming.id] else { return incoming }

            let existingTranslatedText = existing.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let incomingTranslatedText = incoming.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTranslatedText = incomingTranslatedText?.isEmpty == false
                ? incomingTranslatedText
                : (existingTranslatedText?.isEmpty == false ? existingTranslatedText : nil)
            let textChanged =
                existing.text.trimmingCharacters(in: .whitespacesAndNewlines) !=
                incoming.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldRefreshTranslation = (existingTranslatedText?.isEmpty == false) && textChanged

            return MeetingTranscriptSegment(
                id: incoming.id,
                speaker: incoming.speaker,
                startSeconds: incoming.startSeconds,
                endSeconds: incoming.endSeconds,
                text: incoming.text,
                translatedText: resolvedTranslatedText,
                isTranslationPending: incoming.isTranslationPending || existing.isTranslationPending || shouldRefreshTranslation
            )
        }
    }

    private func translateEligibleSegmentsIfNeeded(targetLanguage: TranslationTargetLanguage) {
        for segment in segments where shouldTranslate(segment: segment) {
            markSegment(segment.id) { current in
                current.updatingTranslation(translatedText: current.translatedText, isTranslationPending: true)
            }

            translationTasks[segment.id]?.cancel()
            translationTasks[segment.id] = Task { [weak self] in
                guard let self else { return }
                do {
                    let translatedText = try await self.translationHandler(segment.text, targetLanguage)
                    await MainActor.run {
                        self.markSegment(segment.id) { current in
                            current.updatingTranslation(
                                translatedText: translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? nil
                                    : translatedText.trimmingCharacters(in: .whitespacesAndNewlines),
                                isTranslationPending: false
                            )
                        }
                        self.translationTasks[segment.id] = nil
                    }
                } catch {
                    await MainActor.run {
                        self.markSegment(segment.id) { current in
                            current.updatingTranslation(
                                translatedText: current.translatedText,
                                isTranslationPending: false
                            )
                        }
                        self.translationTasks[segment.id] = nil
                    }
                }
            }
        }
    }

    private func shouldTranslate(segment: MeetingTranscriptSegment) -> Bool {
        guard segment.speaker.isRemote else { return false }
        let translatedText = segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (translatedText.isEmpty || segment.isTranslationPending) && translationTasks[segment.id] == nil
    }

    private func markSegment(_ id: UUID, update: (MeetingTranscriptSegment) -> MeetingTranscriptSegment) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index] = update(segments[index])
    }

    private func cancelTranslationTasks() {
        translationTasks.values.forEach { $0.cancel() }
        translationTasks.removeAll()
    }

    private func clearPendingTranslationState() {
        segments = segments.map { segment in
            guard segment.isTranslationPending else { return segment }
            return segment.updatingTranslation(
                translatedText: segment.translatedText,
                isTranslationPending: false
            )
        }
    }

    private func resolvedStoredTranslationLanguage() -> TranslationTargetLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage),
              let language = TranslationTargetLanguage(rawValue: rawValue)
        else {
            return .english
        }
        return language
    }

    private var summarySettingsSnapshot: MeetingSummarySettingsSnapshot {
        MeetingSummarySettingsSnapshot(
            autoGenerate: summaryAutoGenerate,
            promptTemplate: summaryPromptTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
            modelSelectionID: resolvedSummaryModelSelectionID.isEmpty ? nil : resolvedSummaryModelSelectionID
        )
    }

    private func refreshSummaryConfigurationFromProviders() {
        guard let summarySettingsProvider, let summaryModelOptionsProvider else { return }
        refreshSummaryConfiguration(
            settings: summarySettingsProvider(),
            modelOptions: summaryModelOptionsProvider()
        )
    }

    private static func segmentsContainTranslations(_ segments: [MeetingTranscriptSegment]) -> Bool {
        segments.contains { segment in
            !(segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    private static func initialTranslationLanguageRaw() -> String {
        let savedLanguage = UserDefaults.standard.string(forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage)
        return savedLanguage?.isEmpty == false
            ? savedLanguage!
            : TranslationTargetLanguage.english.rawValue
    }

    private static func resolveSummaryConfiguration(
        settings: MeetingSummarySettingsSnapshot,
        modelOptions: [MeetingSummaryModelOption],
        currentSelectionID: String?
    ) -> MeetingDetailSummaryConfiguration {
        let preferredSelectionID = settings.modelSelectionID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedCurrentSelectionID = currentSelectionID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let resolvedSelectionID: String
        if modelOptions.contains(where: { $0.id == normalizedCurrentSelectionID }) {
            resolvedSelectionID = normalizedCurrentSelectionID
        } else if modelOptions.contains(where: { $0.id == preferredSelectionID }) {
            resolvedSelectionID = preferredSelectionID
        } else {
            resolvedSelectionID = modelOptions.first?.id ?? ""
        }

        return MeetingDetailSummaryConfiguration(
            autoGenerate: settings.autoGenerate,
            promptTemplate: MeetingSummarySupport.resolvedPromptTemplate(settings.promptTemplate),
            modelSelectionID: resolvedSelectionID
        )
    }
}

private struct MeetingDetailSummaryConfiguration {
    let autoGenerate: Bool
    let promptTemplate: String
    let modelSelectionID: String
}

@MainActor
enum MeetingTranscriptExporter {
    static func defaultFilename(prefix: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(prefix)-\(formatter.string(from: Date())).txt"
    }

    static func export(segments: [MeetingTranscriptSegment], defaultFilename: String) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = defaultFilename
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try MeetingTranscriptFormatter.joinedText(for: segments).write(to: url, atomically: true, encoding: .utf8)
    }
}
