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

enum AnswerInteractionMode: Equatable {
    case singleResult
    case conversation
}

enum AnswerSpaceShortcutAction: Equatable {
    case continueAndRecord
    case toggleConversationRecording
}

/// Observable state that drives the overlay UI. Either transcriber populates this.
@MainActor
class OverlayState: ObservableObject {
    @Published var isRecording = false
    @Published var isModelInitializing = false
    @Published var initializingEngine: TranscriptionEngine?
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var statusMessage = ""
    @Published var isEnhancing = false
    @Published var isRequesting = false
    @Published var isFinalizingTranscription = false
    @Published var isCompleting = false
    @Published var displayMode: OverlayDisplayMode = .recording
    @Published var sessionIconMode: OverlaySessionIconMode = .transcription
    @Published var answerTitle = ""
    @Published var answerContent = ""
    @Published var answerInteractionMode: AnswerInteractionMode = .singleResult
    @Published var rewriteConversationTurns: [RewriteConversationTurn] = []
    @Published var latestRewriteResult: RewriteAnswerPayload?
    @Published var latestHistoryEntryID: UUID?
    @Published var rewriteConversationRemoteResponseID: String?
    @Published var pendingConversationUserPrompt: String?
    @Published var isStreamingAnswer = false
    @Published var canInjectAnswer = false
    @Published var isPresented = false
    @Published var sessionTranslationTargetLanguage: TranslationTargetLanguage?
    @Published var sessionTranslationDraftLanguage: TranslationTargetLanguage?
    @Published var isSessionTranslationTargetPickerPresented = false
    @Published var isSessionTranslationLanguageHovering = false
    @Published var allowsSessionTranslationLanguageSwitching = false
    var answerTranslationSourceText = ""

    private var cancellables = Set<AnyCancellable>()
    private var latestSourceTranscribedText = ""
    private var transcribedTextTransformer: ((String) -> String)?

    deinit {
        // Keep an explicit deinit here. On macOS 26 test hosts, the synthesized
        // teardown path intermittently trips a malloc crash while destroying this
        // ObservableObject's @Published storage. An explicit deinit stabilizes
        // the generated destruction path without changing runtime behavior.
    }

    /// Binds to a SpeechTranscriber's published properties.
    func bind(to transcriber: SpeechTranscriber) {
        bind(
            isRecording: transcriber.$isRecording.eraseToAnyPublisher(),
            isModelInitializing: Just(false).eraseToAnyPublisher(),
            audioLevel: transcriber.$audioLevel.eraseToAnyPublisher(),
            transcribedText: transcriber.$transcribedText.eraseToAnyPublisher(),
            isEnhancing: transcriber.$isEnhancing.eraseToAnyPublisher(),
            isRequesting: Just(false).eraseToAnyPublisher(),
            isFinalizingTranscription: transcriber.$isFinalizingTranscription.eraseToAnyPublisher(),
            initializingEngine: .none
        )
    }

    /// Binds to an MLXTranscriber's published properties.
    func bind(to transcriber: MLXTranscriber) {
        bind(
            isRecording: transcriber.$isRecording.eraseToAnyPublisher(),
            isModelInitializing: transcriber.$isModelInitializing.eraseToAnyPublisher(),
            audioLevel: transcriber.$audioLevel.eraseToAnyPublisher(),
            transcribedText: transcriber.$transcribedText.eraseToAnyPublisher(),
            isEnhancing: transcriber.$isEnhancing.eraseToAnyPublisher(),
            isRequesting: Just(false).eraseToAnyPublisher(),
            isFinalizingTranscription: transcriber.$isFinalizingTranscription.eraseToAnyPublisher(),
            initializingEngine: .mlxAudio
        )
    }

    /// Binds to a RemoteASRTranscriber's published properties.
    func bind(to transcriber: RemoteASRTranscriber) {
        bind(
            isRecording: transcriber.$isRecording.eraseToAnyPublisher(),
            isModelInitializing: Just(false).eraseToAnyPublisher(),
            audioLevel: transcriber.$audioLevel.eraseToAnyPublisher(),
            transcribedText: transcriber.$transcribedText.eraseToAnyPublisher(),
            isEnhancing: transcriber.$isEnhancing.eraseToAnyPublisher(),
            isRequesting: transcriber.$isRequesting.eraseToAnyPublisher(),
            isFinalizingTranscription: transcriber.$isFinalizingTranscription.eraseToAnyPublisher(),
            initializingEngine: .none
        )
    }

