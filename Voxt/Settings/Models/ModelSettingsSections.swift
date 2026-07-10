// ModelSettingsSections.swift
// Provides Model Settings Sections for model settings.

import SwiftUI

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

extension ModelSettingsView {
    var translationSettingsCard: some View {
        ModelTaskSettingsCard(
            title: LocalizedStringKey(localized("Translation")),
            providerPickerTitle: LocalizedStringKey(localized("Translation Provider")),
            providerOptions: translationProviderOptions,
            selectedProviderID: $translationModelProviderRaw,
            modelLabelText: translationModelLabelText,
            modelPickerTitle: LocalizedStringKey(localized("Translation Model")),
            modelOptions: translationModelOptions,
            selectedModelBinding: translationModelSelectionBinding,
            modelDisplayText: translationModelDisplayText,
            emptyStateText: translationModelEmptyStateText,
            statusMessage: translationProviderStatusMessage,
            statusIsWarning: translationProviderStatusIsWarning,
            promptTitle: LocalizedStringKey(localized("Translation Prompt")),
            promptText: promptBinding(for: $translationPrompt, kind: .translation),
            defaultPromptText: AppPromptDefaults.text(for: .translation),
            variables: ModelSettingsPromptVariables.translation,
            promptGuidance: PromptAuthoringGuidance.translation
        )
    }

    var rewriteSettingsCard: some View {
        ModelTaskSettingsCard(
            title: LocalizedStringKey(localized("Content Rewrite")),
            providerPickerTitle: LocalizedStringKey(localized("Content Rewrite Provider")),
            providerOptions: rewriteProviderOptions,
            selectedProviderID: $rewriteModelProviderRaw,
            modelLabelText: rewriteModelLabelText,
            modelPickerTitle: LocalizedStringKey(localized("Content Rewrite Model")),
            modelOptions: rewriteModelOptions,
            selectedModelBinding: rewriteModelSelectionBinding,
            modelDisplayText: nil,
            emptyStateText: rewriteModelEmptyStateText,
            statusMessage: nil,
            statusIsWarning: false,
            promptTitle: LocalizedStringKey(localized("Content Rewrite Prompt")),
            promptText: promptBinding(for: $rewritePrompt, kind: .rewrite),
            defaultPromptText: AppPromptDefaults.text(for: .rewrite),
            variables: ModelSettingsPromptVariables.rewrite,
            promptGuidance: PromptAuthoringGuidance.rewrite
        )
    }

