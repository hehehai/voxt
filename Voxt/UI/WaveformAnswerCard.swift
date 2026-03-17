import SwiftUI

struct WaveformAnswerCard: View {
    let title: String
    let content: String
    let didCopyAnswer: Bool
    let onCopy: () -> Void
    let onClose: () -> Void

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "AI Answer") : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                AnswerIconView()
                    .frame(width: 20, height: 20)

                Text(displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 12)

                AnswerHeaderActionButton(
                    accessibilityLabel: String(localized: "Copy"),
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
                    accessibilityLabel: String(localized: "Close"),
                    action: onClose
                ) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

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
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help(accessibilityLabel)
    }
}