    /// Binds to a WhisperKitTranscriber's published properties.
    func bind(to transcriber: WhisperKitTranscriber) {
        bind(
            isRecording: transcriber.$isRecording.eraseToAnyPublisher(),
            isModelInitializing: transcriber.$isModelInitializing.eraseToAnyPublisher(),
            audioLevel: transcriber.$audioLevel.eraseToAnyPublisher(),
            transcribedText: transcriber.$transcribedText.eraseToAnyPublisher(),
            isEnhancing: transcriber.$isEnhancing.eraseToAnyPublisher(),
            isRequesting: Just(false).eraseToAnyPublisher(),
            isFinalizingTranscription: transcriber.$isFinalizingTranscription.eraseToAnyPublisher(),
            initializingEngine: .whisperKit
        )
    }

    func reset() {
        isRecording = false
        isModelInitializing = false
        initializingEngine = nil
        audioLevel = 0
        transcribedText = ""
        statusMessage = ""
        isEnhancing = false
        isRequesting = false
        isFinalizingTranscription = false
        isCompleting = false
        displayMode = .recording
        sessionIconMode = .transcription
        answerTitle = ""
        answerContent = ""
        answerInteractionMode = .singleResult
        rewriteConversationTurns = []
        latestRewriteResult = nil
        latestHistoryEntryID = nil
        rewriteConversationRemoteResponseID = nil
        pendingConversationUserPrompt = nil
        isStreamingAnswer = false
        canInjectAnswer = false
        isPresented = false
        sessionTranslationTargetLanguage = nil
        sessionTranslationDraftLanguage = nil
        isSessionTranslationTargetPickerPresented = false
        isSessionTranslationLanguageHovering = false
        allowsSessionTranslationLanguageSwitching = false
        answerTranslationSourceText = ""
        latestSourceTranscribedText = ""
        transcribedTextTransformer = nil
        cancellables.removeAll()
    }

    func setTranscribedTextTransformer(_ transformer: ((String) -> String)?) {
        transcribedTextTransformer = transformer
        refreshDisplayedTranscribedText()
    }

    func refreshDisplayedTranscribedText() {
        transcribedText = transformedTranscribedText(from: latestSourceTranscribedText)
    }

    func clearDisplayedTranscribedText() {
        transcribedText = ""
    }

    func presentRecording(iconMode: OverlaySessionIconMode? = nil) {
        displayMode = .recording
        if let iconMode {
            sessionIconMode = iconMode
        }
        answerTitle = ""
        answerContent = ""
        isFinalizingTranscription = false
        isStreamingAnswer = false
    }

    func presentProcessing(iconMode: OverlaySessionIconMode? = nil) {
        guard displayMode != .answer else { return }
        displayMode = .processing
        dismissSessionTranslationTargetPicker()
        if let iconMode {
            sessionIconMode = iconMode
        }
    }

    func presentAnswer(title: String, content: String, canInject: Bool) {
        let payload = RewriteAnswerPayloadParser.normalize(RewriteAnswerPayload(
            title: title,
            content: content
        ))
        answerTitle = payload.title
        answerContent = payload.content
        latestRewriteResult = payload
        isStreamingAnswer = false
        canInjectAnswer = canInject
        displayMode = .answer
        isRecording = false
        audioLevel = 0
        isEnhancing = false
        isRequesting = false
        isFinalizingTranscription = false
        isCompleting = false
        statusMessage = ""
        dismissSessionTranslationTargetPicker()

        if isRewriteConversationActive {
            appendConversationResult(payload)
        } else {
            answerInteractionMode = .singleResult
            rewriteConversationTurns = []
            rewriteConversationRemoteResponseID = nil
            pendingConversationUserPrompt = nil
        }
    }

