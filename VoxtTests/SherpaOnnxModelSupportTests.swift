import XCTest
@testable import Voxt

@MainActor
final class SherpaOnnxModelSupportTests: XCTestCase {
    func testLocalSherpaModelsAreHiddenByDefault() {
        XCTAssertTrue(SherpaOnnxModelCatalog.availableModels.isEmpty)
        XCTAssertTrue(SherpaOnnxModelCatalog.displayModels(including: []).isEmpty)
    }

    func testHiddenLocalSherpaModelsRemainSupported() {
        let supportedIDs = Set(SherpaOnnxModelCatalog.supportedModels.map(\.id))

        XCTAssertEqual(
            supportedIDs,
            Set([SherpaOnnxModelCatalog.fireRedModelID, SherpaOnnxModelCatalog.funASRNanoModelID])
        )
    }

    func testHiddenLocalSherpaModelsDisplayWhenExplicitlyIncluded() {
        let fireRedModels = SherpaOnnxModelCatalog.displayModels(
            including: [SherpaOnnxModelCatalog.fireRedModelID]
        )
        let funASRModels = SherpaOnnxModelCatalog.displayModels(
            including: [SherpaOnnxModelCatalog.funASRNanoModelID]
        )

        XCTAssertEqual(fireRedModels.map(\.id), [SherpaOnnxModelCatalog.fireRedModelID])
        XCTAssertEqual(funASRModels.map(\.id), [SherpaOnnxModelCatalog.funASRNanoModelID])
    }
}
