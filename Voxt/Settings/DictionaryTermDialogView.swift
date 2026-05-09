import SwiftUI

private func localizedDictionaryTermDialog(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct DictionaryTermDialogView: View {
    let dialog: DictionaryDialog
    let availableGroups: [AppBranchGroup]
    let onCancel: () -> Void
    let onSave: (String, [String], UUID?) throws -> Void

    @State private var draftTerm: String
    @State private var draftReplacementTermInput = ""
    @State private var draftReplacementTerms: [String]
    @State private var selectedGroupID: UUID?
    @State private var errorMessage: String?

    init(
        dialog: DictionaryDialog,
        availableGroups: [AppBranchGroup],
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, [String], UUID?) throws -> Void
    ) {
        self.dialog = dialog
        self.availableGroups = availableGroups
        self.onCancel = onCancel
        self.onSave = onSave

        switch dialog {
        case .create:
            _draftTerm = State(initialValue: "")
            _draftReplacementTerms = State(initialValue: [])
            _selectedGroupID = State(initialValue: nil)
        case .edit(let entry):
            _draftTerm = State(initialValue: entry.term)
            _draftReplacementTerms = State(initialValue: entry.replacementTerms.map(\.text))
            _selectedGroupID = State(initialValue: entry.groupID)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: dialog.title)
                .font(.title3.weight(.semibold))

            TextField(
                "",
                text: $draftTerm,
                prompt: Text(verbatim: localizedDictionaryTermDialog("Dictionary Term"))
            )
            .textFieldStyle(.plain)
            .settingsFieldSurface()

            SettingsMenuPicker(
                selection: $selectedGroupID,
                options: dictionaryGroupOptions,
                selectedTitle: selectedDictionaryGroupTitle,
                width: 240
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: localizedDictionaryTermDialog("Replacement Match Terms"))
                        .font(.caption.weight(.semibold))

                    Text(verbatim: localizedDictionaryTermDialog(" (Optional. Without them, Voxt still uses normal dictionary matching and high-confidence correction.)"))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: $draftReplacementTermInput,
                        prompt: Text(verbatim: localizedDictionaryTermDialog("Replacement Match Term"))
                    )
                    .textFieldStyle(.plain)
                    .settingsFieldSurface()
                    .onSubmit(addDraftReplacementTerm)

                    Button {
                        addDraftReplacementTerm()
                    } label: {
                        Text(verbatim: localizedDictionaryTermDialog("Add"))
                    }
                    .buttonStyle(SettingsPillButtonStyle())
                    .disabled(draftReplacementTermInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text(verbatim: localizedDictionaryTermDialog("Add phrases that should always resolve to this dictionary term."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if draftReplacementTerms.isEmpty {
                    Text(verbatim: localizedDictionaryTermDialog("No replacement match terms."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    DictionaryEditableTagList(values: draftReplacementTerms) { value in
                        removeDraftReplacementTerm(value)
                    }
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            SettingsDialogActionRow {
                Button {
                    onCancel()
                } label: {
                    Text(verbatim: localizedDictionaryTermDialog("Cancel"))
                }
                .buttonStyle(SettingsPillButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button {
                    save()
                } label: {
                    Text(verbatim: dialog.confirmButtonTitle)
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var dictionaryGroupOptions: [SettingsMenuOption<UUID?>] {
        var options: [SettingsMenuOption<UUID?>] = [
            SettingsMenuOption(value: nil, title: localizedDictionaryTermDialog("Global"))
        ]
        if let selectedGroupID,
           availableGroups.contains(where: { $0.id == selectedGroupID }) == false {
            options.append(SettingsMenuOption(value: selectedGroupID, title: localizedDictionaryTermDialog("Missing Group")))
        }
        options.append(contentsOf: availableGroups.map { group in
            SettingsMenuOption(value: Optional(group.id), title: group.name)
        })
        return options
    }

    private var selectedDictionaryGroupTitle: String {
        guard let selectedGroupID else {
            return localizedDictionaryTermDialog("Global")
        }
        return availableGroups.first(where: { $0.id == selectedGroupID })?.name ?? localizedDictionaryTermDialog("Missing Group")
    }

    private func save() {
        do {
            try onSave(draftTerm, draftReplacementTerms, selectedGroupID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addDraftReplacementTerm() {
        let display = draftReplacementTermInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = DictionaryStore.normalizeTerm(display)
        guard !display.isEmpty, !normalized.isEmpty else {
            errorMessage = AppLocalization.localizedString("Replacement match term cannot be empty.")
            return
        }

        if normalized == DictionaryStore.normalizeTerm(draftTerm) {
            errorMessage = AppLocalization.localizedString("Replacement match term cannot be the same as the dictionary term.")
            return
        }

        if draftReplacementTerms.contains(where: { DictionaryStore.normalizeTerm($0) == normalized }) {
            draftReplacementTermInput = ""
            return
        }

        draftReplacementTerms.append(display)
        draftReplacementTerms.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        draftReplacementTermInput = ""
        errorMessage = nil
    }

    private func removeDraftReplacementTerm(_ value: String) {
        let normalized = DictionaryStore.normalizeTerm(value)
        draftReplacementTerms.removeAll { DictionaryStore.normalizeTerm($0) == normalized }
        errorMessage = nil
    }
}