    func presentStreamingAnswer(title: String, content: String, canInject: Bool) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "AI Answer")
            : title
        let previewPayload = RewriteAnswerPayload(
            title: normalizedTitle,
            content: content
        )

        answerTitle = previewPayload.title
        answerContent = previewPayload.content
        isStreamingAnswer = true
        canInjectAnswer = canInject
        displayMode = .answer
        isRecording = false
        audioLevel = 0
        isFinalizingTranscription = false
        isCompleting = false
        statusMessage = ""
        dismissSessionTranslationTargetPicker()

        if !isRewriteConversationActive {
            answerInteractionMode = .singleResult
            rewriteConversationTurns = []
            rewriteConversationRemoteResponseID = nil
            pendingConversationUserPrompt = nil
        }
    }

    func presentConversationAnswer(content: String, canInject: Bool) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        let payload = RewriteAnswerPayload(title: "", content: trimmedContent)
        answerTitle = ""
        answerContent = payload.content
        latestRewriteResult = payload
        isStreamingAnswer = false
        canInjectAnswer = canInject
        displayMode = .answer
        isRecording = false
        audioLevel = 0
        isEnhancing = false
        isRequesting = false
        isFinalizingTranscription = false
        isCompleting = false
        statusMessage = ""
        dismissSessionTranslationTargetPicker()

        if isRewriteConversationActive {
            appendConversationResult(payload)
        } else {
            answerInteractionMode = .conversation
            rewriteConversationTurns = [RewriteConversationTurn.seed(from: payload)]
            rewriteConversationRemoteResponseID = nil
            pendingConversationUserPrompt = nil
        }
    }

    func presentStreamingConversationAnswer(content: String, canInject: Bool) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        answerTitle = ""
        answerContent = trimmedContent
        isStreamingAnswer = true
        canInjectAnswer = canInject
        displayMode = .answer
        isRecording = false
        audioLevel = 0
        isFinalizingTranscription = false
        isCompleting = false
        statusMessage = ""
        dismissSessionTranslationTargetPicker()
    }

    var shouldAnimateVisuals: Bool {
        isPresented && (
            isRecording ||
                isModelInitializing ||
                displayMode == .processing ||
                isEnhancing ||
                isRequesting ||
                isFinalizingTranscription
        )
    }

    var currentAnswerPayload: RewriteAnswerPayload? {
        let draftTitle = answerTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftContent = answerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draftTitle.isEmpty || !draftContent.isEmpty {
            return RewriteAnswerPayload(title: answerTitle, content: answerContent)
        }

        if let latestRewriteResult {
            return latestRewriteResult
        }

        let content = answerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        return RewriteAnswerPayload(title: answerTitle, content: answerContent)
    }

    var latestCompletedAnswerPayload: RewriteAnswerPayload? {
        if let latestRewriteResult {
            return latestRewriteResult
        }

        guard displayMode == .answer, !isStreamingAnswer else { return nil }
        let content = answerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        return RewriteAnswerPayload(title: answerTitle, content: answerContent)
    }

    var canCopyLatestAnswer: Bool {
        latestCompletedAnswerPayload != nil
    }

    var canShowLatestHistoryDetail: Bool {
        guard displayMode == .answer, !isStreamingAnswer else { return false }
        return latestHistoryEntryID != nil
    }

    var canContinueRewriteAnswer: Bool {
        guard displayMode == .answer,
              sessionIconMode == .rewrite,
              answerInteractionMode == .singleResult,
              latestCompletedAnswerPayload != nil
        else {
            return false
        }
        return true
    }

    var showsRewriteContinueButton: Bool {
        guard displayMode == .answer, sessionIconMode == .rewrite else { return false }
        switch answerInteractionMode {
        case .singleResult:
            return latestCompletedAnswerPayload != nil
        case .conversation:
            return true
        }
    }

    var isRewriteConversationActive: Bool {
        displayMode == .answer &&
            sessionIconMode == .rewrite &&
            answerInteractionMode == .conversation
    }

    var rewriteConversationPromptHistory: [RewriteConversationPromptTurn] {
        rewriteConversationTurns.map(\.promptTurn)
    }

    var answerSpaceShortcutAction: AnswerSpaceShortcutAction? {
        guard displayMode == .answer, sessionIconMode == .rewrite else { return nil }
        switch answerInteractionMode {
        case .singleResult:
            return latestCompletedAnswerPayload == nil ? nil : .continueAndRecord
        case .conversation:
            return .toggleConversationRecording
        }
    }

    func beginRewriteConversationIfNeeded() {
        guard canContinueRewriteAnswer, let payload = latestCompletedAnswerPayload else { return }
        answerInteractionMode = .conversation
        rewriteConversationTurns = [RewriteConversationTurn.seed(from: payload)]
        latestRewriteResult = payload
        rewriteConversationRemoteResponseID = nil
        pendingConversationUserPrompt = nil
    }

    func stageConversationUserPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingConversationUserPrompt = trimmed.isEmpty ? nil : trimmed
    }

    func clearPendingConversationUserPrompt() {
        pendingConversationUserPrompt = nil
    }

    func configureSessionTranslationTargetLanguage(
        _ language: TranslationTargetLanguage?,
        allowsSwitching: Bool
    ) {
        sessionTranslationTargetLanguage = language
        sessionTranslationDraftLanguage = language
        allowsSessionTranslationLanguageSwitching = allowsSwitching
        if !allowsSwitching {
            dismissSessionTranslationTargetPicker()
        }
    }

    func presentSessionTranslationTargetPicker() {
        guard allowsSessionTranslationLanguageSwitching else { return }
        sessionTranslationDraftLanguage = sessionTranslationTargetLanguage
        isSessionTranslationTargetPickerPresented = true
    }

    func dismissSessionTranslationTargetPicker() {
        sessionTranslationDraftLanguage = sessionTranslationTargetLanguage
        isSessionTranslationTargetPickerPresented = false
        isSessionTranslationLanguageHovering = false
    }

    func setSessionTranslationLanguageHovering(_ isHovering: Bool) {
        isSessionTranslationLanguageHovering = isHovering
    }

    func setAnswerTranslationSourceText(_ text: String) {
        answerTranslationSourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func replaceCurrentAnswer(title: String, content: String) {
        let payload = RewriteAnswerPayloadParser.normalize(
            RewriteAnswerPayload(title: title, content: content)
        )
        answerTitle = payload.title
        answerContent = payload.content
        latestRewriteResult = payload
        latestHistoryEntryID = nil
        isStreamingAnswer = false
        isEnhancing = false
        isRequesting = false
        isFinalizingTranscription = false
    }

    private func appendConversationResult(_ payload: RewriteAnswerPayload) {
        latestRewriteResult = payload
        let userPrompt = pendingConversationUserPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pendingConversationUserPrompt = nil

        if rewriteConversationTurns.isEmpty {
            rewriteConversationTurns = [RewriteConversationTurn.seed(from: payload)]
            return
        }

        rewriteConversationTurns.append(
            RewriteConversationTurn(
                userPromptText: userPrompt,
                resultTitle: payload.title,
                resultContent: payload.content
            )
        )
    }

    private func bind(
        isRecording recordingPublisher: AnyPublisher<Bool, Never>,
        isModelInitializing modelInitializingPublisher: AnyPublisher<Bool, Never>,
        audioLevel audioLevelPublisher: AnyPublisher<Float, Never>,
        transcribedText transcribedTextPublisher: AnyPublisher<String, Never>,
        isEnhancing isEnhancingPublisher: AnyPublisher<Bool, Never>,
        isRequesting isRequestingPublisher: AnyPublisher<Bool, Never>,
        isFinalizingTranscription isFinalizingPublisher: AnyPublisher<Bool, Never>,
        initializingEngine: TranscriptionEngine?
    ) {
        cancellables.removeAll()
        audioLevel = 0
        isFinalizingTranscription = false
        self.initializingEngine = initializingEngine

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

        modelInitializingPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] isInitializing in
                guard let self else { return }
                self.isModelInitializing = isInitializing
                self.initializingEngine = isInitializing ? initializingEngine : nil
                if isInitializing {
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
            .removeDuplicates()
            .throttle(for: .milliseconds(70), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] text in
                guard let self else { return }
                self.latestSourceTranscribedText = text
                self.transcribedText = self.transformedTranscribedText(from: text)
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

        isFinalizingPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] isFinalizing in
                self?.isFinalizingTranscription = isFinalizing
            }
            .store(in: &cancellables)
    }

    private static func quantizedAudioLevel(_ rawLevel: Float) -> Float {
        let clamped = max(0, min(rawLevel, 1))
        let steps: Float = 20
        return (clamped * steps).rounded() / steps
    }

    private func transformedTranscribedText(from sourceText: String) -> String {
        transcribedTextTransformer?(sourceText) ?? sourceText
    }
}

