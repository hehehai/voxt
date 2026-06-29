import XCTest
@testable import Voxt

final class ModelLogoKeyTests: XCTestCase {
    func testNemotronASRUsesNvidiaLogo() {
        XCTAssertEqual(
            ModelLogoKey.resolve(title: "Nemotron", engine: "MLX Audio"),
            .nvidia
        )
    }

    func testFunASRNanoEntriesUseQwenLogo() {
        let selectionID = FeatureModelSelectionID.sherpaOnnx(SherpaOnnxModelCatalog.funASRNanoModelID)
        let catalogEntry = ModelCatalogEntry(
            id: selectionID.rawValue,
            title: "FunASR Nano",
            engine: "Sherpa",
            sizeText: "",
            ratingText: "",
            filterTags: [],
            displayTags: [],
            statusText: "",
            usageLocations: [],
            badgeText: nil,
            primaryAction: nil,
            secondaryActions: []
        )
        let selectorEntry = FeatureModelSelectorEntry(
            selectionID: selectionID,
            title: "FunASR Nano",
            engine: "Sherpa",
            sizeText: "",
            ratingText: "",
            filterTags: [],
            displayTags: [],
            statusText: "",
            usageLocations: [],
            badgeText: nil,
            isSelectable: true,
            disabledReason: nil
        )

        XCTAssertEqual(catalogEntry.modelLogoKey, .qwen)
        XCTAssertEqual(
            selectorEntry.modelLogoKey,
            .qwen
        )
    }
}
