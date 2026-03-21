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
    @Published var isRequesting = false
    @Published var isCompleting = false
    @Published var displayMode: OverlayDisplayMode = .recording
    @Published var sessionIconMode: OverlaySessionIconMode = .transcription
    @Published var answerTitle = ""
    @Published var answerContent = ""
    @Published var canInjectAnswer = false
    @Published var isPresented = false

    private var cancellables = Set<AnyCancellable>()

    /// Binds to a SpeechTranscriber's published properties.
    func bind(to transcriber: SpeechTranscriber) {
        bind(
            isRecording: transcriber.$isRecording.eraseToAnyPublisher(),
            audioLevel: transcriber.$audioLevel.eraseToAnyPublisher(),
            transcribedText: transcriber.$transcribedText.eraseToAnyPublisher(),
            isEnhancing: transcriber.$isEnhancing.eraseToAnyPublisher(),
            isRequesting: Just(false).eraseToAnyPublisher()
        )
    }

    /// Binds to an MLXTranscriber's published properties.
    func bind(to transcriber: MLXTranscriber) {
        bind(
            isRecording: transcriber.$isRecording.eraseToAnyPublisher(),
            audioLevel: transcriber.$audioLevel.eraseToAnyPublisher(),
            transcribedText: transcriber.$transcribedText.eraseToAnyPublisher(),
            isEnhancing: transcriber.$isEnhancing.eraseToAnyPublisher(),
            isRequesting: Just(false).eraseToAnyPublisher()
        )
    }

    /// Binds to a RemoteASRTranscriber's published properties.
    func bind(to transcriber: RemoteASRTranscriber) {
        bind(
            isRecording: transcriber.$isRecording.eraseToAnyPublisher(),
            audioLevel: transcriber.$audioLevel.eraseToAnyPublisher(),
            transcribedText: transcriber.$transcribedText.eraseToAnyPublisher(),
            isEnhancing: transcriber.$isEnhancing.eraseToAnyPublisher(),
            isRequesting: transcriber.$isRequesting.eraseToAnyPublisher()
        )
    }

    /// Binds to a WhisperKitTranscriber's published properties.
    func bind(to transcriber: WhisperKitTranscriber) {
        bind(
            isRecording: transcriber.$isRecording.eraseToAnyPublisher(),
            audioLevel: transcriber.$audioLevel.eraseToAnyPublisher(),
            transcribedText: transcriber.$transcribedText.eraseToAnyPublisher(),
            isEnhancing: transcriber.$isEnhancing.eraseToAnyPublisher(),
            isRequesting: Just(false).eraseToAnyPublisher()
        )
    }

    func reset() {
        isRecording = false
        audioLevel = 0
        transcribedText = ""
        statusMessage = ""
        isEnhancing = false
        isRequesting = false
        isCompleting = false
        displayMode = .recording
        sessionIconMode = .transcription
        answerTitle = ""
        answerContent = ""
        canInjectAnswer = false
        isPresented = false
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

    func presentAnswer(title: String, content: String, canInject: Bool) {
        answerTitle = title
        answerContent = content
        canInjectAnswer = canInject
        displayMode = .answer
        isRecording = false
        audioLevel = 0
        isEnhancing = false
        isRequesting = false
        isCompleting = false
        statusMessage = ""
    }

    var shouldAnimateVisuals: Bool {
        isPresented && (isRecording || displayMode == .processing || isEnhancing || isRequesting)
    }

    private func bind(
        isRecording recordingPublisher: AnyPublisher<Bool, Never>,
        audioLevel audioLevelPublisher: AnyPublisher<Float, Never>,
        transcribedText transcribedTextPublisher: AnyPublisher<String, Never>,
        isEnhancing isEnhancingPublisher: AnyPublisher<Bool, Never>,
        isRequesting isRequestingPublisher: AnyPublisher<Bool, Never>
    ) {
        cancellables.removeAll()
        audioLevel = 0

        recordingPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                guard let self else { return }
                self.isRecording = isRecording
                if !isRecording {
                    self.audioLevel = 0
                }
            }
            .store(in: &cancellables)

        audioLevelPublisher
            .combineLatest(recordingPublisher)
            .map { level, isRecording in
                guard isRecording else { return Float.zero }
                return Self.quantizedAudioLevel(level)
            }
            .removeDuplicates()
            .throttle(for: .milliseconds(50), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] level in
                self?.audioLevel = level
            }
            .store(in: &cancellables)

        transcribedTextPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                self?.transcribedText = text
            }
            .store(in: &cancellables)

        isEnhancingPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnhancing in
                self?.isEnhancing = isEnhancing
            }
            .store(in: &cancellables)

        isRequestingPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] isRequesting in
                self?.isRequesting = isRequesting
            }
            .store(in: &cancellables)
    }

    private static func quantizedAudioLevel(_ rawLevel: Float) -> Float {
        let clamped = max(0, min(rawLevel, 1))
        let steps: Float = 20
        return (clamped * steps).rounded() / steps
    }
}

