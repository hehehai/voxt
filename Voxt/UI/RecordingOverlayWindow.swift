import AppKit
import SwiftUI
import Combine
import QuartzCore

enum OverlayDisplayMode: Equatable {
    case recording
    case processing
    case answer
}

enum OverlaySessionIconMode: Equatable {
    case transcription
    case translation
    case rewrite
}

/// Observable state that drives the overlay UI. Either transcriber populates this.
@MainActor
class OverlayState: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var statusMessage = ""
    @Published var isEnhancing = false
    @Published var isCompleting = false
    @Published var displayMode: OverlayDisplayMode = .recording
    @Published var sessionIconMode: OverlaySessionIconMode = .transcription
    @Published var answerTitle = ""
    @Published var answerContent = ""

    private var cancellables = Set<AnyCancellable>()

    /// Binds to a SpeechTranscriber's published properties.
    func bind(to transcriber: SpeechTranscriber) {
        cancellables.removeAll()
        transcriber.$isRecording.assign(to: &$isRecording)
        transcriber.$audioLevel.assign(to: &$audioLevel)
        transcriber.$transcribedText.assign(to: &$transcribedText)
        transcriber.$isEnhancing.assign(to: &$isEnhancing)
    }

    /// Binds to an MLXTranscriber's published properties.
    func bind(to transcriber: MLXTranscriber) {
        cancellables.removeAll()
        transcriber.$isRecording.assign(to: &$isRecording)
        transcriber.$audioLevel.assign(to: &$audioLevel)
        transcriber.$transcribedText.assign(to: &$transcribedText)
        transcriber.$isEnhancing.assign(to: &$isEnhancing)
    }

    /// Binds to a RemoteASRTranscriber's published properties.
    func bind(to transcriber: RemoteASRTranscriber) {
        cancellables.removeAll()
        transcriber.$isRecording.assign(to: &$isRecording)
        transcriber.$audioLevel.assign(to: &$audioLevel)
        transcriber.$transcribedText.assign(to: &$transcribedText)
        transcriber.$isEnhancing.assign(to: &$isEnhancing)
    }

    func reset() {
        isRecording = false
        audioLevel = 0
        transcribedText = ""
        statusMessage = ""
        isEnhancing = false
        isCompleting = false
        displayMode = .recording
        sessionIconMode = .transcription
        answerTitle = ""
        answerContent = ""
        cancellables.removeAll()
    }

    func presentRecording(iconMode: OverlaySessionIconMode? = nil) {
        displayMode = .recording
        if let iconMode {
            sessionIconMode = iconMode
        }
        answerTitle = ""
        answerContent = ""
    }

    func presentProcessing(iconMode: OverlaySessionIconMode? = nil) {
        guard displayMode != .answer else { return }
        displayMode = .processing
        if let iconMode {
            sessionIconMode = iconMode
        }
    }

    func presentAnswer(title: String, content: String) {
        answerTitle = title
        answerContent = content
        displayMode = .answer
        isRecording = false
        isEnhancing = false
        isCompleting = false
        statusMessage = ""
    }
}

/// A borderless, non-activating floating panel that sits at the bottom-center
/// of the main screen and hosts the WaveformView.
class RecordingOverlayWindow: NSPanel {

    private var hostingView: NSHostingView<OverlayContent>?
    private var visibilityToken: UInt64 = 0
    private var displayModeCancellable: AnyCancellable?
    private weak var observedState: OverlayState?
    private var currentPosition: OverlayPosition = .bottom
    var onRequestClose: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }

    func show(state: OverlayState, position: OverlayPosition) {
        visibilityToken &+= 1
        currentPosition = position

        let content = OverlayContent(
            state: state,
            onClose: { [weak self] in self?.onRequestClose?() }
        )

        if let hostingView {
            hostingView.rootView = content
        } else {
            let hosting = NSHostingView(rootView: content)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            contentView = hosting
            self.hostingView = hosting
        }

        observe(state: state)
        updateAppearance(for: state, animated: isVisible)

        if !isVisible {
            alphaValue = 1
            orderFront(nil)
        }
    }

    func hide(completion: (() -> Void)? = nil) {
        let token = visibilityToken
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            guard token == self.visibilityToken else { return }
            self.orderOut(nil)
            completion?()
        })
    }

    private func observe(state: OverlayState) {
        guard observedState !== state else { return }
        observedState = state
        displayModeCancellable = state.$displayMode
            .receive(on: RunLoop.main)
            .sink { [weak self, weak state] _ in
                guard let self, let state else { return }
                self.updateAppearance(for: state, animated: true)
            }
    }

    private func updateAppearance(for state: OverlayState, animated: Bool) {
        ignoresMouseEvents = state.displayMode != .answer
        let targetFrame = frame(for: panelSize(for: state.displayMode), position: currentPosition)

        guard !targetFrame.isEmpty else { return }
        if animated, isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(targetFrame, display: true)
            }
        } else {
            setFrame(targetFrame, display: true)
        }
    }

    private func panelSize(for mode: OverlayDisplayMode) -> CGSize {
        switch mode {
        case .recording, .processing:
            return CGSize(width: 360, height: 140)
        case .answer:
            return CGSize(width: 560, height: 340)
        }
    }

    private func frame(for size: CGSize, position: OverlayPosition) -> CGRect {
        let fixedEdgeDistance: CGFloat = 30
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        guard !visibleFrame.isEmpty else {
            return CGRect(origin: frame.origin, size: size)
        }

        let x = visibleFrame.midX - size.width / 2
        let y: CGFloat
        switch position {
        case .bottom:
            y = visibleFrame.minY + fixedEdgeDistance
        case .top:
            y = visibleFrame.maxY - size.height - fixedEdgeDistance
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

// MARK: - SwiftUI content hosted inside the panel

private struct OverlayContent: View {
    @ObservedObject var state: OverlayState
    let onClose: () -> Void

    var body: some View {
        WaveformView(
            displayMode: state.displayMode,
            sessionIconMode: state.sessionIconMode,
            audioLevel: state.audioLevel,
            isRecording: state.isRecording,
            transcribedText: state.transcribedText,
            statusMessage: state.statusMessage,
            isEnhancing: state.isEnhancing,
            isCompleting: state.isCompleting,
            answerTitle: state.answerTitle,
            answerContent: state.answerContent,
            onClose: onClose
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }
}
