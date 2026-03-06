import Foundation
import AppKit
import ApplicationServices
import AVFoundation
import Speech

extension AppDelegate {
    func beginRecording(outputMode: SessionOutputMode) {
        guard !isSessionActive else { return }
        guard preflightPermissionsForRecording() else { return }

        pendingSessionFinishTask?.cancel()
        pendingSessionFinishTask = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        overlayState.isCompleting = false
        setEnhancingState(false)
        recordingStartedAt = Date()
        recordingStoppedAt = nil
        transcriptionProcessingStartedAt = nil
        sessionOutputMode = outputMode
        enhancementContextSnapshot = nil

        VoxtLog.info(
            "Recording started. output=\(outputMode == .translation ? "translation" : "transcription"), engine=\(transcriptionEngine.rawValue)"
        )

        applyPreferredInputDevice()
        overlayState.statusMessage = ""

        if transcriptionEngine == .mlxAudio {
            switch mlxModelManager.state {
            case .notDownloaded:
                VoxtLog.warning("MLX Audio model not downloaded, falling back to Direct Dictation")
                showOverlayStatus(
                    String(localized: "MLX model is not downloaded. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
            case .error:
                VoxtLog.warning("MLX Audio model error, falling back to Direct Dictation")
                showOverlayStatus(
                    String(localized: "MLX model is unavailable. Open Settings > Model to fix it."),
                    clearAfter: 2.5
                )
            default:
                break
            }
        }

        isSessionActive = true
        if interactionSoundsEnabled {
            interactionSoundPlayer.playStart()
        }

        if transcriptionEngine == .mlxAudio, isMLXReady {
            startMLXRecordingSession()
        } else {
            startSpeechRecordingSession()
        }

        startSilenceMonitoringIfNeeded()
    }

    func endRecording() {
        guard isSessionActive else { return }
        VoxtLog.info("Recording stop requested.")

        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        recordingStoppedAt = Date()
        if transcriptionProcessingStartedAt == nil {
            transcriptionProcessingStartedAt = recordingStoppedAt
        }
        enhancementContextSnapshot = captureEnhancementContextSnapshot()

        if transcriptionEngine == .mlxAudio, isMLXReady {
            mlxTranscriber?.stopRecording()
        } else {
            speechTranscriber.stopRecording()
        }

        // Safety fallback: some engine/device combinations may occasionally fail to
        // report completion. Ensure the session/UI can always recover.
        stopRecordingFallbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard self.isSessionActive else { return }
            VoxtLog.warning("Stop recording fallback triggered; forcing session finish.")
            self.finishSession(after: 0)
        }
    }

    func processTranscription(_ rawText: String) {
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            VoxtLog.info("Transcription result is empty; finishing session.")
            setEnhancingState(false)
            finishSession(after: 0)
            return
        }

        VoxtLog.info("Transcription result received. characters=\(text.count), output=\(sessionOutputMode == .translation ? "translation" : "transcription")")
        VoxtLog.info("Enhancement mode=\(enhancementMode.rawValue), appEnhancementEnabled=\(appEnhancementEnabled)")

        if sessionOutputMode == .translation {
            processTranslatedTranscription(text)
            return
        }

        switch enhancementMode {
        case .off:
            setEnhancingState(false)
            commitTranscription(text, llmDurationSeconds: nil)
            finishSession()

        case .appleIntelligence:
            guard let enhancer else {
                setEnhancingState(false)
                commitTranscription(text, llmDurationSeconds: nil)
                finishSession()
                return
            }

            setEnhancingState(true)
            Task {
                defer {
                    self.setEnhancingState(false)
                    self.finishSession()
                }
                do {
                    if #available(macOS 26.0, *) {
                        let prompt = self.resolvedEnhancementPrompt()
                        let llmStartedAt = Date()
                        let enhanced = try await enhancer.enhance(text, systemPrompt: prompt)
                        let llmDuration = Date().timeIntervalSince(llmStartedAt)
                        self.commitTranscription(enhanced, llmDurationSeconds: llmDuration)
                    } else {
                        self.commitTranscription(text, llmDurationSeconds: nil)
                    }
                } catch {
                    VoxtLog.error("AI enhancement failed, using raw text: \(error)")
                    self.commitTranscription(text, llmDurationSeconds: nil)
                }
            }

        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: customLLMManager.currentModelRepo) else {
                VoxtLog.warning("Custom LLM selected but local model is not installed. Using raw transcription.")
                showOverlayStatus(
                    String(localized: "Custom LLM model is not installed. Open Settings > Model to install it."),
                    clearAfter: 2.5
                )
                setEnhancingState(false)
                commitTranscription(text, llmDurationSeconds: nil)
                finishSession()
                return
            }

