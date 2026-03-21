import SwiftUI
import AppKit
import Combine

struct ModelSettingsView: View {
    @AppStorage(AppPreferenceKey.transcriptionEngine) var engineRaw = TranscriptionEngine.mlxAudio.rawValue
    @AppStorage(AppPreferenceKey.enhancementMode) var enhancementModeRaw = EnhancementMode.off.rawValue
    @AppStorage(AppPreferenceKey.enhancementSystemPrompt) var systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
    @AppStorage(AppPreferenceKey.translationSystemPrompt) var translationPrompt = AppPreferenceKey.defaultTranslationPrompt
    @AppStorage(AppPreferenceKey.rewriteSystemPrompt) var rewritePrompt = AppPreferenceKey.defaultRewritePrompt
    @AppStorage(AppPreferenceKey.mlxModelRepo) var modelRepo = MLXModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.whisperModelID) var whisperModelID = WhisperKitModelManager.defaultModelID
    @AppStorage(AppPreferenceKey.whisperTemperature) var whisperTemperature = 0.0
    @AppStorage(AppPreferenceKey.whisperVADEnabled) var whisperVADEnabled = true
    @AppStorage(AppPreferenceKey.whisperTimestampsEnabled) var whisperTimestampsEnabled = false
    @AppStorage(AppPreferenceKey.whisperRealtimeEnabled) var whisperRealtimeEnabled = true
    @AppStorage(AppPreferenceKey.customLLMModelRepo) var customLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationCustomLLMModelRepo) var translationCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.rewriteCustomLLMModelRepo) var rewriteCustomLLMRepo = CustomLLMModelManager.defaultModelRepo
    @AppStorage(AppPreferenceKey.translationModelProvider) var translationModelProviderRaw = TranslationModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.translationFallbackModelProvider) var translationFallbackModelProviderRaw = TranslationModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.rewriteModelProvider) var rewriteModelProviderRaw = RewriteModelProvider.customLLM.rawValue
    @AppStorage(AppPreferenceKey.translationTargetLanguage) var translationTargetLanguageRaw = TranslationTargetLanguage.english.rawValue
    @AppStorage(AppPreferenceKey.remoteASRSelectedProvider) var remoteASRSelectedProviderRaw = RemoteASRProvider.openAIWhisper.rawValue
    @AppStorage(AppPreferenceKey.remoteASRProviderConfigurations) var remoteASRProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.asrHintSettings) var asrHintSettingsRaw = ASRHintSettingsStore.defaultStoredValue()
    @AppStorage(AppPreferenceKey.userMainLanguageCodes) var userMainLanguageCodesRaw = UserMainLanguageOption.defaultStoredSelectionValue
    @AppStorage(AppPreferenceKey.remoteLLMSelectedProvider) var remoteLLMSelectedProviderRaw = RemoteLLMProvider.openAI.rawValue
    @AppStorage(AppPreferenceKey.remoteLLMProviderConfigurations) var remoteLLMProviderConfigurationsRaw = ""
    @AppStorage(AppPreferenceKey.translationRemoteLLMProvider) var translationRemoteLLMProviderRaw = ""
    @AppStorage(AppPreferenceKey.rewriteRemoteLLMProvider) var rewriteRemoteLLMProviderRaw = ""
    @AppStorage(AppPreferenceKey.useHfMirror) var useHfMirror = false
    @AppStorage(AppPreferenceKey.interfaceLanguage) var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue

    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var whisperModelManager: WhisperKitModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager
    let missingConfigurationIssues: [ConfigurationTransferManager.MissingConfigurationIssue]

    @State var showMirrorInfo = false
    @State var editingASRProvider: RemoteASRProvider?
    @State var editingLLMProvider: RemoteLLMProvider?
    @State var isASRHintSettingsPresented = false
    @State var isWhisperConfigPresented = false

    let modelStateRefreshTimer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    var selectedEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: engineRaw) ?? .mlxAudio
    }

    var selectedEnhancementMode: EnhancementMode {
        EnhancementMode(rawValue: enhancementModeRaw) ?? .off
    }

    var selectedRemoteASRProvider: RemoteASRProvider {
        RemoteASRProvider(rawValue: remoteASRSelectedProviderRaw) ?? .openAIWhisper
    }

    var selectedRemoteLLMProvider: RemoteLLMProvider {
        RemoteLLMProvider(rawValue: remoteLLMSelectedProviderRaw) ?? .openAI
    }

    var selectedTranslationModelProvider: TranslationModelProvider {
        TranslationModelProvider(rawValue: translationModelProviderRaw) ?? .customLLM
    }

    var selectedRewriteModelProvider: RewriteModelProvider {
        RewriteModelProvider(rawValue: rewriteModelProviderRaw) ?? .customLLM
    }

    var selectedTranslationFallbackModelProvider: TranslationModelProvider {
        TranslationProviderResolver.sanitizedFallbackProvider(
            TranslationModelProvider(rawValue: translationFallbackModelProviderRaw) ?? .customLLM
        )
    }

    var selectedTranslationTargetLanguage: TranslationTargetLanguage {
        TranslationTargetLanguage(rawValue: translationTargetLanguageRaw) ?? .english
    }

    var remoteASRConfigurations: [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(from: remoteASRProviderConfigurationsRaw)
    }

    var remoteLLMConfigurations: [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(from: remoteLLMProviderConfigurationsRaw)
    }

    var selectedASRHintTarget: ASRHintTarget {
        ASRHintTarget.from(engine: selectedEngine, remoteProvider: selectedRemoteASRProvider)
    }

    var selectedUserLanguageCodes: [String] {
        UserMainLanguageOption.storedSelection(from: userMainLanguageCodesRaw)
    }

    var appleIntelligenceAvailable: Bool {
        if #available(macOS 26.0, *) {
            return TextEnhancer.isAvailable
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Engine")
                        .font(.headline)

                    HStack(alignment: .center, spacing: 12) {
                        Picker("Engine", selection: $engineRaw) {
                            ForEach(TranscriptionEngine.allCases) { engine in
                                Text(engine.titleKey).tag(engine.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 240, alignment: .leading)

                        Spacer(minLength: 0)

                        Button("Engine Hint Settings") {
                            isASRHintSettingsPresented = true
                        }
                        .controlSize(.regular)
                        .disabled(selectedEngine == .dictation)
                    }

                    Text(selectedEngine.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if selectedEngine == .mlxAudio {
                        mlxModelSection
                    }

                    if selectedEngine == .whisperKit {
                        whisperModelSection
                    }

                    if selectedEngine == .remote {
                        remoteASRSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Text Enhancement")
                        .font(.headline)

                    Picker("Enhancement", selection: $enhancementModeRaw) {
                        Text(EnhancementMode.off.titleKey).tag(EnhancementMode.off.rawValue)
                        Text(EnhancementMode.appleIntelligence.titleKey).tag(EnhancementMode.appleIntelligence.rawValue)
                        Text(EnhancementMode.customLLM.titleKey).tag(EnhancementMode.customLLM.rawValue)
                        Text(EnhancementMode.remoteLLM.titleKey).tag(EnhancementMode.remoteLLM.rawValue)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)

                    if selectedEnhancementMode == .appleIntelligence {
                        appleIntelligenceSection
                    }

                    if selectedEnhancementMode == .customLLM {
                        customLLMSection
                    }

                    if selectedEnhancementMode == .remoteLLM {
                        remoteLLMSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            translationSettingsCard
            rewriteSettingsCard
            TranscriptionTestSectionView()
        }
        .onAppear(perform: handleOnAppear)
        .onChange(of: modelRepo) { _, newValue in
            let canonicalRepo = MLXModelManager.canonicalModelRepo(newValue)
            if canonicalRepo != newValue {
                modelRepo = canonicalRepo
                return
            }
            mlxModelManager.updateModel(repo: canonicalRepo)
        }
        .onChange(of: whisperModelID) { _, newValue in
            let canonicalModelID = WhisperKitModelManager.canonicalModelID(newValue)
            if canonicalModelID != newValue {
                whisperModelID = canonicalModelID
                return
            }
            whisperModelManager.updateModel(id: canonicalModelID)
        }
        .onChange(of: customLLMRepo) { _, newValue in
            customLLMManager.updateModel(repo: newValue)
            ensureTranslationModelSelectionConsistency()
            ensureRewriteModelSelectionConsistency()
        }
        .onChange(of: translationModelProviderRaw) { _, _ in
            syncTranslationFallbackProvider()
            ensureTranslationModelSelectionConsistency()
        }
        .onChange(of: rewriteModelProviderRaw) { _, _ in
            ensureRewriteModelSelectionConsistency()
        }
        .onChange(of: remoteLLMProviderConfigurationsRaw) { _, _ in
            ensureTranslationModelSelectionConsistency()
            ensureRewriteModelSelectionConsistency()
        }
        .onChange(of: useHfMirror) { _, _ in
            updateMirrorSetting()
        }
        .onReceive(modelStateRefreshTimer) { _ in
            refreshModelInstallStateIfNeeded()
            syncTranslationFallbackProvider()
            ensureTranslationModelSelectionConsistency()
            ensureRewriteModelSelectionConsistency()
        }
        .sheet(item: $editingASRProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: asrCredentialHint(for: provider),
                showsDoubaoFields: provider == .doubaoASR,
                testTarget: .asr(provider),
                configuration: RemoteModelConfigurationStore.resolvedASRConfiguration(
                    provider: provider,
                    stored: remoteASRConfigurations
                )
            ) { updated in
                saveRemoteASRConfiguration(updated)
            }
        }
        .sheet(item: $editingLLMProvider) { provider in
            RemoteProviderConfigurationSheet(
                providerTitle: provider.title,
                credentialHint: nil,
                showsDoubaoFields: false,
                testTarget: .llm(provider),
                configuration: RemoteModelConfigurationStore.resolvedLLMConfiguration(
                    provider: provider,
                    stored: remoteLLMConfigurations
                )
            ) { updated in
                saveRemoteLLMConfiguration(updated)
            }
        }
        .sheet(isPresented: $isASRHintSettingsPresented) {
            ASRHintSettingsSheet(
                target: selectedASRHintTarget,
                userLanguageCodes: selectedUserLanguageCodes,
                mlxModelRepo: selectedEngine == .mlxAudio ? modelRepo : nil,
                initialSettings: resolvedASRHintSettings(for: selectedASRHintTarget)
            ) { updated in
                saveASRHintSettings(updated, for: selectedASRHintTarget)
            }
        }
        .sheet(isPresented: $isWhisperConfigPresented) {
            whisperConfigurationSheet
        }
        .id(interfaceLanguageRaw)
    }
}
