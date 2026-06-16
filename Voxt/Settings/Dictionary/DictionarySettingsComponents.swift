// DictionarySettingsComponents.swift
// Provides Dictionary Settings Components for dictionary settings.

import SwiftUI

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct DictionaryFilterPicker: View {
    @Binding var selectedFilter: DictionaryFilter

    var body: some View {
        HStack(spacing: 2) {
            ForEach(DictionaryFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    Text(LocalizedStringKey(filter.titleKey))
                }
                .buttonStyle(DictionaryFilterSegmentedButtonStyle(isSelected: selectedFilter == filter))
            }
        }
        .padding(2)
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
    }
}

private struct DictionaryFilterSegmentedButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        DictionaryFilterSegmentedButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct DictionaryFilterSegmentedButtonBody: View {
    let configuration: DictionaryFilterSegmentedButtonStyle.Configuration
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(isSelected || isHovered ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected || isHovered ? Color.accentColor.opacity(0.14) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected || isHovered ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .onHover { isHovered = $0 }
    }
}

struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isDeleteHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.term)
                .font(.system(size: 12.5, weight: .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 28)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 32, alignment: .center)
        .contentShape(Rectangle())
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
        .brightness(isHovering ? 0.035 : 0)
        .overlay {
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .strokeBorder(
                    Color.accentColor.opacity(isHovering ? 0.42 : 0),
                    lineWidth: 1
                )
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onTapGesture(perform: onEdit)
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isDeleteHovering ? Color.red : Color.secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(isDeleteHovering ? 0.12 : 0))
                    )
            }
            .buttonStyle(.plain)
            .help(localized("Delete"))
            .onHover { hovering in
                isDeleteHovering = hovering
            }
            .padding(6)
        }
    }
}

struct DictionarySuggestionRow: View {
    let suggestion: DictionarySuggestion
    let scopeLabel: String
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        DictionaryListRowContainer(
            content: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.term)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .textSelection(.enabled)

                    HStack(spacing: 6) {
                        DictionaryCapsuleBadge(
                            title: scopeLabel,
                            fill: Color.secondary.opacity(0.12),
                            foreground: Color.secondary
                        )
                    }
                }
            },
            actions: {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(SettingsCompactIconButtonStyle())
                .help(localized("Add to Dictionary"))

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(SettingsCompactIconButtonStyle())
                .help(localized("Ignore"))
            }
        )
    }
}

enum DictionaryDialog: Identifiable {
    case create(categoryID: UUID?)
    case edit(DictionaryEntry)

    var id: String {
        switch self {
        case .create(let categoryID):
            return "create-\(categoryID?.uuidString ?? "default")"
        case .edit(let entry):
            return "edit-\(entry.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .create:
            return localized("Create Dictionary Term")
        case .edit:
            return localized("Edit Dictionary Term")
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .create:
            return localized("Create")
        case .edit:
            return localized("Save")
        }
    }
}

enum DictionaryCategoryDialog: Identifiable {
    case create
    case edit(DictionaryCategory)

    var id: String {
        switch self {
        case .create:
            return "create-category"
        case .edit(let category):
            return "edit-category-\(category.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .create:
            return localized("Create Dictionary Category")
        case .edit:
            return localized("Edit Dictionary Category")
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .create:
            return localized("Create")
        case .edit:
            return localized("Save")
        }
    }
}

struct DictionaryCategoryDialogView: View {
    let dialog: DictionaryCategoryDialog
    let onCancel: () -> Void
    let onSave: (String) throws -> Void

    @State private var draftName: String
    @State private var errorMessage: String?

    init(
        dialog: DictionaryCategoryDialog,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String) throws -> Void
    ) {
        self.dialog = dialog
        self.onCancel = onCancel
        self.onSave = onSave
        switch dialog {
        case .create:
            _draftName = State(initialValue: "")
        case .edit(let category):
            _draftName = State(initialValue: category.name)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: dialog.title)
                .font(.title3.weight(.semibold))

            TextField(
                "",
                text: $draftName,
                prompt: Text(verbatim: localized("Category Name"))
            )
            .textFieldStyle(.plain)
            .settingsFieldSurface()
            .onSubmit(save)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            SettingsDialogActionRow {
                Button(localized("Cancel")) {
                    onCancel()
                }
                .buttonStyle(SettingsPillButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(dialog.confirmButtonTitle) {
                    save()
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .settingsDialogChrome(width: 420, onClose: onCancel)
    }

    private func save() {
        do {
            try onSave(draftName)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DictionaryListRowContainer<Content: View, Actions: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            content()

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                actions()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
    }
}

private struct DictionaryCapsuleBadge: View {
    let title: Text
    let fill: Color
    let foreground: Color

    init<Title: StringProtocol>(title: Title, fill: Color, foreground: Color) {
        self.title = Text(String(title))
        self.fill = fill
        self.foreground = foreground
    }

    init(title: LocalizedStringKey, fill: Color, foreground: Color) {
        self.title = Text(title)
        self.fill = fill
        self.foreground = foreground
    }

    var body: some View {
        title
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
            .foregroundStyle(foreground)
    }
}

struct DictionaryEditableTagList: View {
    let values: [String]
    let onRemove: (String) -> Void

    var body: some View {
        DictionaryFlexibleTagLayout(tags: values) { value in
            HStack(spacing: 6) {
                Text(value)
                    .lineLimit(1)
                    .textSelection(.enabled)

                Button {
                    onRemove(value)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
            )
        }
    }
}

private struct DictionaryFlexibleTagLayout<Content: View>: View {
    let tags: [String]
    let content: (String) -> Content

    var body: some View {
        GeometryReader { proxy in
            generateContent(in: proxy)
        }
        .frame(minHeight: 10)
    }

    private func generateContent(in proxy: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return ZStack(alignment: .topLeading) {
            ForEach(tags, id: \.self) { tag in
                content(tag)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .alignmentGuide(.leading) { dimension in
                        if abs(width - dimension.width) > proxy.size.width {
                            width = 0
                            height -= dimension.height
                        }
                        let result = width
                        width = tag == tags.last ? 0 : width - dimension.width
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if tag == tags.last {
                            height = 0
                        }
                        return result
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
