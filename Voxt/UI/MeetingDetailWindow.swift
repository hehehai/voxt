import AppKit
import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MeetingDetailWindowManager {
    static let shared = MeetingDetailWindowManager()

    private var historyControllers: [UUID: MeetingDetailWindowController] = [:]
    private var liveController: MeetingDetailWindowController?

    func presentHistoryMeeting(
        entry: TranscriptionHistoryEntry,
        audioURL: URL?,
        translationHandler: @escaping @MainActor (String, TranslationTargetLanguage) async throws -> String
    ) {
        if let controller = historyControllers[entry.id] {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = MeetingDetailViewModel(
            title: String(localized: "Meeting Details"),
            subtitle: entry.createdAt.formatted(date: .abbreviated, time: .shortened),
            segments: entry.meetingSegments ?? [],
            audioURL: audioURL,
            translationHandler: translationHandler
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
        translationHandler: @escaping @MainActor (String, TranslationTargetLanguage) async throws -> String
    ) {
        if let controller = liveController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = MeetingDetailViewModel(
            liveState: state,
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
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = AppLocalization.localizedString("Meeting Details")
        window.center()
        window.setFrameAutosaveName("VoxtMeetingDetailWindow")

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

@MainActor
private final class MeetingDetailViewModel: ObservableObject {
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

    let mode: Mode
    let audioURL: URL?

    private let translationHandler: @MainActor (String, TranslationTargetLanguage) async throws -> String
    private var cancellables = Set<AnyCancellable>()
    private var translationTasks: [UUID: Task<Void, Never>] = [:]

    init(
        title: String,
        subtitle: String,
        segments: [MeetingTranscriptSegment],
        audioURL: URL?,
        translationHandler: @escaping @MainActor (String, TranslationTargetLanguage) async throws -> String
    ) {
        self.mode = .history
        self.title = title
        self.subtitle = subtitle
        self.segments = segments
        self.audioURL = audioURL
        self.isPaused = true
        self.translationHandler = translationHandler
        let savedLanguage = UserDefaults.standard.string(forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage)
        self.translationDraftLanguageRaw = savedLanguage?.isEmpty == false
            ? savedLanguage!
            : TranslationTargetLanguage.english.rawValue
        self.translationEnabled = Self.segmentsContainTranslations(segments)
    }

    init(
        liveState: MeetingOverlayState,
        translationHandler: @escaping @MainActor (String, TranslationTargetLanguage) async throws -> String
    ) {
        self.mode = .live
        self.title = String(localized: "Meeting Details")
        self.subtitle = liveState.isPaused
            ? String(localized: "Meeting Paused")
            : String(localized: "Meeting In Progress")
        self.segments = liveState.segments
        self.audioURL = nil
        self.isPaused = liveState.isPaused
        self.translationHandler = translationHandler
        let savedLanguage = UserDefaults.standard.string(forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage)
        self.translationDraftLanguageRaw = savedLanguage?.isEmpty == false
            ? savedLanguage!
            : TranslationTargetLanguage.english.rawValue
        self.translationEnabled = liveState.realtimeTranslateEnabled || Self.segmentsContainTranslations(liveState.segments)

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

    var canExport: Bool {
        switch mode {
        case .history:
            return !segments.isEmpty
        case .live:
            return isPaused && !segments.isEmpty
        }
    }

    func export() throws {
        try MeetingTranscriptExporter.export(
            segments: segments,
            defaultFilename: MeetingTranscriptExporter.defaultFilename(prefix: "Voxt-Meeting")
        )
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

    private func updateLiveSegments(_ incomingSegments: [MeetingTranscriptSegment]) {
        segments = mergeSegmentsPreservingTranslationState(incomingSegments)
        if translationEnabled {
            translateEligibleSegmentsIfNeeded(targetLanguage: resolvedStoredTranslationLanguage())
        }
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

            return MeetingTranscriptSegment(
                id: incoming.id,
                speaker: incoming.speaker,
                startSeconds: incoming.startSeconds,
                endSeconds: incoming.endSeconds,
                text: incoming.text,
                translatedText: resolvedTranslatedText,
                isTranslationPending: incoming.isTranslationPending || existing.isTranslationPending
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
        guard segment.speaker == .them else { return false }
        let translatedText = segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return translatedText.isEmpty && !segment.isTranslationPending
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

    private static func segmentsContainTranslations(_ segments: [MeetingTranscriptSegment]) -> Bool {
        segments.contains { segment in
            !(segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }
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
            VStack(spacing: 0) {
                header

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(viewModel.segments) { segment in
                                MeetingDetailSegmentRow(
                                    segment: segment,
                                    isActive: activeSegmentID == segment.id,
                                    showsTranslation: viewModel.translationEnabled
                                )
                                .id(segment.id)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                    }
                    .onAppear {
                        updateActiveSegment(for: playbackController.currentTime)
                    }
                    .onChange(of: playbackController.currentTime) { _, newValue in
                        guard viewModel.mode == .history else { return }
                        updateActiveSegment(for: newValue)
                        guard !isScrubbing, let activeSegmentID else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(activeSegmentID, anchor: .center)
                        }
                    }
                    .onChange(of: viewModel.segments) { _, newValue in
                        guard viewModel.mode == .live, let newest = newValue.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(newest, anchor: .bottom)
                        }
                    }
                }

                Divider()

                bottomBar
            }
            .frame(minWidth: 760, minHeight: 560)

            if viewModel.isTranslationLanguagePickerPresented {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                translationLanguageDialog
            }
        }
    }

    private var translationLanguageDialog: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Choose Translation Language"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(String(localized: "Realtime translation in detail view only translates Them segments."))
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
                                            : Color.primary.opacity(0.04)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        viewModel.translationDraftLanguageRaw == language.rawValue
                                            ? Color.accentColor.opacity(0.28)
                                            : Color.primary.opacity(0.08),
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
                Button(String(localized: "取消")) {
                    viewModel.cancelTranslationLanguageSelection()
                }
                .controlSize(.small)

                Button(String(localized: "开始翻译")) {
                    viewModel.confirmTranslationLanguageSelection()
                }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.title)
                    .font(.headline)
                Text(viewModel.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Text(String(localized: "Realtime Translation"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { viewModel.translationEnabled },
                        set: { viewModel.setTranslationEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.82)
            }

            Button(String(localized: "导出")) {
                try? viewModel.export()
            }
            .controlSize(.small)
            .disabled(!viewModel.canExport)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.mode == .history {
                if playbackController.isAvailable {
                    HStack(spacing: 10) {
                        Button {
                            playbackController.togglePlayPause()
                        } label: {
                            Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Color.accentColor.opacity(0.12))
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
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var timerLabel: String {
        "\(MeetingTranscriptFormatter.timestampString(for: playbackController.currentTime)) / \(MeetingTranscriptFormatter.timestampString(for: playbackController.duration))"
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(MeetingTranscriptFormatter.timestampString(for: segment.startSeconds))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(segment.speaker.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(segment.speaker == .me ? .blue : .green)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(segment.text)
                    .font(.body)
                    .foregroundStyle(.primary)
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
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isActive ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
