import SwiftUI
import Foundation
import AppKit

struct WaveformView: View {
    @AppStorage(AppPreferenceKey.overlayCardOpacity) private var overlayCardOpacity = 82
    @AppStorage(AppPreferenceKey.overlayCardCornerRadius) private var overlayCardCornerRadius = 24

    static let defaultWaveformBarWidth: CGFloat = 3.2
    static let defaultWaveformBarSpacing: CGFloat = 2.5
    static let defaultWaveformSlotWidth: CGFloat = 94
    static let defaultSessionLanguagePickerWidth: CGFloat = 198

    static func waveformVisualWidth(
        barCount: Int = 16,
        barWidth: CGFloat = Self.defaultWaveformBarWidth,
        barSpacing: CGFloat = Self.defaultWaveformBarSpacing
    ) -> CGFloat {
        guard barCount > 0 else { return 0 }
        return (CGFloat(barCount) * barWidth) + (CGFloat(barCount - 1) * barSpacing)
    }

    static func shouldShowSessionTranslationLanguagePill(
        displayMode: OverlayDisplayMode,
        allowsSwitching: Bool,
        sessionTranslationTargetLanguage: TranslationTargetLanguage?,
        isHovering: Bool,
        isPickerPresented: Bool
    ) -> Bool {
        (displayMode == .recording || displayMode == .answer) &&
            allowsSwitching &&
            sessionTranslationTargetLanguage != nil &&
            (isHovering || isPickerPresented)
    }

    private let waveformBarWidth: CGFloat = Self.defaultWaveformBarWidth
    private let waveformBarSpacing: CGFloat = Self.defaultWaveformBarSpacing
    var displayMode: OverlayDisplayMode
    var sessionIconMode: OverlaySessionIconMode
    var isModelInitializing: Bool = false
    var initializingEngine: TranscriptionEngine? = nil
    var audioLevel: Float
    var isRecording: Bool
    var shouldAnimate: Bool
    var transcribedText: String
    var statusMessage: String = ""
    var isEnhancing: Bool = false
    var isRequesting: Bool = false
    var isFinalizingTranscription: Bool = false
    var isCompleting: Bool = false
    var answerTitle: String = ""
    var answerContent: String = ""
    var isStreamingAnswer: Bool = false
    var answerInteractionMode: AnswerInteractionMode = .singleResult
    var rewriteConversationTurns: [RewriteConversationTurn] = []
    var latestRewriteResult: RewriteAnswerPayload? = nil
    var canInjectAnswer: Bool = false
    var canCopyAnswer: Bool = false
    var canContinueAnswer: Bool = false
    var canShowHistoryDetail: Bool = false
    var sessionTranslationTargetLanguage: TranslationTargetLanguage? = nil
    var sessionTranslationDraftLanguage: TranslationTargetLanguage? = nil
    var isSessionTranslationTargetPickerPresented: Bool = false
    var isSessionTranslationLanguageHovering: Bool = false
    var allowsSessionTranslationLanguageSwitching: Bool = false
    var onInject: () -> Void = {}
    var onContinue: () -> Void = {}
    var onToggleConversationRecording: () -> Void = {}
    var onShowHistoryDetail: () -> Void = {}
    var onClose: () -> Void = {}
    var onSessionTranslationLanguageHoverChanged: (Bool) -> Void = { _ in }
    var onToggleSessionTranslationTargetPicker: () -> Void = {}
    var onSelectSessionTranslationTargetLanguage: (TranslationTargetLanguage) -> Void = { _ in }
    var onDismissSessionTranslationTargetPicker: () -> Void = {}

    private let iconSlotSize = CGSize(width: 16, height: 28)
    private let barAreaHeight: CGFloat = 28
    private let waveformSlotWidth: CGFloat = Self.defaultWaveformSlotWidth
    private let sessionLanguagePickerWidth: CGFloat = Self.defaultSessionLanguagePickerWidth
    private let barCount = 16
    private let basePhases: [Double] = (0..<16).map { Double($0) * 0.4 }
    private let baseTravelPhase = 0.0

    @State private var phases: [Double] = (0..<16).map { Double($0) * 0.4 }
    @State private var travelPhase = 0.0
    @State private var animTimer: Timer?
    @State private var currentAnimationInterval: TimeInterval?
    @State private var appeared = false
    @State private var textScrollID = UUID()
    @State private var didCopyAnswer = false
    @State private var copyFeedbackToken = UUID()

