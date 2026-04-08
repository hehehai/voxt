import SwiftUI
import Foundation

struct RemoteProviderConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppPreferenceKey.remoteASRSelectedProvider) private var selectedRemoteASRProviderRaw = RemoteASRProvider.openAIWhisper.rawValue

    let providerTitle: String
    let credentialHint: String?
    let showsDoubaoFields: Bool
    let testTarget: RemoteProviderTestTarget
    let configuration: RemoteProviderConfiguration
    let onSave: (RemoteProviderConfiguration) -> Void

    @State private var selectedProviderModel = ""
    @State private var customModelID = ""
    @State private var selectedMeetingModel = ""
    @State private var customMeetingModelID = ""
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var appID = ""
    @State private var accessToken = ""
    @State private var openAIChunkPseudoRealtimeEnabled = false
    @State private var isTestingConnection = false
    @State private var testResultMessage: String?
    @State private var testResultIsSuccess = false

    private var providerModelMenuOptions: [SettingsMenuOption<String>] {
        if let llmProvider = llmProviderForPicker {
            return (
                llmProvider.latestModelOptions +
                llmProvider.basicModelOptions +
                llmProvider.advancedModelOptions
            ).map { SettingsMenuOption(value: $0.id, title: $0.title) } + [
                SettingsMenuOption(value: customModelOptionID, title: "Custom...")
            ]
        }
        return providerModelOptions.map { SettingsMenuOption(value: $0.id, title: $0.title) }
    }

    private var providerModelSelectedTitle: String {
        providerModelMenuOptions.first(where: { $0.value == resolvedSelectionForPicker })?.title
            ?? "Custom..."
    }

    private var meetingModelMenuOptions: [SettingsMenuOption<String>] {
        meetingModelOptions.map { SettingsMenuOption(value: $0.id, title: $0.title) } + [
            SettingsMenuOption(value: customModelOptionID, title: "Custom...")
        ]
    }

    private var meetingModelSelectedTitle: String {
        meetingModelMenuOptions.first(where: { $0.value == resolvedMeetingSelectionForPicker })?.title
            ?? "Custom..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.format("Configure %@", providerTitle))
                .font(.title3.weight(.semibold))

            modelSection

            if showsMeetingASRSection {
                meetingModelSection
            }

            if !isDoubaoASRTest {
                endpointAndKeySection
            }

            if showsDoubaoFields {
                doubaoCredentialsSection
            }

            if isOpenAIASRTest {
                openAIChunkSection
            }

            if let credentialHint, !credentialHint.isEmpty {
                Text(credentialHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let activeProviderNotice {
                Text(activeProviderNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionSection

            if let testResultMessage, !testResultMessage.isEmpty {
                Text(testResultMessage)
                    .font(.caption)
                    .foregroundStyle(testResultIsSuccess ? .green : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear {
            configureModelSelection()
            customModelID = configuration.model
            configureMeetingModelSelection()
            customMeetingModelID = configuration.meetingModel
            endpoint = configuration.endpoint
            apiKey = configuration.apiKey
            appID = configuration.appID
            accessToken = configuration.accessToken
            openAIChunkPseudoRealtimeEnabled = configuration.openAIChunkPseudoRealtimeEnabled
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SettingsMenuPicker(
                selection: providerModelSelectionBinding,
                options: providerModelMenuOptions,
                selectedTitle: providerModelSelectedTitle,
                width: 240
            )

            if llmProviderForPicker != nil && resolvedSelectionForPicker == customModelOptionID {
                Text("Custom Model ID (Optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g. doubao-seed-2-0-pro-260215", text: $customModelID)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }
        }
    }

    private var endpointAndKeySection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("Endpoint (Optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("https://...", text: $endpoint)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
                if !endpointPresets.isEmpty {
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(endpointPresets, id: \.id) { preset in
                                Button(preset.title) {
                                    endpoint = preset.url
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text("Apply Preset")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 10, height: 30))

                        if !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button("Clear") {
                                endpoint = ""
                            }
                            .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 10, height: 30))
                        }

                        Spacer()
                    }
                    Text("Aliyun API keys are region-specific; use the matching endpoint.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("Paste API key", text: $apiKey)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }
        }
    }

    private var meetingModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meeting ASR")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SettingsMenuPicker(
                selection: meetingModelSelectionBinding,
                options: meetingModelMenuOptions,
                selectedTitle: meetingModelSelectedTitle,
                width: 240
            )

            if resolvedMeetingSelectionForPicker == customModelOptionID {
                Text("Custom Meeting Model ID")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g. qwen3-asr-flash-filetrans", text: $customMeetingModelID)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            Text("Used only for Meeting Notes transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var doubaoCredentialsSection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("App ID")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("App ID", text: $appID)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Access Token")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("Paste access token", text: $accessToken)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }
        }
    }

    private var openAIChunkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Chunk Pseudo Realtime Preview", isOn: $openAIChunkPseudoRealtimeEnabled)
                .toggleStyle(.switch)
            Text("Enable segmented OpenAI ASR preview during recording. This roughly doubles usage.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionSection: some View {
        SettingsDialogActionRow {
            if isTestingConnection {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Test") {
                testConnection()
            }
            .buttonStyle(SettingsPillButtonStyle())
            .disabled(isTestingConnection)

            if showsMeetingASRSection {
                Button("Test Meeting ASR") {
                    testMeetingConnection()
                }
                .buttonStyle(SettingsPillButtonStyle())
                .disabled(isTestingConnection)
            }
        } trailing: {
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(SettingsPillButtonStyle())
            .keyboardShortcut(.cancelAction)

            Button("Save") {
                onSave(currentConfigurationSnapshot)
                dismiss()
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private var currentConfigurationSnapshot: RemoteProviderConfiguration {
        RemoteProviderConfiguration(
            providerID: configuration.providerID,
            model: resolvedModelValue(),
            meetingModel: resolvedMeetingModelValue(),
            endpoint: isDoubaoASRTest ? "" : endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: isDoubaoASRTest ? "" : apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
            accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
            openAIChunkPseudoRealtimeEnabled: isOpenAIASRTest ? openAIChunkPseudoRealtimeEnabled : false
        )
    }

    private func testConnection() {
        runConnectionTest(for: testTarget, modelForLog: currentConfigurationSnapshot.model)
    }

    private func testMeetingConnection() {
        guard let provider = asrProviderForSheet else { return }
        runConnectionTest(
            for: .meetingASR(provider),
            modelForLog: currentConfigurationSnapshot.meetingModel
        )
    }

    private func runConnectionTest(
        for target: RemoteProviderTestTarget,
        modelForLog: String
    ) {
        let snapshot = currentConfigurationSnapshot
        isTestingConnection = true
        testResultMessage = nil
        testResultIsSuccess = false
        VoxtLog.info(
            "Remote provider test started. target=\(RemoteProviderConfigurationPolicy.testTargetLogName(target)), provider=\(configuration.providerID), model=\(modelForLog), meetingModel=\(snapshot.meetingModel), endpoint=\(sanitizedEndpointForLog(snapshot.endpoint)), hasAPIKey=\(!snapshot.apiKey.isEmpty), hasAppID=\(!snapshot.appID.isEmpty), hasAccessToken=\(!snapshot.accessToken.isEmpty)"
        )

        Task {
            do {
                let tester = RemoteProviderConnectivityTester(testTarget: target)
                let message = try await tester.run(configuration: snapshot)
                await MainActor.run {
                    isTestingConnection = false
                    testResultIsSuccess = true
                    testResultMessage = message
                    VoxtLog.info(
                        "Remote provider test succeeded. target=\(RemoteProviderConfigurationPolicy.testTargetLogName(target)), provider=\(configuration.providerID), model=\(modelForLog), message=\(message)"
                    )
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    testResultIsSuccess = false
                    testResultMessage = error.localizedDescription
                    VoxtLog.warning(
                        "Remote provider test failed. target=\(RemoteProviderConfigurationPolicy.testTargetLogName(target)), provider=\(configuration.providerID), model=\(modelForLog), error=\(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private var testTargetLogName: String {
        RemoteProviderConfigurationPolicy.testTargetLogName(testTarget)
    }

    private func sanitizedEndpointForLog(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "<default>" : trimmed
    }

    private var isDoubaoASRTest: Bool {
        RemoteProviderConfigurationPolicy.isDoubaoASRTest(testTarget)
    }

    private var isOpenAIASRTest: Bool {
        RemoteProviderConfigurationPolicy.isOpenAIASRTest(testTarget)
    }

    private var customModelOptionID: String {
        RemoteProviderConfigurationPolicy.customModelOptionID
    }

    private var asrProviderForSheet: RemoteASRProvider? {
        if case .asr(let provider) = testTarget {
            return provider
        }
        if case .meetingASR(let provider) = testTarget {
            return provider
        }
        return nil
    }

    private var activeProviderNotice: String? {
        guard let provider = asrProviderForSheet else { return nil }
        let active = RemoteASRProvider(rawValue: selectedRemoteASRProviderRaw) ?? .openAIWhisper
        guard active != provider else { return nil }
        return AppLocalization.format(
            "Current active Remote ASR provider is %@. Testing %@ here does not switch the active provider.",
            active.title,
            provider.title
        )
    }

    private var showsMeetingASRSection: Bool {
        guard let provider = asrProviderForSheet else { return false }
        return RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(provider, configuration: configuration)
    }

    private var meetingModelOptions: [RemoteModelOption] {
        guard let provider = asrProviderForSheet else { return [] }
        return RemoteASRMeetingConfiguration.meetingModelOptions(for: provider)
    }

    private var providerModelOptions: [RemoteModelOption] {
        RemoteProviderConfigurationPolicy.providerModelOptions(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    private var pickerModelOptionIDs: [String] {
        RemoteProviderConfigurationPolicy.pickerModelOptionIDs(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    private var resolvedSelectionForPicker: String {
        RemoteProviderConfigurationPolicy.resolvedSelection(
            target: testTarget,
            selectedProviderModel: selectedProviderModel,
            configuredModel: configuration.model
        )
    }

    private var providerModelSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedSelectionForPicker },
            set: {
                selectedProviderModel = $0
                if llmProviderForPicker != nil,
                   $0 != customModelOptionID,
                   customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    customModelID = $0
                }
            }
        )
    }

    private var llmProviderForPicker: RemoteLLMProvider? {
        RemoteProviderConfigurationPolicy.llmProvider(for: testTarget)
    }

    private func configureModelSelection() {
        selectedProviderModel = RemoteProviderConfigurationPolicy.initialSelection(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    private func configureMeetingModelSelection() {
        let trimmed = configuration.meetingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let optionIDs = Set(meetingModelOptions.map(\.id))
        if optionIDs.contains(trimmed) {
            selectedMeetingModel = trimmed
            return
        }
        if let provider = asrProviderForSheet {
            let suggested = RemoteASRMeetingConfiguration.suggestedMeetingModel(for: provider)
            if optionIDs.contains(suggested) {
                selectedMeetingModel = suggested
                return
            }
        }
        selectedMeetingModel = customModelOptionID
    }

    private func resolvedModelValue() -> String {
        RemoteProviderConfigurationPolicy.resolvedModelValue(
            target: testTarget,
            resolvedSelection: resolvedSelectionForPicker,
            customModelID: customModelID
        )
    }

    private var resolvedMeetingSelectionForPicker: String {
        let trimmed = selectedMeetingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let optionIDs = Set(meetingModelOptions.map(\.id))
        if optionIDs.contains(trimmed) {
            return trimmed
        }
        let configured = configuration.meetingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if optionIDs.contains(configured) {
            return configured
        }
        return customModelOptionID
    }

    private var meetingModelSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedMeetingSelectionForPicker },
            set: {
                selectedMeetingModel = $0
                if $0 != customModelOptionID,
                   customMeetingModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    customMeetingModelID = $0
                }
            }
        )
    }

    private func resolvedMeetingModelValue() -> String {
        guard showsMeetingASRSection else {
            return configuration.meetingModel
        }
        if resolvedMeetingSelectionForPicker == customModelOptionID {
            return customMeetingModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return resolvedMeetingSelectionForPicker
    }

    private var endpointPresets: [RemoteEndpointPreset] {
        RemoteProviderConfigurationPolicy.endpointPresets(
            target: testTarget,
            resolvedModel: resolvedModelValue()
        )
    }

}
