import XCTest
@testable import Voxt

final class FeatureSettingsStoreTests: XCTestCase {
    private func withEphemeralDefaults(
        _ body: (UserDefaults) throws -> Void
    ) rethrows {
        let suiteName = "FeatureSettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected ephemeral UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        try body(defaults)
    }

    func testMigrateIfNeededRemovesObsoleteLatencyProfileKeys() throws {
        try withEphemeralDefaults { defaults in
            defaults.set("instant", forKey: "enhancementLatencyProfile")
            defaults.set("quality", forKey: "translationLatencyProfile")
            defaults.set("balanced", forKey: "rewriteLatencyProfile")

            FeatureSettingsStore.migrateIfNeeded(defaults: defaults)

            XCTAssertNil(defaults.object(forKey: "enhancementLatencyProfile"))
            XCTAssertNil(defaults.object(forKey: "translationLatencyProfile"))
            XCTAssertNil(defaults.object(forKey: "rewriteLatencyProfile"))
            XCTAssertNotNil(defaults.string(forKey: AppPreferenceKey.featureSettings))
        }
    }

    func testLoadRemovesObsoleteLatencyProfileKeysAndDerivesSettings() throws {
        try withEphemeralDefaults { defaults in
            defaults.set("quality", forKey: "enhancementLatencyProfile")
            defaults.set(EnhancementMode.customLLM.rawValue, forKey: AppPreferenceKey.enhancementMode)
            defaults.set("mlx-community/Qwen3.5-2B-4bit", forKey: AppPreferenceKey.customLLMModelRepo)

            let settings = FeatureSettingsStore.load(defaults: defaults)

            XCTAssertNil(defaults.object(forKey: "enhancementLatencyProfile"))
            XCTAssertTrue(settings.transcription.llmEnabled)
            XCTAssertEqual(
                settings.transcription.llmSelectionID,
                .localLLM("mlx-community/Qwen3.5-2B-4bit")
            )
        }
    }

    func testSaveRemovesObsoleteLatencyProfileKeysWithoutAffectingStoredSettings() throws {
        try withEphemeralDefaults { defaults in
            defaults.set("instant", forKey: "enhancementLatencyProfile")
            defaults.set("balanced", forKey: "translationLatencyProfile")
            defaults.set("quality", forKey: "rewriteLatencyProfile")

            let settings = FeatureSettingsStore.deriveFromLegacy(defaults: defaults)
            FeatureSettingsStore.save(settings, defaults: defaults)
            let reloaded = FeatureSettingsStore.load(defaults: defaults)

            XCTAssertNil(defaults.object(forKey: "enhancementLatencyProfile"))
            XCTAssertNil(defaults.object(forKey: "translationLatencyProfile"))
            XCTAssertNil(defaults.object(forKey: "rewriteLatencyProfile"))
            XCTAssertEqual(reloaded, settings)
        }
    }

    func testSaveSyncsLegacyAppEnhancementFlagForMenuVisibility() throws {
        try withEphemeralDefaults { defaults in
            var settings = FeatureSettingsStore.deriveFromLegacy(defaults: defaults)
            settings.rewrite.appEnhancementEnabled = true

            FeatureSettingsStore.save(settings, defaults: defaults)

            XCTAssertTrue(defaults.bool(forKey: AppPreferenceKey.appEnhancementEnabled))

            settings.rewrite.appEnhancementEnabled = false
            FeatureSettingsStore.save(settings, defaults: defaults)

            XCTAssertFalse(defaults.bool(forKey: AppPreferenceKey.appEnhancementEnabled))
        }
    }
}
