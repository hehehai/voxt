import Foundation
import AppKit
import ApplicationServices

extension AppDelegate {
    static let rawTranscriptionTemplateVariable = EnhancementPromptResolver.rawTranscriptionTemplateVariable
    static let userMainLanguageTemplateVariable = EnhancementPromptResolver.userMainLanguageTemplateVariable

    struct EnhancementPromptResolution {
        enum Delivery {
            case systemPrompt
            case userMessage
        }

        let content: String
        let delivery: Delivery
    }

    func resolveGlobalEnhancementPromptTemplate(_ prompt: String, rawTranscription: String) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return AppPreferenceKey.defaultEnhancementPrompt }
        let resolved = resolveEnhancementPromptVariables(in: trimmedPrompt, rawTranscription: rawTranscription)
        return appendDictionaryEnhancementGlossary(to: resolved, sourceText: rawTranscription)
    }

    func resolvedGlobalEnhancementPrompt() -> String {
        let globalPrompt = UserDefaults.standard.string(forKey: AppPreferenceKey.enhancementSystemPrompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPrompt = (globalPrompt?.isEmpty == false) ? globalPrompt! : AppPreferenceKey.defaultEnhancementPrompt
        return fallbackPrompt
    }

    func resolvedEnhancementPrompt(rawTranscription: String) -> EnhancementPromptResolution {
        let groups = loadAppBranchGroups()
        let urlsByID = loadAppBranchURLsByID()
        let context = currentEnhancementContext()
        let frontmostBundleID = context.bundleID
        let focusedAppName = NSWorkspace.shared.frontmostApplication?.localizedName
        let normalizedActiveURL = isBrowserBundleID(frontmostBundleID)
            ? AppBranchURLPatternService.normalizedURLForMatching(
                activeBrowserTabURL(frontmostBundleID: frontmostBundleID)
            )
            : nil
        let glossary = dictionaryStore.glossaryContext(
            for: rawTranscription,
            activeGroupID: activeDictionaryGroupID()
        )?.glossaryText()

        let resolution = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: resolvedGlobalEnhancementPrompt(),
                rawTranscription: rawTranscription,
                userMainLanguagePromptValue: userMainLanguagePromptValue,
                dictionaryGlossary: glossary,
                appEnhancementEnabled: appEnhancementEnabled,
                groups: groups,
                urlsByID: urlsByID,
                frontmostBundleID: frontmostBundleID,
                focusedAppName: focusedAppName,
                normalizedActiveURL: normalizedActiveURL,
                supportedBrowserBundleIDs: supportedBrowserBundleIDs()
            )
        )

        lastEnhancementPromptContext = EnhancementPromptContext(
            focusedAppName: resolution.promptContext.focusedAppName,
            matchedGroupID: resolution.promptContext.matchedGroupID,
            matchedAppGroupName: resolution.promptContext.matchedAppGroupName,
            matchedURLGroupName: resolution.promptContext.matchedURLGroupName
        )

        switch resolution.source {
        case .globalDefault(.appBranchDisabled):
            VoxtLog.info("Enhancement prompt source: global/default (app branch disabled)")
        case .globalDefault(.noGroups):
            VoxtLog.info("Enhancement prompt source: global/default (no app branch groups)")
        case .globalDefault(.browserURLUnavailable(let bundleID)):
            VoxtLog.info("Enhancement prompt source: global/default (browser url unavailable), bundleID=\(bundleID ?? "nil")")
        case .globalDefault(.browserURLNoMatch(let bundleID, let url)):
            VoxtLog.info("Enhancement prompt source: global/default (browser url no group match), bundleID=\(bundleID ?? "nil"), url=\(url)")
        case .globalDefault(.noGroupMatch(let bundleID)):
            VoxtLog.info("Enhancement prompt source: global/default (no group match), bundleID=\(bundleID ?? "nil")")
        case .appGroup(let groupName, let bundleID):
            VoxtLog.info("Enhancement prompt source: group(app) group=\(groupName), bundleID=\(bundleID)")
        case .urlGroup(let groupName, let pattern, let url):
            VoxtLog.info("Enhancement prompt source: group(url) group=\(groupName), pattern=\(pattern), url=\(url)")
        }

        return EnhancementPromptResolution(
            content: resolution.content,
            delivery: resolution.delivery == EnhancementPromptResolver.Delivery.systemPrompt ? .systemPrompt : .userMessage
        )
    }

    func captureEnhancementContextSnapshot() -> EnhancementContextSnapshot {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return EnhancementContextSnapshot(
            bundleID: frontmostBundleID,
            capturedAt: Date()
        )
    }

    func currentDictionaryScope() -> (groupID: UUID?, groupName: String?) {
        let groups = loadAppBranchGroups()
        guard !groups.isEmpty else { return (nil, nil) }

        let urlsByID = loadAppBranchURLsByID()
        let context = currentEnhancementContext()
        let frontmostBundleID = context.bundleID

        if isBrowserBundleID(frontmostBundleID) {
            let activeURL = activeBrowserTabURL(frontmostBundleID: frontmostBundleID)
            guard let normalizedActiveURL = AppBranchURLPatternService.normalizedURLForMatching(activeURL) else {
                return (nil, nil)
            }
            if let match = AppBranchURLPatternService.firstGroupMatch(
                groups: groups,
                urlsByID: urlsByID,
                normalizedURL: normalizedActiveURL
            ) {
                return (match.groupID, match.groupName)
            }
            return (nil, nil)
        }

        guard let frontmostBundleID else { return (nil, nil) }
        if let group = groups.first(where: { $0.appBundleIDs.contains(frontmostBundleID) }) {
            return (group.id, group.name)
        }
        return (nil, nil)
    }

    private func resolveEnhancementPromptVariables(in prompt: String, rawTranscription: String) -> String {
        prompt
            .replacingOccurrences(of: Self.rawTranscriptionTemplateVariable, with: rawTranscription)
            .replacingOccurrences(of: Self.userMainLanguageTemplateVariable, with: userMainLanguagePromptValue)
    }

    private func loadAppBranchGroups() -> [AppBranchGroup] {
        guard let data = UserDefaults.standard.data(forKey: AppPreferenceKey.appBranchGroups) else { return [] }
        return (try? JSONDecoder().decode([AppBranchGroup].self, from: data)) ?? []
    }

    private func loadAppBranchURLsByID() -> [UUID: String] {
        guard let data = UserDefaults.standard.data(forKey: AppPreferenceKey.appBranchURLs),
              let items = try? JSONDecoder().decode([BranchURLItem].self, from: data)
        else {
            return [:]
        }

        var result: [UUID: String] = [:]
        for item in items {
            result[item.id] = AppBranchURLPatternService.normalizedPattern(item.pattern)
        }
        return result
    }

    private func currentEnhancementContext() -> EnhancementContextSnapshot {
        if let snapshot = enhancementContextSnapshot {
            let age = Date().timeIntervalSince(snapshot.capturedAt)
            if age <= 20 {
                return snapshot
            }
        }
        return captureEnhancementContextSnapshot()
    }

    private func isBrowserBundleID(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return supportedBrowserBundleIDs().contains(bundleID)
    }

    private func activeBrowserTabURL(frontmostBundleID: String?) -> String? {
        guard let frontmostBundleID else { return nil }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: frontmostBundleID)
            .contains(where: { !$0.isTerminated }) else {
            VoxtLog.info("Browser process not running while resolving active tab URL. bundleID=\(frontmostBundleID)")
            return nil
        }
        guard let provider = browserScriptProvider(for: frontmostBundleID) else { return nil }
        if let scriptedURL = runAppleScriptCandidates(provider.scripts, providerName: provider.name) {
            return scriptedURL
        }
        if let axURL = activeBrowserTabURLFromAccessibility(frontmostBundleID: frontmostBundleID) {
            VoxtLog.info("Browser active-tab URL read succeeded via AX fallback. provider=\(provider.name)")
            return axURL
        }
        return nil
    }

    private func browserScriptProvider(for bundleID: String) -> BrowserScriptProvider? {
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return BrowserScriptProvider(
                name: "Safari",
                scripts: [
                    "tell application id \"\(bundleID)\" to get URL of front document",
                    "tell application id \"\(bundleID)\" to get URL of current tab of front window",
                    "tell application \"Safari\" to get URL of front document"
                ]
            )
        case "com.google.Chrome":
            return BrowserScriptProvider(
                name: "Google Chrome",
                scripts: [
                    "tell application id \"com.google.Chrome\" to get the URL of active tab of front window",
                    "tell application \"Google Chrome\" to get the URL of active tab of front window"
                ]
            )
        case "com.microsoft.edgemac":
            return BrowserScriptProvider(
                name: "Microsoft Edge",
                scripts: [
                    "tell application id \"com.microsoft.edgemac\" to get the URL of active tab of front window",
                    "tell application \"Microsoft Edge\" to get the URL of active tab of front window"
                ]
            )
        case "com.brave.Browser":
            return BrowserScriptProvider(
                name: "Brave Browser",
                scripts: [
                    "tell application id \"com.brave.Browser\" to get the URL of active tab of front window",
                    "tell application \"Brave Browser\" to get the URL of active tab of front window"
                ]
            )
        case "company.thebrowser.Browser":
            return BrowserScriptProvider(
                name: "Arc",
                scripts: [
                    "tell application id \"company.thebrowser.Browser\" to get the URL of active tab of front window",
                    "tell application id \"company.thebrowser.Browser\" to get the URL of active tab of window 1",
                    "tell application \"Arc\" to get the URL of active tab of front window"
                ]
            )
        default:
            guard let customDisplayName = customBrowserDisplayName(for: bundleID) else {
                return nil
            }
            return BrowserScriptProvider(
                name: customDisplayName,
                scripts: scriptsForCustomBrowser(bundleID: bundleID, displayName: customDisplayName)
            )
        }
    }

    private func supportedBrowserBundleIDs() -> Set<String> {
        var bundleIDs: Set<String> = [
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview",
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "company.thebrowser.Browser"
        ]
        for browser in loadStoredCustomBrowsers() where !browser.bundleID.isEmpty {
            bundleIDs.insert(browser.bundleID)
        }
        return bundleIDs
    }

    private func customBrowserDisplayName(for bundleID: String) -> String? {
        loadStoredCustomBrowsers().first { $0.bundleID == bundleID }?.displayName
    }

    private func loadStoredCustomBrowsers() -> [StoredCustomBrowser] {
        guard let json = UserDefaults.standard.string(forKey: AppPreferenceKey.appBranchCustomBrowsers),
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([StoredCustomBrowser].self, from: data) else {
            return []
        }
        return decoded
    }

    private func scriptsForCustomBrowser(bundleID: String, displayName: String) -> [String] {
        [
            "tell application id \"\(bundleID)\" to get URL of front document",
            "tell application id \"\(bundleID)\" to get URL of current tab of front window",
            "tell application id \"\(bundleID)\" to get the URL of active tab of front window",
            "tell application id \"\(bundleID)\" to get the URL of active tab of window 1",
            "tell application \"\(displayName)\" to get URL of front document",
            "tell application \"\(displayName)\" to get the URL of active tab of front window"
        ]
    }

    private func runAppleScriptCandidates(_ sources: [String], providerName: String) -> String? {
        var lastError: NSDictionary?
        for (index, source) in sources.enumerated() {
            var executionError: NSDictionary?
            let startedAt = Date()
            if let output = runAppleScript(source, error: &executionError, logFailure: false, timeout: 0.8),
               !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                if index > 0 {
                    VoxtLog.info("Browser active-tab URL read succeeded via fallback. provider=\(providerName), candidate=\(index + 1), elapsedMs=\(elapsedMs)")
                }
                return output
            }
            if let executionError {
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                VoxtLog.info(
                    "Browser active-tab URL candidate failed. provider=\(providerName), candidate=\(index + 1), elapsedMs=\(elapsedMs), error=\(executionError)"
                )
                lastError = executionError
                if let errorNumber = executionError["NSAppleScriptErrorNumber"] as? Int, errorNumber == -600 {
                    break
                }
            } else {
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                VoxtLog.info(
                    "Browser active-tab URL candidate returned empty/timed out. provider=\(providerName), candidate=\(index + 1), elapsedMs=\(elapsedMs)"
                )
            }
        }
        if let lastError {
            VoxtLog.info("Browser active-tab URL read failed. provider=\(providerName), error=\(lastError)")
        }
        return nil
    }

    private func runAppleScript(
        _ source: String,
        error: inout NSDictionary?,
        logFailure: Bool = true,
        timeout: TimeInterval? = nil
    ) -> String? {
        let wrappedSource: String
        if let timeout, timeout > 0 {
            let seconds = max(1, Int(ceil(timeout)))
            wrappedSource = """
            with timeout of \(seconds) seconds
            \(source)
            end timeout
            """
        } else {
            wrappedSource = source
        }

        guard let script = NSAppleScript(source: wrappedSource) else { return nil }
        guard let output = script.executeAndReturnError(&error).stringValue else {
            if logFailure, let error {
                VoxtLog.info("Browser active-tab URL read failed: \(error)")
            }
            return nil
        }
        return output
    }

    private func activeBrowserTabURLFromAccessibility(frontmostBundleID: String) -> String? {
        guard AccessibilityPermissionManager.isTrusted() else {
            VoxtLog.info("Browser active-tab AX fallback unavailable: accessibility not trusted")
            return nil
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == frontmostBundleID
        else {
            VoxtLog.info("Browser active-tab AX fallback skipped: frontmost app changed")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )
        if focusedStatus == .success,
           let focusedWindow = focusedWindowValue {
            if let url = axDocumentURL(from: focusedWindow) {
                return url
            }
        } else {
            VoxtLog.info("Browser active-tab AX fallback focused window unavailable: status=\(focusedStatus.rawValue)")
        }

        var mainWindowValue: CFTypeRef?
        let mainStatus = AXUIElementCopyAttributeValue(
            appElement,
            kAXMainWindowAttribute as CFString,
            &mainWindowValue
        )
        if mainStatus == .success,
           let mainWindow = mainWindowValue {
            return axDocumentURL(from: mainWindow)
        }
        VoxtLog.info("Browser active-tab AX fallback main window unavailable: status=\(mainStatus.rawValue)")
        return nil
    }

    private func axDocumentURL(from windowRef: CFTypeRef) -> String? {
        guard CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let windowElement = unsafeBitCast(windowRef, to: AXUIElement.self)
        var documentValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            windowElement,
            kAXDocumentAttribute as CFString,
            &documentValue
        )
        guard status == .success, let documentValue else {
            VoxtLog.info("Browser active-tab AX fallback document attribute unavailable: status=\(status.rawValue)")
            return nil
        }
        return documentValue as? String
    }

}
