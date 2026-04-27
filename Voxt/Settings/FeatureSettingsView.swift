import SwiftUI

struct FeatureSettingsView: View {
    let selectedTab: FeatureSettingsTab
    let navigationRequest: SettingsNavigationRequest?
    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var whisperModelManager: WhisperKitModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager

    @AppStorage(AppPreferenceKey.featureSettings) private var featureSettingsRaw = ""
    @AppStorage(AppPreferenceKey.remoteASRProviderConfigurations) private var remoteASRProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.remoteLLMProviderConfigurations) private var remoteLLMProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.userMainLanguageCodes) private var userMainLanguageCodesRaw = UserMainLanguageOption.defaultStoredSelectionValue
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue

    @State var featureSettings = FeatureSettingsStore.load()
    @State var selectorSheet: FeatureModelSelectorSheet?
    @State var interactionSoundPlayer = InteractionSoundPlayer()

    var body: some View {
        Group {
            switch selectedTab {
            case .transcription:
                transcriptionContent
            case .note:
                noteContent
            case .translation:
                translationContent
            case .rewrite:
                rewriteContent
            case .appEnhancement:
                AppEnhancementSettingsView(navigationRequest: navigationRequest)
            case .meeting:
                meetingContent
            }
        }
        .sheet(item: $selectorSheet) { sheet in
            FeatureModelSelectorDialog(
                title: sheet.title,
                entries: selectorEntries(for: sheet),
                selectedID: selectedSelectionID(for: sheet),
                onSelect: { selectionID in
                    applySelection(selectionID, for: sheet)
                }
            )
        }
        .onAppear(perform: reloadFeatureSettings)
        .onChange(of: featureSettingsRaw) { _, _ in
            reloadFeatureSettings()
        }
        .id(interfaceLanguageRaw)
    }

    func binding<Value>(
        get: @escaping () -> Value,
        set: @escaping (Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: get,
            set: { newValue in
                set(newValue)
                FeatureSettingsStore.save(featureSettings, defaults: .standard)
                reloadFeatureSettings()
            }
        )
    }

    func reloadFeatureSettings() {
        featureSettings = FeatureSettingsStore.load(defaults: .standard)
    }

    var selectorBuilder: FeatureModelCatalogBuilder {
        FeatureModelCatalogBuilder(
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager,
            customLLMManager: customLLMManager,
            featureSettings: featureSettings,
            remoteASRProviderConfigurationsRaw: remoteASRProviderConfigurationsRaw,
            remoteLLMProviderConfigurationsRaw: remoteLLMProviderConfigurationsRaw,
            appleIntelligenceAvailable: appleIntelligenceAvailable,
            primaryUserLanguageCode: selectedUserLanguageCodes.first
        )
    }

    var selectedUserLanguageCodes: [String] {
        UserMainLanguageOption.storedSelection(from: userMainLanguageCodesRaw)
    }

    func selectedSelectionID(for sheet: FeatureModelSelectorSheet) -> FeatureModelSelectionID {
        switch sheet {
        case .transcriptionASR:
            return featureSettings.transcription.asrSelectionID
        case .transcriptionLLM:
            return featureSettings.transcription.llmSelectionID
        case .transcriptionNoteTitle:
            return featureSettings.transcription.notes.titleModelSelectionID
        case .translationASR:
            return featureSettings.translation.asrSelectionID
        case .translationModel:
            return featureSettings.translation.modelSelectionID
        case .rewriteASR:
            return featureSettings.rewrite.asrSelectionID
        case .rewriteLLM:
            return featureSettings.rewrite.llmSelectionID
        case .meetingASR:
            return featureSettings.meeting.asrSelectionID
        case .meetingSummary:
            return featureSettings.meeting.summaryModelSelectionID
        }
    }

    func applySelection(_ selectionID: FeatureModelSelectionID, for sheet: FeatureModelSelectorSheet) {
        FeatureSettingsStore.update(defaults: .standard) { settings in
            switch sheet {
            case .transcriptionASR:
                settings.transcription.asrSelectionID = selectionID
            case .transcriptionLLM:
                settings.transcription.llmSelectionID = selectionID
            case .transcriptionNoteTitle:
                settings.transcription.notes.titleModelSelectionID = selectionID
            case .translationASR:
                settings.translation.asrSelectionID = selectionID
            case .translationModel:
                settings.translation.modelSelectionID = selectionID
            case .rewriteASR:
                settings.rewrite.asrSelectionID = selectionID
            case .rewriteLLM:
                settings.rewrite.llmSelectionID = selectionID
            case .meetingASR:
                settings.meeting.asrSelectionID = selectionID
            case .meetingSummary:
                settings.meeting.summaryModelSelectionID = selectionID
            }
        }
        reloadFeatureSettings()
    }

    func selectorEntries(for sheet: FeatureModelSelectorSheet) -> [FeatureModelSelectorEntry] {
        selectorBuilder.entries(for: sheet)
    }

    func asrSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        selectorBuilder.asrSelectionSummary(selectionID)
    }

    func llmSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        selectorBuilder.llmSelectionSummary(selectionID)
    }

    func translationSelectionSummary(_ selectionID: FeatureModelSelectionID) -> String {
        selectorBuilder.translationSelectionSummary(selectionID)
    }

    var appleIntelligenceAvailable: Bool {
        if #available(macOS 26.0, *) {
            return TextEnhancer.isAvailable
        }
        return false
    }
}
