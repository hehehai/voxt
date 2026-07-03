// OnboardingPreferenceManagerTests.swift
// Provides Onboarding Preference Manager Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class OnboardingPreferenceManagerTests: XCTestCase {
    func testResolvedCompletionStateDefaultsToFalseForFreshInstall() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        let directory = try TemporaryDirectory()
        let fileManager = TestAppSupportFileManager(applicationSupportDirectory: directory.url)

        let completed = OnboardingPreferenceManager.resolvedCompletionState(
            defaults: defaults,
            fileManager: fileManager,
            bundleIdentifier: suiteName
        )

        XCTAssertFalse(completed)
        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, false)
    }

    func testResolvedCompletionStateTreatsExistingPersistentDomainAsCompleted() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        let directory = try TemporaryDirectory()
        let fileManager = TestAppSupportFileManager(applicationSupportDirectory: directory.url)
        defaults.setPersistentDomain(
            [AppPreferenceKey.translationTargetLanguage: TranslationTargetLanguage.english.rawValue],
            forName: suiteName
        )

        let completed = OnboardingPreferenceManager.resolvedCompletionState(
            defaults: defaults,
            fileManager: fileManager,
            bundleIdentifier: suiteName
        )

        XCTAssertTrue(completed)
        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, true)
    }

    func testResolvedCompletionStateTreatsExistingAppSupportDirectoryAsCompleted() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        let directory = try TemporaryDirectory()
        let appSupportDirectory = directory.url.appendingPathComponent("Voxt", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        let fileManager = TestAppSupportFileManager(applicationSupportDirectory: directory.url)

        let completed = OnboardingPreferenceManager.resolvedCompletionState(
            defaults: defaults,
            fileManager: fileManager,
            bundleIdentifier: suiteName
        )

        XCTAssertTrue(completed)
        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, true)
    }

    func testMarkCompletedClearsSavedStep() {
        let defaults = TestDoubles.makeUserDefaults()
        OnboardingPreferenceManager.saveLastStep(.finish, defaults: defaults)

        OnboardingPreferenceManager.markCompleted(defaults: defaults)

        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, true)
        XCTAssertNil(defaults.string(forKey: AppPreferenceKey.onboardingLastStepID))
    }

    func testGuideStepPersistsAndIsClearedWhenCompleted() {
        let defaults = TestDoubles.makeUserDefaults()
        OnboardingPreferenceManager.saveLastGuideStep(.models, defaults: defaults)

        XCTAssertEqual(OnboardingPreferenceManager.savedLastGuideStep(defaults: defaults), .models)

        OnboardingPreferenceManager.markCompleted(defaults: defaults)

        XCTAssertEqual(defaults.object(forKey: AppPreferenceKey.onboardingCompleted) as? Bool, true)
        XCTAssertNil(OnboardingPreferenceManager.savedLastGuideStep(defaults: defaults))
    }

    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "VoxtTests.Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

final class ModelStorageDirectoryManagerResolutionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ModelStorageDirectoryManager.resetForTesting()
    }

    override func tearDown() {
        ModelStorageDirectoryManager.resetForTesting()
        super.tearDown()
    }

    func testAutomaticResolutionUsesNewWriteRootAndLegacyReadFallback() {
        let defaults = TestDoubles.makeUserDefaults(testName: "ModelStorageDirectoryManagerTests.automaticResolution")
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)

        let resolution = ModelStorageDirectoryManager.resolvedRootResolution(defaults: defaults)

        XCTAssertEqual(resolution.writeRootURL.standardizedFileURL.path, ModelStorageDirectoryManager.defaultRootURL.standardizedFileURL.path)
        XCTAssertEqual(
            resolution.readableRootURLs.map(\.standardizedFileURL.path),
            [
                ModelStorageDirectoryManager.defaultRootURL.standardizedFileURL.path,
                ModelStorageDirectoryManager.legacyDefaultRootURL.standardizedFileURL.path,
            ]
        )
    }

    func testStoredPathUsesSingleReadWriteRoot() throws {
        let defaults = TestDoubles.makeUserDefaults(testName: "ModelStorageDirectoryManagerTests.storedPath")
        let directory = try TemporaryDirectory()
        let customRoot = directory.url.appendingPathComponent("custom-model-root", isDirectory: true)
        defaults.set(customRoot.path, forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)

        let resolution = ModelStorageDirectoryManager.resolvedRootResolution(defaults: defaults)

        XCTAssertEqual(resolution.writeRootURL.standardizedFileURL.path, customRoot.standardizedFileURL.path)
        XCTAssertEqual(resolution.readableRootURLs.map(\.standardizedFileURL.path), [customRoot.standardizedFileURL.path])
    }

    func testLegacyStoredPathWithoutBookmarkUsesAutomaticResolution() {
        let defaults = TestDoubles.makeUserDefaults(testName: "ModelStorageDirectoryManagerTests.legacyStoredPathAutomaticResolution")
        defaults.set(
            ModelStorageDirectoryManager.legacyDefaultRootURL.standardizedFileURL.path,
            forKey: AppPreferenceKey.modelStorageRootPath
        )
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)

        let resolution = ModelStorageDirectoryManager.resolvedRootResolution(defaults: defaults)

        XCTAssertEqual(resolution.writeRootURL.standardizedFileURL.path, ModelStorageDirectoryManager.defaultRootURL.standardizedFileURL.path)
        XCTAssertEqual(
            resolution.readableRootURLs.map(\.standardizedFileURL.path),
            [
                ModelStorageDirectoryManager.defaultRootURL.standardizedFileURL.path,
                ModelStorageDirectoryManager.legacyDefaultRootURL.standardizedFileURL.path,
            ]
        )
    }

    func testResolvedRootURLReturnsWriteRoot() throws {
        let defaults = TestDoubles.makeUserDefaults(testName: "ModelStorageDirectoryManagerTests.resolvedRootURL")
        let directory = try TemporaryDirectory()
        let customRoot = directory.url.appendingPathComponent("another-root", isDirectory: true)
        defaults.set(customRoot.path, forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)

        let resolvedRoot = ModelStorageDirectoryManager.resolvedRootURL(defaults: defaults)

        XCTAssertEqual(resolvedRoot.standardizedFileURL.path, customRoot.standardizedFileURL.path)
    }

    func testResolvedDerivedRootURLTracksWriteRoot() throws {
        let defaults = TestDoubles.makeUserDefaults(testName: "ModelStorageDirectoryManagerTests.derivedRootURL")
        let directory = try TemporaryDirectory()
        let customRoot = directory.url.appendingPathComponent("another-root", isDirectory: true)
        defaults.set(customRoot.path, forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)

        let derivedRoot = ModelStorageDirectoryManager.resolvedDerivedRootURL(defaults: defaults)

        XCTAssertEqual(
            derivedRoot.standardizedFileURL.path,
            customRoot
                .appendingPathComponent(".derived-model-artifacts", isDirectory: true)
                .standardizedFileURL.path
        )
    }
}

private final class TestAppSupportFileManager: FileManager {
    private let applicationSupportDirectory: URL

    init(applicationSupportDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
        super.init()
    }

    override func url(
        for directory: SearchPathDirectory,
        in domain: SearchPathDomainMask,
        appropriateFor url: URL?,
        create shouldCreate: Bool
    ) throws -> URL {
        if directory == .applicationSupportDirectory, domain == .userDomainMask {
            return applicationSupportDirectory
        }
        return try super.url(
            for: directory,
            in: domain,
            appropriateFor: url,
            create: shouldCreate
        )
    }
}