/// A borderless, non-activating floating panel that sits at the bottom-center
/// of the main screen and hosts the WaveformView.
class RecordingOverlayWindow: NSPanel {

    private var hostingView: NSHostingView<OverlayContent>?
    private var visibilityToken: UInt64 = 0
    private var displayModeCancellable: AnyCancellable?
    private var overlayAppearanceCancellable: AnyCancellable?
    private weak var observedState: OverlayState?
    private var currentPosition: OverlayPosition = .bottom
    var onRequestClose: (() -> Void)?
    var onRequestInject: (() -> Void)?

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

        overlayAppearanceCancellable = NotificationCenter.default.publisher(for: .voxtOverlayAppearanceDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let state = self.observedState else { return }
                let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.overlayPosition) ?? OverlayPosition.bottom.rawValue
                self.currentPosition = OverlayPosition(rawValue: raw) ?? .bottom
                self.updateAppearance(for: state, animated: self.isVisible)
            }
    }

    override var canBecomeKey: Bool { true }

    func show(state: OverlayState, position: OverlayPosition) {
        VoxtLog.info(
            "Overlay show requested. wasVisible=\(isVisible), displayMode=\(state.displayMode), position=\(position.rawValue)",
            verbose: true
        )
        visibilityToken &+= 1
        currentPosition = position
        state.isPresented = true

        let content = OverlayContent(
            state: state,
            onInject: { [weak self] in self?.onRequestInject?() },
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
        hostingView?.needsLayout = true
        contentView?.needsLayout = true
        hostingView?.displayIfNeeded()
        contentView?.displayIfNeeded()
        displayIfNeeded()

        if !isVisible {
            alphaValue = 1
            orderFrontRegardless()
        }
    }

    func hide(completion: (() -> Void)? = nil) {
        VoxtLog.info("Overlay hide requested. isVisible=\(isVisible)", verbose: true)
        observedState?.isPresented = false
        observedState?.audioLevel = 0

        guard isVisible else {
            orderOut(nil)
            completion?()
            return
        }

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
        let fixedEdgeDistance = overlayScreenEdgeInset
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

    private var overlayScreenEdgeInset: CGFloat {
        let storedValue = UserDefaults.standard.object(forKey: AppPreferenceKey.overlayScreenEdgeInset) as? Int ?? 30
        return CGFloat(min(max(storedValue, 0), 120))
    }
}

// MARK: - SwiftUI content hosted inside the panel

private struct OverlayContent: View {
    @ObservedObject var state: OverlayState
    let onInject: () -> Void
    let onClose: () -> Void

    var body: some View {
        WaveformView(
            displayMode: state.displayMode,
            sessionIconMode: state.sessionIconMode,
            audioLevel: state.audioLevel,
            isRecording: state.isRecording,
            shouldAnimate: state.shouldAnimateVisuals,
            transcribedText: state.transcribedText,
            statusMessage: state.statusMessage,
            isEnhancing: state.isEnhancing,
            isRequesting: state.isRequesting,
            isCompleting: state.isCompleting,
            answerTitle: state.answerTitle,
            answerContent: state.answerContent,
            canInjectAnswer: state.canInjectAnswer,
            onInject: onInject,
            onClose: onClose
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }
}
