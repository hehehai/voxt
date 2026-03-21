import SwiftUI

private struct MeetingBottomVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

struct MeetingOverlayContainerView: View {
    @ObservedObject var state: MeetingOverlayState
    let onClose: () -> Void
    let onToggleCollapse: () -> Void
    let onTogglePause: () -> Void
    let onShowDetail: () -> Void
    let onRealtimeTranslateToggle: (Bool) -> Void
    let onConfirmRealtimeTranslationLanguage: () -> Void
    let onCancelRealtimeTranslationLanguage: () -> Void
    let onConfirmCancelMeeting: () -> Void
    let onConfirmFinishMeeting: () -> Void
    let onDismissCloseConfirmation: () -> Void
    let onCopySegment: (MeetingTranscriptSegment) -> Void

    var body: some View {
        MeetingOverlayCard(
            state: state,
            onClose: onClose,
            onToggleCollapse: onToggleCollapse,
            onTogglePause: onTogglePause,
            onShowDetail: onShowDetail,
            onRealtimeTranslateToggle: onRealtimeTranslateToggle,
            onConfirmRealtimeTranslationLanguage: onConfirmRealtimeTranslationLanguage,
            onCancelRealtimeTranslationLanguage: onCancelRealtimeTranslationLanguage,
            onConfirmCancelMeeting: onConfirmCancelMeeting,
            onConfirmFinishMeeting: onConfirmFinishMeeting,
            onDismissCloseConfirmation: onDismissCloseConfirmation,
            onCopySegment: onCopySegment
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }
}

private struct MeetingOverlayCard: View {
    @AppStorage(AppPreferenceKey.overlayCardOpacity) private var overlayCardOpacity = 82
    @AppStorage(AppPreferenceKey.overlayCardCornerRadius) private var overlayCardCornerRadius = 24

    @ObservedObject var state: MeetingOverlayState
    let onClose: () -> Void
    let onToggleCollapse: () -> Void
    let onTogglePause: () -> Void
    let onShowDetail: () -> Void
    let onRealtimeTranslateToggle: (Bool) -> Void
    let onConfirmRealtimeTranslationLanguage: () -> Void
    let onCancelRealtimeTranslationLanguage: () -> Void
    let onConfirmCancelMeeting: () -> Void
    let onConfirmFinishMeeting: () -> Void
    let onDismissCloseConfirmation: () -> Void
    let onCopySegment: (MeetingTranscriptSegment) -> Void

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                header

                if !state.isCollapsed {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(height: 1)

                    transcriptContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, state.isCollapsed ? 12 : 16)
            .background(cardBackground)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )

            if state.isCloseConfirmationPresented || state.isRealtimeTranslationLanguagePickerPresented {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if state.isCloseConfirmationPresented {
                            onDismissCloseConfirmation()
                        }
                    }