/// A borderless, non-activating floating panel that sits at the bottom-center
/// of the main screen and hosts the WaveformView.
class RecordingOverlayWindow: NSPanel {

    private var hostingView: NSHostingView<OverlayContent>?
    private var visibilityToken: UInt64 = 0
    private var appearanceStateCancellable: AnyCancellable?
    private var pickerStateCancellable: AnyCancellable?
    private var overlayAppearanceCancellable: AnyCancellable?
    private weak var observedState: OverlayState?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var currentPosition: OverlayPosition = .bottom
    var onRequestClose: (() -> Void)?
    var onRequestInject: (() -> Void)?
    var onRequestContinue: (() -> Void)?
    var onRequestConversationRecordToggle: (() -> Void)?
    var onRequestDetail: (() -> Void)?
    var onRequestSessionTranslationTargetPickerToggle: (() -> Void)?
    var onRequestSessionTranslationTargetLanguageSelect: ((TranslationTargetLanguage) -> Void)?
    var onRequestSessionTranslationTargetPickerDismiss: (() -> Void)?

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
            onContinue: { [weak self] in self?.onRequestContinue?() },
            onToggleConversationRecording: { [weak self] in self?.onRequestConversationRecordToggle?() },
            onShowDetail: { [weak self] in self?.onRequestDetail?() },
            onClose: { [weak self] in self?.onRequestClose?() },
            onToggleSessionTranslationTargetPicker: { [weak self] in
                self?.onRequestSessionTranslationTargetPickerToggle?()
            },
            onSelectSessionTranslationTargetLanguage: { [weak self] language in
                self?.onRequestSessionTranslationTargetLanguageSelect?(language)
            },
            onDismissSessionTranslationTargetPicker: { [weak self] in
                self?.onRequestSessionTranslationTargetPickerDismiss?()
            }
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

