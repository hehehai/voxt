// MeetingDetailWindow.swift
// Provides Meeting Detail Window for meeting detail windows.

import AppKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
final class MeetingDetailWindowManager {
    static let shared = MeetingDetailWindowManager()

    typealias TranslationHandler = @MainActor (String, TranslationTargetLanguage) -> MeetingTranslationOperation
    typealias SummarySettingsProvider = @MainActor () -> MeetingSummarySettingsSnapshot
    typealias SummaryModelOptionsProvider = @MainActor () -> [MeetingSummaryModelOption]
    typealias SummaryStatusProvider = @MainActor (MeetingSummarySettingsSnapshot) -> MeetingSummaryProviderStatus
    typealias SummaryGenerator = @MainActor (String, MeetingSummarySettingsSnapshot) async throws -> MeetingSummarySnapshot
    typealias SummaryPersistence = @MainActor (UUID, MeetingSummarySnapshot?) -> TranscriptionHistoryEntry?
    typealias SummaryChatAnswerer = @MainActor (String, MeetingSummarySnapshot?, [MeetingSummaryChatMessage], String, MeetingSummarySettingsSnapshot) async throws -> String
    typealias SummaryChatPersistence = @MainActor (UUID, [MeetingSummaryChatMessage]) -> TranscriptionHistoryEntry?
    typealias TranscriptSegmentsPersistence = @MainActor (UUID, [MeetingTranscriptSegment]) -> TranscriptionHistoryEntry?

    private var historyControllers: [UUID: MeetingDetailWindowController] = [:]
    private var liveController: MeetingDetailWindowController?

    func presentHistoryMeeting(
        entry: TranscriptionHistoryEntry,
        audioURL: URL?,
        initialSummarySettings: MeetingSummarySettingsSnapshot,
        summaryModelOptionsProvider: @escaping SummaryModelOptionsProvider,
        summarySettingsProvider: @escaping SummarySettingsProvider,
        translationHandler: @escaping TranslationHandler,
        summaryStatusProvider: @escaping SummaryStatusProvider,
        summaryGenerator: @escaping SummaryGenerator,
        summaryPersistence: @escaping SummaryPersistence,
        summaryChatAnswerer: @escaping SummaryChatAnswerer,
        summaryChatPersistence: @escaping SummaryChatPersistence,
        transcriptSegmentsPersistence: @escaping TranscriptSegmentsPersistence
    ) {
        if let controller = historyControllers[entry.id] {
            controller.refreshSummaryConfiguration(
                settings: summarySettingsProvider(),
                modelOptions: summaryModelOptionsProvider()
            )
            controller.showWindow(nil)
            AppBehaviorController.bringStandardWindowToFront(controller.window)
            return
        }

        let summaryModelOptions = summaryModelOptionsProvider()

        let viewModel = MeetingDetailViewModel(
            title: AppLocalization.localizedString("Meeting Details"),
            subtitle: entry.createdAt.formatted(date: .abbreviated, time: .shortened),
            historyEntryID: entry.id,
            initialSummary: entry.transcriptSummary,
            initialSummaryChatMessages: entry.transcriptSummaryChatMessages ?? [],
            initialSummarySettings: initialSummarySettings,
            summaryModelOptions: summaryModelOptions,
            summarySettingsProvider: summarySettingsProvider,
            summaryModelOptionsProvider: summaryModelOptionsProvider,
            segments: entry.transcriptSegments ?? [],
            captureMode: entry.meetingCaptureMode,
            audioURL: audioURL,
            translationHandler: translationHandler,
            summaryStatusProvider: summaryStatusProvider,
            summaryGenerator: summaryGenerator,
            summaryPersistence: summaryPersistence,
            summaryChatAnswerer: summaryChatAnswerer,
            summaryChatPersistence: summaryChatPersistence,
            transcriptSegmentsPersistence: transcriptSegmentsPersistence
        )
        let controller = MeetingDetailWindowController(viewModel: viewModel) { [weak self] in
            self?.historyControllers[entry.id] = nil
        }
        historyControllers[entry.id] = controller
        controller.showWindow(nil)
        AppBehaviorController.bringStandardWindowToFront(controller.window)
    }