    @ViewBuilder
    var mlxModelSection: some View {
        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text(localized("Model"))
                .font(.subheadline.weight(.medium))

            HStack(alignment: .center, spacing: 12) {
                SettingsMenuPicker(
                    selection: $modelRepo,
                    options: mlxModelManager.displayModelsIncludingInstalled().map { model in
                        SettingsMenuOption(value: model.id, title: model.title)
                    },
                    selectedTitle: mlxModelManager.displayTitle(for: modelRepo),
                    width: 260
                )

                Spacer()

                Button(localized("Configure")) {
                    activeLocalASRConfigurationTarget = .mlx(repo: modelRepo)
                }
                .buttonStyle(SettingsPillButtonStyle())
            }

            Text(modelLocalizedDescription(for: modelRepo))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(mlxConfigurationSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ModelTableView(title: LocalizedStringKey(localized("Models")), rows: mlxRows, viewportHeight: 320)

        if let downloadStatus = mlxInstallSnapshot(for: modelRepo).downloadStatus {
            ModelDownloadStatusView(status: downloadStatus)
        }
    }

    @ViewBuilder
    func localASRConfigurationSheet(for target: LocalASRConfigurationTarget) -> some View {
        switch target {
        case .mlx(let repo):
            MLXASRConfigurationSheetView(
                modelRepo: repo,
                modelTitle: mlxModelManager.displayTitle(for: repo),
                family: MLXModelFamily.family(for: repo),
                hintSettings: asrHintSettingsBinding(for: .mlxAudio),
                tuningSettings: mlxLocalTuningSettingsBinding(for: repo),
                userLanguageCodes: selectedUserLanguageCodes
            ) {
                activeLocalASRConfigurationTarget = nil
            }
        case .sherpaOnnx(let modelID):
            SherpaOnnxASRConfigurationSheetView(
                modelID: modelID,
                option: SherpaOnnxModelCatalog.option(for: modelID),
                hintSettings: asrHintSettingsBinding(for: .sherpaOnnx),
                tuningSettings: sherpaOnnxLocalTuningSettingsBinding(for: modelID),
                userLanguageCodes: selectedUserLanguageCodes
            ) {
                activeLocalASRConfigurationTarget = nil
            }
        }
    }

    @ViewBuilder
    var appleIntelligenceSection: some View {
        Divider()

        if appleIntelligenceAvailable {
            ResettablePromptSection(
                title: LocalizedStringKey(localized("System Prompt")),
                text: promptBinding(for: $systemPrompt, kind: .enhancement),
                defaultText: AppPromptDefaults.text(for: .enhancement),
                variables: ModelSettingsPromptVariables.enhancement,
                guidance: PromptAuthoringGuidance.enhancement,
                variablesTitle: PromptAuthoringGuidance.optionalVariablesTitle
            )

            HStack {
                Text(localized("Customise how Apple Intelligence enhances your transcriptions."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(localized("Apple Intelligence is not available on this Mac, so system prompt enhancement cannot be used."))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    var customLLMSection: some View {
        Divider()

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(localized("Local LLM Configuration"))
                    .font(.subheadline.weight(.medium))
                Text(customLLMGenerationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if customLLMManager.isModelDownloaded(repo: customLLMRepo) {
                Button(localized("Configure")) {
                    isCustomLLMConfigurationPresented = true
                }
                .buttonStyle(SettingsPillButtonStyle())
            }
        }

        ResettablePromptSection(
            title: LocalizedStringKey(localized("System Prompt")),
            text: promptBinding(for: $systemPrompt, kind: .enhancement),
            defaultText: AppPromptDefaults.text(for: .enhancement),
            variables: ModelSettingsPromptVariables.enhancement
        )

        ModelTableView(title: LocalizedStringKey(localized("Custom LLM Models")), rows: customLLMRows, viewportHeight: 260)

        if let downloadStatus = customLLMInstallSnapshot(for: customLLMRepo).downloadStatus {
            ModelDownloadStatusView(status: downloadStatus)
        }
    }

    @ViewBuilder
    var remoteASRSection: some View {
        Divider()

        Text(localized("Remote ASR Providers"))
            .font(.subheadline.weight(.medium))

        ModelTableView(title: LocalizedStringKey(localized("Providers")), rows: remoteASRRows, viewportHeight: 220)
    }

    @ViewBuilder
    var remoteLLMSection: some View {
        Divider()

        ResettablePromptSection(
            title: LocalizedStringKey(localized("System Prompt")),
            text: promptBinding(for: $systemPrompt, kind: .enhancement),
            defaultText: AppPromptDefaults.text(for: .enhancement),
            variables: ModelSettingsPromptVariables.enhancement
        )

        HStack {
            Text(localized("Configure a remote provider and model, then click Use."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ModelTableView(title: LocalizedStringKey(localized("Remote LLM Providers")), rows: remoteLLMRows, viewportHeight: 280)
    }
}

private struct MLXASRConfigurationSheetView: View {
    private static let dictionaryTermsVariable = [
        PromptTemplateVariableDescriptor(
            token: AppPreferenceKey.asrDictionaryTermsTemplateVariable,
            tipKey: "Template tip {{DICTIONARY_TERMS}}"
        )
    ]

    let modelRepo: String
    let modelTitle: String
    let family: MLXModelFamily
    @Binding var hintSettings: ASRHintSettings
    @Binding var tuningSettings: MLXLocalTuningSettings
    @State private var mossUsageScope: MossASRUsageScope = .dictation
    let userLanguageCodes: [String]
    let onDone: () -> Void

    private var mainLanguageSummary: String {
        ASRHintResolver.selectedLanguageSummary(userLanguageCodes)
    }

    private var secondaryLanguageSummary: String {
        ASRHintResolver.secondaryLanguageSummary(userLanguageCodes)
    }

    private var resolvedLanguage: String {
        guard hintSettings.followsUserMainLanguage else {
            return AppLocalization.localizedString("Automatic")
        }
        return ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: hintSettings,
            userLanguageCodes: userLanguageCodes,
            mlxModelRepo: modelRepo
        ).language ?? AppLocalization.localizedString("Automatic")
    }

    private var resolvedLanguageCode: String? {
        guard hintSettings.followsUserMainLanguage else { return nil }
        return ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: hintSettings,
            userLanguageCodes: userLanguageCodes,
            mlxModelRepo: modelRepo
        ).language
    }

    private var canaryTaskLanguages: (source: String, target: String) {
        CanaryLanguageSupport.resolvedTaskLanguages(
            mode: tuningSettings.canaryTaskMode,
            sourceLanguage: resolvedLanguageCode,
            translationLanguage: tuningSettings.canaryTranslationLanguage
        )
    }

    private var senseVoiceSupportedLanguageSummary: String {
        AppLocalization.localizedString("Automatic, zh, en, yue, ja, ko")
    }

    private var canaryTranslationLanguageOptions: [SettingsMenuOption<String>] {
        CanaryLanguageSupport.translationTargetCodes.map {
            SettingsMenuOption(value: $0, title: CanaryLanguageSupport.title(for: $0))
        }
    }

    private var mossOutputModeBinding: Binding<MossASROutputMode> {
        Binding(
            get: {
                switch mossUsageScope {
                case .dictation: tuningSettings.mossOutputMode
                case .meeting: tuningSettings.mossMeetingOutputMode
                }
            },
            set: { mode in
                switch mossUsageScope {
                case .dictation: tuningSettings.mossOutputMode = mode
                case .meeting: tuningSettings.mossMeetingOutputMode = mode
                }
            }
        )
    }

    private var mossHotwordsBinding: Binding<String> {
        Binding(
            get: {
                switch mossUsageScope {
                case .dictation: tuningSettings.mossHotwords
                case .meeting: tuningSettings.mossMeetingHotwords
                }
            },
            set: { value in
                switch mossUsageScope {
                case .dictation: tuningSettings.mossHotwords = value
                case .meeting: tuningSettings.mossMeetingHotwords = value
                }
            }
        )
    }

    private var mossCustomPromptBinding: Binding<String> {
        Binding(
            get: {
                switch mossUsageScope {
                case .dictation: tuningSettings.mossCustomPrompt
                case .meeting: tuningSettings.mossMeetingCustomPrompt
                }
            },
            set: { value in
                switch mossUsageScope {
                case .dictation: tuningSettings.mossCustomPrompt = value
                case .meeting: tuningSettings.mossMeetingCustomPrompt = value
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("MLX ASR Configuration"))
                .font(.title3.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(modelTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if family.supportsRecognitionPreset {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localized("Preset"))
                                .font(.subheadline.weight(.medium))
                            SettingsMenuPicker(
                                selection: Binding(
                                    get: { tuningSettings.preset.rawValue },
                                    set: { rawValue in
                                        guard let preset = LocalASRRecognitionPreset(rawValue: rawValue) else { return }
                                        tuningSettings.preset = preset
                                    }
                                ),
                                options: LocalASRRecognitionPreset.allCases.map {
                                    SettingsMenuOption(value: $0.rawValue, title: $0.title)
                                },
                                selectedTitle: tuningSettings.preset.title,
                                width: 220
                            )
                            Text(tuningSettings.preset.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if family.supportsWhisperTemperature {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(localized("Temperature"))
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(String(format: "%.2f", tuningSettings.whisperTemperature))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $tuningSettings.whisperTemperature, in: 0...1, step: 0.05)
                            Text(localized("Higher values allow more variation. Keep this near 0 for deterministic dictation."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if family.supportsSharedLanguageRouting {
                        Toggle(localized("Follow User Main Language"), isOn: $hintSettings.followsUserMainLanguage)
                            .toggleStyle(.switch)

                        HStack(alignment: .top, spacing: 16) {
                            localInfoRow(label: localized("Primary language"), value: mainLanguageSummary)
                            localInfoRow(label: localized("Resolved language"), value: resolvedLanguage)
                        }

                        localInfoRow(label: localized("Other languages"), value: secondaryLanguageSummary)
                    }

                    if family == .senseVoice {
                        localInfoRow(
                            label: localized("Supported routes"),
                            value: senseVoiceSupportedLanguageSummary
                        )
                        Text(localized("SenseVoice only accepts explicit language routing for zh, en, yue, ja, and ko here. Any other primary language falls back to Automatic."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if family == .mossTranscribeDiarize {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localized("Usage"))
                                .font(.subheadline.weight(.medium))
                            Picker(localized("Usage"), selection: $mossUsageScope) {
                                ForEach(MossASRUsageScope.allCases) { scope in
                                    Text(scope.title).tag(scope)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(localized("Output Format"))
                                .font(.subheadline.weight(.medium))
                            SettingsMenuPicker(
                                selection: Binding(
                                    get: { mossOutputModeBinding.wrappedValue.rawValue },
                                    set: { rawValue in
                                        guard let mode = MossASROutputMode(rawValue: rawValue) else { return }
                                        mossOutputModeBinding.wrappedValue = mode
                                    }
                                ),
                                options: MossASROutputMode.allCases.map {
                                    SettingsMenuOption(value: $0.rawValue, title: $0.title)
                                },
                                selectedTitle: mossOutputModeBinding.wrappedValue.title,
                                width: 240
                            )
                            Text(mossOutputModeBinding.wrappedValue.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(localized("Hotwords"))
                            .font(.subheadline.weight(.medium))
                        PromptEditorView(
                            text: mossHotwordsBinding,
                            height: 90,
                            variables: Self.dictionaryTermsVariable
                        )
                        Text(localized("Names and terms are appended to the MOSS prompt using its official Hotwords format."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if mossOutputModeBinding.wrappedValue == .customPrompt {
                            Text(localized("Recognition Prompt"))
                                .font(.subheadline.weight(.medium))
                            PromptEditorView(text: mossCustomPromptBinding, height: 120)
                            Text(localized("This instruction replaces the standard MOSS transcription format prompt."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if family == .cohereTranscribe {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localized("Long Audio Segmentation"))
                                .font(.subheadline.weight(.medium))
                            SettingsMenuPicker(
                                selection: Binding(
                                    get: { tuningSettings.cohereLongFormStrategy.rawValue },
                                    set: { rawValue in
                                        guard let strategy = CohereLongFormStrategy(rawValue: rawValue) else { return }
                                        tuningSettings.cohereLongFormStrategy = strategy
                                    }
                                ),
                                options: CohereLongFormStrategy.allCases.map {
                                    SettingsMenuOption(value: $0.rawValue, title: $0.title)
                                },
                                selectedTitle: tuningSettings.cohereLongFormStrategy.title,
                                width: 220
                            )
                            Text(tuningSettings.cohereLongFormStrategy.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Toggle(localized("Punctuation and Capitalization"), isOn: $tuningSettings.cohereUsePunctuation)
                            .toggleStyle(.switch)
                        SettingsIntegerStepperField(
                            title: localized("Max Output Tokens"),
                            value: $tuningSettings.cohereMaxTokens,
                            range: 32...2048,
                            step: 32,
                            help: localized("Increase this only when long recordings are being truncated.")
                        )
                        decodingTemperatureControl(value: $tuningSettings.cohereTemperature)
                    }

                    if family == .canary {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localized("Task"))
                                .font(.subheadline.weight(.medium))
                            SettingsMenuPicker(
                                selection: Binding(
                                    get: { tuningSettings.canaryTaskMode.rawValue },
                                    set: { rawValue in
                                        guard let mode = CanaryTaskMode(rawValue: rawValue) else { return }
                                        tuningSettings.canaryTaskMode = mode
                                    }
                                ),
                                options: CanaryTaskMode.allCases.map {
                                    SettingsMenuOption(value: $0.rawValue, title: $0.title)
                                },
                                selectedTitle: tuningSettings.canaryTaskMode.title,
                                width: 240
                            )
                            Text(localized("Canary supports transcription in 25 European languages and translation only when the source or target is English."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if tuningSettings.canaryTaskMode == .translateFromEnglish {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(localized("Translation Language"))
                                    .font(.subheadline.weight(.medium))
                                SettingsMenuPicker(
                                    selection: $tuningSettings.canaryTranslationLanguage,
                                    options: canaryTranslationLanguageOptions,
                                    selectedTitle: CanaryLanguageSupport.title(for: tuningSettings.canaryTranslationLanguage),
                                    width: 240
                                )
                            }
                        }

                        HStack(alignment: .top, spacing: 16) {
                            localInfoRow(
                                label: localized("Task source"),
                                value: CanaryLanguageSupport.title(for: canaryTaskLanguages.source)
                            )
                            localInfoRow(
                                label: localized("Task output"),
                                value: CanaryLanguageSupport.title(for: canaryTaskLanguages.target)
                            )
                        }

                        Toggle(localized("Punctuation and Capitalization"), isOn: $tuningSettings.canaryUsePunctuation)
                            .toggleStyle(.switch)
                        SettingsIntegerStepperField(
                            title: localized("Max Output Tokens"),
                            value: $tuningSettings.canaryMaxTokens,
                            range: 32...2048,
                            step: 32,
                            help: localized("Increase this only when transcription or translation is being truncated.")
                        )
                        decodingTemperatureControl(value: $tuningSettings.canaryTemperature)
                    }

                    if family == .moonshine {
                        localInfoRow(label: localized("Model language"), value: localized("English"))
                        SettingsIntegerStepperField(
                            title: localized("Max Output Tokens"),
                            value: $tuningSettings.moonshineMaxTokens,
                            range: 32...2048,
                            step: 32,
                            help: localized("Increase this only when long utterances are being truncated.")
                        )
                        decodingTemperatureControl(value: $tuningSettings.moonshineTemperature)
                    }

                    if family == .mmsCTC {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(localized("MMS Adapter Language"))
                                .font(.subheadline.weight(.medium))
                            TextField("eng", text: $tuningSettings.mmsLanguageCode)
                                .textFieldStyle(.plain)
                                .modifier(
                                    SettingsFieldSurfaceModifier(
                                        width: 140,
                                        minHeight: 30,
                                        horizontalPadding: 8,
                                        alignment: .leading
                                    )
                                )
                            Text(localized("Use the checkpoint's ISO 639-3 adapter code, for example eng, cmn, jpn, deu, or fra."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if family == .wav2vec2CTC {
                        localInfoRow(label: localized("Model language"), value: localized("English"))
                        Text(localized("This checkpoint uses greedy CTC decoding and does not expose sampling or prompt controls."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if family == .lasrCTC {
                        Text(localized("LASR uses greedy CTC decoding. Language and vocabulary are defined by the checkpoint."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if family.supportsContextBias {
                        Text(localized("Recognition Context"))
                            .font(.subheadline.weight(.medium))
                        PromptEditorView(text: $tuningSettings.qwenContextBias, height: 110, variables: Self.dictionaryTermsVariable)
                        Text(localized("Concise names, terms, and product vocabulary."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if family.supportsPromptBias {
                        Text(localized("Recognition Prompt"))
                            .font(.subheadline.weight(.medium))
                        PromptEditorView(text: $tuningSettings.granitePromptBias, height: 110, variables: Self.dictionaryTermsVariable)
                        Text(localized("Recognition-focused spelling and terminology preferences."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if family.supportsITN {
                        Toggle(localized("Enable ITN"), isOn: $tuningSettings.senseVoiceUseITN)
                            .toggleStyle(.switch)
                        Text(localized("ITN lets SenseVoice normalize spoken numbers, dates, and similar expressions into written form."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if family == .generic {
                        Text(localized("This model family only exposes preset and language controls."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if family == .senseVoice {
                        Text(localized("SenseVoice only exposes language routing and ITN here. Recognition presets are not used by this model path."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 4)
            }
            .frame(maxHeight: SettingsUIStyle.modelConfigurationScrollMaxHeight)

            SettingsDialogActionRow {
                Button(localized("Reset to Default")) {
                    hintSettings = ASRHintSettingsStore.defaultSettings(for: .mlxAudio)
                    tuningSettings = MLXLocalTuningSettings.defaults(for: .balanced, family: family)
                }
                .buttonStyle(SettingsPillButtonStyle())
            } trailing: {
                Button(localized("Done")) {
                    onDone()
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .settingsDialogChrome(
            width: SettingsUIStyle.modelConfigurationDialogWidth,
            maxHeight: SettingsUIStyle.modelConfigurationDialogMaxHeight,
            onClose: onDone
        )
    }

    private func localInfoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func decodingTemperatureControl(value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(localized("Temperature"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1, step: 0.05)
            Text(localized("Keep this at 0 for deterministic decoding; higher values sample alternative tokens."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SherpaOnnxASRConfigurationSheetView: View {
    private static let dictionaryTermsVariable = [
        PromptTemplateVariableDescriptor(
            token: AppPreferenceKey.asrDictionaryTermsTemplateVariable,
            tipKey: "Template tip {{DICTIONARY_TERMS}}"
        )
    ]

    let modelID: SherpaOnnxModelID
    let option: SherpaOnnxModelOption
    @Binding var hintSettings: ASRHintSettings
    @Binding var tuningSettings: SherpaOnnxLocalTuningSettings
    let userLanguageCodes: [String]
    let onDone: () -> Void

    private var mainLanguageSummary: String {
        ASRHintResolver.selectedLanguageSummary(userLanguageCodes)
    }

    private var secondaryLanguageSummary: String {
        ASRHintResolver.secondaryLanguageSummary(userLanguageCodes)
    }

    private var resolvedLanguage: String {
        guard hintSettings.followsUserMainLanguage else {
            return AppLocalization.localizedString("Automatic")
        }
        return ASRHintResolver.resolve(
            target: .sherpaOnnx,
            settings: hintSettings,
            userLanguageCodes: userLanguageCodes
        ).language ?? AppLocalization.localizedString("Automatic")
    }

    private var supportedLanguageSummary: String {
        switch option.kind {
        case .fireRedASRCTC:
            return AppLocalization.localizedString("Automatic, zh, en")
        case .funASRNano:
            return AppLocalization.localizedString("Automatic, zh, en, yue, ja, ko")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Sherpa ASR Configuration"))
                .font(.title3.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(option.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    localInfoRow(label: localized("Supported routes"), value: supportedLanguageSummary)

                    if option.kind == .funASRNano {
                        Toggle(localized("Follow User Main Language"), isOn: $hintSettings.followsUserMainLanguage)
                            .toggleStyle(.switch)

                        HStack(alignment: .top, spacing: 16) {
                            localInfoRow(label: localized("Primary language"), value: mainLanguageSummary)
                            localInfoRow(label: localized("Resolved language"), value: resolvedLanguage)
                        }

                        localInfoRow(label: localized("Other languages"), value: secondaryLanguageSummary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(localized("Recognition Context"))
                                .font(.subheadline.weight(.medium))
                            PromptEditorView(text: $tuningSettings.contextBias, height: 110, variables: Self.dictionaryTermsVariable)
                            Text(localized("Concise names, terms, and product vocabulary."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsIntegerStepperField(
                        title: localized("Threads"),
                        value: $tuningSettings.numThreads,
                        range: 1...8,
                        step: 1,
                        help: localized("Higher values can improve offline decode speed, but also use more CPU.")
                    )

                    switch option.kind {
                    case .fireRedASRCTC:
                        EmptyView()
                    case .funASRNano:
                        funASRControls
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 4)
            }
            .frame(maxHeight: SettingsUIStyle.modelConfigurationScrollMaxHeight)

            SettingsDialogActionRow {
                Button(localized("Reset to Default")) {
                    hintSettings = ASRHintSettingsStore.defaultSettings(for: .sherpaOnnx)
                    tuningSettings = SherpaOnnxLocalTuningSettings.defaults(for: option.kind)
                }
                .buttonStyle(SettingsPillButtonStyle())
            } trailing: {
                Button(localized("Done")) {
                    onDone()
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .settingsDialogChrome(
            width: SettingsUIStyle.modelConfigurationDialogWidth,
            maxHeight: SettingsUIStyle.modelConfigurationDialogMaxHeight,
            onClose: onDone
        )
    }

    private var funASRControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(localized("Enable ITN"), isOn: $tuningSettings.funASRUseITN)
                .toggleStyle(.switch)
            Text(localized("ITN normalizes spoken numbers, dates, and similar expressions into written form."))
                .font(.caption)
                .foregroundStyle(.secondary)

            SettingsIntegerStepperField(
                title: localized("Max New Tokens"),
                value: $tuningSettings.funASRMaxNewTokens,
                range: 64...2048,
                step: 64,
                help: localized("Use a larger value only for long utterances that are being truncated.")
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(localized("Top P"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(String(format: "%.2f", tuningSettings.funASRTopP))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $tuningSettings.funASRTopP, in: 0.1...1.0, step: 0.05)
                Text(localized("Keep this conservative for stable dictation output."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func localInfoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct SettingsIntegerStepperField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let help: String

    private var clampedValue: Binding<Int> {
        Binding(
            get: { value },
            set: { value = clamped($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    TextField("", value: clampedValue, formatter: Self.integerFormatter)
                        .font(.caption.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.plain)
                        .modifier(
                            SettingsFieldSurfaceModifier(
                                width: 72,
                                minHeight: 28,
                                horizontalPadding: 8,
                                alignment: .trailing
                            )
                        )
                        .onSubmit {
                            value = clamped(value)
                        }

                    Stepper("", value: clampedValue, in: range, step: step)
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                }
            }

            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            value = clamped(value)
        }
    }

    private func clamped(_ candidate: Int) -> Int {
        min(max(candidate, range.lowerBound), range.upperBound)
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = 0
        return formatter
    }()
}
