import SwiftUI

private func localizedHistoryDetail(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct HistoryDetailSheetContent: View {
    @Environment(\.dismiss) private var dismiss

    let locale: Locale
    @StateObject private var viewModel: TranscriptionDetailViewModel

    init(
        entry: TranscriptionHistoryEntry,
        audioURL: URL?,
        locale: Locale
    ) {
        self.locale = locale

        let manualCorrectionHandler: TranscriptionDetailViewModel.ManualCorrectionHandler? = { entry, correctedText in
            guard let appDelegate = AppDelegate.shared else {
                throw NSError(
                    domain: "Voxt.HistoryDetail",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: localizedHistoryDetail("Unable to access the application context.")]
                )
            }
            return try await appDelegate.applyManualDictionaryCorrection(
                entry: entry,
                correctedText: correctedText
            )
        }

        _viewModel = StateObject(
            wrappedValue: TranscriptionDetailViewModel(
                entry: entry,
                audioURL: audioURL,
                followUpStatusProvider: { _ in
                    TranscriptionFollowUpProviderStatus(isAvailable: false, message: "")
                },
                followUpAnswerer: { _, _, _ in
                    throw NSError(
                        domain: "Voxt.HistoryDetail",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: localizedHistoryDetail("Follow-up is unavailable in this view.")]
                    )
                },
                followUpPersistence: { _, _ in nil },
                manualCorrectionHandler: manualCorrectionHandler
            )
        )
    }

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
                viewModel: viewModel,
                locale: locale,
                style: .window
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}