    func presentLiveMeeting(
        state: MeetingOverlayState,
        initialSummarySettings: MeetingSummarySettingsSnapshot,
        summaryModelOptionsProvider: @escaping SummaryModelOptionsProvider,
        summarySettingsProvider: @escaping SummarySettingsProvider,
        translationHandler: @escaping TranslationHandler
    ) {
        if let controller = liveController {
            controller.refreshSummaryConfiguration(
                settings: summarySettingsProvider(),
                modelOptions: summaryModelOptionsProvider()
            )
            controller.showWindow(nil)
            AppBehaviorController.bringStandardWindowToFront(controller.window)
            return
        }

        let viewModel = MeetingDetailViewModel(
            liveState: state,
            initialSummarySettings: initialSummarySettings,
            summaryModelOptions: summaryModelOptionsProvider(),
            summarySettingsProvider: summarySettingsProvider,
            summaryModelOptionsProvider: summaryModelOptionsProvider,
            translationHandler: translationHandler
        )
        let controller = MeetingDetailWindowController(viewModel: viewModel) { [weak self] in
            self?.liveController = nil
        }
        liveController = controller
        controller.showWindow(nil)
        AppBehaviorController.bringStandardWindowToFront(controller.window)
    }

    func closeLiveWindow() {
        liveController?.close()
        liveController = nil
    }
}

@MainActor
private final class MeetingDetailWindowController: NSWindowController, NSWindowDelegate {
    private static let defaultWindowSize = NSSize(width: 1040, height: 700)
    private static let minimumWindowSize = NSSize(width: 860, height: 560)

    private let onClose: () -> Void

    init(viewModel: MeetingDetailViewModel, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let rootView = MeetingDetailWindowView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = AppLocalization.localizedString("Meeting Details")
        window.center()
        window.setFrameAutosaveName("VoxtMeetingDetailWindow")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = SettingsUIStyle.windowBackgroundNSColor
        window.hasShadow = true
        window.collectionBehavior = []
        window.level = .normal
        window.minSize = Self.minimumWindowSize
        window.setContentSize(Self.defaultWindowSize)

        super.init(window: window)
        window.delegate = self
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        positionWindowTrafficLightButtons(window)
        scheduleTrafficLightButtonPositionUpdate(for: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    func windowDidResize(_ notification: Notification) {
        guard let window else { return }
        scheduleTrafficLightButtonPositionUpdate(for: window)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window else { return }
        scheduleTrafficLightButtonPositionUpdate(for: window)
    }

    func refreshSummaryConfiguration(
        settings: MeetingSummarySettingsSnapshot,
        modelOptions: [MeetingSummaryModelOption]
    ) {
        guard let hostingController = window?.contentViewController as? NSHostingController<MeetingDetailWindowView> else {
            return
        }
        hostingController.rootView.viewModel.refreshSummaryConfiguration(
            settings: settings,
            modelOptions: modelOptions
        )
    }

    private func positionWindowTrafficLightButtons(_ window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let miniaturizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let container = closeButton.superview
        else {
            return
        }

        let leftInset: CGFloat = 15
        let topInset: CGFloat = 21
        let spacing: CGFloat = 6

        let buttonSize = closeButton.frame.size
        let y = container.bounds.height - topInset - buttonSize.height
        let closeX = leftInset
        let miniaturizeX = closeX + buttonSize.width + spacing
        let zoomX = miniaturizeX + buttonSize.width + spacing

        closeButton.translatesAutoresizingMaskIntoConstraints = true
        miniaturizeButton.translatesAutoresizingMaskIntoConstraints = true
        zoomButton.translatesAutoresizingMaskIntoConstraints = true

        closeButton.setFrameOrigin(CGPoint(x: closeX, y: y))
        miniaturizeButton.setFrameOrigin(CGPoint(x: miniaturizeX, y: y))
        zoomButton.setFrameOrigin(CGPoint(x: zoomX, y: y))
    }

    private func scheduleTrafficLightButtonPositionUpdate(for window: NSWindow) {
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.positionWindowTrafficLightButtons(window)
        }
    }
}

@MainActor
private final class MeetingDetailPlaybackController: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    init(audioURL: URL?) {
        guard let audioURL else { return }
        player = try? AVAudioPlayer(contentsOf: audioURL)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    deinit {
        timer?.invalidate()
    }

    var isAvailable: Bool {
        player != nil && duration > 0
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(time, duration))
        player.currentTime = clamped
        currentTime = clamped
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

private struct MeetingDetailWindowView: View {
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @ObservedObject var viewModel: MeetingDetailViewModel
    @StateObject private var playbackController: MeetingDetailPlaybackController
    @State private var activeSegmentID: UUID?
    @State private var speakerRenameGroupID: String?
    @State private var speakerRenameDraft = ""
    @State private var isScrubbing = false
    @State private var scrollRequest: MeetingTranscriptScrollRequest?
    @State private var scrollGeneration: UInt64 = 0
    @State private var displayedSegmentIDs: Set<UUID> = []

