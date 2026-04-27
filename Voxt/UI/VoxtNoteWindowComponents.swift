import SwiftUI

struct VoxtNoteWindowView: View {
    @ObservedObject var store: VoxtNoteStore
    let onComplete: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onRequestClose: () -> Void
    let onExpansionChanged: (Bool) -> Void

    @State private var isExpanded = false
    @State private var pendingCollapseTask: Task<Void, Never>?

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            noteCard
                .frame(width: 270)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(Color.clear)
        .onDisappear {
            pendingCollapseTask?.cancel()
            pendingCollapseTask = nil
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(store.incompleteItems) { item in
                            NoteListRow(
                                item: item,
                                onCopy: {
                                    copyStringToPasteboard(item.text)
                                },
                                onComplete: {
                                    onComplete(item.id)
                                },
                                onDelete: {
                                    onDelete(item.id)
                                }
                            )
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: 228, alignment: .topLeading)
                .padding(.bottom, 12)
            }

            barRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover(perform: handleHover)
    }

    private var barRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.92))

            Text("\(store.incompleteItems.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            Text(store.latestIncompleteItem?.title ?? "Notes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRequestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func handleHover(_ hovering: Bool) {
        guard !store.items.isEmpty else { return }
        pendingCollapseTask?.cancel()
        pendingCollapseTask = nil

        if hovering {
            withAnimation(.easeOut(duration: 0.16)) {
                isExpanded = true
            }
            onExpansionChanged(true)
            return
        }

        pendingCollapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                isExpanded = false
            }
            onExpansionChanged(false)
        }
    }
}

private struct NoteRowActionButton: View {
    let systemName: String
    var iconSize: CGFloat = 10
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(.white.opacity(isHovering ? 0.14 : 0.001))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }
}

private struct NoteListRow: View {
    let item: VoxtNoteItem
    let onCopy: () -> Void
    let onComplete: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false
    @State private var isHovering = false
    @State private var didCopy = false
    @State private var copyFeedbackTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .padding(.trailing, 92)

            Text(item.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(isExpanded ? nil : 3)
                .multilineTextAlignment(.leading)
                .padding(.trailing, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.16)) {
                isExpanded.toggle()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            trailingAccessory
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
        .onDisappear {
            copyFeedbackTask?.cancel()
            copyFeedbackTask = nil
        }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if isHovering {
            HStack(alignment: .center, spacing: 4) {
                NoteRowActionButton(
                    systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc.fill",
                    iconSize: 8,
                    action: {
                        onCopy()
                        showCopyFeedback()
                    }
                )
                NoteRowActionButton(systemName: "checkmark.circle", action: onComplete)
                NoteRowActionButton(systemName: "trash", action: onDelete)
            }
        } else if let createdAtText = RelativeNoteTimestampFormatter.noteCardTimestamp(for: item.createdAt) {
            Text(createdAtText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.44))
                .lineLimit(1)
        }
    }

    private func showCopyFeedback() {
        copyFeedbackTask?.cancel()
        withAnimation(.easeInOut(duration: 0.14)) {
            didCopy = true
        }
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.14)) {
                    didCopy = false
                }
                copyFeedbackTask = nil
            }
        }
    }
}
