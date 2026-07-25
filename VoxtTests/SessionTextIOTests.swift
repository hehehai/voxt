// SessionTextIOTests.swift
// Provides Session Text IOTests for Voxt test coverage.

import XCTest
@testable import Voxt

@MainActor
final class SessionTextIOTests: XCTestCase {
    func testSelectedTextDictionaryHotkeyAcceptsThirtyCharacters() {
        let candidate = String(repeating: "词", count: 30)
        XCTAssertEqual(SelectedTextDictionaryHotkeySupport.candidateTerm(from: candidate), candidate)
    }

    func testSelectedTextDictionaryHotkeyRejectsMoreThanThirtyCharacters() {
        let candidate = String(repeating: "词", count: 31)
        XCTAssertNil(SelectedTextDictionaryHotkeySupport.candidateTerm(from: candidate))
    }

    func testSelectedTextDictionaryHotkeyTrimsWhitespace() {
        XCTAssertEqual(
            SelectedTextDictionaryHotkeySupport.candidateTerm(from: "  OpenAI\n"),
            "OpenAI"
        )
    }

    func testSelectedTextDictionaryHotkeyRejectsEmptySelection() {
        XCTAssertNil(SelectedTextDictionaryHotkeySupport.candidateTerm(from: " \n "))
        XCTAssertNil(SelectedTextDictionaryHotkeySupport.candidateTerm(from: nil))
    }

    func testSelectedTextSystemSelectionRejectsCaretOnlyRange() {
        XCTAssertFalse(SelectedTextSystemSelectionSupport.hasNonEmptySelectedTextRange(length: 0))
    }

    func testSelectedTextSystemSelectionAcceptsNonEmptyRange() {
        XCTAssertTrue(SelectedTextSystemSelectionSupport.hasNonEmptySelectedTextRange(length: 1))
        XCTAssertTrue(SelectedTextSystemSelectionSupport.hasNonEmptySelectedTextRange(length: 12))
    }

    func testSimulatedCopyPolicyByAXEvidenceClass() {
        // Caret-only range: deny.
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.shouldAttemptSimulatedCopy(
                focusedElementAvailable: true,
                selectedTextRange: CFRange(location: 12, length: 0),
                isBrowser: false,
                copiesLineOnEmptySelection: false
            )
        )

        // Non-empty range: allow recovery copy.
        XCTAssertTrue(
            SelectedTextSystemSelectionSupport.shouldAttemptSimulatedCopy(
                focusedElementAvailable: true,
                selectedTextRange: CFRange(location: 0, length: 4),
                isBrowser: false,
                copiesLineOnEmptySelection: false
            )
        )

        // AX focus dead, but app does not invent a line copy (e.g. WeChat).
        XCTAssertTrue(
            SelectedTextSystemSelectionSupport.shouldAttemptSimulatedCopy(
                focusedElementAvailable: false,
                selectedTextRange: nil,
                isBrowser: false,
                copiesLineOnEmptySelection: false
            )
        )