    private var displayText: String {
        let message = statusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty { return message }
        return sanitizedDisplayText(transcribedText)
    }

    private var hasText: Bool { !displayText.isEmpty }
    private var isAnswerMode: Bool { displayMode == .answer }
    private var isCompact: Bool { !hasText && !isAnswerMode }
    private var cornerRadius: CGFloat { CGFloat(min(max(overlayCardCornerRadius, 0), 40)) }
    private var cardOpacity: Double { Double(min(max(overlayCardOpacity, 0), 100)) / 100.0 }
    private var textOverflows: Bool { displayText.count > 38 }
    private var showsLoadingSpinner: Bool {
        !isCompleting && (isEnhancing || isRequesting || isFinalizingTranscription)
    }
    private var showsInitializationIcon: Bool { isModelInitializing && !showsLoadingSpinner }
    private var showsSessionTranslationLanguagePill: Bool {
        Self.shouldShowSessionTranslationLanguagePill(
            displayMode: displayMode,
            allowsSwitching: allowsSessionTranslationLanguageSwitching,
            sessionTranslationTargetLanguage: sessionTranslationTargetLanguage,
            isHovering: isSessionTranslationLanguageHovering,
            isPickerPresented: isSessionTranslationTargetPickerPresented
        )
    }
    private var selectedSessionTranslationLanguage: TranslationTargetLanguage? {
        sessionTranslationDraftLanguage ?? sessionTranslationTargetLanguage
    }
    private var showsAnswerTranslationSelector: Bool {
        isAnswerMode &&
            answerInteractionMode == .singleResult &&
            sessionIconMode == .translation &&
            allowsSessionTranslationLanguageSwitching &&
            sessionTranslationTargetLanguage != nil
    }
    private var waveformVisualWidth: CGFloat {
        Self.waveformVisualWidth(
            barCount: barCount,
            barWidth: waveformBarWidth,
            barSpacing: waveformBarSpacing
        )
    }
    private var displayedAnswerPayload: RewriteAnswerPayload {
        let hasDraft = !answerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !answerContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasDraft {
            return RewriteAnswerPayload(title: answerTitle, content: answerContent)
        }
        return latestRewriteResult ?? RewriteAnswerPayload(title: answerTitle, content: answerContent)
    }

