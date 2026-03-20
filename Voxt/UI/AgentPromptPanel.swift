import SwiftUI
import AppKit
import Combine

@MainActor
final class AgentPromptPanelState: ObservableObject {
    @Published var isPresented = false
    @Published var title = AppLocalization.localizedString("AI needs your input")
    @Published var questions: [String] = []
    @Published var contextHint = ""
    @Published var phase: AgentPromptState = .idle

    func present(request: AgentPromptRequest) {
        title = AppLocalization.localizedString("AI needs your input")
        questions = request.questions
        contextHint = request.contextHint ?? ""
        phase = .prompting
        isPresented = true
    }

    func reset() {
        isPresented = false
        title = AppLocalization.localizedString("AI needs your input")
        questions = []
        contextHint = ""
        phase = .idle
    }
}

final class AgentPromptPanel: NSPanel, NSWindowDelegate {
    private var hostingView: NSHostingView<AgentPromptPanelContent>?

    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onCancel: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show(state: AgentPromptPanelState, overlayState: OverlayState) {
        let content = AgentPromptPanelContent(
            state: state,
            overlayState: overlayState,
            onStartRecording: { [weak self] in self?.onStartRecording?() },
            onStopRecording: { [weak self] in self?.onStopRecording?() },
            onCancel: { [weak self] in self?.onCancel?() }
        )

        if let hostingView {
            hostingView.rootView = content
        } else {
            let hostingView = NSHostingView(rootView: content)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            contentView = hostingView
            self.hostingView = hostingView
        }

        centerOnMainScreen()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCancel?()
        return false
    }

    private func centerOnMainScreen() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - frame.width / 2
        let y = visibleFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct AgentPromptPanelContent: View {
    @ObservedObject var state: AgentPromptPanelState
    @ObservedObject var overlayState: OverlayState
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onCancel: () -> Void

    private var isRecordingPhase: Bool {
        state.phase == .recording
    }

    private var isPromptingPhase: Bool {
        state.phase == .prompting
    }

    private var isTranscribingPhase: Bool {
        state.phase == .transcribing
    }

    private var actionTitle: String {
        isPromptingPhase
            ? AppLocalization.localizedString("Start Recording")
            : AppLocalization.localizedString("Stop")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(state.title)
                .font(.title3.weight(.semibold))

            if !state.contextHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(state.contextHint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(state.questions.enumerated()), id: \.offset) { index, question in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(question)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(AppLocalization.localizedString("Voice Capture"))
                    .font(.headline)

                WaveformView(
                    displayMode: isTranscribingPhase ? .processing : .recording,
                    sessionIconMode: .transcription,
                    audioLevel: overlayState.audioLevel,
                    isRecording: overlayState.isRecording,
                    shouldAnimate: overlayState.isRecording || isTranscribingPhase,
                    transcribedText: overlayState.transcribedText,
                    statusMessage: overlayState.statusMessage,
                    isEnhancing: false,
                    isRequesting: isTranscribingPhase
                )
                .frame(width: 400, height: 110, alignment: .topLeading)

                Text(helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(AppLocalization.localizedString("Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(actionTitle, action: primaryAction)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isTranscribingPhase)
            }
        }
        .padding(20)
        .frame(width: 540, height: 420, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var helperText: String {
        if isPromptingPhase {
            return AppLocalization.localizedString("Press Enter or Space to begin recording, or Esc to cancel.")
        }
        if isRecordingPhase {
            return AppLocalization.localizedString("Press Enter to stop and submit your answer, or Esc to cancel.")
        }
        if isTranscribingPhase {
            return AppLocalization.localizedString("Transcribing your answer…")
        }
        return AppLocalization.localizedString("Waiting for input.")
    }

    private func primaryAction() {
        if isPromptingPhase {
            onStartRecording()
        } else if isRecordingPhase {
            onStopRecording()
        }
    }
}
