import Darwin
import AppKit
import Foundation

enum VoxtLog {
    struct ExportPayload {
        let filename: String
        let content: String
    }

    private enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    nonisolated(unsafe) static var verboseEnabled = false

    nonisolated static func info(_ message: @autoclosure () -> String, verbose: Bool = false) {
        log(message(), level: .info, verbose: verbose)
    }

    nonisolated static func hotkey(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.hotkeyDebugLoggingEnabled) else { return }
        log(message(), level: .info)
    }

    nonisolated static func llm(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.llmDebugLoggingEnabled) else { return }
        log(message(), level: .info)
    }

    nonisolated static func model(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.llmDebugLoggingEnabled) else { return }
        log(message(), level: .info)
    }

    nonisolated static func llmPreview(_ text: String, limit: Int = 1200) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "<empty>" }
        guard normalized.count > limit else { return normalized }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: limit)
        return "\(normalized[..<endIndex])…"
    }

    nonisolated static func warning(_ message: @autoclosure () -> String) {
        log(message(), level: .warning)
    }

    nonisolated static func error(_ message: @autoclosure () -> String) {
        log(message(), level: .error)
    }

    nonisolated static func latestLogUpdateDate() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    static func latestLogExportPayload(limit: Int = 1000) -> ExportPayload {
        lock.lock()
        defer { lock.unlock() }
        loadCacheIfNeeded()

        let content = composedLogContent(limit: limit)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "voxt-log-\(formatter.string(from: Date())).txt"
        return ExportPayload(filename: filename, content: content)
    }

    static func latestLogDisplayText(limit: Int = 1000) -> String {
        lock.lock()
        defer { lock.unlock() }
        loadCacheIfNeeded()
        return composedLogContent(limit: limit)
    }

    static func exportLatestLogs(limit: Int = 1000) throws -> URL {
        let payload = latestLogExportPayload(limit: limit)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(payload.filename)
        try payload.content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private nonisolated static let lock = NSLock()
    private nonisolated static let maxStoredLines = 10000
    private nonisolated(unsafe) static var didLoadCache = false
    private nonisolated(unsafe) static var logLines: [String] = []
    private nonisolated(unsafe) static let lineDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated static var logFileURL: URL {
        let supportDirectory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = supportDirectory ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("voxt.log")
    }

    private nonisolated static func log(_ message: String, level: Level, verbose: Bool = false) {
        guard !verbose || verboseEnabled else { return }
        let line = formatLine(message: message, level: level)
        print(line)
        persist(line: line)
    }

    private nonisolated static func formatLine(message: String, level: Level) -> String {
        let dateText = lineDateFormatter.string(from: Date())
        return "[Voxt] \(dateText) [\(level.rawValue)] \(message)"
    }

    private nonisolated static func persist(line: String) {
        lock.lock()
        defer { lock.unlock() }
        loadCacheIfNeeded()
        logLines.append(line)
        trimIfNeeded()
        writeAllLines()
    }

    private nonisolated static func loadCacheIfNeeded() {
        guard !didLoadCache else { return }
        didLoadCache = true
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8), !content.isEmpty else {
            logLines = []
            return
        }
        logLines = content
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        trimIfNeeded()
    }

    private nonisolated static func trimIfNeeded() {
        guard logLines.count > maxStoredLines else { return }
        logLines = Array(logLines.suffix(maxStoredLines))
    }

    private nonisolated static func writeAllLines() {
        do {
            try FileManager.default.createDirectory(
                at: logFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let text = logLines.joined(separator: "\n")
            try text.write(to: logFileURL, atomically: true, encoding: .utf8)
        } catch {
            // Keep logging non-fatal.
        }
    }

    private static func composedLogContent(limit: Int) -> String {
        let resolvedLimit = max(1, limit)
        let selectedLines = Array(logLines.suffix(resolvedLimit))
        let logText = selectedLines.isEmpty
            ? "[Voxt] <\(AppLocalization.localizedString("No logs available"))>"
            : selectedLines.joined(separator: "\n")
        return [
            logText,
            "========== \(AppLocalization.localizedString("App Meta")) ==========",
            diagnosticsMetadataText()
        ].joined(separator: "\n\n")
    }

    private static func diagnosticsMetadataText(defaults: UserDefaults = .standard) -> String {
        let featureSettings = FeatureSettingsStore.load(defaults: defaults)
        let proxySettings = VoxtNetworkSession.currentProxySettings
        let systemProxyStatus = VoxtNetworkSession.currentSystemProxyStatus
        let remoteASRProvider = RemoteASRProvider(rawValue: defaults.string(forKey: AppPreferenceKey.remoteASRSelectedProvider) ?? "")
            ?? .openAIWhisper
        let remoteLLMProvider = RemoteLLMProvider(rawValue: defaults.string(forKey: AppPreferenceKey.remoteLLMSelectedProvider) ?? "")
            ?? .openAI
        let remoteASRConfigurations = RemoteModelConfigurationStore.loadConfigurations(
            from: defaults.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? "",
            sensitiveValueLoading: .metadataOnly
        )
        let remoteLLMConfigurations = RemoteModelConfigurationStore.loadConfigurations(
            from: defaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? "",
            sensitiveValueLoading: .metadataOnly
        )
        let resolvedRemoteASRConfiguration = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: remoteASRProvider,
            stored: remoteASRConfigurations
        )
        let resolvedRemoteLLMConfiguration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: remoteLLMProvider,
            stored: remoteLLMConfigurations
        )
        let selectedEngine = TranscriptionEngine(rawValue: defaults.string(forKey: AppPreferenceKey.transcriptionEngine) ?? "")
            ?? .mlxAudio
        let enhancementMode = EnhancementMode(rawValue: defaults.string(forKey: AppPreferenceKey.enhancementMode) ?? "")
            ?? .off
        let whisperModelID = WhisperKitModelManager.canonicalModelID(
            defaults.string(forKey: AppPreferenceKey.whisperModelID) ?? WhisperKitModelManager.defaultModelID
        )
        let mlxModelRepo = MLXModelManager.canonicalModelRepo(
            defaults.string(forKey: AppPreferenceKey.mlxModelRepo) ?? MLXModelCatalog.defaultModelRepo
        )
        let translationProvider = TranslationModelProvider(
            rawValue: defaults.string(forKey: AppPreferenceKey.translationModelProvider) ?? ""
        ) ?? .customLLM
        let rewriteProvider = RewriteModelProvider(
            rawValue: defaults.string(forKey: AppPreferenceKey.rewriteModelProvider) ?? ""
        ) ?? .customLLM
        let translationRemoteProvider = RemoteLLMProvider(
            rawValue: defaults.string(forKey: AppPreferenceKey.translationRemoteLLMProvider) ?? ""
        )
        let rewriteRemoteProvider = RemoteLLMProvider(
            rawValue: defaults.string(forKey: AppPreferenceKey.rewriteRemoteLLMProvider) ?? ""
        )
        let hotkeyPreset = HotkeyPreference.Preset(
            rawValue: defaults.string(forKey: AppPreferenceKey.hotkeyPreset) ?? ""
        ) ?? .fnCombo
        let hotkeyTriggerMode = HotkeyPreference.TriggerMode(
            rawValue: defaults.string(forKey: AppPreferenceKey.hotkeyTriggerMode) ?? ""
        ) ?? .longPress
        let interactionSoundPreset = InteractionSoundPreset(
            rawValue: defaults.string(forKey: AppPreferenceKey.interactionSoundPreset) ?? ""
        ) ?? .soft
        let voiceEndPreset = VoiceEndCommandPreset(
            rawValue: defaults.string(forKey: AppPreferenceKey.voiceEndCommandPreset) ?? ""
        ) ?? .over

        var lines: [String] = []
        lines.append("generatedAt: \(lineDateFormatter.string(from: Date()))")
        lines.append("appVersion: \(bundleVersionText())")
        lines.append("bundleID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("machine: \(machineSummary())")
        lines.append("locale: \(Locale.current.identifier)")
        lines.append("preferredLanguages: \(Locale.preferredLanguages.joined(separator: ", "))")
        lines.append("timeZone: \(TimeZone.current.identifier)")
        lines.append("selectedTranscriptionEngine: \(selectedEngine.rawValue) [\(selectedEngine.title)]")
        lines.append("enhancementMode: \(enhancementMode.rawValue) [\(enhancementMode.title)]")
        lines.append("realtimeTextDisplayEnabled: \(defaults.bool(forKey: AppPreferenceKey.realtimeTextDisplayEnabled))")
        lines.append("whisperRealtimeEnabled: \(defaults.bool(forKey: AppPreferenceKey.whisperRealtimeEnabled))")
        lines.append("voiceEndCommandEnabled: \(defaults.bool(forKey: AppPreferenceKey.voiceEndCommandEnabled))")
        lines.append("voiceEndCommandPreset: \(voiceEndPreset.rawValue) [\(voiceEndPreset.title)]")
        lines.append("voiceEndCommandText: \(nonEmptyOrPlaceholder(defaults.string(forKey: AppPreferenceKey.voiceEndCommandText), placeholder: "<preset>"))")
        lines.append("escapeKeyCancelsOverlaySession: \(defaults.object(forKey: AppPreferenceKey.escapeKeyCancelsOverlaySession) as? Bool ?? true)")
        lines.append("hotkeyPreset: \(hotkeyPreset.rawValue) [\(hotkeyPreset.title)]")
        lines.append("hotkeyTriggerMode: \(hotkeyTriggerMode.rawValue) [\(hotkeyTriggerMode.title)]")
        lines.append("hotkeyDebugLoggingEnabled: \(defaults.bool(forKey: AppPreferenceKey.hotkeyDebugLoggingEnabled))")
        lines.append("modelDebugLoggingEnabled: \(defaults.bool(forKey: AppPreferenceKey.llmDebugLoggingEnabled))")
        lines.append("activeInputDeviceUID: \(nonEmptyOrPlaceholder(defaults.string(forKey: AppPreferenceKey.activeInputDeviceUID)))")
        lines.append("microphoneAutoSwitchEnabled: \(defaults.object(forKey: AppPreferenceKey.microphoneAutoSwitchEnabled) as? Bool ?? true)")
        lines.append("muteSystemAudioWhileRecording: \(defaults.bool(forKey: AppPreferenceKey.muteSystemAudioWhileRecording))")
        lines.append("interactionSoundsEnabled: \(defaults.object(forKey: AppPreferenceKey.interactionSoundsEnabled) as? Bool ?? true)")
        lines.append("interactionSoundPreset: \(interactionSoundPreset.rawValue) [\(interactionSoundPreset.title)]")
        lines.append("historyEnabled: \(defaults.object(forKey: AppPreferenceKey.historyEnabled) as? Bool ?? true)")
        lines.append("historyAudioStorageEnabled: \(defaults.bool(forKey: AppPreferenceKey.historyAudioStorageEnabled))")
        lines.append("useHfMirror: \(defaults.bool(forKey: AppPreferenceKey.useHfMirror))")
        lines.append("localModelIdleUnloadDelaySeconds: \(AppPreferenceKey.resolvedLocalModelIdleUnloadDelaySeconds(defaults: defaults))")
        lines.append("mlxModel: \(mlxModelRepo) [\(MLXModelCatalog.displayTitle(for: mlxModelRepo))]")
        lines.append("whisperModel: \(whisperModelID) [\(WhisperKitModelCatalog.displayTitle(for: whisperModelID))]")
        lines.append("customLLMModelRepo: \(nonEmptyOrPlaceholder(defaults.string(forKey: AppPreferenceKey.customLLMModelRepo)))")
        lines.append("translationCustomLLMModelRepo: \(nonEmptyOrPlaceholder(defaults.string(forKey: AppPreferenceKey.translationCustomLLMModelRepo)))")
        lines.append("rewriteCustomLLMModelRepo: \(nonEmptyOrPlaceholder(defaults.string(forKey: AppPreferenceKey.rewriteCustomLLMModelRepo)))")
        lines.append("proxyMode: \(proxySettings.mode.rawValue)")
        lines.append("proxyRoute: \(proxyRouteSummary(settings: proxySettings, systemStatus: systemProxyStatus))")
        lines.append("translationProvider: \(translationProvider.rawValue) [\(translationProvider.title)]")
        lines.append("translationRemoteProvider: \(resolvedProviderSummary(translationRemoteProvider))")
        lines.append("rewriteProvider: \(rewriteProvider.rawValue) [\(rewriteProvider.title)]")
        lines.append("rewriteRemoteProvider: \(resolvedProviderSummary(rewriteRemoteProvider))")
        lines.append("selectedRemoteASR: \(remoteASRProvider.rawValue) [\(remoteASRProvider.title)]")
        lines.append("selectedRemoteASRConfiguration: \(remoteASRConfigurationSummary(provider: remoteASRProvider, configuration: resolvedRemoteASRConfiguration))")
        lines.append("selectedRemoteLLM: \(remoteLLMProvider.rawValue) [\(remoteLLMProvider.title)]")
        lines.append("selectedRemoteLLMConfiguration: \(remoteLLMConfigurationSummary(provider: remoteLLMProvider, configuration: resolvedRemoteLLMConfiguration))")
        lines.append("feature.transcription.asrSelectionID: \(featureSettings.transcription.asrSelectionID.rawValue)")
        lines.append("feature.transcription.llmEnabled: \(featureSettings.transcription.llmEnabled)")
        lines.append("feature.transcription.llmSelectionID: \(featureSettings.transcription.llmSelectionID.rawValue)")
        lines.append("feature.transcription.notes.enabled: \(featureSettings.transcription.notes.enabled)")
        lines.append("feature.transcription.notes.titleModelSelectionID: \(featureSettings.transcription.notes.titleModelSelectionID.rawValue)")
        lines.append("feature.translation.asrSelectionID: \(featureSettings.translation.asrSelectionID.rawValue)")
        lines.append("feature.translation.modelSelectionID: \(featureSettings.translation.modelSelectionID.rawValue)")
        lines.append("feature.translation.targetLanguage: \(featureSettings.translation.targetLanguage.rawValue)")
        lines.append("feature.translation.replaceSelectedText: \(featureSettings.translation.replaceSelectedText)")
        lines.append("feature.translation.showResultWindow: \(featureSettings.translation.showResultWindow)")
        lines.append("feature.rewrite.asrSelectionID: \(featureSettings.rewrite.asrSelectionID.rawValue)")
        lines.append("feature.rewrite.llmSelectionID: \(featureSettings.rewrite.llmSelectionID.rawValue)")
        lines.append("feature.rewrite.appEnhancementEnabled: \(featureSettings.rewrite.appEnhancementEnabled)")
        lines.append("feature.rewrite.continueShortcut: \(shortcutSummary(featureSettings.rewrite.continueShortcut))")

        let configuredASRSummaries = RemoteASRProvider.allCases.compactMap { provider -> String? in
            guard let configuration = remoteASRConfigurations[provider.rawValue],
                  configuration.isConfigured || configuration.hasUsableModel || !configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            return remoteASRConfigurationSummary(provider: provider, configuration: configuration)
        }
        let configuredLLMSummaries = RemoteLLMProvider.allCases.compactMap { provider -> String? in
            guard let configuration = remoteLLMConfigurations[provider.rawValue],
                  configuration.isConfigured || configuration.hasUsableModel || !configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            return remoteLLMConfigurationSummary(provider: provider, configuration: configuration)
        }
        lines.append("configuredRemoteASRProviders: \(configuredASRSummaries.isEmpty ? "<none>" : configuredASRSummaries.joined(separator: " | "))")
        lines.append("configuredRemoteLLMProviders: \(configuredLLMSummaries.isEmpty ? "<none>" : configuredLLMSummaries.joined(separator: " | "))")

        return lines.joined(separator: "\n")
    }

    private static func bundleVersionText() -> String {
        let bundle = Bundle.main
        let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch (shortVersion?.isEmpty == false ? shortVersion : nil, buildVersion?.isEmpty == false ? buildVersion : nil) {
        case let (shortVersion?, buildVersion?):
            return "\(shortVersion) (\(buildVersion))"
        case let (shortVersion?, nil):
            return shortVersion
        case let (nil, buildVersion?):
            return buildVersion
        default:
            return "unknown"
        }
    }

    private static func machineSummary() -> String {
        let model = sysctlString(named: "hw.model")
        let machine = sysctlString(named: "hw.machine")
        if model == machine {
            return model
        }
        return "\(model) / \(machine)"
    }

    private static func sysctlString(named name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return "unknown"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return "unknown"
        }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "unknown" : value
    }

    private static func proxyRouteSummary(
        settings: VoxtNetworkSession.ProxySettings,
        systemStatus: VoxtNetworkSession.SystemProxyStatus
    ) -> String {
        switch settings.mode {
        case .system:
            return systemStatus.preferredSummary ?? "<none>"
        case .disabled:
            return "direct"
        case .custom:
            let host = settings.host.isEmpty ? "<missing-host>" : settings.host
            let port = settings.port.map(String.init) ?? "<missing-port>"
            let auth = settings.hasCredentials ? "auth" : "noauth"
            return "\(settings.scheme.rawValue)://\(host):\(port) [\(auth)]"
        }
    }

    private static func remoteASRConfigurationSummary(
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        var extras: [String] = [
            "provider=\(provider.rawValue)",
            "configured=\(configuration.isConfigured)",
            "model=\(model.isEmpty ? "<empty>" : model)",
            "endpoint=\(endpoint.isEmpty ? "<default>" : endpoint)"
        ]
        if provider == .openAIWhisper {
            extras.append("pseudoRealtime=\(configuration.openAIChunkPseudoRealtimeEnabled)")
        }
        if provider == .aliyunBailianASR {
            extras.append("route=\(aliyunASRRouteSummary(for: configuration.model))")
        }
        return extras.joined(separator: ", ")
    }

    private static func remoteLLMConfigurationSummary(
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration
    ) -> String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        var extras: [String] = [
            "provider=\(provider.rawValue)",
            "configured=\(configuration.isConfigured)",
            "model=\(model.isEmpty ? "<empty>" : model)",
            "endpoint=\(endpoint.isEmpty ? "<default>" : endpoint)",
            "searchEnabled=\(configuration.searchEnabled)"
        ]
        if provider == .codex {
            extras.append("fastMode=\(configuration.codexFastModeEnabled)")
        }
        return extras.joined(separator: ", ")
    }

    private static func aliyunASRRouteSummary(for model: String) -> String {
        if let kind = RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: model) {
            switch kind {
            case .qwenASR:
                return "qwen-realtime"
            case .omniASR:
                return "omni-realtime"
            }
        }
        if RemoteASREndpointSupport.isAliyunFunRealtimeModel(model) {
            return "fun-realtime"
        }
        if RemoteASREndpointSupport.isAliyunFileTranscriptionModel(model) {
            return "file-transcription"
        }
        return "unknown"
    }

    private static func resolvedProviderSummary(_ provider: RemoteLLMProvider?) -> String {
        guard let provider else { return "<unset>" }
        return "\(provider.rawValue) [\(provider.title)]"
    }

    private static func shortcutSummary(_ shortcut: FeatureShortcutSettings) -> String {
        "keyCode=\(shortcut.keyCode), modifiers=\(shortcut.modifiers.rawValue), sidedModifiers=\(shortcut.sidedModifiers.rawValue)"
    }

    private static func nonEmptyOrPlaceholder(_ value: String?, placeholder: String = "<empty>") -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? placeholder : trimmed
    }
}
