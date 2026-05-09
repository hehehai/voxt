import SwiftUI

private func localizedHistoryDetail(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct HistoryDetailSheetContent: View {
    @Environment(\.dismiss) private var dismiss

    let entry: TranscriptionHistoryEntry
    let audioURL: URL?
    let locale: Locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(localizedHistoryDetail("History Details"))
                    .font(.title3.weight(.semibold))

                Spacer(minLength: 12)

                Button(localizedHistoryDetail("Close")) {
                    dismiss()
                }
                .buttonStyle(SettingsPillButtonStyle())
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            TranscriptionDetailContentView(
                entry: entry,
                audioURL: audioURL,
                locale: locale,
                style: .window
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}
