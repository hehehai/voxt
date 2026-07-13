// ModelSettingsCatalogSnapshotBuilderTests.swift
// Provides Model Settings Catalog Snapshot Builder Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class ModelSettingsCatalogSnapshotBuilderTests: XCTestCase {
    func testModelCatalogStatusTagsAreMutuallyExclusive() {
        let inUseTag = AppLocalization.localizedString("In Use")

        let installedOnly = ModelCatalogTag.toggledTags(current: [], tag: installedTag)
        XCTAssertEqual(installedOnly, [installedTag])

        let configuredOnly = ModelCatalogTag.toggledTags(current: installedOnly, tag: configuredTag)
        XCTAssertEqual(configuredOnly, [configuredTag])

        let inUseOnly = ModelCatalogTag.toggledTags(current: configuredOnly, tag: inUseTag)
        XCTAssertEqual(inUseOnly, [inUseTag])

        XCTAssertTrue(ModelCatalogTag.toggledTags(current: inUseOnly, tag: inUseTag).isEmpty)
    }

    func testBuildPrioritizesEntriesAlreadyInUse() {
        let snapshot = ModelSettingsCatalogSnapshotBuilder.build(
            entries: [
                makeEntry(id: "local-idle", filterTags: [localTag, installedTag]),
                makeEntry(id: "remote-in-use", filterTags: [remoteTag, configuredTag], usageLocations: ["Translation"])
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

    func testBuildAppliesSingleSelectedStatusFilter() {
        let snapshot = ModelSettingsCatalogSnapshotBuilder.build(
            entries: [
                makeEntry(id: "installed-local", filterTags: [localTag, installedTag]),
                makeEntry(id: "configured-remote", filterTags: [remoteTag, configuredTag]),
                makeEntry(id: "plain-local", filterTags: [localTag])
            ],
            selectedTags: [configuredTag]
        )

        XCTAssertEqual(snapshot.filteredEntries.map(\.id), ["configured-remote"])
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