        // AX focus dead + line-copy editor (Cursor / VS Code): deny.
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.shouldAttemptSimulatedCopy(
                focusedElementAvailable: false,
                selectedTextRange: nil,
                isBrowser: false,
                copiesLineOnEmptySelection: true
            )
        )

        // Focused editor without range attribute: deny.
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.shouldAttemptSimulatedCopy(
                focusedElementAvailable: true,
                selectedTextRange: nil,
                isBrowser: false,
                copiesLineOnEmptySelection: false
            )
        )

        // Browser focused without range attribute: allow.
        XCTAssertTrue(
            SelectedTextSystemSelectionSupport.shouldAttemptSimulatedCopy(
                focusedElementAvailable: true,
                selectedTextRange: nil,
                isBrowser: true,
                copiesLineOnEmptySelection: false
            )
        )
    }

    func testAXBlackoutClipboardProbeOnlyWhenLineCopyEditorHasNoAXSurface() {
        XCTAssertTrue(
            SelectedTextSystemSelectionSupport.shouldAttemptAXBlackoutClipboardProbe(
                focusedElementAvailable: false,
                axWindowCandidatesAvailable: false,
                copiesLineOnEmptySelection: true
            )
        )
        // Still have window candidates: keep denying unfiltered Cmd+C.
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.shouldAttemptAXBlackoutClipboardProbe(
                focusedElementAvailable: false,
                axWindowCandidatesAvailable: true,
                copiesLineOnEmptySelection: true
            )
        )
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.shouldAttemptAXBlackoutClipboardProbe(
                focusedElementAvailable: false,
                axWindowCandidatesAvailable: false,
                copiesLineOnEmptySelection: false
            )
        )
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.shouldAttemptAXBlackoutClipboardProbe(
                focusedElementAvailable: true,
                axWindowCandidatesAvailable: false,
                copiesLineOnEmptySelection: true
            )
        )
    }

    func testLooksLikeEmptySelectionLineCopyRecognizesClipboardCapabilityShape() {
        XCTAssertTrue(
            SelectedTextSystemSelectionSupport.looksLikeEmptySelectionLineCopy(
                rawClipboardText: "    const foo = 1;\n"
            )
        )
        XCTAssertTrue(
            SelectedTextSystemSelectionSupport.looksLikeEmptySelectionLineCopy(
                rawClipboardText: "single line\r\n"
            )
        )
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.looksLikeEmptySelectionLineCopy(
                rawClipboardText: "selectedWord"
            )
        )
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.looksLikeEmptySelectionLineCopy(
                rawClipboardText: "line one\nline two\n"
            )
        )
    }

    func testCopiesCurrentLineWhenSelectionEmptyRecognizesEditorFamilies() {
        let lineCopyEditors = [
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.vscodium",
            "com.todesktop.230313mzl4w4u92", // Cursor
            "com.exafunction.windsurf",
            "com.google.antigravity",
            "com.jetbrains.intellij",
            "com.jetbrains.WebStorm",
            "com.sublimetext.4",
            "dev.zed.Zed",
            "com.trae.app",
            "cn.trae.app",
            "com.qoder.app",
            "org.example.MyVSCodeFork"
        ]
        for bundleID in lineCopyEditors {
            XCTAssertTrue(
                SelectedTextSystemSelectionSupport.copiesCurrentLineWhenSelectionEmpty(bundleID: bundleID),
                "Expected line-copy editor classification for \(bundleID)"
            )
        }

        let safeApps = [
            "com.tencent.xinWeChat",
            "com.apple.Safari",
            "com.google.Chrome",
            "com.apple.TextEdit",
            "com.apple.Notes",
            "com.tinyspeck.slackmacgap"
        ]
        for bundleID in safeApps {
            XCTAssertFalse(
                SelectedTextSystemSelectionSupport.copiesCurrentLineWhenSelectionEmpty(bundleID: bundleID),
                "Expected non-line-copy classification for \(bundleID)"
            )
        }
    }

    func testBrowserSelectionScriptsIncludeJavaScriptSelection() {
        let safariScripts = BrowserAutomationScriptBuilder.selectionScripts(
            bundleID: "com.apple.Safari",
            displayName: "Safari"
        )
        XCTAssertFalse(safariScripts.isEmpty)
        XCTAssertTrue(safariScripts.contains(where: { $0.contains("window.getSelection().toString()") }))
        XCTAssertTrue(safariScripts.contains(where: { $0.contains("do JavaScript") }))

        let chromeScripts = BrowserAutomationScriptBuilder.selectionScripts(
            bundleID: "com.google.Chrome",
            displayName: "Google Chrome"
        )
        XCTAssertFalse(chromeScripts.isEmpty)
        XCTAssertTrue(chromeScripts.contains(where: { $0.contains("execute javascript") }))
    }

    func testConfirmedCaretOnlyShortCircuitsFurtherSelectionProbes() {
        XCTAssertTrue(
            SelectedTextSystemSelectionSupport.isConfirmedCaretOnly(
                selectedTextRange: CFRange(location: 8, length: 0)
            )
        )
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.isConfirmedCaretOnly(
                selectedTextRange: CFRange(location: 0, length: 3)
            )
        )
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.isConfirmedCaretOnly(selectedTextRange: nil)
        )
    }

    func testDefinitiveEmptyBrowserSelectionStopsDialectRetries() {
        XCTAssertTrue(
            SelectedTextSystemSelectionSupport.isDefinitiveEmptyBrowserSelection(
                output: "",
                hadExecutionError: false
            )
        )
        XCTAssertTrue(
            SelectedTextSystemSelectionSupport.isDefinitiveEmptyBrowserSelection(
                output: "  \n\t",
                hadExecutionError: false
            )
        )
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.isDefinitiveEmptyBrowserSelection(
                output: "hello",
                hadExecutionError: false
            )
        )
        // Script-form failures should keep trying other dialects.
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.isDefinitiveEmptyBrowserSelection(
                output: nil,
                hadExecutionError: true
            )
        )
        XCTAssertFalse(
            SelectedTextSystemSelectionSupport.isDefinitiveEmptyBrowserSelection(
                output: "",
                hadExecutionError: true
            )
        )
    }

    func testSelectionProbeDenialDetailMatchesCapabilityClasses() {
        XCTAssertEqual(
            SelectedTextSystemSelectionSupport.denialDetail(
                allowCopy: true,
                focusedElementAvailable: false,
                selectedTextRange: nil,
                isBrowser: false,
                copiesLineOnEmptySelection: false
            ),
            "copy-missed"
        )
        XCTAssertEqual(
            SelectedTextSystemSelectionSupport.denialDetail(
                allowCopy: false,
                focusedElementAvailable: false,
                selectedTextRange: nil,
                isBrowser: false,
                copiesLineOnEmptySelection: true
            ),
            "ax-focus-unavailable-line-copy-editor"
        )
        XCTAssertEqual(
            SelectedTextSystemSelectionSupport.denialDetail(
                allowCopy: false,
                focusedElementAvailable: true,
                selectedTextRange: CFRange(location: 3, length: 0),
                isBrowser: false,
                copiesLineOnEmptySelection: false
            ),
            "confirmed-caret-only"
        )
        XCTAssertEqual(
            SelectedTextSystemSelectionSupport.denialDetail(
                allowCopy: false,
                focusedElementAvailable: true,
                selectedTextRange: nil,
                isBrowser: false,
                copiesLineOnEmptySelection: false
            ),
            "focused-without-range-non-browser"
        )
    }

    func testRewriteAlwaysPresentsAnswerOverlay() {
        XCTAssertTrue(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: false
            )
        )
        XCTAssertTrue(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: true
            )
        )
    }

    func testOnlyDirectAnswerRewriteUsesStructuredOutput() {
        XCTAssertTrue(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .rewrite,
                hasSelectedSourceText: true
            )
        )
    }

    func testNonRewriteSessionsDoNotPresentRewriteAnswerOverlay() {
        XCTAssertFalse(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .transcription,
                hasSelectedSourceText: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .transcription,
                hasSelectedSourceText: false
            )
        )

        XCTAssertFalse(
            AppDelegate.shouldPresentRewriteAnswerOverlay(
                sessionOutputMode: .translation,
                hasSelectedSourceText: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldUseStructuredRewriteAnswerOutput(
                sessionOutputMode: .translation,
                hasSelectedSourceText: false
            )
        )
    }

    func testSelectedTextTranslationShowsAnswerOverlayOnlyWhenConfigured() {
        XCTAssertTrue(
            AppDelegate.shouldPresentSelectedTextTranslationAnswerOverlay(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true,
                showResultWindow: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentSelectedTextTranslationAnswerOverlay(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true,
                showResultWindow: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentSelectedTextTranslationAnswerOverlay(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: false,
                showResultWindow: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldPresentSelectedTextTranslationAnswerOverlay(
                sessionOutputMode: .transcription,
                isSelectedTextTranslationFlow: true,
                showResultWindow: true
            )
        )
    }

    func testSelectedTextTranslationAutoInjectFollowsResultWindowToggle() {
        XCTAssertTrue(
            AppDelegate.shouldAutoInjectSelectedTextTranslationResult(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true,
                showResultWindow: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldAutoInjectSelectedTextTranslationResult(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true,
                showResultWindow: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldAutoInjectSelectedTextTranslationResult(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: false,
                showResultWindow: false
            )
        )
    }

    func testPreparedDeliveryContextAppliesDictionaryCorrectionsBeforeDelivery() {
        let matcher = DictionaryMatcher(
            entries: [TestFactories.makeEntry(term: "Anthropic", observedVariants: ["anthropic ai"])],
            blockedGlobalMatchKeys: []
        )

        let context = AppDelegate.preparedDeliveryContext(
            originalText: """
            {"title":"AI Answer","content":"anthropic ai"}
            """,
            llmDurationSeconds: 0.5,
            sessionOutputMode: .rewrite,
            userMainLanguage: .fallbackOption(),
            matcher: matcher,
            usesConservativeEvidence: false,
            automaticReplacementEnabled: true
        )

        XCTAssertEqual(context.outputText, "Anthropic")
        XCTAssertEqual(context.dictionaryCorrectedTerms, ["Anthropic"])
        XCTAssertEqual(context.rewriteAnswerPayload?.title, "AI Answer")
        XCTAssertEqual(context.rewriteAnswerPayload?.content, "Anthropic")
    }

    func testPreparedDeliveryContextKeepsOriginalTextForConservativeDictionaryEvidence() {
        let matcher = DictionaryMatcher(
            entries: [TestFactories.makeEntry(term: "Anthropic", observedVariants: ["anthropic ai"])],
            blockedGlobalMatchKeys: []
        )

        let context = AppDelegate.preparedDeliveryContext(
            originalText: "anthropic ai",
            llmDurationSeconds: nil,
            sessionOutputMode: .transcription,
            userMainLanguage: .fallbackOption(),
            matcher: matcher,
            usesConservativeEvidence: true,
            automaticReplacementEnabled: true
        )

        XCTAssertEqual(context.outputText, "anthropic ai")
        XCTAssertEqual(context.dictionaryCorrectedTerms, [])
        XCTAssertEqual(context.dictionaryMatches.map(\.term), ["Anthropic"])
    }

    func testPreparedDeliveryContextPreservesTextWhenAutomaticReplacementIsDisabled() {
        let matcher = DictionaryMatcher(
            entries: [TestFactories.makeEntry(term: "Anthropic", observedVariants: ["anthropic ai"])],
            blockedGlobalMatchKeys: []
        )

        let context = AppDelegate.preparedDeliveryContext(
            originalText: """
            {"title":"AI Answer","content":"anthropic ai"}
            """,
            llmDurationSeconds: nil,
            sessionOutputMode: .rewrite,
            userMainLanguage: .fallbackOption(),
            matcher: matcher,
            usesConservativeEvidence: false,
            automaticReplacementEnabled: false
        )

        XCTAssertEqual(context.outputText, "anthropic ai")
        XCTAssertEqual(context.dictionaryCorrectedTerms, [])
        XCTAssertEqual(context.dictionaryMatches.map(\.term), ["Anthropic"])
        XCTAssertEqual(context.rewriteAnswerPayload?.content, "anthropic ai")
    }
}
