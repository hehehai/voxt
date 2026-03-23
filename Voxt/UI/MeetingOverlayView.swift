import SwiftUI

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
                        .padding(.top, 6)
                        .padding(.bottom, 8)

                    transcriptContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, state.isCollapsed ? 10 : 14)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Group {
                        if state.isModelInitializing {
                            ModelInitializingIconView()
                        } else {
                            TranscriptionModeIconView()
                        }
                    }
                    .frame(width: 18, height: 18)

                    MeetingMiniWaveform(
                        waveformState: state.waveformState,
                        isSubdued: state.isModelInitializing
                    )
                        .frame(width: state.isCollapsed ? 96 : 116, height: 28)
                }

                Spacer(minLength: 12)

                if !state.isCollapsed {
                    HStack(spacing: 8) {
                        Text(String(localized: "Realtime Translation"))
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
                        .toggleStyle(MeetingInlineSwitchStyle())
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
            Text(String(localized: "Choose Translation Language"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(String(localized: "Realtime translation only translates Them segments."))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(TranslationTargetLanguage.allCases) { language in
                        Button {
                            state.realtimeTranslationDraftLanguageRaw = language.rawValue
                        } label: {
                            HStack(spacing: 10) {
                                Text(language.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))

                                Spacer(minLength: 8)

                                if state.realtimeTranslationDraftLanguageRaw == language.rawValue {
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
                                        state.realtimeTranslationDraftLanguageRaw == language.rawValue
                                            ? Color.accentColor.opacity(0.20)
                                            : .white.opacity(0.05)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        state.realtimeTranslationDraftLanguageRaw == language.rawValue
                                            ? Color.accentColor.opacity(0.36)
                                            : .white.opacity(0.08),
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
                    onCancelRealtimeTranslationLanguage()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.94))
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
                .foregroundStyle(.white.opacity(0.94))
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
            Text(String(localized: "End this meeting transcription?"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(String(localized: "Canceling will discard this meeting; finishing will save it and open Meeting Details."))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 10) {
                Button(String(localized: "Cancel Transcription")) {
                    onConfirmCancelMeeting()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.94))
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

                Button(String(localized: "Finish Transcription")) {
                    onConfirmFinishMeeting()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.94))
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

private struct MeetingInlineSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(configuration.isOn ? Color.accentColor.opacity(0.92) : .white.opacity(0.10))
                    .frame(width: 36, height: 20)

                Circle()
                    .fill(.white.opacity(0.96))
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
            .animation(.easeInOut(duration: 0.16), value: configuration.isOn)
        }
        .frame(width: 36, height: 20)
        .contentShape(Capsule(style: .continuous))
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}
