import AppKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
final class MeetingDetailWindowManager {
    static let shared = MeetingDetailWindowManager()

    typealias TranslationHandler = @MainActor (String, TranslationTargetLanguage) async throws -> String
    typealias SummarySettingsProvider = @MainActor () -> MeetingSummarySettingsSnapshot
    typealias SummaryModelOptionsProvider = @MainActor () -> [MeetingSummaryModelOption]
    typealias SummaryStatusProvider = @MainActor (MeetingSummarySettingsSnapshot) -> MeetingSummaryProviderStatus
    typealias SummaryGenerator = @MainActor (String, MeetingSummarySettingsSnapshot) async throws -> MeetingSummarySnapshot
    typealias SummaryPersistence = @MainActor (UUID, MeetingSummarySnapshot?) -> TranscriptionHistoryEntry?
    typealias SummaryChatAnswerer = @MainActor (String, MeetingSummarySnapshot?, [MeetingSummaryChatMessage], String, MeetingSummarySettingsSnapshot) async throws -> String
    typealias SummaryChatPersistence = @MainActor (UUID, [MeetingSummaryChatMessage]) -> TranscriptionHistoryEntry?

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
        summaryChatPersistence: @escaping SummaryChatPersistence
    ) {
        if let controller = historyControllers[entry.id] {
            controller.refreshSummaryConfiguration(
                settings: summarySettingsProvider(),
                modelOptions: summaryModelOptionsProvider()
            )
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let summaryModelOptions = summaryModelOptionsProvider()

        let viewModel = MeetingDetailViewModel(
            title: String(localized: "Meeting Details"),
            subtitle: entry.createdAt.formatted(date: .abbreviated, time: .shortened),
            historyEntryID: entry.id,
            initialSummary: entry.meetingSummary,
            initialSummaryChatMessages: entry.meetingSummaryChatMessages ?? [],
            initialSummarySettings: initialSummarySettings,
            summaryModelOptions: summaryModelOptions,
            summarySettingsProvider: summarySettingsProvider,
            summaryModelOptionsProvider: summaryModelOptionsProvider,
            segments: entry.meetingSegments ?? [],
            audioURL: audioURL,
            translationHandler: translationHandler,
            summaryStatusProvider: summaryStatusProvider,
            summaryGenerator: summaryGenerator,
            summaryPersistence: summaryPersistence,
            summaryChatAnswerer: summaryChatAnswerer,
            summaryChatPersistence: summaryChatPersistence
        )
        let controller = MeetingDetailWindowController(viewModel: viewModel) { [weak self] in
            self?.historyControllers[entry.id] = nil
        }
        historyControllers[entry.id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeLiveWindow() {
        liveController?.close()
        liveController = nil
    }
}

@MainActor
private final class MeetingDetailWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(viewModel: MeetingDetailViewModel, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let rootView = MeetingDetailWindowView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
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
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

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
    @ObservedObject var viewModel: MeetingDetailViewModel
    @StateObject private var playbackController: MeetingDetailPlaybackController
    @State private var activeSegmentID: UUID?
    @State private var isScrubbing = false

    init(viewModel: MeetingDetailViewModel) {
        self.viewModel = viewModel
        _playbackController = StateObject(wrappedValue: MeetingDetailPlaybackController(audioURL: viewModel.audioURL))
    }

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let sidebarWidth = max(300, min(proxy.size.width / 3.0, 380))

                ZStack {
                    windowShell

                    HStack(alignment: .top, spacing: 8) {
                        leftPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if !viewModel.isSummaryCollapsed {
                            rightSidebar
                                .frame(width: sidebarWidth)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .padding(10)
                }
            }
            .frame(minWidth: 980, minHeight: 650)
            .ignoresSafeArea(.container, edges: .top)
            .onAppear {
                viewModel.handleViewAppear()
                updateActiveSegment(for: playbackController.currentTime)
            }

            if viewModel.isTranslationLanguagePickerPresented {
                Color.black.opacity(0.14)
                    .ignoresSafeArea()

                translationLanguageDialog
            }

            if viewModel.isSummarySettingsPresented {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()

                MeetingDetailSummarySettingsDialog(viewModel: viewModel)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private var windowShell: some View {
        RoundedRectangle(cornerRadius: MeetingDetailUIStyle.windowCornerRadius, style: .continuous)
            .fill(MeetingDetailUIStyle.windowFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: MeetingDetailUIStyle.windowCornerRadius, style: .continuous)
                    .strokeBorder(MeetingDetailUIStyle.borderColor, lineWidth: 1)
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

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button(String(localized: "Search")) {
                    viewModel.toggleSearchPresentation()
                }
                .buttonStyle(MeetingToolbarButtonStyle(isActive: viewModel.isSearchPresented))

                Button(String(localized: "Translate")) {
                    viewModel.toggleTranslation()
                }
                .buttonStyle(MeetingToolbarButtonStyle(isActive: viewModel.translationEnabled))

                Button(String(localized: "Export")) {
                    try? viewModel.export()
                }
                .buttonStyle(MeetingToolbarButtonStyle())
                .disabled(!viewModel.canExport)

                Rectangle()
                    .fill(MeetingDetailUIStyle.dividerColor)
                    .frame(width: 1, height: 18)

                Button(
                    viewModel.isSummaryCollapsed
                        ? String(localized: "Expand Summary")
                        : String(localized: "Collapse Summary")
                ) {
                    viewModel.toggleSummaryCollapsed()
                }
                .buttonStyle(MeetingToolbarButtonStyle(isActive: viewModel.isSummaryCollapsed))
            }
        }
    }

    private var transcriptTabPicker: some View {
        HStack(spacing: 2) {
            ForEach(MeetingDetailViewModel.TranscriptPresentationMode.allCases) { mode in
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
            return String(localized: "Timeline")
        case .speakerMarks:
            return String(localized: "Speaker Marks")
        }
    }

    private var transcriptSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(String(localized: "Search transcript"), text: $viewModel.searchQuery)
                .textFieldStyle(.plain)

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    transcriptCaption

                    if displayedSegments.isEmpty {
                        transcriptEmptyState
                    } else if viewModel.transcriptPresentationMode == .timeline {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(displayedSegments) { segment in
                                MeetingDetailSegmentRow(
                                    segment: segment,
                                    isActive: activeSegmentID == segment.id,
                                    showsTranslation: viewModel.translationEnabled,
                                    isSearchMatch: segmentMatchesSearch(segment)
                                )
                                .id(segment.id)
                            }
                        }
                    } else {
                        speakerMarksPane
                    }
                }
                .padding(16)
            }
            .meetingDetailPanelSurface(cornerRadius: 16)
            .onChange(of: playbackController.currentTime) { _, newValue in
                guard viewModel.mode == .history else { return }
                updateActiveSegment(for: newValue)
                guard !isScrubbing,
                      viewModel.transcriptPresentationMode == .timeline,
                      let activeSegmentID,
                      displayedSegments.contains(where: { $0.id == activeSegmentID })
                else {
                    return
                }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(activeSegmentID, anchor: .center)
                }
            }
            .onChange(of: viewModel.segments) { _, newValue in
                guard viewModel.mode == .live,
                      viewModel.transcriptPresentationMode == .timeline,
                      let newest = displayedNewestSegmentID(in: newValue)
                else {
                    return
                }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(newest, anchor: .bottom)
                }
            }
        }
    }

    private var transcriptCaption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Meeting Transcript"))
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
                Text(String(localized: "The transcript timeline for you and remote speakers will appear here once the meeting starts."))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(String(localized: "This panel stays focused on the detailed transcript and synced playback."))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .center)
        } else {
            VStack(spacing: 10) {
                Text(String(localized: "No matching transcript segments."))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(String(localized: "Try a different keyword or clear the current search."))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
        }
    }

    private var speakerMarksPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ForEach(speakerOverviewSpeakers, id: \.rawValue) { speaker in
                    speakerOverviewCard(for: speaker)
                }
            }

            ForEach(displayedSpeakerMarks, id: \.rawValue) { speaker in
                let segments = displayedSegments.filter { $0.speaker == speaker }
                if !segments.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(speaker.displayTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text(AppLocalization.format("%d", segments.count))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(MeetingDetailUIStyle.mutedFillColor)
                                )
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(segments) { segment in
                                MeetingDetailSegmentRow(
                                    segment: segment,
                                    isActive: activeSegmentID == segment.id,
                                    showsTranslation: viewModel.translationEnabled,
                                    isSearchMatch: segmentMatchesSearch(segment)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private func speakerOverviewCard(for speaker: MeetingSpeaker) -> some View {
        let segments = displayedSegments.filter { $0.speaker == speaker }
        let totalWords = segments.reduce(0) { partialResult, segment in
            partialResult + segment.text.split(whereSeparator: \.isWhitespace).count
        }

        return VStack(alignment: .leading, spacing: 6) {
            Text(speaker.displayTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(AppLocalization.format("%d", segments.count))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)

            Text(AppLocalization.format("%d words", totalWords))
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

    private var speakerOverviewSpeakers: [MeetingSpeaker] {
        orderedSpeakers(in: displayedSegments)
    }

    private var displayedSpeakerMarks: [MeetingSpeaker] {
        orderedSpeakers(in: displayedSegments)
    }

    private func orderedSpeakers(in segments: [MeetingTranscriptSegment]) -> [MeetingSpeaker] {
        let speakers = Array(Set(segments.map(\.speaker)))
        return speakers.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case (.me, .me), (.them, .them):
                return false
            case (.me, _):
                return true
            case (_, .me):
                return false
            case (.them, _):
                return true
            case (_, .them):
                return false
            case (.remote(let leftIndex), .remote(let rightIndex)):
                return leftIndex < rightIndex
            }
        }
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
                    Text(String(localized: "No playable audio is available for this meeting record yet."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(
                    viewModel.canExport
                        ? String(localized: "The meeting is paused. You can export the current record.")
                        : String(localized: "The meeting is in progress. Pause it to export the current record.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .meetingDetailPanelSurface(cornerRadius: 16)
    }

    private var rightSidebar: some View {
        MeetingDetailSummarySidebar(viewModel: viewModel)
    }

    private var translationLanguageDialog: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Choose Translation Language"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(String(localized: "Realtime translation in detail view translates remote-speaker segments only."))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(TranslationTargetLanguage.allCases) { language in
                        Button {
                            viewModel.translationDraftLanguageRaw = language.rawValue
                        } label: {
                            HStack(spacing: 10) {
                                Text(language.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 8)

                                if viewModel.translationDraftLanguageRaw == language.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.accentColor.opacity(0.95))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        viewModel.translationDraftLanguageRaw == language.rawValue
                                            ? Color.accentColor.opacity(0.14)
                                            : MeetingDetailUIStyle.mutedFillColor
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        viewModel.translationDraftLanguageRaw == language.rawValue
                                            ? Color.accentColor.opacity(0.28)
                                            : MeetingDetailUIStyle.borderColor,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)

            HStack(spacing: 10) {
                Button(String(localized: "Cancel")) {
                    viewModel.cancelTranslationLanguageSelection()
                }
                .buttonStyle(MeetingPillButtonStyle())

                Spacer(minLength: 8)

                Button(String(localized: "Start Translation")) {
                    viewModel.confirmTranslationLanguageSelection()
                }
                .buttonStyle(MeetingPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MeetingDetailUIStyle.windowFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(MeetingDetailUIStyle.borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
    }

    private var timerLabel: String {
        "\(MeetingTranscriptFormatter.timestampString(for: playbackController.currentTime)) / \(MeetingTranscriptFormatter.timestampString(for: playbackController.duration))"
    }

    private var displayedSegments: [MeetingTranscriptSegment] {
        let query = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.segments }
        return viewModel.segments.filter(segmentMatchesSearch)
    }

    private func displayedNewestSegmentID(in segments: [MeetingTranscriptSegment]) -> UUID? {
        let query = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return segments.last?.id
        }
        return segments.last(where: segmentMatchesSearch)?.id
    }

    private func segmentMatchesSearch(_ segment: MeetingTranscriptSegment) -> Bool {
        let query = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return segment.text.localizedCaseInsensitiveContains(query)
            || (segment.translatedText?.localizedCaseInsensitiveContains(query) ?? false)
            || segment.speaker.displayTitle.localizedCaseInsensitiveContains(query)
            || MeetingTranscriptFormatter.timestampString(for: segment.startSeconds).localizedCaseInsensitiveContains(query)
    }

    private func updateActiveSegment(for currentTime: TimeInterval) {
        let newActiveSegment = viewModel.segments.last(where: { $0.startSeconds <= currentTime }) ?? viewModel.segments.first
        activeSegmentID = newActiveSegment?.id
    }

}

private struct MeetingDetailSegmentRow: View {
    let segment: MeetingTranscriptSegment
    let isActive: Bool
    let showsTranslation: Bool
    let isSearchMatch: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(MeetingTranscriptFormatter.timestampString(for: segment.startSeconds))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(segment.speaker.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(segment.speaker == .me ? Color(red: 0.16, green: 0.47, blue: 0.88) : Color(red: 0.12, green: 0.58, blue: 0.32))

                Spacer(minLength: 8)
            }

            Text(segment.text)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.94))
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsTranslation,
               let translatedText = segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !translatedText.isEmpty {
                Text(translatedText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if showsTranslation, segment.isTranslationPending {
                Text(String(localized: "Translating…"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.75))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.12)
        }
        if isSearchMatch {
            return Color.orange.opacity(0.12)
        }
        return MeetingDetailUIStyle.mutedFillColor
    }

    private var borderColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.38)
        }
        if isSearchMatch {
            return Color.orange.opacity(0.28)
        }
        return MeetingDetailUIStyle.softBorderColor
    }
}