    init(viewModel: MeetingDetailViewModel) {
        self.viewModel = viewModel
        _playbackController = StateObject(wrappedValue: MeetingDetailPlaybackController(audioURL: viewModel.audioURL))
    }

    var body: some View {
        let _ = interfaceLanguageRaw
        ZStack {
            GeometryReader { proxy in
                let sidebarWidth = max(300, min(proxy.size.width / 3.0, 380))

                HStack(alignment: .top, spacing: 8) {
                    leftPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !viewModel.isSummaryCollapsed {
                        rightSidebar
                            .frame(width: sidebarWidth)
                            .frame(maxHeight: .infinity)
                    }
                }
                .padding(12)
            }
            .frame(minWidth: 980, minHeight: 650)
            .ignoresSafeArea(.container, edges: .top)
            .onAppear {
                viewModel.handleViewAppear()
                displayedSegmentIDs = Set(viewModel.displayedSegments.map(\.id))
                updateActiveSegment(for: playbackController.currentTime)
            }

            if speakerRenameGroupID != nil {
                dialogDimmingMask(opacity: 0.14)

                speakerRenameDialog
            }

        }
        .background(MeetingDetailUIStyle.windowFillColor)
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: $viewModel.isTranslationLanguagePickerPresented) {
            translationLanguageDialog
        }
        .sheet(isPresented: $viewModel.isSummarySettingsPresented) {
            MeetingDetailSummarySettingsDialog(viewModel: viewModel)
        }
        .onChange(of: viewModel.segmentStructureRevision) { _, _ in
            displayedSegmentIDs = Set(viewModel.displayedSegments.map(\.id))
            updateActiveSegment(for: playbackController.currentTime)
            requestLiveScrollToNewestIfNeeded()
        }
        .onChange(of: viewModel.displayedSegments) { _, newValue in
            displayedSegmentIDs = Set(newValue.map(\.id))
        }
        .onChange(of: playbackController.currentTime) { _, newValue in
            guard viewModel.mode == .history else { return }
            updateActiveSegment(for: newValue)
        }
        .onChange(of: activeSegmentID) { _, newValue in
            requestHistoryScrollToActiveSegment(newValue)
        }
        .onChange(of: isScrubbing) { _, scrubbing in
            guard !scrubbing else { return }
            requestHistoryScrollToActiveSegment(activeSegmentID)
        }
    }

    private func dialogDimmingMask(opacity: Double) -> some View {
        Color.black.opacity(opacity)
            .ignoresSafeArea()
            .clipShape(
                RoundedRectangle(cornerRadius: MeetingDetailUIStyle.windowCornerRadius, style: .continuous)
            )
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            topToolbar

            if viewModel.isSearchPresented {
                transcriptSearchBar
            }

            transcriptPane

            playbackPane
        }
    }

    private var topToolbar: some View {
        HStack(alignment: .center, spacing: 10) {
            Color.clear
                .frame(width: 62, height: 1)

            transcriptTabPicker

            if viewModel.transcriptPresentationMode == .timeline,
               viewModel.showsSpeakerDisplayModePicker {
                transcriptSpeakerDisplayModePicker
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button(AppLocalization.localizedString("Search")) {
                    viewModel.toggleSearchPresentation()
                }
                .buttonStyle(MeetingToolbarButtonStyle(isActive: viewModel.isSearchPresented))

                Button(AppLocalization.localizedString("Translate")) {
                    viewModel.toggleTranslation()
                }
                .buttonStyle(MeetingToolbarButtonStyle(isActive: viewModel.translationEnabled))

                Button(AppLocalization.localizedString("Export")) {
                    try? viewModel.export()
                }
                .buttonStyle(MeetingToolbarButtonStyle())
                .disabled(!viewModel.canExport)

                Rectangle()
                    .fill(MeetingDetailUIStyle.dividerColor)
                    .frame(width: 1, height: 18)

                Button(
                    viewModel.isSummaryCollapsed
                        ? AppLocalization.localizedString("Expand Summary")
                        : AppLocalization.localizedString("Collapse Summary")
                ) {
                    viewModel.toggleSummaryCollapsed()
                }
                .buttonStyle(MeetingToolbarButtonStyle(isActive: viewModel.isSummaryCollapsed))
            }
        }
    }

