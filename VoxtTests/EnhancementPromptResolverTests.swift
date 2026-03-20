import XCTest
@testable import Voxt

final class EnhancementPromptResolverTests: XCTestCase {
    func testDisabledAppBranchFallsBackToGlobalPrompt() {
        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Clean {{RAW_TRANSCRIPTION}} for {{USER_MAIN_LANGUAGE}}",
                rawTranscription: "hello",
                userMainLanguagePromptValue: "English",
                dictionaryGlossary: "- OpenAI",
                appEnhancementEnabled: false,
                groups: [],
                urlsByID: [:],
                frontmostBundleID: nil,
                focusedAppName: "Notes",
                normalizedActiveURL: nil,
                supportedBrowserBundleIDs: []
            )
        )

        XCTAssertEqual(output.delivery, .systemPrompt)
        XCTAssertEqual(output.promptContext.focusedAppName, "Notes")
        XCTAssertContains(output.content, "Clean hello for English")
        XCTAssertContains(output.content, "Dictionary Guidance")
        XCTAssertEqual(output.source, .globalDefault(.appBranchDisabled))
    }

    func testBrowserURLMatchUsesGroupPromptAndUserMessageDelivery() {
        let docsID = UUID()
        let docsGroup = TestFactories.makeAppBranchGroup(
            name: "Docs",
            prompt: "Docs {{RAW_TRANSCRIPTION}} {{USER_MAIN_LANGUAGE}}",
            urlPatternIDs: [docsID]
        )

        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Global",
                rawTranscription: "fix this",
                userMainLanguagePromptValue: "English",
                dictionaryGlossary: nil,
                appEnhancementEnabled: true,
                groups: [docsGroup],
                urlsByID: [docsID: "example.com/docs/*"],
                frontmostBundleID: "com.google.Chrome",
                focusedAppName: "Google Chrome",
                normalizedActiveURL: "example.com/docs/page",
                supportedBrowserBundleIDs: ["com.google.Chrome"]
            )
        )

        XCTAssertEqual(output.delivery, .userMessage)
        XCTAssertEqual(output.promptContext.matchedGroupID, docsGroup.id)
        XCTAssertEqual(output.promptContext.matchedURLGroupName, "Docs")
        XCTAssertContains(output.content, "Docs fix this English")
    }

    func testBrowserWithoutURLFallsBackAndKeepsContextEmpty() {
        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Global",
                rawTranscription: "fix this",
                userMainLanguagePromptValue: "English",
                dictionaryGlossary: nil,
                appEnhancementEnabled: true,
                groups: [TestFactories.makeAppBranchGroup(name: "Docs", prompt: "Prompt")],
                urlsByID: [:],
                frontmostBundleID: "com.google.Chrome",
                focusedAppName: "Google Chrome",
                normalizedActiveURL: nil,
                supportedBrowserBundleIDs: ["com.google.Chrome"]
            )
        )

        XCTAssertEqual(output.delivery, .systemPrompt)
        XCTAssertNil(output.promptContext.matchedGroupID)
        XCTAssertEqual(output.source, .globalDefault(.browserURLUnavailable(bundleID: "com.google.Chrome")))
    }

    func testAppGroupMatchUsesAppPrompt() {
        let group = TestFactories.makeAppBranchGroup(
            name: "Xcode",
            prompt: "Xcode {{RAW_TRANSCRIPTION}}",
            appBundleIDs: ["com.apple.dt.Xcode"]
        )

        let output = EnhancementPromptResolver.resolve(
            .init(
                globalPrompt: "Global",
                rawTranscription: "rewrite",
                userMainLanguagePromptValue: "English",
                dictionaryGlossary: nil,
                appEnhancementEnabled: true,
                groups: [group],
                urlsByID: [:],
                frontmostBundleID: "com.apple.dt.Xcode",
                focusedAppName: "Xcode",
                normalizedActiveURL: nil,
                supportedBrowserBundleIDs: []
            )
        )

        XCTAssertEqual(output.delivery, .userMessage)
        XCTAssertEqual(output.promptContext.matchedAppGroupName, "Xcode")
        XCTAssertContains(output.content, "Xcode rewrite")
    }
}

