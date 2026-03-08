import AppKit
import SwiftUI
import Combine

/// Observable state that drives the overlay UI. Either transcriber populates this.
@MainActor
class OverlayState: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var statusMessage = ""
    @Published var isEnhancing = false
    @Published var isCompleting = false

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
        cancellables.removeAll()
    }
}

/// A borderless, non-activating floating panel that sits at the bottom-center
/// of the main screen and hosts the WaveformView.
class RecordingOverlayWindow: NSPanel {

    private var hostingView: NSHostingView<OverlayContent>?

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

    func show(state: OverlayState, position: OverlayPosition) {
        let content = OverlayContent(state: state)
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        contentView = hosting
        hostingView = hosting

        // Position at top-center or bottom-center based on settings.
        let size = CGSize(width: 360, height: 140)
        let fixedEdgeDistance: CGFloat = 30
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - size.width / 2
            let y: CGFloat
            switch position {
            case .bottom:
                y = screen.visibleFrame.minY + fixedEdgeDistance
            case .top:
                y = screen.visibleFrame.maxY - size.height - fixedEdgeDistance
            }
            setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: false)
        }

        alphaValue = 1
        orderFront(nil)
    }

    func hide(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }
}

// MARK: - SwiftUI content hosted inside the panel

private struct OverlayContent: View {
    @ObservedObject var state: OverlayState

    var body: some View {
        WaveformView(
            audioLevel: state.audioLevel,
            isRecording: state.isRecording,
            transcribedText: state.transcribedText,
            statusMessage: state.statusMessage,
            isEnhancing: state.isEnhancing,
            isCompleting: state.isCompleting
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }
}
