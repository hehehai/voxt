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

    func presentHistoryMeeting(entry: TranscriptionHistoryEntry, audioURL: URL?) {
        if let controller = historyControllers[entry.id] {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = MeetingDetailViewModel(
            title: String(localized: "会议详情"),
            subtitle: entry.createdAt.formatted(date: .abbreviated, time: .shortened),
            segments: entry.meetingSegments ?? [],
            audioURL: audioURL,
            canExportProvider: { !(entry.meetingSegments ?? []).isEmpty },
            exportHandler: {
                try MeetingTranscriptExporter.export(
                    segments: entry.meetingSegments ?? [],
                    defaultFilename: MeetingTranscriptExporter.defaultFilename(prefix: "Voxt-Meeting")
                )
            }
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
        onExport: @escaping () -> Void
    ) {
        if let controller = liveController {
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewModel = MeetingDetailViewModel(
            liveState: state,
            exportHandler: onExport
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

    let mode: Mode
    let audioURL: URL?

    private let canExportProvider: () -> Bool
    private let exportHandler: () throws -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        title: String,
        subtitle: String,
        segments: [MeetingTranscriptSegment],
        audioURL: URL?,
        canExportProvider: @escaping () -> Bool,
        exportHandler: @escaping () throws -> Void
    ) {
        self.mode = .history
        self.title = title
        self.subtitle = subtitle
        self.segments = segments
        self.audioURL = audioURL
        self.canExportProvider = canExportProvider
        self.exportHandler = exportHandler
        self.isPaused = true
    }

    init(
        liveState: MeetingOverlayState,
        exportHandler: @escaping () -> Void
    ) {
        self.mode = .live
        self.title = String(localized: "会议详情")
        self.subtitle = liveState.isPaused
            ? String(localized: "会议已暂停")
            : String(localized: "会议进行中")
        self.segments = liveState.segments
        self.audioURL = nil
        self.isPaused = liveState.isPaused
        self.canExportProvider = { liveState.isPaused && !liveState.segments.isEmpty }
        self.exportHandler = exportHandler

        liveState.$segments
            .receive(on: RunLoop.main)
            .sink { [weak self] segments in
                self?.segments = segments
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(liveState.$isPaused, liveState.$isRecording)
            .receive(on: RunLoop.main)
            .sink { [weak self] isPaused, isRecording in
                self?.isPaused = isPaused
                self?.subtitle = isPaused
                    ? String(localized: "会议已暂停")
                    : (isRecording ? String(localized: "会议进行中") : String(localized: "会议已结束"))
            }
            .store(in: &cancellables)
    }

    var canExport: Bool {
        canExportProvider()
    }

    func export() throws {
        try exportHandler()
    }
}

@MainActor
private enum MeetingTranscriptExporter {
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
        VStack(spacing: 0) {
            header

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.segments) { segment in
                            MeetingDetailSegmentRow(
                                segment: segment,
                                isActive: activeSegmentID == segment.id
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
                    Text(String(localized: "这条会议记录还没有可回放音频。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(
                    viewModel.canExport
                        ? String(localized: "会议已暂停，可以导出当前记录。")
                        : String(localized: "会议进行中，暂停后可导出当前记录。")
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

                if let translatedText = segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !translatedText.isEmpty {
                    Text(translatedText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if segment.isTranslationPending {
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