    private var copyableAnswerPayload: RewriteAnswerPayload? {
        if let latestRewriteResult {
            return latestRewriteResult
        }
        guard !isStreamingAnswer else { return nil }
        let trimmed = answerContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return RewriteAnswerPayload(title: answerTitle, content: answerContent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isAnswerMode && isSessionTranslationTargetPickerPresented {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    sessionTranslationLanguagePicker
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.92, anchor: .bottom))
                        )

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            cardView
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSessionTranslationTargetPickerPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .scaleEffect(appeared ? 1.0 : 0.5, anchor: .bottom)
        .opacity(appeared ? 1.0 : 0.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.5, blendDuration: 0.1), value: appeared)
        .onHover { hovering in
            guard allowsSessionTranslationLanguageSwitching else { return }
            onSessionTranslationLanguageHoverChanged(hovering)
        }
        .onAppear {
            updateAnimationState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                appeared = true
            }
        }
        .onDisappear {
            stopAnimating()
            appeared = false
        }
        .onChange(of: shouldAnimate) {
            updateAnimationState()
        }
        .onChange(of: displayMode) {
            updateAnimationState()
        }
        .onChange(of: isRecording) {
            updateAnimationState()
        }
    }

    private var cardView: some View {
        Group {
            if isAnswerMode {
                answerCard
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else {
                compactCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(.horizontal, isAnswerMode ? 18 : (isCompact ? 14 : 20))
        .padding(.vertical, isAnswerMode ? 16 : (isCompact ? 10 : 12))
        .background(cardBackground)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: displayMode)
        .animation(.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0.1), value: isCompact)
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onTapGesture {
            guard isSessionTranslationTargetPickerPresented, !showsAnswerTranslationSelector else { return }
            onDismissSessionTranslationTargetPicker()
        }
    }

    private var compactCard: some View {
        VStack(spacing: isCompact ? 0 : 8) {
            HStack(spacing: 10) {
                leadingStatusIcon
                    .frame(width: iconSlotSize.width, height: iconSlotSize.height, alignment: .center)
                    .transition(.opacity)

                waveformSlot
            }
            .frame(height: barAreaHeight)
            .animation(.easeInOut(duration: 0.25), value: showsLoadingSpinner)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: showsSessionTranslationLanguagePill)

            if hasText {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            Text(displayText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .id(textScrollID)

                            Spacer().frame(width: 4)
                        }
                    }
                    .frame(maxWidth: 260)
                    .mask(
                        HStack(spacing: 0) {
                            if textOverflows {
                                LinearGradient(
                                    colors: [.clear, .white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 16)
                                .transition(.opacity)
                            }
                            Color.white
                        }
                    )
                    .onChange(of: displayText) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(textScrollID, anchor: .trailing)
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var waveformSlot: some View {
        if showsLoadingSpinner {
            processingBars
                .frame(width: waveformSlotWidth, height: barAreaHeight, alignment: .center)
                .transition(.opacity)
        } else if showsSessionTranslationLanguagePill {
            ZStack {
                Color.clear

                sessionTranslationLanguagePill
            }
            .frame(width: waveformSlotWidth, height: barAreaHeight, alignment: .center)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        } else {
            waveformBars
                .frame(width: waveformVisualWidth, height: barAreaHeight, alignment: .center)
                .transition(.opacity)
        }
    }

    private var sessionTranslationLanguagePill: some View {
        Button(action: onToggleSessionTranslationTargetPicker) {
            HStack(spacing: 6) {
                Text(sessionTranslationTargetLanguage?.title ?? "")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 62, alignment: .center)

                Image(systemName: isSessionTranslationTargetPickerPresented ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(.white.opacity(0.09))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSessionTranslationTargetPickerPresented ? Color.accentColor.opacity(0.28) : .white.opacity(0.14),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "Target Language")))
        .fixedSize(horizontal: true, vertical: false)
    }

    private var sessionTranslationLanguagePicker: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(TranslationTargetLanguage.allCases) { language in
                    Button {
                        onSelectSessionTranslationTargetLanguage(language)
                    } label: {
                        sessionTranslationLanguageRow(for: language)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
        }
        .frame(width: sessionLanguagePickerWidth, alignment: .top)
        .frame(maxHeight: 184, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
        .accessibilityLabel(Text(String(localized: "Translation Language")))
    }

    private func sessionTranslationLanguageRow(for language: TranslationTargetLanguage) -> some View {
        let isSelected = selectedSessionTranslationLanguage == language
        let backgroundColor: Color = isSelected ? Color.accentColor.opacity(0.20) : .white.opacity(0.05)
        let borderColor: Color = isSelected ? Color.accentColor.opacity(0.36) : .white.opacity(0.08)

        return HStack(spacing: 10) {
            Text(language.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.95))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var answerCard: some View {
        WaveformAnswerCard(
            title: displayedAnswerPayload.title,
            content: displayedAnswerPayload.content,
            answerInteractionMode: answerInteractionMode,
            conversationTurns: rewriteConversationTurns,
            streamingUserPromptText: conversationStreamingUserPromptText,
            canInjectAnswer: canInjectAnswer,
            canCopyAnswer: canCopyAnswer,
            canContinueAnswer: canContinueAnswer,
            canShowHistoryDetail: showsAnswerTranslationSelector ? false : canShowHistoryDetail,
            didCopyAnswer: didCopyAnswer,
            isRecording: isRecording,
            isProcessing: isEnhancing || isRequesting || isFinalizingTranscription,
            audioLevel: audioLevel,
            shouldAnimateWave: shouldAnimate,
            streamingDraftPayload: answerInteractionMode == .conversation && isStreamingAnswer
                ? displayedAnswerPayload
                : nil,
            showsSessionTranslationSelector: showsAnswerTranslationSelector,
            sessionTranslationTargetLanguage: sessionTranslationTargetLanguage,
            sessionTranslationDraftLanguage: sessionTranslationDraftLanguage,
            isSessionTranslationTargetPickerPresented: isSessionTranslationTargetPickerPresented,
            onInject: onInject,
            onContinue: onContinue,
            onToggleConversationRecording: onToggleConversationRecording,
            onShowDetail: onShowHistoryDetail,
            onCopy: copyAnswerToPasteboard,
            onClose: onClose,
            onToggleSessionTranslationTargetPicker: onToggleSessionTranslationTargetPicker,
            onSelectSessionTranslationTargetLanguage: onSelectSessionTranslationTargetLanguage,
            onDismissSessionTranslationTargetPicker: onDismissSessionTranslationTargetPicker
        )
    }

    private var conversationStreamingUserPromptText: String? {
        guard answerInteractionMode == .conversation else { return nil }
        let trimmed = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, (isRecording || isEnhancing || isRequesting || isFinalizingTranscription) else { return nil }
        return trimmed
    }

    @ViewBuilder
    private var leadingStatusIcon: some View {
        if isCompleting {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 14, height: 14, alignment: .center)
        } else if showsInitializationIcon {
            ModelInitializingIconView()
                .frame(width: 14, height: 14, alignment: .center)
        } else {
            compactModeIcon
                .frame(width: 14, height: 14, alignment: .center)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.black.opacity(cardOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
    }

    private func sanitizedDisplayText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if !(trimmed.hasPrefix("{") || trimmed.hasPrefix("[")) {
            return trimmed
        }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let text = extractText(from: object),
           !text.isEmpty {
            return text
        }

        if let text = extractLooseText(from: trimmed), !text.isEmpty {
            return text
        }

        return trimmed
    }

    private func extractText(from object: Any) -> String? {
        if let value = object as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let dict = object as? [String: Any] {
            for key in ["text", "transcript", "delta", "result_text", "content"] {
                if let value = dict[key], let extracted = extractText(from: value), !extracted.isEmpty {
                    return extracted
                }
            }
            for value in dict.values {
                if let extracted = extractText(from: value), !extracted.isEmpty {
                    return extracted
                }
            }
        }
        if let array = object as? [Any] {
            for value in array {
                if let extracted = extractText(from: value), !extracted.isEmpty {
                    return extracted
                }
            }
        }
        return nil
    }

    private func extractLooseText(from value: String) -> String? {
        let patterns = [
            #"(?:["']?text["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?transcript["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?delta["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?text["']?\s*:\s*)([^,}\]]+)"#,
            #"(?:["']?transcript["']?\s*:\s*)([^,}\]]+)"#,
            #"(?:["']?delta["']?\s*:\s*)([^,}\]]+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = regex.firstMatch(in: value, options: [], range: range),
                  match.numberOfRanges > 1,
                  let textRange = Range(match.range(at: 1), in: value) else {
                continue
            }
            var result = String(value[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (result.hasPrefix("\"") && result.hasSuffix("\"")) ||
                (result.hasPrefix("'") && result.hasSuffix("'")) {
                result.removeFirst()
                result.removeLast()
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !result.isEmpty { return result }
        }
        return nil
    }

    private var waveformBars: some View {
        HStack(alignment: .center, spacing: waveformBarSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.98), Color.white.opacity(0.80)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: waveformBarWidth, height: barHeight(for: index))
                    .shadow(color: .white.opacity(glowOpacity(for: index)), radius: 3, x: 0, y: 0)
            }
        }
        .frame(height: barAreaHeight)
    }

    private var processingBars: some View {
        HStack(alignment: .center, spacing: waveformBarSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(processingBarOpacity(for: index)))
                    .frame(width: 2.5, height: processingBarHeight(for: index))
            }
        }
        .frame(height: barAreaHeight)
    }

    @ViewBuilder
    private var compactModeIcon: some View {
        if showsLoadingSpinner {
            LoadingSpinnerIconView(isAnimating: shouldAnimate)
                .frame(width: 14, height: 14)
        } else if showsInitializationIcon {
            ModelInitializingIconView()
                .frame(width: 14, height: 14)
        } else {
            switch sessionIconMode {
            case .transcription:
                TranscriptionModeIconView()
                    .frame(width: 14, height: 14)
                    .opacity(0.92)
            case .translation:
                TranslationModeIconView()
                    .frame(width: 14, height: 14)
                    .opacity(0.92)
            case .rewrite:
                RewriteModeIconView()
                    .frame(width: 14, height: 14)
                    .opacity(0.92)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let minH: CGFloat = 4
        let maxH: CGFloat = 23
        let phase = phases[index]
        let sine = (sin(phase) + 1) / 2

        if isModelInitializing {
            let quietPattern: [CGFloat] = [4.0, 4.7, 5.4, 6.0, 5.0, 4.3, 5.2, 5.8]
            return quietPattern[index % quietPattern.count]
        }

        if isRecording {
            let level = normalizedAudioLevel(audioLevel)
            let audioEnvelope = pow(level, 0.84)
            let travelEnvelope = recordingTravelEnvelope(for: index)
            let ambientEnvelope = CGFloat(sine * 0.65 + 0.35)
            let baseFloor = 0.012 + min(0.025, level * 0.03)
            let travelStrength = 0.005 + audioEnvelope * 0.95
            let ambientStrength = 0.004 + audioEnvelope * 0.05
            let mixedEnvelope = min(1.0, baseFloor + travelEnvelope * travelStrength + ambientEnvelope * ambientStrength)
            let driven = minH + (maxH - minH) * mixedEnvelope
            return max(minH, driven)
        }

        if displayMode == .processing {
            return minH + CGFloat(3.5 * sine)
        }

        return staticBarHeight(for: index)
    }

    private func glowOpacity(for index: Int) -> Double {
        if isModelInitializing {
            return 0.03
        }
        guard isRecording else { return 0.08 }
        let level = Double(normalizedAudioLevel(audioLevel))
        let travelEnvelope = Double(recordingTravelEnvelope(for: index))
        let ambientPulse = (sin(phases[index] * 1.15) + 1) / 2
        let glow = 0.02 + ambientPulse * 0.01 + travelEnvelope * 0.05 + level * (0.025 + travelEnvelope * 0.07)
        return min(0.2, glow)
    }

    private func normalizedAudioLevel(_ raw: Float) -> CGFloat {
        let clamped = max(0, min(raw, 1))
        let gained = min(1.0, pow(Double(clamped), 1.08) * 0.56)
        return CGFloat(gained)
    }

    private func staticBarHeight(for index: Int) -> CGFloat {
        let pattern: [CGFloat] = [5, 7, 10, 12, 9, 6, 8, 11]
        return pattern[index % pattern.count]
    }

    private func processingBarHeight(for index: Int) -> CGFloat {
        let phase = phases[index]
        let sine = (sin(phase) + 1) / 2
        let minH: CGFloat = 6
        let maxH: CGFloat = 10
        return minH + (maxH - minH) * CGFloat(sine)
    }

    private func processingBarOpacity(for index: Int) -> Double {
        let phase = phases[index]
        let sine = (sin(phase * 1.2) + 1) / 2
        return 0.35 + 0.4 * sine
    }

    private func recordingTravelEnvelope(for index: Int) -> CGFloat {
        let head = travelPhase
        let distance = wrappedDistance(from: Double(index), to: head, period: Double(barCount))
        let sigma = 2.15
        let gaussian = exp(-(distance * distance) / (2 * sigma * sigma))
        return CGFloat(gaussian)
    }

    private func wrappedDistance(from index: Double, to head: Double, period: Double) -> Double {
        var delta = index - head
        if delta > period / 2 {
            delta -= period
        } else if delta < -period / 2 {
            delta += period
        }
        return delta
    }

    private var desiredAnimationInterval: TimeInterval? {
        guard shouldAnimate else { return nil }

        switch displayMode {
        case .recording:
            return isRecording ? (1.0 / 20.0) : nil
        case .processing:
            return 1.0 / 10.0
        case .answer:
            return nil
        }
    }

    private var animationSpeed: Double {
        switch displayMode {
        case .recording:
            return isRecording ? 0.16 : 0
        case .processing:
            return 0.06
        case .answer:
            return 0
        }
    }

    private func updateAnimationState() {
        guard let interval = desiredAnimationInterval else {
            stopAnimating(resetPhases: true)
            return
        }

        guard animTimer == nil || currentAnimationInterval != interval else { return }
        startAnimating(interval: interval)
    }

    private func startAnimating(interval: TimeInterval) {
        stopAnimating(resetPhases: false)
        currentAnimationInterval = interval
        animTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                let speed = animationSpeed
                guard speed > 0 else { return }
                if displayMode == .recording && isRecording {
                    travelPhase.formTruncatingRemainder(dividingBy: Double(barCount))
                    travelPhase += 0.62
                    if travelPhase >= Double(barCount) {
                        travelPhase -= Double(barCount)
                    }

                    for i in 0..<barCount {
                        phases[i] += 0.11 + Double(i) * 0.004
                    }
                } else {
                    for i in 0..<barCount {
                        phases[i] += speed + Double(i) * 0.006
                    }
                }
            }
        }
    }

    private func stopAnimating(resetPhases: Bool = true) {
        animTimer?.invalidate()
        animTimer = nil
        currentAnimationInterval = nil
        if resetPhases {
            phases = basePhases
            travelPhase = baseTravelPhase
        }
    }

    private func copyAnswerToPasteboard() {
        guard let payload = copyableAnswerPayload else { return }
        copyTextToPasteboard(payload.content)
        let token = UUID()
        copyFeedbackToken = token
        didCopyAnswer = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard copyFeedbackToken == token else { return }
            didCopyAnswer = false
        }
    }

    private func copyTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
