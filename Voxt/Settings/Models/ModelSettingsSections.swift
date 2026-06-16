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
                    options: MLXModelManager.availableModels.map { model in
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

                HStack(spacing: 6) {
                    Toggle(localized("Use China mirror"), isOn: $useHfMirror)
                        .toggleStyle(.switch)

                    Button {
                        showMirrorInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showMirrorInfo, arrowEdge: .top) {
                        Text("https://hf-mirror.com/")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
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
    var whisperModelSection: some View {
        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text(localized("Model"))
                .font(.subheadline.weight(.medium))

            HStack(alignment: .center, spacing: 12) {
                SettingsMenuPicker(
                    selection: whisperModelSelectionBinding,
                    options: WhisperKitModelManager.availableModels.map { model in
                        SettingsMenuOption(value: model.id, title: AppLocalization.localizedString(model.title))
                    },
                    selectedTitle: whisperModelManager.displayTitle(for: whisperModelID),
                    width: 260
                )

                Spacer()

                Button(localized("Configure")) {
                    activeLocalASRConfigurationTarget = .whisper(modelID: whisperModelID)
                }
                .buttonStyle(SettingsPillButtonStyle())

                HStack(spacing: 6) {
                    Toggle(localized("Use China mirror"), isOn: $useHfMirror)
                        .toggleStyle(.switch)

                    Button {
                        showMirrorInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showMirrorInfo, arrowEdge: .top) {
                        Text("https://hf-mirror.com/")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
            }

            Text(whisperModelLocalizedDescription(for: whisperModelID))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(whisperConfigurationSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        ModelTableView(title: LocalizedStringKey(localized("Whisper Models")), rows: whisperRows, viewportHeight: 260)

        if let downloadStatus = whisperInstallSnapshot(for: whisperModelID).downloadStatus {
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
        case .whisper:
            WhisperASRConfigurationSheetView(
                hintSettings: asrHintSettingsBinding(for: .whisperKit),
                tuningSettings: whisperLocalTuningSettingsBinding(),
                whisperTemperature: $whisperTemperature,
                whisperVADEnabled: $whisperVADEnabled,
                whisperTimestampsEnabled: $whisperTimestampsEnabled,
                whisperRealtimeEnabled: $whisperRealtimeEnabled,
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

    private var senseVoiceSupportedLanguageSummary: String {
        AppLocalization.localizedString("Automatic, zh, en, yue, ja, ko")
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

                    Toggle(localized("Follow User Main Language"), isOn: $hintSettings.followsUserMainLanguage)
                        .toggleStyle(.switch)

                    HStack(alignment: .top, spacing: 16) {
                        localInfoRow(label: localized("Primary language"), value: mainLanguageSummary)
                        localInfoRow(label: localized("Resolved language"), value: resolvedLanguage)
                    }

                    localInfoRow(label: localized("Other languages"), value: secondaryLanguageSummary)

                    if family == .senseVoice {
                        localInfoRow(
                            label: localized("Supported routes"),
                            value: senseVoiceSupportedLanguageSummary
                        )
                        Text(localized("SenseVoice only accepts explicit language routing for zh, en, yue, ja, and ko here. Any other primary language falls back to Automatic."))
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

                    if !family.supportsContextBias
                        && !family.supportsPromptBias
                        && !family.supportsITN
                    {
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
}

private struct WhisperASRConfigurationSheetView: View {
    private static let dictionaryTermsVariable = [
        PromptTemplateVariableDescriptor(
            token: AppPreferenceKey.asrDictionaryTermsTemplateVariable,
            tipKey: "Template tip {{DICTIONARY_TERMS}}"
        )
    ]

    @Binding var hintSettings: ASRHintSettings
    @Binding var tuningSettings: WhisperLocalTuningSettings
    @Binding var whisperTemperature: Double
    @Binding var whisperVADEnabled: Bool
    @Binding var whisperTimestampsEnabled: Bool
    @Binding var whisperRealtimeEnabled: Bool
    let userLanguageCodes: [String]
    let onDone: () -> Void

    private var mainLanguageSummary: String {
        ASRHintResolver.selectedLanguageSummary(userLanguageCodes)
    }

    private var secondaryLanguageSummary: String {
        ASRHintResolver.secondaryLanguageSummary(userLanguageCodes)
    }

    private var resolvedLanguage: String {
        ASRHintResolver.resolve(
            target: .whisperKit,
            settings: hintSettings,
            userLanguageCodes: userLanguageCodes
        ).language ?? AppLocalization.localizedString("Automatic")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("Whisper Configuration"))
                .font(.title3.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localized("Preset"))
                            .font(.subheadline.weight(.medium))
                        SettingsMenuPicker(
                            selection: Binding(
                                get: { tuningSettings.preset.rawValue },
                                set: { rawValue in
                                    guard let preset = LocalASRRecognitionPreset(rawValue: rawValue) else { return }
                                    tuningSettings = WhisperLocalTuningSettings.defaults(for: preset)
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

                    Toggle(localized("Follow User Main Language"), isOn: $hintSettings.followsUserMainLanguage)
                        .toggleStyle(.switch)

                    HStack(alignment: .top, spacing: 16) {
                        localInfoRow(label: localized("Primary language"), value: mainLanguageSummary)
                        localInfoRow(label: localized("Resolved language"), value: resolvedLanguage)
                    }

                    localInfoRow(label: localized("Other languages"), value: secondaryLanguageSummary)

                    Text(localized("Recognition Prompt"))
                        .font(.subheadline.weight(.medium))
                    PromptEditorView(text: $hintSettings.promptTemplate, height: 110, variables: Self.dictionaryTermsVariable)
                    Text(localized("Short recognition-focused names, terms, or formatting preferences."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            Toggle(localized("Enable VAD"), isOn: $whisperVADEnabled)
                                .toggleStyle(.switch)
                            Toggle(localized("Enable Timestamps"), isOn: $whisperTimestampsEnabled)
                                .toggleStyle(.switch)
                            Toggle(localized("Live Realtime (Experimental)"), isOn: $whisperRealtimeEnabled)
                                .toggleStyle(.switch)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(localized("Temperature"))
                                Spacer()
                                Text(String(format: "%.1f", whisperTemperature))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $whisperTemperature, in: 0...1, step: 0.1)
                        }

                        whisperIntegerRow(
                            title: localized("Fallback Count"),
                            value: $tuningSettings.temperatureFallbackCount,
                            range: 0...8
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(localized("Fallback Increment"))
                                Spacer()
                                Text(String(format: "%.1f", tuningSettings.temperatureIncrementOnFallback))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $tuningSettings.temperatureIncrementOnFallback, in: 0...1, step: 0.1)
                        }

                        whisperThresholdRow(
                            title: localized("No Speech Threshold"),
                            value: $tuningSettings.noSpeechThreshold,
                            range: 0...1
                        )
                        whisperThresholdRow(
                            title: localized("Log Prob Threshold"),
                            value: $tuningSettings.logProbThreshold,
                            range: -3...0
                        )
                        whisperThresholdRow(
                            title: localized("Compression Ratio Threshold"),
                            value: $tuningSettings.compressionRatioThreshold,
                            range: 1...4
                        )
                    }

                    Text(localized("Applies to Whisper sessions. Realtime streams partial text before final correction."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.trailing, 4)
            }
            .frame(maxHeight: SettingsUIStyle.modelConfigurationScrollMaxHeight)

            SettingsDialogActionRow {
                Button(localized("Reset to Default")) {
                    hintSettings = ASRHintSettingsStore.defaultSettings(for: .whisperKit)
                    tuningSettings = WhisperLocalTuningSettings.defaults(for: .balanced)
                    whisperTemperature = 0
                    whisperVADEnabled = true
                    whisperTimestampsEnabled = false
                    whisperRealtimeEnabled = false
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

    private func whisperThresholdRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.05)
        }
    }

    private func whisperIntegerRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
            Spacer()
            WhisperIntegerInputField(value: value, range: range, width: 72)
        }
    }
}

private struct WhisperIntegerInputField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let width: CGFloat

    @State private var text: String

    init(value: Binding<Int>, range: ClosedRange<Int>, width: CGFloat) {
        _value = value
        self.range = range
        self.width = width
        _text = State(initialValue: String(min(max(value.wrappedValue, range.lowerBound), range.upperBound)))
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .settingsFieldSurface(width: width, alignment: .trailing)
            .multilineTextAlignment(.trailing)
            .onChange(of: text) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                guard !digits.isEmpty else { return }

                let parsed = Int(digits) ?? range.lowerBound
                let clamped = min(max(parsed, range.lowerBound), range.upperBound)
                value = clamped

                let normalized = String(clamped)
                if text != normalized {
                    text = normalized
                }
            }
            .onSubmit {
                syncTextToValue()
            }
            .onChange(of: value) { _, newValue in
                let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                let normalized = String(clamped)
                if text != normalized {
                    text = normalized
                }
            }
            .onAppear {
                syncTextToValue()
            }
    }

    private func syncTextToValue() {
        let digits = text.filter(\.isNumber)
        let parsed = Int(digits) ?? value
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        value = clamped

        let normalized = String(clamped)
        if text != normalized {
            text = normalized
        }
    }
}
