import SwiftUI

extension RemoteProviderConfigurationSheet {
    var providerModelMenuOptions: [SettingsMenuOption<String>] {
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

    var providerModelSelectedTitle: String {
        providerModelMenuOptions.first(where: { $0.value == resolvedSelectionForPicker })?.title
            ?? "Custom..."
    }

    var meetingModelMenuOptions: [SettingsMenuOption<String>] {
        meetingModelOptions.map { SettingsMenuOption(value: $0.id, title: $0.title) } + [
            SettingsMenuOption(value: customModelOptionID, title: "Custom...")
        ]
    }

    var meetingModelSelectedTitle: String {
        meetingModelMenuOptions.first(where: { $0.value == resolvedMeetingSelectionForPicker })?.title
            ?? "Custom..."
    }

    var currentConfigurationSnapshot: RemoteProviderConfiguration {
        RemoteProviderConfiguration(
            providerID: configuration.providerID,
            model: resolvedModelValue(),
            meetingModel: resolvedMeetingModelValue(),
            endpoint: isDoubaoASRTest ? "" : endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: isDoubaoASRTest ? "" : apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
            accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
            openAIChunkPseudoRealtimeEnabled: isOpenAIASRTest ? openAIChunkPseudoRealtimeEnabled : false,
            doubaoDictionaryMode: doubaoDictionaryMode,
            doubaoEnableRequestHotwords: doubaoEnableRequestHotwords,
            doubaoEnableRequestCorrections: doubaoEnableRequestCorrections
        )
    }

    var isDoubaoASRTest: Bool {
        RemoteProviderConfigurationPolicy.isDoubaoASRTest(testTarget)
    }

    var isOpenAIASRTest: Bool {
        RemoteProviderConfigurationPolicy.isOpenAIASRTest(testTarget)
    }

    var customModelOptionID: String {
        RemoteProviderConfigurationPolicy.customModelOptionID
    }

    var asrProviderForSheet: RemoteASRProvider? {
        if case .asr(let provider) = testTarget {
            return provider
        }
        if case .meetingASR(let provider) = testTarget {
            return provider
        }
        return nil
    }

    var activeProviderNotice: String? {
        guard let provider = asrProviderForSheet else { return nil }
        let active = RemoteASRProvider(rawValue: selectedRemoteASRProviderRaw) ?? .openAIWhisper
        guard active != provider else { return nil }
        return AppLocalization.format(
            "Current active Remote ASR provider is %@. Testing %@ here does not switch the active provider.",
            active.title,
            provider.title
        )
    }

    var showsMeetingASRSection: Bool {
        guard let provider = asrProviderForSheet else { return false }
        return RemoteASRMeetingConfiguration.requiresDedicatedMeetingModel(provider, configuration: configuration)
    }

    var meetingModelOptions: [RemoteModelOption] {
        guard let provider = asrProviderForSheet else { return [] }
        return RemoteASRMeetingConfiguration.meetingModelOptions(for: provider)
    }

    var providerModelOptions: [RemoteModelOption] {
        RemoteProviderConfigurationPolicy.providerModelOptions(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    var resolvedSelectionForPicker: String {
        RemoteProviderConfigurationPolicy.resolvedSelection(
            target: testTarget,
            selectedProviderModel: selectedProviderModel,
            configuredModel: configuration.model
        )
    }

    var providerModelSelectionBinding: Binding<String> {
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

    var llmProviderForPicker: RemoteLLMProvider? {
        RemoteProviderConfigurationPolicy.llmProvider(for: testTarget)
    }

    func configureModelSelection() {
        selectedProviderModel = RemoteProviderConfigurationPolicy.initialSelection(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    func configureMeetingModelSelection() {
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

    func resolvedModelValue() -> String {
        RemoteProviderConfigurationPolicy.resolvedModelValue(
            target: testTarget,
            resolvedSelection: resolvedSelectionForPicker,
            customModelID: customModelID
        )
    }

    var resolvedMeetingSelectionForPicker: String {
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

    var meetingModelSelectionBinding: Binding<String> {
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

    func resolvedMeetingModelValue() -> String {
        guard showsMeetingASRSection else {
            return configuration.meetingModel
        }
        if resolvedMeetingSelectionForPicker == customModelOptionID {
            return customMeetingModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return resolvedMeetingSelectionForPicker
    }

    var endpointPresets: [RemoteEndpointPreset] {
        RemoteProviderConfigurationPolicy.endpointPresets(
            target: testTarget,
            resolvedModel: resolvedModelValue()
        )
    }

    func testConnection() {
        runConnectionTest(for: testTarget, modelForLog: currentConfigurationSnapshot.model)
    }

    func testMeetingConnection() {
        guard let provider = asrProviderForSheet else { return }
        runConnectionTest(
            for: .meetingASR(provider),
            modelForLog: currentConfigurationSnapshot.meetingModel
        )
    }

    func runConnectionTest(
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

    func sanitizedEndpointForLog(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "<default>" : trimmed
    }
}