                if state.isCloseConfirmationPresented {
                    meetingCloseConfirmationDialog
                } else {
                    realtimeTranslationLanguageDialog
                }
            }
        }
        .padding(.horizontal, 12)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                TranscriptionModeIconView()
                    .frame(width: 18, height: 18)

                MeetingMiniWaveform(waveformState: state.waveformState)
                    .frame(width: state.isCollapsed ? 128 : 116, height: 28)
            }

            Spacer(minLength: 12)

            if !state.isCollapsed {
                HStack(spacing: 8) {
                    Text(String(localized: "实时翻译"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))

                    Toggle(
                        "",
                        isOn: Binding(
                            get: { state.realtimeTranslateEnabled },
                            set: { onRealtimeTranslateToggle($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.82)
                }

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1, height: 18)

                AnswerHeaderActionButton(
                    accessibilityLabel: state.isPaused ? String(localized: "Resume") : String(localized: "Pause"),
                    action: onTogglePause
                ) {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                AnswerHeaderActionButton(
                    accessibilityLabel: String(localized: "Detail"),
                    action: onShowDetail
                ) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                AnswerHeaderActionButton(
                    accessibilityLabel: String(localized: "Collapse"),
                    action: onToggleCollapse
                ) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            } else {
                AnswerHeaderActionButton(
                    accessibilityLabel: state.isPaused ? String(localized: "Resume") : String(localized: "Pause"),
                    action: onTogglePause
                ) {
                    Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }

                AnswerHeaderActionButton(
                    accessibilityLabel: String(localized: "Expand"),
                    action: onToggleCollapse
                ) {
                    Image(systemName: "arrow.down.left.and.arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            AnswerHeaderActionButton(
                accessibilityLabel: String(localized: "Close"),
                action: onClose
            ) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var transcriptContent: some View {
        MeetingTranscriptScrollView(
            segments: state.segments,
            onCopySegment: onCopySegment
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 14)
    }

    private var realtimeTranslationLanguageDialog: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "选择翻译语言"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(String(localized: "实时翻译会只翻译 them 的内容。"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            Picker(
                "",
                selection: $state.realtimeTranslationDraftLanguageRaw
            ) {
                ForEach(TranslationTargetLanguage.allCases) { language in
                    Text(language.title).tag(language.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            HStack(spacing: 10) {
                Button(String(localized: "取消")) {
                    onCancelRealtimeTranslationLanguage()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )

                Button(String(localized: "开始翻译")) {
                    onConfirmRealtimeTranslationLanguage()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 20, y: 12)
    }

    private var meetingCloseConfirmationDialog: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "结束这场会议转录？"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(String(localized: "取消转录不会保存历史记录；结束转录会保存历史记录并打开会议详情。"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 10) {
                Button(String(localized: "取消转录")) {
                    onConfirmCancelMeeting()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.red.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.red.opacity(0.28), lineWidth: 1)
                )

                Button(String(localized: "结束转录")) {
                    onConfirmFinishMeeting()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.black.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 20, y: 12)
    }

    private var cornerRadius: CGFloat {
        CGFloat(min(max(overlayCardCornerRadius, 0), 40))
    }

    private var cardOpacity: Double {
        Double(min(max(overlayCardOpacity, 0), 100)) / 100.0
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.black.opacity(cardOpacity))
    }
}

private struct MeetingTranscriptScrollView: View {
    let segments: [MeetingTranscriptSegment]
    let onCopySegment: (MeetingTranscriptSegment) -> Void

    @State private var bottomVisible = true
    @State private var hasUnreadAtBottom = false
    @State private var copiedSegmentID: UUID?
    @State private var copyFeedbackToken = UUID()

    var body: some View {
        GeometryReader { outerProxy in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if segments.isEmpty {
                                VStack(spacing: 10) {
                                    Text(String(localized: "会议开始后，这里会持续显示 我 / them 的时间线。"))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))

                                    Text(String(localized: "滚动离开底部时会暂停自动滚动。"))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.42))
                                }
                                .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
                            } else {
                                ForEach(segments) { segment in
                                    MeetingTranscriptRow(
                                        segment: segment,
                                        onTap: {
                                        onCopySegment(segment)
                                        let token = UUID()
                                        copyFeedbackToken = token
                                        copiedSegmentID = segment.id
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                            guard copyFeedbackToken == token else { return }
                                            copiedSegmentID = nil
                                        }
                                        },
                                        isCopied: copiedSegmentID == segment.id
                                    )
                                }
                            }

                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: MeetingBottomVisibilityPreferenceKey.self,
                                        value: abs(geo.frame(in: .named("MeetingTranscriptScroll")).maxY - outerProxy.size.height) < 36
                                    )
                            }
                            .frame(height: 1)
                            .id("meeting-bottom-anchor")
                        }
                        .padding(.trailing, 10)
                    }
                    .coordinateSpace(name: "MeetingTranscriptScroll")
                    .onPreferenceChange(MeetingBottomVisibilityPreferenceKey.self) { isVisible in
                        bottomVisible = isVisible
                        if isVisible {
                            hasUnreadAtBottom = false
                        }
                    }
                    .onChange(of: segments.count) { _, _ in
                        if bottomVisible {
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo("meeting-bottom-anchor", anchor: .bottom)
                            }
                        } else {
                            hasUnreadAtBottom = true
                        }
                    }
                    .onAppear {
                        proxy.scrollTo("meeting-bottom-anchor", anchor: .bottom)
                    }

                    if hasUnreadAtBottom {
                        Button {
                            hasUnreadAtBottom = false
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo("meeting-bottom-anchor", anchor: .bottom)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(String(localized: "最新"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.black.opacity(0.78))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                        .padding(.bottom, 4)
                    }
                }
            }
        }
    }
}

private struct MeetingTranscriptRow: View {
    let segment: MeetingTranscriptSegment
    let onTap: () -> Void
    let isCopied: Bool

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(MeetingTranscriptFormatter.timestampString(for: segment.startSeconds))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.48))

                        Text(segment.speaker.displayTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(segment.speaker == .me ? Color(red: 0.55, green: 0.78, blue: 1.0) : Color(red: 0.56, green: 0.93, blue: 0.72))
                    }

                    Spacer(minLength: 8)

                    if isCopied {
                        CopySuccessIconView()
                            .frame(width: 14, height: 14)
                    }
                }

                Text(segment.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let translatedText = segment.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !translatedText.isEmpty {
                    Text(translatedText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if segment.isTranslationPending {
                    Text(String(localized: "Translating…"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.44))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MeetingMiniWaveform: View {
    @ObservedObject var waveformState: RecentAudioWaveformState

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<waveformState.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(WaveformBarVisuals.barGradient)
                    .frame(width: 4, height: barHeight(for: index))
                    .shadow(color: .white.opacity(glowOpacity(for: index)), radius: 2.5, x: 0, y: 0)
            }
        }
        .frame(height: 28)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseLevel = waveformState.barLevels.indices.contains(index) ? waveformState.barLevels[index] : 0
        return WaveformBarVisuals.barHeight(
            level: baseLevel,
            minHeight: 2.5,
            maxHeight: 22
        )
    }

    private func glowOpacity(for index: Int) -> Double {
        let baseLevel = waveformState.barLevels.indices.contains(index) ? waveformState.barLevels[index] : 0
        return WaveformBarVisuals.glowOpacity(level: baseLevel, base: 0.03, gain: 0.18, cap: 0.22)
    }
}
