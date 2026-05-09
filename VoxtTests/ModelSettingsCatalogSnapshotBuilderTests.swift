import XCTest
@testable import Voxt

final class ModelSettingsCatalogSnapshotBuilderTests: XCTestCase {
    func testBuildPrioritizesEntriesAlreadyInUse() {
        let snapshot = ModelSettingsCatalogSnapshotBuilder.build(
            entries: [
                makeEntry(id: "local-idle", filterTags: [localTag, installedTag]),
                makeEntry(id: "remote-in-use", filterTags: [remoteTag, configuredTag], usageLocations: ["Meeting"])
            ],
            selectedTags: []
        )

        XCTAssertEqual(snapshot.allEntries.map(\.id), ["remote-in-use", "local-idle"])
    }

    func testBuildKeepsBothLocationTagsVisibleWhenFilteringToLocal() {
        let snapshot = ModelSettingsCatalogSnapshotBuilder.build(
            entries: [
                makeEntry(id: "local", filterTags: [localTag, fastTag]),
                makeEntry(id: "remote", filterTags: [remoteTag, configuredTag])
            ],
            selectedTags: [localTag]
        )

        XCTAssertEqual(snapshot.availableTagGroups.first, [localTag, remoteTag])
        XCTAssertEqual(snapshot.filteredEntries.map(\.id), ["local"])
    }

    func testBuildFiltersEntriesBySelectedTagSubset() {
        let snapshot = ModelSettingsCatalogSnapshotBuilder.build(
            entries: [
                makeEntry(id: "installed-local", filterTags: [localTag, installedTag]),
                makeEntry(id: "plain-local", filterTags: [localTag]),
                makeEntry(id: "configured-remote", filterTags: [remoteTag, configuredTag])
            ],
            selectedTags: [localTag, installedTag]
        )

        XCTAssertEqual(snapshot.filteredEntries.map(\.id), ["installed-local"])
    }

    private func makeEntry(
        id: String,
        filterTags: [String],
        usageLocations: [String] = []
    ) -> ModelCatalogEntry {
        ModelCatalogEntry(
            id: id,
            title: id,
            engine: "MLX",
            sizeText: "",
            ratingText: "",
            filterTags: filterTags,
            displayTags: filterTags,
            statusText: "",
            usageLocations: usageLocations,
            badgeText: nil,
            primaryAction: nil,
            secondaryActions: []
        )
    }

    private var localTag: String { AppLocalization.localizedString("Local") }
    private var remoteTag: String { AppLocalization.localizedString("Remote") }
    private var fastTag: String { AppLocalization.localizedString("Fast") }
    private var installedTag: String { AppLocalization.localizedString("Installed") }
    private var configuredTag: String { AppLocalization.localizedString("Configured") }
}