    private var transcriptTabPicker: some View {
        HStack(spacing: 2) {
            ForEach(viewModel.availableTranscriptPresentationModes) { mode in
                Button {
                    viewModel.setTranscriptPresentationMode(mode)
                } label: {
                    Text(transcriptTabTitle(for: mode))
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    viewModel.transcriptPresentationMode == mode
                        ? Color.accentColor
                        : Color.secondary
                )
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            viewModel.transcriptPresentationMode == mode
                                ? Color.accentColor.opacity(0.14)
                                : .clear
                        )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            viewModel.transcriptPresentationMode == mode
                                ? Color.accentColor.opacity(0.45)
                                : .clear,
                            lineWidth: 1
                        )
                }
            }
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MeetingDetailUIStyle.controlFillColor)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MeetingDetailUIStyle.borderColor, lineWidth: 1)
        }
    }

    private func transcriptTabTitle(for mode: MeetingDetailViewModel.TranscriptPresentationMode) -> String {
        switch mode {
        case .timeline:
            return AppLocalization.localizedString("Timeline")
        case .speakerMarks:
            return AppLocalization.localizedString("Speaker Marks")
        }
    }

    private var transcriptSpeakerDisplayModePicker: some View {
        HStack(spacing: 2) {
            ForEach(MeetingDetailViewModel.TranscriptSpeakerDisplayMode.allCases) { mode in
                Button {
                    viewModel.setTranscriptSpeakerDisplayMode(mode)
                } label: {
                    Text(transcriptSpeakerDisplayModeTitle(for: mode))
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    viewModel.transcriptSpeakerDisplayMode == mode
                        ? Color.primary
                        : Color.secondary
                )
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            viewModel.transcriptSpeakerDisplayMode == mode
                                ? MeetingDetailUIStyle.windowFillColor
                                : .clear
                        )
                )
            }
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MeetingDetailUIStyle.controlFillColor.opacity(0.72))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MeetingDetailUIStyle.borderColor.opacity(0.72), lineWidth: 1)
        }
    }

    private func transcriptSpeakerDisplayModeTitle(
        for mode: MeetingDetailViewModel.TranscriptSpeakerDisplayMode
    ) -> String {
        switch mode {
        case .source:
            return AppLocalization.localizedString("Audio Source")
        case .speaker:
            return AppLocalization.localizedString("Speaker")
        }
    }

    private var transcriptSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(
                AppLocalization.localizedString("Search transcript"),
                text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.setSearchQuery($0) }
                )
            )
                .textFieldStyle(.plain)

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.setSearchQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .meetingDetailPanelSurface(cornerRadius: 12)
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            transcriptCaption

            if viewModel.isFinalizing {
                meetingFinalizationBanner
            }

            if viewModel.displayedSegments.isEmpty {
                transcriptEmptyState
            } else if viewModel.transcriptPresentationMode == .timeline {
                MeetingDetailTranscriptListPane(
                    rows: timelineVirtualRows,
                    showsTranslation: viewModel.translationEnabled,
                    scrollRequest: scrollRequest
                )
                .equatable()
            } else {
                speakerMarksPane
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .meetingDetailPanelSurface(cornerRadius: 16)
    }

    private var timelineVirtualRows: [MeetingTranscriptVirtualRow] {
        MeetingTranscriptListSupport.timelineRows(
            from: viewModel.displayedSegments,
            activeSegmentID: activeSegmentID,
            showsTranslation: viewModel.translationEnabled,
            searchQuery: viewModel.searchQuery,
            speakerTitle: viewModel.timelineSpeakerTitle(for:)
        )
    }

    private var speakerMarkVirtualRows: [MeetingTranscriptVirtualRow] {
        MeetingTranscriptListSupport.speakerMarkRows(
            from: viewModel.speakerGroups,
            activeSegmentID: activeSegmentID,
            showsTranslation: viewModel.translationEnabled,
            searchQuery: viewModel.searchQuery
        )
    }

    private var transcriptCaption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalization.localizedString("Meeting Transcript"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            Text(viewModel.subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var transcriptEmptyState: some View {
        if viewModel.segments.isEmpty {
            VStack(spacing: 10) {
                if viewModel.isFinalizing {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(
                    viewModel.isFinalizing
                        ? AppLocalization.localizedString("Preparing final transcript…")
                        : transcriptEmptyTitle
                )
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(
                    viewModel.isFinalizing
                        ? AppLocalization.localizedString("Voxt is finishing audio flushing, final transcription, and speaker analysis.")
                        : transcriptEmptyMessage
                )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
        } else {
            VStack(spacing: 10) {
                Text(AppLocalization.localizedString("No matching transcript segments."))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(AppLocalization.localizedString("Try a different keyword or clear the current search."))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
        }
    }

    private var transcriptEmptyTitle: String {
        if viewModel.mode == .history, viewModel.audioURL != nil {
            return AppLocalization.localizedString("No transcript was produced for this recording.")
        }
        return AppLocalization.localizedString("The transcript timeline for Me / Them will appear here once the meeting starts.")
    }

    private var transcriptEmptyMessage: String {
        if viewModel.mode == .history, viewModel.audioURL != nil {
            return AppLocalization.localizedString("The audio recording is saved and available for playback.")
        }
        return AppLocalization.localizedString("This panel stays focused on the detailed transcript and synced playback.")
    }

    private var meetingFinalizationBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalization.localizedString("Preparing final meeting details…"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(AppLocalization.localizedString("Current transcript is available now. Final text, speaker labels, audio playback, and summary will update when processing finishes."))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 1)
        )
    }

    private var speakerMarksPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                ForEach(viewModel.speakerGroups) { group in
                    speakerOverviewCard(for: group)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            MeetingDetailTranscriptListPane(
                rows: speakerMarkVirtualRows,
                showsTranslation: viewModel.translationEnabled,
                scrollRequest: scrollRequest
            )
            .equatable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func speakerOverviewCard(for group: MeetingDetailSpeakerGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                if viewModel.canEditSpeakers {
                    Button {
                        presentSpeakerRename(for: group)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(AppLocalization.localizedString("Rename Speaker"))
                }
            }

            Text(AppLocalization.format("%d", group.segments.count))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)

            Text(AppLocalization.format("%d words", group.wordCount))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MeetingDetailUIStyle.controlFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(MeetingDetailUIStyle.softBorderColor, lineWidth: 1)
        )
    }

    private var speakerRenameDialog: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(AppLocalization.localizedString("Rename Speaker"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(AppLocalization.localizedString("This name will be applied to all matching transcript segments."))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            TextField(AppLocalization.localizedString("Speaker name"), text: $speakerRenameDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MeetingDetailUIStyle.controlFillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(MeetingDetailUIStyle.borderColor, lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button(AppLocalization.localizedString("Cancel")) {
                    cancelSpeakerRename()
                }
                .buttonStyle(MeetingPillButtonStyle())

                Spacer(minLength: 8)

                Button(AppLocalization.localizedString("Save")) {
                    commitSpeakerRename()
                }
                .buttonStyle(MeetingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(SettingsUIStyle.dialogPadding)
        .frame(width: 400)
        .background(SettingsUIStyle.windowBackgroundColor)
        .clipShape(
            RoundedRectangle(cornerRadius: SettingsUIStyle.dialogCornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUIStyle.dialogCornerRadius, style: .continuous)
                .strokeBorder(SettingsUIStyle.dialogBorderColor, lineWidth: 0.7)
        )
    }

    @ViewBuilder
    private var playbackPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.mode == .history {
                if playbackController.isAvailable {
                    HStack(spacing: 12) {
                        Button {
                            playbackController.togglePlayPause()
                        } label: {
                            Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.16))
                                )
                        }
                        .buttonStyle(.plain)

                        Slider(
                            value: Binding(
                                get: { playbackController.currentTime },
                                set: { playbackController.seek(to: $0) }
                            ),
                            in: 0...max(playbackController.duration, 0.1),
                            onEditingChanged: { editing in
                                isScrubbing = editing
                            }
                        )

                        Text(timerLabel)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 96, alignment: .trailing)
                    }
                } else {
                    HistoryAudioUnavailableView(compact: false)
                }
            } else {
                if viewModel.isFinalizing {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text(AppLocalization.localizedString("Audio playback will be available after the meeting is saved."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(
                        viewModel.canExport
                            ? AppLocalization.localizedString("The meeting is paused. You can export the current record.")
                            : AppLocalization.localizedString("The meeting is in progress. Pause it to export the current record.")
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .meetingDetailPanelSurface(cornerRadius: 16)
    }

    private var rightSidebar: some View {
        MeetingDetailSummarySidebar(viewModel: viewModel)
    }

    private var translationLanguageDialog: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(AppLocalization.localizedString("Choose Translation Language"))
                .font(.title3.weight(.semibold))

            SettingsMenuPicker(
                selection: $viewModel.translationDraftLanguageRaw,
                options: TranslationTargetLanguage.allCases.map { language in
                    SettingsMenuOption(value: language.rawValue, title: language.title)
                },
                selectedTitle: translationDraftLanguage.title,
                width: 320
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .accessibilityLabel(AppLocalization.localizedString("Target Language"))

            SettingsDialogActionRow {
                Button(AppLocalization.localizedString("Cancel")) {
                    viewModel.cancelTranslationLanguageSelection()
                }
                .buttonStyle(SettingsPillButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(AppLocalization.localizedString("Start Translation")) {
                    viewModel.confirmTranslationLanguageSelection()
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .settingsDialogChrome(width: 400, onClose: {
            viewModel.cancelTranslationLanguageSelection()
        })
    }

    private var translationDraftLanguage: TranslationTargetLanguage {
        TranslationTargetLanguage(rawValue: viewModel.translationDraftLanguageRaw) ?? .english
    }

    private var timerLabel: String {
        "\(MeetingTranscriptFormatter.timestampString(for: playbackController.currentTime)) / \(MeetingTranscriptFormatter.timestampString(for: playbackController.duration))"
    }

    private func updateActiveSegment(for currentTime: TimeInterval) {
        guard viewModel.mode == .history else {
            activeSegmentID = nil
            return
        }
        guard currentTime > 0.01 || playbackController.isPlaying || isScrubbing else {
            activeSegmentID = nil
            return
        }
        let newActiveSegment = activeSegment(at: currentTime)
        activeSegmentID = newActiveSegment?.id
    }

    private func activeSegment(at currentTime: TimeInterval) -> MeetingTranscriptSegment? {
        let segments = viewModel.segments
        guard !segments.isEmpty else { return nil }

        var low = 0
        var high = segments.count
        while low < high {
            let mid = (low + high) / 2
            if segments[mid].startSeconds <= currentTime {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low > 0 ? segments[low - 1] : segments.first
    }

    private func requestHistoryScrollToActiveSegment(_ segmentID: UUID?) {
        guard viewModel.mode == .history else { return }
        guard !isScrubbing else { return }
        guard viewModel.transcriptPresentationMode == .timeline else { return }
        guard let segmentID, displayedSegmentIDs.contains(segmentID) else { return }
        scrollGeneration &+= 1
        scrollRequest = MeetingTranscriptScrollRequest(
            rowID: segmentID.uuidString,
            anchor: .center,
            generation: scrollGeneration
        )
    }

    private func requestLiveScrollToNewestIfNeeded() {
        guard viewModel.mode == .live else { return }
        guard viewModel.transcriptPresentationMode == .timeline else { return }
        guard let newest = viewModel.displayedNewestSegmentID() else { return }
        scrollGeneration &+= 1
        scrollRequest = MeetingTranscriptScrollRequest(
            rowID: newest.uuidString,
            anchor: .bottom,
            generation: scrollGeneration
        )
    }

    private func presentSpeakerRename(for group: MeetingDetailSpeakerGroup) {
        speakerRenameGroupID = group.id
        speakerRenameDraft = group.title
    }

    private func cancelSpeakerRename() {
        speakerRenameGroupID = nil
        speakerRenameDraft = ""
    }

    private func commitSpeakerRename() {
        guard let speakerRenameGroupID else { return }
        viewModel.renameSpeaker(identityKey: speakerRenameGroupID, displayName: speakerRenameDraft)
        cancelSpeakerRename()
    }
}

private struct MeetingDetailTranscriptListPane: View, Equatable {
    let rows: [MeetingTranscriptVirtualRow]
    let showsTranslation: Bool
    let scrollRequest: MeetingTranscriptScrollRequest?

    static func == (
        lhs: MeetingDetailTranscriptListPane,
        rhs: MeetingDetailTranscriptListPane
    ) -> Bool {
        lhs.rows == rhs.rows
            && lhs.showsTranslation == rhs.showsTranslation
            && lhs.scrollRequest == rhs.scrollRequest
    }

    var body: some View {
        MeetingTranscriptVirtualList(
            rows: rows,
            showsTranslation: showsTranslation,
            scrollRequest: scrollRequest
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
