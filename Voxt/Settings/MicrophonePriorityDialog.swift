import SwiftUI
import UniformTypeIdentifiers

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct MicrophonePriorityDialog: View {
    let state: MicrophoneResolvedState
    let onUseNow: (String) -> Void
    let onAutoSwitchChanged: (Bool) -> Void
    let onReorderPriority: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var orderedEntries: [MicrophoneDisplayEntry]
    @State private var draggedUID: String?

    init(
        state: MicrophoneResolvedState,
        onUseNow: @escaping (String) -> Void,
        onAutoSwitchChanged: @escaping (Bool) -> Void,
        onReorderPriority: @escaping ([String]) -> Void
    ) {
        self.state = state
        self.onUseNow = onUseNow
        self.onAutoSwitchChanged = onAutoSwitchChanged
        self.onReorderPriority = onReorderPriority
        _orderedEntries = State(initialValue: state.entries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if orderedEntries.isEmpty {
                Text(localized("No available microphone devices"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(orderedEntries.enumerated()), id: \.element.uid) { index, entry in
                            MicrophonePriorityListRow(
                                entry: entry,
                                index: index,
                                onBeginDrag: { beginDrag(for: entry.uid) },
                                onMoveToTop: { moveEntryToTop(uid: entry.uid) },
                                onUse: { onUseNow(entry.uid) }
                            )
                                .onDrop(
                                    of: [UTType.text.identifier],
                                    delegate: MicrophonePriorityRowDropDelegate(
                                        targetUID: entry.uid,
                                        entries: $orderedEntries,
                                        draggedUID: $draggedUID,
                                        onReorder: persistReorder
                                    )
                                )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 220, maxHeight: 250)
            }

            SettingsDialogActionRow {
                Button(localized("Done")) {
                    dismiss()
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .settingsDialogChrome(width: 560, height: 380, onClose: { dismiss() })
        .onChange(of: state.entries) { _, newValue in
            orderedEntries = newValue
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("Microphone Priority"))
                    .font(.headline)
                Text(state.activeDevice?.name ?? String(localized: "No available microphone devices"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 12) {
                Text(localized("Drag to set the preferred microphone order."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Toggle(localized("Auto Switch"), isOn: autoSwitchBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .padding(.trailing, 44)
    }

    private var autoSwitchBinding: Binding<Bool> {
        Binding(
            get: { state.autoSwitchEnabled },
            set: { onAutoSwitchChanged($0) }
        )
    }

    private func moveEntryToTop(uid: String) {
        guard let sourceIndex = orderedEntries.firstIndex(where: { $0.uid == uid }) else { return }
        var reordered = orderedEntries
        let moved = reordered.remove(at: sourceIndex)
        reordered.insert(moved, at: 0)
        orderedEntries = reordered
        persistReorder(reordered.map(\.uid))
    }

    private func persistReorder(_ orderedUIDs: [String]) {
        onReorderPriority(orderedUIDs)
    }

    private func beginDrag(for uid: String) -> NSItemProvider {
        draggedUID = uid
        return NSItemProvider(object: uid as NSString)
    }
}
