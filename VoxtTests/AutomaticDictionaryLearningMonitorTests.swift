import XCTest
@testable import Voxt

@MainActor
final class AutomaticDictionaryLearningMonitorTests: XCTestCase {
    func testBuildsLearningRequestForInPlaceCorrection() {
        let outcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "anthropic ai",
            baselineText: "Please ship anthropic ai today.",
            finalText: "Please ship Anthropic today."
        )

        guard case .ready(let request) = outcome else {
            return XCTFail("Expected ready outcome, got \(outcome)")
        }

        XCTAssertEqual(request.insertedText, "anthropic ai")
        XCTAssertEqual(request.baselineChangedFragment, "anthropic ai")
        XCTAssertEqual(request.finalChangedFragment, "Anthropic")
        XCTAssertLessThanOrEqual(request.editRatio, AutomaticDictionaryLearningMonitor.maximumEditRatio)
    }

    func testBuildsLearningRequestForEqualLengthReplacement() {
        let outcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "Waxed",
            baselineText: "Our app is named Waxed.",
            finalText: "Our app is named Voxt."
        )

        guard case .ready(let request) = outcome else {
            return XCTFail("Expected ready outcome, got \(outcome)")
        }

        XCTAssertEqual(request.baselineChangedFragment, "Waxed")
        XCTAssertEqual(request.finalChangedFragment, "Voxt")
        XCTAssertLessThanOrEqual(request.editRatio, AutomaticDictionaryLearningMonitor.maximumEditRatio)
    }

    func testBuildsLearningRequestForAdjacentEnglishPhraseCorrection() {
        let outcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "你好，您来帮我看一下我们新的公众号里面的 code code 有什么文章。",
            baselineText: "你好，您来帮我看一下我们新的公众号里面的 code code 有什么文章。",
            finalText: "你好，您来帮我看一下我们新的公众号里面的 claude code 有什么文章。"
        )

        guard case .ready(let request) = outcome else {
            return XCTFail("Expected ready outcome, got \(outcome)")
        }

        XCTAssertEqual(request.baselineChangedFragment, "code code")
        XCTAssertEqual(request.finalChangedFragment, "claude code")
        XCTAssertLessThanOrEqual(request.editRatio, AutomaticDictionaryLearningMonitor.maximumEditRatio)
    }

    func testBuildsLearningRequestForMultiClauseChineseCorrectionWithoutMergingWholeSentence() {
        let outcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "看一下我们投坑中有没有新的词源了。这个新的词源也需要接飞。",
            baselineText: "看一下我们投坑中有没有新的词源了。这个新的词源也需要接飞。",
            finalText: "看一下我们投坑中有没有新的词元了。这个新的词元也需要接入。"
        )

        guard case .ready(let request) = outcome else {
            return XCTFail("Expected ready outcome, got \(outcome)")
        }

        XCTAssertEqual(request.baselineChangedFragment, "词源")
        XCTAssertEqual(request.finalChangedFragment, "词元")
        XCTAssertLessThanOrEqual(request.editRatio, AutomaticDictionaryLearningMonitor.maximumEditRatio)
    }

    func testDirectCandidateTermsFallbackReturnsFinalCorrectedToolName() {
        let request = AutomaticDictionaryLearningRequest(
            insertedText: "帮我看一下我们的 WeChat 里面有没有 Cloud Code 新发的消息。",
            baselineContext: "帮我看一下我们的 WeChat 里面有没有 Cloud Code 新发的消息。",
            finalContext: "帮我看一下我们的 WeChat 里面有没有 Claude Code 新发的消息。",
            baselineChangedFragment: "Cloud Code",
            finalChangedFragment: "Claude Code",
            editRatio: 0.12
        )

        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.directCandidateTerms(
                for: request,
                existingTerms: ["Voxt"]
            ),
            ["Claude Code"]
        )
    }

    func testBuildsLearningRequestWhenBaselineWrapsInsertedTextAcrossLines() {
        let outcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "React JS 和 Next JS",
            baselineText: "我们使用了 React JS\n和 Next JS 来实现整个 APP 的链路。",
            finalText: "我们使用了 React 和 Next JS 来实现整个 APP 的链路。"
        )

        guard case .ready(let request) = outcome else {
            return XCTFail("Expected ready outcome, got \(outcome)")
        }

        XCTAssertEqual(request.baselineChangedFragment, "JS")
        XCTAssertEqual(request.finalChangedFragment, "")
        XCTAssertLessThanOrEqual(request.editRatio, AutomaticDictionaryLearningMonitor.maximumEditRatio)
    }

    func testBuildsLearningRequestFromTerminalLineWhenFinalSnapshotContainsCommandOutput() {
        let outcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "你帮我看一下我们的 Go Host 能不能识别我们现在 APP 中的内容呀？",
            baselineText: """
            ~/x/doit/voxt-service
            > 你帮我看一下我们的 Go Host 能不能识别我们现在 APP 中的内容呀？
            """,
            finalText: """
            > 你帮我看一下我们的 Ghostty 能不能识别我们现在 APP 中的内容呀？
            zsh: command not found: 你帮我看一下我们的

            ~/x/doit/voxt-service
            """
        )

        guard case .ready(let request) = outcome else {
            return XCTFail("Expected ready outcome, got \(outcome)")
        }

        XCTAssertEqual(request.baselineChangedFragment, "Go Host")
        XCTAssertEqual(request.finalChangedFragment, "Ghostty")
        XCTAssertLessThanOrEqual(request.editRatio, AutomaticDictionaryLearningMonitor.maximumEditRatio)
    }

    func testObservationScopedTextPrefersEchoedCommandLineAfterPromptClears() {
        let scopedText = AutomaticDictionaryLearningMonitor.observationScopedText(
            insertedText: "看一下我们投坑中有没有新的词源了。这个新的词源是也需要接飞的。",
            baselineText: """
            ~/x/doit/voxt-service  main !20 ?9
            > 看一下我们投坑中有没有新的词源了。这个新的词源是也需要接飞的。
            """,
            currentText: """
            > 看一下我们 token 中有没有新的词元了。这个新的词元也需要计费。
            zsh: command not found: 看一下我们

            ~/x/doit/voxt-service  main !20 ?9
            >
            """
        )

        XCTAssertEqual(
            scopedText,
            "看一下我们 token 中有没有新的词元了。这个新的词元也需要计费。"
        )
    }

    func testObservationSettlesAfterEchoedCommandContainsCompletedReplacement() {
        let baselineText = "看一下我们投坑中有没有新的词源了。这个新的词源是也需要接飞的。"
        let echoedFinalText = "看一下我们 token 中有没有新的词元了。这个新的词元也需要计费。"

        XCTAssertFalse(
            AutomaticDictionaryLearningMonitor.shouldContinueObservingForPotentialReplacement(
                baselineText: baselineText,
                currentFinalText: echoedFinalText
            )
        )
    }

    func testBuildsLearningRequestWithExpandedTokenBoundaryFragments() {
        let outcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "你帮我识别一下 WeChat 中的输入文本，我们是支持的吗？还有我们要支持一下 SG 狼魔鬼穷的文本查询。",
            baselineText: "你帮我识别一下 WeChat 中的输入文本，我们是支持的吗？还有我们要支持一下 SG 狼魔鬼穷的文本查询。",
            finalText: "你帮我识别一下 WeChat 中的输入文本，我们是支持的吗？还有我们要支持一下 SGLang 魔鬼群的文本查询。"
        )

        guard case .ready(let request) = outcome else {
            return XCTFail("Expected ready outcome, got \(outcome)")
        }

        XCTAssertTrue(request.baselineChangedFragment.hasPrefix("SG 狼魔鬼穷"))
        XCTAssertTrue(request.finalChangedFragment.hasPrefix("SGLang 魔鬼群"))
        XCTAssertLessThanOrEqual(request.editRatio, AutomaticDictionaryLearningMonitor.maximumEditRatio)
    }

    func testBuildsLearningRequestByComparingInsertedTextAgainstFinalScopedLine() {
        let outcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "你好，你帮我们看一下 WeChat 中的 SG 骆魔鬼群，他们用户在说什么？",
            baselineText: """
            > 你帮我看一下我们的 Ghostty 能不能识别我们现在 APP 中的内容呀？
            zsh: command not found: 你帮我看一下我们的

             ~/x/doit/voxt-service  main !20 ?9
            > 你好，你帮我们看一下 WeChat 中的 SG 骆魔鬼群，他们用户在说什么？
            """,
            finalText: """
            > 你帮我看一下我们的 Ghostty 能不能识别我们现在 APP 中的内容呀？
            zsh: command not found: 你帮我看一下我们的
            > 你好，你帮我们看一下 WeChat 中的 SGLang魔鬼群，他们用户在说什么？
            zsh: command not found: 你好，你帮我们看一下

             ~/x/doit/voxt-service  main !20 ?9
            >
            """
        )

        guard case .ready(let request) = outcome else {
            return XCTFail("Expected ready outcome, got \(outcome)")
        }

        XCTAssertEqual(
            request.baselineContext,
            "你好，你帮我们看一下 WeChat 中的 SG 骆魔鬼群，他们用户在说什么？"
        )
        XCTAssertEqual(
            request.finalContext,
            "你好，你帮我们看一下 WeChat 中的 SGLang魔鬼群，他们用户在说什么？"
        )
        XCTAssertEqual(request.baselineChangedFragment, "SG 骆魔鬼群")
        XCTAssertEqual(request.finalChangedFragment, "SGLang魔鬼群")
        XCTAssertLessThanOrEqual(request.editRatio, AutomaticDictionaryLearningMonitor.maximumEditRatio)
    }

    func testContinuesObservingWhenLatestEditLooksLikeDeletionOnly() {
        XCTAssertTrue(
            AutomaticDictionaryLearningMonitor.shouldContinueObservingForPotentialReplacement(
                baselineText: "我们配合 Go Hoste 来实现 Terminal CLI 的输入。",
                currentFinalText: "我们配合  来实现 Terminal CLI 的输入。"
            )
        )
    }

    func testDoesNotContinueObservingWhenReplacementTextAlreadyExists() {
        XCTAssertFalse(
            AutomaticDictionaryLearningMonitor.shouldContinueObservingForPotentialReplacement(
                baselineText: "我们配合 Go Hoste 来实现 Terminal CLI 的输入。",
                currentFinalText: "我们配合 Ghostty 来实现 Terminal CLI 的输入。"
            )
        )
    }

    func testObservationStopsAfterConsecutiveMissingSnapshotsBeforeAnyEdit() {
        var state = AutomaticDictionaryLearningObservationState(
            baselineText: "baseline"
        )

        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .continueObserving
        )
        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .continueObserving
        )
        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .stopWithoutAnalysis
        )
    }

    func testObservationSettlesAfterConsecutiveMissingSnapshotsOnceEditIsIdle() {
        var state = AutomaticDictionaryLearningObservationState(
            baselineText: "我们配合 Go Hoste 来实现 Terminal CLI 的输入。"
        )
        state.latestText = "我们配合 Ghostty 来实现 Terminal CLI 的输入。"
        state.didObserveChange = true
        state.lastChangeElapsedSeconds = AutomaticDictionaryLearningMonitor.idleSettleSeconds + 0.1

        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .continueObserving
        )
        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .continueObserving
        )
        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .settleForAnalysis(finalText: "我们配合 Ghostty 来实现 Terminal CLI 的输入。")
        )
    }

    func testObservationDoesNotSettleAfterMissingSnapshotsBeforeIdleThreshold() {
        var state = AutomaticDictionaryLearningObservationState(
            baselineText: "我们配合 Go Hoste 来实现 Terminal CLI 的输入。"
        )
        state.latestText = "我们配合 Ghostty 来实现 Terminal CLI 的输入。"
        state.didObserveChange = true
        state.lastChangeElapsedSeconds = AutomaticDictionaryLearningMonitor.idleSettleSeconds - 0.1

        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .continueObserving
        )
        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .continueObserving
        )
        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .continueObserving
        )
    }

    func testObservationDoesNotSettleAfterMissingSnapshotsWhenReplacementStillIncomplete() {
        var state = AutomaticDictionaryLearningObservationState(
            baselineText: "你好，你帮我看一下我们的微信中有没有新的消息，特别是 Cloud Code 和我们的 Go Host。我们为了识别 Terminal CLI，做了一些优化。"
        )
        state.latestText = "你好，你帮我看一下我们的微信中有没有新的消息，特别是 Claude Code 和我们的 。我们为了识别 Terminal CLI，做了一些优化。"
        state.didObserveChange = true
        state.lastChangeElapsedSeconds = AutomaticDictionaryLearningMonitor.idleSettleSeconds + 0.1

        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .continueObserving
        )
        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .continueObserving
        )
        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state),
            .continueObserving
        )
    }

    func testObservationContinuesWhenIdleSnapshotStillLooksLikeDeletionOnly() {
        var state = AutomaticDictionaryLearningObservationState(
            baselineText: "我们配合 Go Hoste 来实现 Terminal CLI 的输入。"
        )
        state.latestText = "我们配合  来实现 Terminal CLI 的输入。"
        state.didObserveChange = true

        let decision = AutomaticDictionaryLearningMonitor.observeSnapshot(
            text: "我们配合  来实现 Terminal CLI 的输入。",
            elapsedSinceLastChange: AutomaticDictionaryLearningMonitor.idleSettleSeconds + 0.1,
            state: &state
        )

        XCTAssertEqual(decision, .continueObserving)
    }

    func testObservationContinuesWhenIdleSnapshotStillContainsUnfinishedDeletionGroup() {
        var state = AutomaticDictionaryLearningObservationState(
            baselineText: "你好，你帮我看一下我们的微信中有没有新的消息，特别是 Cloud Code 和我们的 Go Host。我们为了识别 Terminal CLI，做了一些优化。"
        )
        state.latestText = "你好，你帮我看一下我们的微信中有没有新的消息，特别是 Claude Code 和我们的 。我们为了识别 Terminal CLI，做了一些优化。"
        state.didObserveChange = true

        let decision = AutomaticDictionaryLearningMonitor.observeSnapshot(
            text: state.latestText,
            elapsedSinceLastChange: AutomaticDictionaryLearningMonitor.idleSettleSeconds + 0.1,
            state: &state
        )

        XCTAssertEqual(decision, .continueObserving)
    }

    func testObservationSettlesWhenIdleSnapshotContainsCompletedReplacement() {
        var state = AutomaticDictionaryLearningObservationState(
            baselineText: "我们配合 Go Hoste 来实现 Terminal CLI 的输入。"
        )
        state.latestText = "我们配合 Ghostty 来实现 Terminal CLI 的输入。"
        state.didObserveChange = true

        let decision = AutomaticDictionaryLearningMonitor.observeSnapshot(
            text: "我们配合 Ghostty 来实现 Terminal CLI 的输入。",
            elapsedSinceLastChange: AutomaticDictionaryLearningMonitor.idleSettleSeconds + 0.1,
            state: &state
        )

        XCTAssertEqual(
            decision,
            .settleForAnalysis(finalText: "我们配合 Ghostty 来实现 Terminal CLI 的输入。")
        )
    }

    func testStableFocusedEditDoesNotFinalizeObservationImmediately() {
        XCTAssertFalse(
            AutomaticDictionaryLearningMonitor.shouldFinalizeWhileFocused(
                decision: .settleForAnalysis(finalText: "Claude Code")
            )
        )
    }

    func testObservationResetsMissingCounterWhenFocusedSnapshotReturns() {
        var state = AutomaticDictionaryLearningObservationState(
            baselineText: "baseline"
        )
        _ = AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state)
        _ = AutomaticDictionaryLearningMonitor.observeMissingSnapshot(state: &state)

        let decision = AutomaticDictionaryLearningMonitor.observeSnapshot(
            text: "baseline",
            elapsedSinceLastChange: nil,
            state: &state
        )

        XCTAssertEqual(decision, .continueObserving)
        XCTAssertEqual(state.consecutiveMissingSnapshots, 0)
        XCTAssertFalse(state.didObserveChange)
    }

    func testObservationSettlesAfterDeletionIntermediateWhenReplacementIsCompleted() {
        var state = AutomaticDictionaryLearningObservationState(
            baselineText: "我们配合 Go Hoste 来实现 Terminal CLI 的输入。"
        )
        state.latestText = "我们配合  来实现 Terminal CLI 的输入。"
        state.didObserveChange = true

        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeSnapshot(
                text: "我们配合 Ghostty 来实现 Terminal CLI 的输入。",
                elapsedSinceLastChange: 0.2,
                state: &state
            ),
            .continueObserving
        )

        XCTAssertEqual(
            AutomaticDictionaryLearningMonitor.observeSnapshot(
                text: "我们配合 Ghostty 来实现 Terminal CLI 的输入。",
                elapsedSinceLastChange: AutomaticDictionaryLearningMonitor.idleSettleSeconds + 0.1,
                state: &state
            ),
            .settleForAnalysis(finalText: "我们配合 Ghostty 来实现 Terminal CLI 的输入。")
        )
    }

    func testObservationRegistersNewInputChangeAndResetsMissingCounter() {
        var state = AutomaticDictionaryLearningObservationState(
            baselineText: "baseline"
        )
        state.consecutiveMissingSnapshots = 2

        let decision = AutomaticDictionaryLearningMonitor.observeSnapshot(
            text: "baseline updated",
            elapsedSinceLastChange: nil,
            state: &state
        )

        XCTAssertEqual(decision, .continueObserving)
        XCTAssertEqual(state.latestText, "baseline updated")
        XCTAssertTrue(state.didObserveChange)
        XCTAssertEqual(state.consecutiveMissingSnapshots, 0)
        XCTAssertEqual(state.lastChangeElapsedSeconds, 0)
    }

    func testRejectsPureAppendAfterInsertion() {
        let outcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "hello",
            baselineText: "hello",
            finalText: "hello world"
        )

        assertSkipped(outcome, contains: "does not intersect inserted text")
    }

    func testRejectsUnrelatedEditsOutsideInsertedText() {
        let outcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "Anthropic",
            baselineText: "Anthropic works. tomorrow 3pm",
            finalText: "Anthropic works. tomorrow 4pm"
        )

        assertSkipped(outcome, contains: "does not intersect inserted text")
    }

    func testRejectsLargeRewrite() {
        let outcome = AutomaticDictionaryLearningMonitor.makeLearningRequest(
            insertedText: "short note",
            baselineText: "short note",
            finalText: "Completely different long paragraph with multiple rewritten clauses and unrelated content."
        )

        assertSkipped(outcome, contains: "edit ratio")
    }

    func testBuildPromptResolvesTemplateVariables() {
        let request = AutomaticDictionaryLearningRequest(
            insertedText: "anthropic ai",
            baselineContext: "Please ship anthropic ai today.",
            finalContext: "Please ship Anthropic today.",
            baselineChangedFragment: "anthropic ai",
            finalChangedFragment: "Anthropic",
            editRatio: 0.2
        )

        let prompt = AutomaticDictionaryLearningMonitor.buildPrompt(
            template: """
            \(AppPreferenceKey.automaticDictionaryLearningMainLanguageTemplateVariable)
            \(AppPreferenceKey.automaticDictionaryLearningOtherLanguagesTemplateVariable)
            \(AppPreferenceKey.automaticDictionaryLearningInsertedTextTemplateVariable)
            \(AppPreferenceKey.automaticDictionaryLearningFinalFragmentTemplateVariable)
            \(AppPreferenceKey.automaticDictionaryLearningExistingTermsTemplateVariable)
            """,
            for: request,
            existingTerms: ["OpenAI", "Claude"],
            userMainLanguage: "Chinese",
            userOtherLanguages: "English"
        )

        XCTAssertTrue(prompt.contains("Chinese"))
        XCTAssertTrue(prompt.contains("English"))
        XCTAssertTrue(prompt.contains("anthropic ai"))
        XCTAssertTrue(prompt.contains("Anthropic"))
        XCTAssertTrue(prompt.contains("- OpenAI"))
        XCTAssertTrue(prompt.contains("- Claude"))
        XCTAssertFalse(prompt.contains(AppPreferenceKey.automaticDictionaryLearningExistingTermsTemplateVariable))
    }

    func testBuildPromptUsesEmptyPlaceholderForExistingTerms() {
        let request = AutomaticDictionaryLearningRequest(
            insertedText: "Voxt",
            baselineContext: "Voxt",
            finalContext: "Voxt",
            baselineChangedFragment: "vox",
            finalChangedFragment: "Voxt",
            editRatio: 0.1
        )

        let prompt = AutomaticDictionaryLearningMonitor.buildPrompt(
            template: AppPreferenceKey.automaticDictionaryLearningExistingTermsTemplateVariable,
            for: request,
            existingTerms: [],
            userMainLanguage: "Chinese",
            userOtherLanguages: "English"
        )

        XCTAssertTrue(prompt.contains("(empty)"))
    }

    func testBuildPromptCapsExistingTermListToTwentyItems() {
        let request = AutomaticDictionaryLearningRequest(
            insertedText: "Voxt",
            baselineContext: "Voxt",
            finalContext: "Voxt",
            baselineChangedFragment: "vox",
            finalChangedFragment: "Voxt",
            editRatio: 0.1
        )

        let existingTerms = (1...100).map { "Term\($0)" }
        let prompt = AutomaticDictionaryLearningMonitor.buildPrompt(
            template: AppPreferenceKey.automaticDictionaryLearningExistingTermsTemplateVariable,
            for: request,
            existingTerms: existingTerms,
            userMainLanguage: "Chinese",
            userOtherLanguages: "English"
        )

        XCTAssertTrue(prompt.contains("- Term1"))
        XCTAssertTrue(prompt.contains("- Term20"))
        XCTAssertFalse(prompt.contains("- Term21"))
    }

    private func assertSkipped(
        _ outcome: AutomaticDictionaryLearningMonitor.RequestOutcome,
        contains expectedReasonFragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .skipped(let reason) = outcome else {
            return XCTFail("Expected skipped outcome, got \(outcome)", file: file, line: line)
        }
        XCTAssertTrue(
            reason.contains(expectedReasonFragment),
            "Expected reason to contain '\(expectedReasonFragment)', got '\(reason)'",
            file: file,
            line: line
        )
    }
}
