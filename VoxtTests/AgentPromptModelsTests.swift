import XCTest
@testable import Voxt

@MainActor
final class AgentPromptModelsTests: XCTestCase {
    func testAnsweredToolResponseProducesStructuredPayload() {
        let response = AgentPromptToolResponse.answered("Need the remote branch, not main.")

        XCTAssertEqual(response.responsePayload["status"] as? String, "answered")
        XCTAssertEqual(response.responsePayload["transcript"] as? String, "Need the remote branch, not main.")
        XCTAssertNil(response.responsePayload["error_code"])
    }

    func testQuestionSummaryUsesFirstQuestionAndCount() {
        let request = AgentPromptRequest(
            id: UUID(),
            questions: ["Which branch should I target?", "Should I also update docs?"],
            contextHint: "Pull request feedback",
            timeoutSeconds: 180
        )

        XCTAssertEqual(request.questionSummary, "Which branch should I target? +1")
    }

    func testEndpointURLUsesLoopbackAndConfiguredPort() {
        XCTAssertEqual(
            AgentMCPServerController.endpointURLString(for: 51090),
            "http://127.0.0.1:51090/mcp"
        )
    }
}
