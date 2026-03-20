import SwiftUI

struct WaveformAnswerCard: View {
    let title: String
    let content: String
    let canInjectAnswer: Bool
    let didCopyAnswer: Bool
    let onInject: () -> Void
    let onCopy: () -> Void
    let onClose: () -> Void

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppLocalization.localizedString("AI Answer") : trimmed
    }

    var body: some View {
        OverlayCardShell(
            title: displayTitle,
            headerActions: {
                if canInjectAnswer {
                    AnswerHeaderActionButton(
                        accessibilityLabel: AppLocalization.localizedString("Inject into Current Input"),
                        action: onInject
                    ) {
                        Image(systemName: "arrow.down.to.line.compact")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                AnswerHeaderActionButton(
                    accessibilityLabel: AppLocalization.localizedString("Copy Answer"),
                    action: onCopy
                ) {
                    if didCopyAnswer {
                        CopySuccessIconView()
                            .frame(width: 15, height: 15)
                    } else {
                        CopyIconView()
                            .frame(width: 15, height: 15)
                    }
                }

                AnswerHeaderActionButton(
                    accessibilityLabel: AppLocalization.localizedString("Close"),
                    action: onClose
                ) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            },
            bodyContent: {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(content)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.trailing, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
            }
        )
    }
}

struct OverlayPromptCard: View {
    let title: String
    let contextHint: String
    let questions: [String]
    let shortcutLabel: String
    let canConfirm: Bool
    let onConfirm: () -> Void
    let onClose: () -> Void

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppLocalization.localizedString("AI needs your input") : trimmed
    }

    var body: some View {
        OverlayCardShell(
            title: displayTitle,
            headerActions: {
                PromptShortcutActionButton(
                    label: shortcutLabel,
                    accessibilityLabel: shortcutLabel,
                    action: onConfirm
                )
                .disabled(!canConfirm)

                AnswerHeaderActionButton(
                    accessibilityLabel: AppLocalization.localizedString("Close"),
                    action: onClose
                ) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            },
            bodyContent: {
                VStack(alignment: .leading, spacing: 12) {
                    if !contextHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(contextHint)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1).")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.72))
                                    Text(question)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.92))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 210, alignment: .topLeading)
                }
            }
        )
    }
}

private struct OverlayCardShell<HeaderActions: View, BodyContent: View>: View {
    let title: String
    @ViewBuilder let headerActions: () -> HeaderActions
    @ViewBuilder let bodyContent: () -> BodyContent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                AnswerIconView()
                    .frame(width: 20, height: 20)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 12)

                headerActions()
            }

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            bodyContent()
        }
    }
}

struct AnswerHeaderActionButton<Label: View>: View {
    let accessibilityLabel: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHovered ? .white.opacity(0.16) : .white.opacity(0.08))
                )
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(isHovered ? 0.18 : 0), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

struct PromptShortcutActionButton: View {
    let label: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    Capsule()
                        .fill(isHovered ? .white.opacity(0.16) : .white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(isHovered ? 0.18 : 0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}