        if !isVisible {
            alphaValue = 1
            orderFrontRegardless()
        }
    }

    @discardableResult
    func handleAnswerSpaceShortcut() -> Bool {
        guard let state = observedState,
              let action = state.answerSpaceShortcutAction
        else {
            return false
        }

        switch action {
        case .continueAndRecord:
            onRequestContinue?()
        case .toggleConversationRecording:
            onRequestConversationRecordToggle?()
        }
        return true
    }

    func hide(animated: Bool = true, completion: (() -> Void)? = nil) {
        VoxtLog.info("Overlay hide requested. isVisible=\(isVisible)", verbose: true)
        observedState?.isPresented = false
        observedState?.audioLevel = 0
        removeOutsideClickMonitors()

        guard isVisible else {
            orderOut(nil)
            completion?()
            return
        }

        guard animated else {
            alphaValue = 0
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
        appearanceStateCancellable = Publishers.CombineLatest4(
            state.$displayMode,
            state.$allowsSessionTranslationLanguageSwitching,
            state.$isSessionTranslationTargetPickerPresented,
            state.$answerInteractionMode
        )
        .receive(on: RunLoop.main)
        .sink { [weak self, weak state] _ in
            guard let self, let state else { return }
            self.updateAppearance(for: state, animated: true)
        }

        pickerStateCancellable = state.$isSessionTranslationTargetPickerPresented
            .receive(on: RunLoop.main)
            .sink { [weak self, weak state] isPresented in
                guard let self, let state else { return }
                if isPresented {
                    self.installOutsideClickMonitors()
                } else {
                    self.removeOutsideClickMonitors()
                }
                self.updateMouseInteraction(for: state)
            }
    }

    private func updateAppearance(for state: OverlayState, animated: Bool) {
        updateMouseInteraction(for: state)
        let targetFrame = frame(for: panelSize(for: state), position: currentPosition)

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

    private func panelSize(for state: OverlayState) -> CGSize {
        switch state.displayMode {
        case .recording, .processing:
            return CGSize(width: 360, height: state.isSessionTranslationTargetPickerPresented ? 388 : 140)
        case .answer:
            return CGSize(width: 560, height: state.isSessionTranslationTargetPickerPresented ? 540 : 340)
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

    private func updateMouseInteraction(for state: OverlayState) {
        ignoresMouseEvents = !(
            state.displayMode == .answer ||
            (state.displayMode == .recording && state.allowsSessionTranslationLanguageSwitching)
        )
    }

    private func installOutsideClickMonitors() {
        guard localClickMonitor == nil, globalClickMonitor == nil else { return }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handleOutsideClickIfNeeded(eventLocationInScreen: NSEvent.mouseLocation, sourceWindow: event.window)
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleOutsideClickIfNeeded(eventLocationInScreen: NSEvent.mouseLocation, sourceWindow: nil)
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func handleOutsideClickIfNeeded(eventLocationInScreen: NSPoint, sourceWindow: NSWindow?) {
        guard let state = observedState,
              state.isSessionTranslationTargetPickerPresented
        else {
            return
        }

        if sourceWindow === self {
            return
        }

        guard !frame.contains(eventLocationInScreen) else { return }
        onRequestSessionTranslationTargetPickerDismiss?()
    }

    deinit {
        removeOutsideClickMonitors()
    }
}

// MARK: - SwiftUI content hosted inside the panel

private struct OverlayContent: View {
    @ObservedObject var state: OverlayState
    let onInject: () -> Void
    let onContinue: () -> Void
    let onToggleConversationRecording: () -> Void
    let onShowDetail: () -> Void
    let onClose: () -> Void
    let onToggleSessionTranslationTargetPicker: () -> Void
    let onSelectSessionTranslationTargetLanguage: (TranslationTargetLanguage) -> Void
    let onDismissSessionTranslationTargetPicker: () -> Void

    var body: some View {
        WaveformView(
            displayMode: state.displayMode,
            sessionIconMode: state.sessionIconMode,
            isModelInitializing: state.isModelInitializing,
            initializingEngine: state.initializingEngine,
            audioLevel: state.audioLevel,
            isRecording: state.isRecording,
            shouldAnimate: state.shouldAnimateVisuals,
            transcribedText: state.transcribedText,
            statusMessage: state.statusMessage,
            isEnhancing: state.isEnhancing,
            isRequesting: state.isRequesting,
            isFinalizingTranscription: state.isFinalizingTranscription,
            isCompleting: state.isCompleting,
            answerTitle: state.answerTitle,
            answerContent: state.answerContent,
            isStreamingAnswer: state.isStreamingAnswer,
            answerInteractionMode: state.answerInteractionMode,
            rewriteConversationTurns: state.rewriteConversationTurns,
            latestRewriteResult: state.latestRewriteResult,
            canInjectAnswer: state.canInjectAnswer,
            canCopyAnswer: state.canCopyLatestAnswer,
            canContinueAnswer: state.showsRewriteContinueButton,
            canShowHistoryDetail: state.canShowLatestHistoryDetail,
            sessionTranslationTargetLanguage: state.sessionTranslationTargetLanguage,
            sessionTranslationDraftLanguage: state.sessionTranslationDraftLanguage,
            isSessionTranslationTargetPickerPresented: state.isSessionTranslationTargetPickerPresented,
            isSessionTranslationLanguageHovering: state.isSessionTranslationLanguageHovering,
            allowsSessionTranslationLanguageSwitching: state.allowsSessionTranslationLanguageSwitching,
            onInject: onInject,
            onContinue: onContinue,
            onToggleConversationRecording: onToggleConversationRecording,
            onShowHistoryDetail: onShowDetail,
            onClose: onClose,
            onSessionTranslationLanguageHoverChanged: state.setSessionTranslationLanguageHovering,
            onToggleSessionTranslationTargetPicker: onToggleSessionTranslationTargetPicker,
            onSelectSessionTranslationTargetLanguage: onSelectSessionTranslationTargetLanguage,
            onDismissSessionTranslationTargetPicker: onDismissSessionTranslationTargetPicker
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }
}