            setEnhancingState(true)
            Task {
                defer {
                    self.setEnhancingState(false)
                    self.finishSession()
                }
                let llmStartedAt = Date()
                let prompt = self.resolvedEnhancementPrompt()
                do {
                    let enhanced = try await self.customLLMManager.enhance(text, systemPrompt: prompt)
                    let llmDuration = Date().timeIntervalSince(llmStartedAt)
                    self.commitTranscription(enhanced, llmDurationSeconds: llmDuration)
                } catch {
                    VoxtLog.error("Custom LLM enhancement failed, using raw text: \(error)")
                    self.commitTranscription(text, llmDurationSeconds: nil)
                }
            }
        }
    }

    func startPauseLLMIfNeeded() {
        guard enhancementMode != .off else { return }
        let input = overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        pauseLLMTask?.cancel()
        pauseLLMTask = Task { [weak self] in
            guard let self else { return }
            self.setEnhancingState(true)
            defer {
                self.setEnhancingState(false)
                self.pauseLLMTask = nil
            }

            do {
                switch self.enhancementMode {
                case .appleIntelligence:
                    guard let enhancer else { return }
                    if #available(macOS 26.0, *) {
                        let prompt = self.resolvedEnhancementPrompt()
                        let enhanced = try await enhancer.enhance(input, systemPrompt: prompt)
                        guard !Task.isCancelled else { return }
                        guard self.isSessionActive else { return }

                        // Apply only if text has not moved forward during this pause.
                        let current = self.overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if current == input {
                            self.mlxTranscriber?.transcribedText = enhanced
                        }
                    }

                case .customLLM:
                    guard self.customLLMManager.isModelDownloaded(repo: self.customLLMManager.currentModelRepo) else {
                        return
                    }
                    let prompt = self.resolvedEnhancementPrompt()
                    let enhanced = try await self.customLLMManager.enhance(input, systemPrompt: prompt)
                    guard !Task.isCancelled else { return }
                    guard self.isSessionActive else { return }

                    // Apply only if text has not moved forward during this pause.
                    let current = self.overlayState.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if current == input {
                        self.mlxTranscriber?.transcribedText = enhanced
                    }

                case .off:
                    return
                }
            } catch {
                VoxtLog.warning("Pause-time LLM enhancement skipped: \(error)")
            }
        }
    }

    func finishSession(after delay: TimeInterval = 0) {
        pendingSessionFinishTask?.cancel()
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil

        let resolvedDelay = delay > 0 ? delay : sessionFinishDelay
        overlayState.isCompleting = resolvedDelay > 0
        pendingSessionFinishTask = Task { [weak self] in
            guard let self else { return }

            if resolvedDelay > 0 {
                do {
                    try await Task.sleep(for: .seconds(resolvedDelay))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            self.overlayWindow.hide()
            if self.interactionSoundsEnabled {
                self.interactionSoundPlayer.playEnd()
            }
            self.isSessionActive = false
            self.sessionOutputMode = .transcription
            self.isSelectedTextTranslationFlow = false
            self.enhancementContextSnapshot = nil
            self.overlayState.isCompleting = false
            self.pendingSessionFinishTask = nil
        }
    }

    func showOverlayStatus(_ message: String, clearAfter seconds: TimeInterval = 2.4) {
        overlayStatusClearTask?.cancel()
        overlayState.statusMessage = message
        overlayStatusClearTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            if self.overlayState.statusMessage == message {
                self.overlayState.statusMessage = ""
            }
            self.overlayStatusClearTask = nil
        }
    }

    func showOverlayReminder(_ message: String, autoHideAfter seconds: TimeInterval = 2.4) {
        overlayReminderTask?.cancel()
        overlayStatusClearTask?.cancel()
        overlayState.reset()
        overlayState.statusMessage = message
        overlayWindow.show(state: overlayState, position: overlayPosition)

        overlayReminderTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self.overlayWindow.hide()
            self.overlayState.reset()
            self.overlayReminderTask = nil
        }
    }

    func setEnhancingState(_ isEnhancing: Bool) {
        overlayState.isEnhancing = isEnhancing
        if transcriptionEngine == .mlxAudio {
            mlxTranscriber?.isEnhancing = isEnhancing
        } else {
            speechTranscriber.isEnhancing = isEnhancing
        }
    }

    private var isMLXReady: Bool {
        switch mlxModelManager.state {
        case .downloaded, .ready, .loading:
            return true
        default:
            return false
        }
    }

    private func processTranslatedTranscription(_ text: String) {
        VoxtLog.info(
            "Translation flow started. inputChars=\(text.count), targetLanguage=\(translationTargetLanguage.instructionName), enhancementMode=\(enhancementMode.rawValue)"
        )
        setEnhancingState(true)
        Task {
            defer {
                self.setEnhancingState(false)
                self.finishSession()
            }

            let llmStartedAt = Date()
            do {
                // Translation mode uses a two-stage LLM pipeline for better quality:
                // 1) enhancement with app-branch prompt, 2) translation with translation prompt.
                let enhanced = try await self.enhanceTextIfNeeded(text, useAppBranchPrompt: true)
                let translated = try await self.translateText(enhanced, targetLanguage: self.translationTargetLanguage)
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                if self.looksUntranslated(source: text, result: translated) {
                    VoxtLog.warning("Translation output may be untranslated. sourceChars=\(text.count), outputChars=\(translated.count)")
                }
                VoxtLog.info("Translation flow succeeded. outputChars=\(translated.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.commitTranscription(translated, llmDurationSeconds: llmDuration)
            } catch {
                VoxtLog.warning("Translation flow failed, using raw text: \(error)")
                self.commitTranscription(text, llmDurationSeconds: nil)
            }
        }
    }

    func beginSelectedTextTranslationIfPossible() -> Bool {
        guard translateSelectedTextOnTranslationHotkey else { return false }
        guard !isSessionActive else { return false }
        guard let selectedText = selectedTextFromSystemSelection(),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return false
        }

        pendingSessionFinishTask?.cancel()
        pendingSessionFinishTask = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        pauseLLMTask?.cancel()
        pauseLLMTask = nil
        overlayState.reset()
        overlayState.transcribedText = selectedText
        overlayState.statusMessage = ""
        overlayWindow.show(state: overlayState, position: overlayPosition)

        let startedAt = Date()
        isSessionActive = true
        isSelectedTextTranslationFlow = true
        sessionOutputMode = .translation
        recordingStartedAt = startedAt
        recordingStoppedAt = startedAt
        transcriptionProcessingStartedAt = startedAt
        enhancementContextSnapshot = nil
        lastEnhancementPromptContext = nil

        if interactionSoundsEnabled {
            interactionSoundPlayer.playStart()
        }

        VoxtLog.info("Selected text translation started. inputChars=\(selectedText.count)")
        processSelectedTextTranslation(selectedText)
        return true
    }

    private func enhanceTextIfNeeded(_ text: String, useAppBranchPrompt: Bool = true) async throws -> String {
        let prompt = useAppBranchPrompt ? resolvedEnhancementPrompt() : resolvedGlobalEnhancementPrompt()
        if !useAppBranchPrompt {
            VoxtLog.info("Enhancement prompt source: global/default (translation flow)")
        }
        switch enhancementMode {
        case .off:
            return text
        case .appleIntelligence:
            guard let enhancer else { return text }
            if #available(macOS 26.0, *) {
                return try await enhancer.enhance(text, systemPrompt: prompt)
            }
            return text
        case .customLLM:
            guard customLLMManager.isModelDownloaded(repo: customLLMManager.currentModelRepo) else { return text }
            return try await customLLMManager.enhance(text, systemPrompt: prompt)
        }
    }

    private func translateText(_ text: String, targetLanguage: TranslationTargetLanguage) async throws -> String {
        let resolvedPrompt = resolvedTranslationPrompt(
            targetLanguage: targetLanguage,
            strict: false
        )
        let translationRepo = translationCustomLLMRepo
        VoxtLog.info(
            "Translation request. promptChars=\(resolvedPrompt.count), inputChars=\(text.count), translationRepo=\(translationRepo)"
        )

        switch enhancementMode {
        case .customLLM where customLLMManager.isModelDownloaded(repo: translationRepo):
            VoxtLog.info("Translation provider selected: customLLM(primary)")
            return try await customLLMManager.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: resolvedPrompt,
                modelRepo: translationRepo
            )
        case .customLLM:
            VoxtLog.warning("Translation primary customLLM unavailable: model not downloaded. repo=\(translationRepo)")
            showOverlayStatus(
                String(localized: "Custom LLM model is not installed. Open Settings > Model to install it."),
                clearAfter: 2.5
            )
        default:
            break
        }

        if #available(macOS 26.0, *), let enhancer {
            VoxtLog.info("Translation provider selected: appleIntelligence")
            return try await enhancer.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: resolvedPrompt
            )
        }

        if customLLMManager.isModelDownloaded(repo: translationRepo) {
            VoxtLog.info("Translation provider selected: customLLM(fallback)")
            return try await customLLMManager.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: resolvedPrompt,
                modelRepo: translationRepo
            )
        }

        VoxtLog.warning("Translation provider unavailable: returning original text.")
        return text
    }

    private func translateTextStrict(_ text: String, targetLanguage: TranslationTargetLanguage) async throws -> String {
        let strictPrompt = resolvedTranslationPrompt(
            targetLanguage: targetLanguage,
            strict: true
        )
        let translationRepo = translationCustomLLMRepo
        VoxtLog.info(
            "Strict translation retry. promptChars=\(strictPrompt.count), inputChars=\(text.count), translationRepo=\(translationRepo)"
        )

        switch enhancementMode {
        case .customLLM where customLLMManager.isModelDownloaded(repo: translationRepo):
            return try await customLLMManager.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: strictPrompt,
                modelRepo: translationRepo
            )
        default:
            break
        }

        if #available(macOS 26.0, *), let enhancer {
            return try await enhancer.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: strictPrompt
            )
        }

        if customLLMManager.isModelDownloaded(repo: translationRepo) {
            return try await customLLMManager.translate(
                text,
                targetLanguage: targetLanguage,
                systemPrompt: strictPrompt,
                modelRepo: translationRepo
            )
        }
        return text
    }

    private func resolvedTranslationPrompt(
        targetLanguage: TranslationTargetLanguage,
        strict: Bool
    ) -> String {
        let basePrompt = translationSystemPrompt.replacingOccurrences(
            of: "{target_language}",
            with: targetLanguage.instructionName
        )
        let enforcement = strict
            ? """
            Mandatory translation rules:
            - Translate every linguistic token into \(targetLanguage.instructionName), including very short text (1-3 characters).
            - Output must not copy source-language wording.
            - Keep proper nouns, product names, URLs, emails, and pure numbers/symbols unchanged when needed.
            - Do not add explanations, quotes, or markdown.
            - Return only the translated text.
            """
            : """
            Mandatory translation rules:
            - Translate to \(targetLanguage.instructionName).
            - Keep meaning, tone, names, numbers, and formatting.
            - For short text, still translate when it is linguistic content.
            - Do not output explanations.
            - Return only the translated text.
            """
        return "\(basePrompt)\n\(enforcement)"
    }

    private func processSelectedTextTranslation(_ text: String) {
        setEnhancingState(true)
        Task {
            defer {
                self.setEnhancingState(false)
                self.isSelectedTextTranslationFlow = false
                self.finishSession()
            }

            let llmStartedAt = Date()
            do {
                var translated = try await self.translateText(text, targetLanguage: self.translationTargetLanguage)
                if self.looksUntranslated(source: text, result: translated) {
                    VoxtLog.warning("Selected text translation first-pass looks untranslated. Retrying with strict translation prompt.")
                    translated = try await self.translateTextStrict(text, targetLanguage: self.translationTargetLanguage)
                }
                let llmDuration = Date().timeIntervalSince(llmStartedAt)
                if self.looksUntranslated(source: text, result: translated) {
                    VoxtLog.warning("Selected text translation output may be untranslated. inputChars=\(text.count), outputChars=\(translated.count)")
                }
                VoxtLog.info("Selected text translation succeeded. outputChars=\(translated.count), llmDurationSec=\(String(format: "%.3f", llmDuration))")
                self.overlayState.transcribedText = translated
                self.commitTranscription(translated, llmDurationSeconds: llmDuration)
            } catch {
                VoxtLog.warning("Selected text translation failed, using original selected text: \(error)")
                self.overlayState.transcribedText = text
                self.commitTranscription(text, llmDurationSeconds: nil)
            }
        }
    }

    private func looksUntranslated(source: String, result: String) -> Bool {
        let sourceTrimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultTrimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceTrimmed.isEmpty, !resultTrimmed.isEmpty else { return false }
        return sourceTrimmed.caseInsensitiveCompare(resultTrimmed) == .orderedSame
    }

    private func selectedTextFromSystemSelection() -> String? {
        if let axSelected = selectedTextFromAXFocusedElement(),
           !axSelected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return axSelected
        }
        return selectedTextBySimulatedCopy()
    }

    private func selectedTextFromAXFocusedElement() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusedStatus == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedElement = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        var selectedTextRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )
        guard selectedStatus == .success, let selectedTextRef else {
            return nil
        }

        if let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            return selectedText
        }
        if let selectedText = selectedTextRef as? NSAttributedString, !selectedText.string.isEmpty {
            return selectedText.string
        }
        return nil
    }

    private func selectedTextBySimulatedCopy() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        let cKeyCode: CGKeyCode = 0x08
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        cmdUp?.flags = .maskCommand
        guard cmdDown != nil, cmdUp != nil else { return nil }

        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)
        Thread.sleep(forTimeInterval: 0.06)

        let copied = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        pasteboard.clearContents()
        if let previous, !previous.isEmpty {
            pasteboard.setString(previous, forType: .string)
        }

        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }

    private func commitTranscription(_ text: String, llmDurationSeconds: TimeInterval?) {
        let normalized = normalizedOutputText(text)
        typeText(normalized)
        appendHistoryIfNeeded(text: normalized, llmDurationSeconds: llmDurationSeconds)
    }

    private func normalizedOutputText(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return value }

        // Remove paired wrapping double quotes generated by some LLM responses.
        let left = value.first
        let right = value.last
        let isWrappedByDoubleQuotes =
            (left == "\"" && right == "\"") ||
            (left == "“" && right == "”")

        if isWrappedByDoubleQuotes {
            value.removeFirst()
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value
    }

    private func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string) ?? ""
        let accessibilityTrusted = AXIsProcessTrusted()
        let keepResultInClipboard = autoCopyWhenNoFocusedInput

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard accessibilityTrusted else {
            promptForAccessibilityPermission()
            VoxtLog.warning("Accessibility permission missing. Transcription copied; paste manually after granting permission.")
            return
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            VoxtLog.error("typeText failed: unable to create CGEventSource")
            return
        }

        let vKeyCode: CGKeyCode = 0x09
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        cmdUp?.flags = .maskCommand

        guard cmdDown != nil, cmdUp != nil else {
            VoxtLog.error("typeText failed: unable to create key events")
            return
        }

        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)

        if !keepResultInClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                pasteboard.clearContents()
                if !previous.isEmpty {
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    private func promptForAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func startMLXRecordingSession() {
        let mlx = mlxTranscriber ?? MLXTranscriber(modelManager: mlxModelManager)
        mlxTranscriber = mlx
        overlayState.statusMessage = ""
        mlx.setPreferredInputDevice(selectedInputDeviceID)
        mlx.onTranscriptionFinished = { [weak self] text in
            self?.processTranscription(text)
        }
        overlayState.bind(to: mlx)
        overlayWindow.show(
            state: overlayState,
            position: overlayPosition
        )
        mlx.startRecording()
    }

    private func startSpeechRecordingSession() {
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.speechTranscriber.requestPermissions()
            guard granted else {
                self.showOverlayReminder(
                    String(localized: "Please enable required permissions in Settings > Permissions.")
                )
                return
            }

            self.overlayState.statusMessage = ""
            self.speechTranscriber.onTranscriptionFinished = { [weak self] text in
                self?.processTranscription(text)
            }
            self.overlayState.bind(to: self.speechTranscriber)
            self.overlayWindow.show(
                state: self.overlayState,
                position: self.overlayPosition
            )
            self.speechTranscriber.startRecording()
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    private func preflightPermissionsForRecording() -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            VoxtLog.warning("Recording blocked: microphone permission not granted.")
            showOverlayReminder(
                String(localized: "Microphone permission is required. Enable it in Settings > Permissions.")
            )
            return false
        }

        if transcriptionEngine == .dictation && SFSpeechRecognizer.authorizationStatus() != .authorized {
            VoxtLog.warning("Recording blocked: speech recognition permission not granted for Direct Dictation.")
            showOverlayReminder(
                String(localized: "Speech Recognition permission is required for Direct Dictation. Enable it in Settings > Permissions.")
            )
            return false
        }

        if !AXIsProcessTrusted() {
            showOverlayStatus(
                String(localized: "Please enable required permissions in Settings > Permissions."),
                clearAfter: 2.2
            )
        }

        return true
    }

    private func applyPreferredInputDevice() {
        speechTranscriber.setPreferredInputDevice(selectedInputDeviceID)
        mlxTranscriber?.setPreferredInputDevice(selectedInputDeviceID)
    }

    private func startSilenceMonitoringIfNeeded() {
        silenceMonitorTask?.cancel()
        pauseLLMTask?.cancel()
        pauseLLMTask = nil

        guard transcriptionEngine == .mlxAudio else { return }

        lastSignificantAudioAt = Date()
        didTriggerPauseTranscription = false
        didTriggerPauseLLM = false

        silenceMonitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.isSessionActive {
                guard self.overlayState.isRecording else {
                    do {
                        try await Task.sleep(for: .milliseconds(200))
                    } catch {
                        return
                    }
                    continue
                }

                let level = self.overlayState.audioLevel
                if level > self.silenceAudioLevelThreshold {
                    self.lastSignificantAudioAt = Date()
                    self.didTriggerPauseTranscription = false
                    self.didTriggerPauseLLM = false
                    self.pauseLLMTask?.cancel()
                    self.pauseLLMTask = nil
                    self.setEnhancingState(false)
                } else {
                    let silentDuration = Date().timeIntervalSince(self.lastSignificantAudioAt)

                    if silentDuration >= 2.0, !self.didTriggerPauseTranscription {
                        self.didTriggerPauseTranscription = true
                        self.mlxTranscriber?.forceIntermediateTranscription()
                    }

                    if silentDuration >= 4.0, !self.didTriggerPauseLLM {
                        self.didTriggerPauseLLM = true
                        self.startPauseLLMIfNeeded()
                    }
                }

                do {
                    try await Task.sleep(for: .milliseconds(200))
                } catch {
                    return
                }
            }
        }
    }
}
