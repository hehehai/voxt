import XCTest
@testable import Voxt

final class FeaturePromptDraftCoordinatorTests: XCTestCase {
    func testInitSeedsDraftAndSyncedText() {
        let coordinator = FeaturePromptDraftCoordinator(text: "Base prompt")

        XCTAssertEqual(coordinator.draft, "Base prompt")
        XCTAssertEqual(coordinator.lastSyncedText, "Base prompt")
    }

    func testTakePendingPersistReturnsNilWhenDraftMatchesSyncedText() {
        var coordinator = FeaturePromptDraftCoordinator(text: "Base prompt")

        XCTAssertNil(coordinator.takePendingPersist())
    }

    func testTakePendingPersistReturnsDraftAndAdvancesSyncedText() {
        var coordinator = FeaturePromptDraftCoordinator(text: "Base prompt")
        coordinator.updateDraft("Edited prompt")

        XCTAssertEqual(coordinator.takePendingPersist(), "Edited prompt")
        XCTAssertEqual(coordinator.lastSyncedText, "Edited prompt")
        XCTAssertNil(coordinator.takePendingPersist())
    }

    func testTakePendingPersistSkipsStaleDebouncePayload() {
        var coordinator = FeaturePromptDraftCoordinator(text: "Base prompt")
        coordinator.updateDraft("Edited once")
        coordinator.updateDraft("Edited twice")

        XCTAssertNil(coordinator.takePendingPersist(expectedText: "Edited once"))
        XCTAssertEqual(coordinator.lastSyncedText, "Base prompt")
        XCTAssertEqual(coordinator.takePendingPersist(expectedText: "Edited twice"), "Edited twice")
    }

    func testSyncExternalTextIgnoresRoundTripEchoOfOwnWrite() {
        var coordinator = FeaturePromptDraftCoordinator(text: "Base prompt")
        coordinator.updateDraft("Edited prompt")
        XCTAssertEqual(coordinator.takePendingPersist(), "Edited prompt")

        coordinator.syncExternalText("Edited prompt")

        XCTAssertEqual(coordinator.draft, "Edited prompt")
        XCTAssertEqual(coordinator.lastSyncedText, "Edited prompt")
    }

    func testSyncExternalTextAppliesRealExternalMutation() {
        var coordinator = FeaturePromptDraftCoordinator(text: "Base prompt")

        coordinator.syncExternalText("External prompt")

        XCTAssertEqual(coordinator.draft, "External prompt")
        XCTAssertEqual(coordinator.lastSyncedText, "External prompt")
        XCTAssertNil(coordinator.takePendingPersist())
    }
}
