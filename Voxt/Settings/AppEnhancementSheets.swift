import SwiftUI

struct GroupEditorSheet: View {
    let title: String
    let actionTitle: String
    @Binding var name: String
    @Binding var prompt: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.localizedString("Group Name"))
                    .font(.headline)
                TextField(AppLocalization.localizedString("Enter group name"), text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.localizedString("Prompt"))
                    .font(.headline)
                TextEditor(text: $prompt)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .padding(8)
                    .frame(minHeight: 160, alignment: .topLeading)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 6)

            HStack {
                Spacer()
                Button(AppLocalization.localizedString("Cancel"), action: onCancel)
                Button(actionTitle, action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}

struct URLBatchEditorSheet: View {
    let title: String
    let actionTitle: String
    @Binding var text: String
    let errorMessage: String?
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.localizedString("URL Patterns"))
                    .font(.headline)
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .padding(8)
                    .frame(minHeight: 180, alignment: .topLeading)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    )

                Text(AppLocalization.localizedString("Enter one wildcard pattern per line. Examples: google.com/*, *.google.com/*, x.*.google.com/*/doc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 6)

            HStack {
                Spacer()
                Button(AppLocalization.localizedString("Cancel"), action: onCancel)
                Button(actionTitle, action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}

struct URLDetailSheet: View {
    let pattern: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.localizedString("URL Detail"))
                .font(.title3.weight(.semibold))

            Text(pattern)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button(AppLocalization.localizedString("Close"), action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
