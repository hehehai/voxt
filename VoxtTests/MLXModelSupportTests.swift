// MLXModelSupportTests.swift
// Provides MLXModel Support Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class MLXModelSupportTests: XCTestCase {
    func testCanonicalModelRepoMapsLegacyRepos() {
        XCTAssertEqual(
            MLXModelCatalog.canonicalModelRepo("mlx-community/Parakeet-0.6B"),
            "mlx-community/parakeet-tdt-0.6b-v3"
        )
        XCTAssertEqual(
            MLXModelCatalog.canonicalModelRepo("mlx-community/FireRedASR2"),
            "mlx-community/FireRedASR2-AED-mlx"
        )
        XCTAssertEqual(
            MLXModelCatalog.canonicalModelRepo("mlx-community/Qwen3-ASR-0.6B-4bit"),
            "mlx-community/Qwen3-ASR-0.6B-4bit"
        )
    }

    func testRealtimeCapabilityUsesCanonicalizedRepo() {
        XCTAssertTrue(
            MLXModelCatalog.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-2602")
        )
        XCTAssertTrue(
            MLXModelCatalog.isRealtimeCapableModelRepo("mlx-community/Voxtral-Mini-4B-Realtime-6bit")
        )
        XCTAssertFalse(
            MLXModelCatalog.isRealtimeCapableModelRepo("mlx-community/Qwen3-ASR-0.6B-4bit")
        )
    }

    func testLiveModeUsesNativeSessionForSupportedRealtimeFamilies() {
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "mlx-community/Qwen3-ASR-0.6B-4bit"),
            .nativeQwenLive
        )
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "mlx-community/Qwen3-ASR-1.7B-6bit"),
            .nativeQwenLive
        )
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit"),
            .nativeNemotronLive
        )
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "beshkenadze/cohere-transcribe-03-2026-mlx-fp16"),
            .nativeStreamingLive
        )
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "OpenMOSS-Team/MOSS-Transcribe-Diarize"),
            .nativeStreamingLive
        )
        XCTAssertEqual(
            MLXModelCatalog.liveMode(for: "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit"),
            .nativeVoxtralLive
        )
    }

    func testQwen3CatalogTagsExposeRealtimeBadge() {
        XCTAssertTrue(
            MLXModelCatalog.catalogTagKeys(for: "mlx-community/Qwen3-ASR-0.6B-4bit").contains("Realtime")
        )
        XCTAssertTrue(
            MLXModelCatalog.catalogTagKeys(for: "mlx-community/Qwen3-ASR-1.7B-6bit").contains("Realtime")
        )
    }

    func testNemotronCatalogTagsExposeMultilingualBadge() {
        let tagKeys = MLXModelCatalog.catalogTagKeys(for: "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit")
        XCTAssertTrue(tagKeys.contains("Multilingual"))
        XCTAssertTrue(tagKeys.contains("Realtime"))
    }

    func testCapabilityRegistryUsesExactLanguageMatrices() {
        let qwen = MLXModelCatalog.capability(for: "mlx-community/Qwen3-ASR-0.6B-4bit")
        XCTAssertTrue(qwen.supportsLanguage(code: "zh"))
        XCTAssertTrue(qwen.supportsLanguage(code: "yue"))
        XCTAssertFalse(qwen.supportsLanguage(code: "sw"))
        XCTAssertEqual(qwen.kvCachePolicy, .conservativeQwen)

        let parakeetV3 = MLXModelCatalog.capability(for: "mlx-community/parakeet-tdt-0.6b-v3")
        XCTAssertEqual(parakeetV3.family, .parakeet)
        XCTAssertEqual(parakeetV3.supportedLanguageCodes.count, 25)
        XCTAssertTrue(parakeetV3.supportsLanguage(code: "de"))
        XCTAssertFalse(parakeetV3.supportsLanguage(code: "zh"))

        let legacyParakeet = MLXModelCatalog.capability(for: "mlx-community/parakeet-tdt-0.6b-v2")
        XCTAssertEqual(legacyParakeet.supportedLanguageCodes, ["en"])

        let nemotron = MLXModelCatalog.capability(for: "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit")
        XCTAssertTrue(nemotron.supportsLanguage(code: "zh"))
        XCTAssertTrue(nemotron.supportsLanguage(code: "ja"))
        XCTAssertFalse(nemotron.supportsLanguage(code: "el"))

        let voxtral = MLXModelCatalog.capability(for: "mlx-community/Voxtral-Mini-4B-Realtime-6bit")
        XCTAssertEqual(voxtral.supportedLanguageCodes.count, 13)
        XCTAssertTrue(voxtral.supportsLanguage(code: "zh"))
        XCTAssertFalse(voxtral.supportsLanguage(code: "yue"))
    }

    func testEveryCatalogModelHasAnExplicitCapability() {
        let missingRepos = MLXModelCatalog.supportedModels
            .map(\.id)
            .filter { !MLXModelCatalog.hasRegisteredCapability(for: $0) }

        XCTAssertEqual(missingRepos, [])
    }

    func testCapabilityRegistryDrivesFormsAndStructuredOutput() {
        let parakeet = MLXModelCatalog.capability(for: "mlx-community/parakeet-tdt-0.6b-v3")
        XCTAssertTrue(parakeet.configurationCapabilities.isEmpty)
        XCTAssertEqual(parakeet.languageRouting, .automatic)
        XCTAssertEqual(parakeet.timingGranularity, .sentence)
        XCTAssertTrue(parakeet.timingGranularity.providesReliableSegments)
        XCTAssertTrue(parakeet.outputCapabilities.contains(.timestamps))

        let nemotron = MLXModelCatalog.capability(for: "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit")
        XCTAssertEqual(nemotron.timingGranularity, .sentence)
        XCTAssertTrue(nemotron.outputCapabilities.contains(.timestamps))

        let moss = MLXModelCatalog.capability(for: "OpenMOSS-Team/MOSS-Transcribe-Diarize")
        XCTAssertTrue(moss.configurationCapabilities.contains(.mossPromptAndOutput))
        XCTAssertTrue(moss.outputCapabilities.contains(.timestamps))
        XCTAssertTrue(moss.outputCapabilities.contains(.speakerLabels))
        XCTAssertEqual(moss.timingGranularity, .sentence)
        XCTAssertEqual(moss.vadPolicy, .preserveTimeline)

        let whisper = MLXModelCatalog.capability(for: "mlx-community/whisper-large-v3-turbo")
        XCTAssertEqual(whisper.timingGranularity, .chunk)
        XCTAssertFalse(whisper.timingGranularity.providesReliableSegments)
        XCTAssertFalse(whisper.configurationCapabilities.contains(.recognitionPreset))
        XCTAssertNil(whisper.kvCachePolicy)

        let canary = MLXModelCatalog.capability(for: "Mediform/canary-1b-v2-mlx-q8")
        XCTAssertEqual(canary.timingGranularity, .none)
        XCTAssertFalse(canary.outputCapabilities.contains(.timestamps))

        let senseVoice = MLXModelCatalog.capability(for: "mlx-community/SenseVoiceSmall")
        XCTAssertTrue(senseVoice.configurationCapabilities.contains(.senseVoiceITN))
        XCTAssertTrue(senseVoice.outputCapabilities.contains(.emotion))
        XCTAssertTrue(senseVoice.outputCapabilities.contains(.audioEvents))
    }

    func testMMSAdapterCatalogMatchesFL102Checkpoint() {
        XCTAssertEqual(MMSLanguageAdapterOption.all.count, 102)
        XCTAssertTrue(MMSLanguageAdapterOption.all.contains(where: { $0.id == "eng" && $0.appLanguageCode == "en" }))
        XCTAssertTrue(MMSLanguageAdapterOption.all.contains(where: { $0.id == "cmn-script_simplified" && $0.appLanguageCode == "zh" }))
        XCTAssertTrue(MMSLanguageAdapterOption.all.contains(where: { $0.id == "yue-script_traditional" && $0.appLanguageCode == "yue" }))
        XCTAssertTrue(MLXModelCatalog.supportsLanguage("ja", for: "facebook/mms-1b-fl102"))
        XCTAssertFalse(MLXModelCatalog.supportsLanguage("bo", for: "facebook/mms-1b-fl102"))
    }

    func testFallbackRemoteSizeSupportsLegacyAndCuratedRepos() {
        XCTAssertEqual(
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/FireRedASR2"),
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/FireRedASR2-AED-mlx")
        )
        XCTAssertNotNil(
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/Qwen3-ASR-0.6B-4bit")
        )
        XCTAssertNotNil(
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/whisper-large-v3-turbo")
        )
        XCTAssertNotNil(
            MLXModelCatalog.fallbackRemoteSizeText(repo: "mlx-community/whisper-small-mlx")
        )
    }

    func testWhisperMigrationMapsLegacyModelIDsToMLXRepos() {
        XCTAssertEqual(
            MLXWhisperMigrationSupport.repo(forLegacyWhisperModelID: "tiny"),
            "mlx-community/whisper-tiny-mlx"
        )
        XCTAssertEqual(
            MLXWhisperMigrationSupport.repo(forLegacyWhisperModelID: "base"),
            "mlx-community/whisper-base-mlx"
        )
        XCTAssertEqual(
            MLXWhisperMigrationSupport.repo(forLegacyWhisperModelID: "medium"),
            "mlx-community/whisper-large-v3-turbo"
        )
        XCTAssertTrue(
            MLXWhisperMigrationSupport.isWhisperRepo("mlx-community/whisper-large-v3-turbo")
        )
    }

    func testTinyAndBaseWhisperReposAreHiddenUnlessInstalled() {
        let defaultDisplayRepos = Set(MLXModelCatalog.displayModels(includingInstalled: []).map(\.id))

        XCTAssertFalse(defaultDisplayRepos.contains("mlx-community/whisper-tiny-mlx"))
        XCTAssertFalse(defaultDisplayRepos.contains("mlx-community/whisper-base-mlx"))

        let displayReposIncludingInstalled = Set(
            MLXModelCatalog.displayModels(includingInstalled: ["mlx-community/whisper-base-mlx"]).map(\.id)
        )

        XCTAssertTrue(displayReposIncludingInstalled.contains("mlx-community/whisper-base-mlx"))
    }

    func testVoxtralReposAreHiddenUnlessInstalled() {
        let repos = [
            "mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit",
            "mlx-community/Voxtral-Mini-4B-Realtime-6bit",
            "mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16",
        ]
        let defaultDisplayRepos = Set(MLXModelCatalog.displayModels(includingInstalled: []).map(\.id))

        for repo in repos {
            XCTAssertFalse(defaultDisplayRepos.contains(repo))
        }

        let installedRepo = "mlx-community/Voxtral-Mini-4B-Realtime-6bit"
        let displayReposIncludingInstalled = Set(
            MLXModelCatalog.displayModels(includingInstalled: [installedRepo]).map(\.id)
        )

        XCTAssertTrue(displayReposIncludingInstalled.contains(installedRepo))
        XCTAssertEqual(MLXModelCatalog.liveMode(for: installedRepo), .nativeVoxtralLive)
    }

    func testCanaryRepoIsHiddenUnlessInstalled() {
        let repo = "Mediform/canary-1b-v2-mlx-q8"

        XCTAssertFalse(
            MLXModelCatalog.displayModels(includingInstalled: []).contains { $0.id == repo }
        )
        XCTAssertTrue(
            MLXModelCatalog.displayModels(includingInstalled: [repo]).contains { $0.id == repo }
        )
        XCTAssertEqual(MLXModelCatalog.capability(for: repo).family, .canary)
    }

    func testGraniteRepoIsHiddenUnlessInstalled() {
        let repo = "mlx-community/granite-4.0-1b-speech-5bit"

        XCTAssertFalse(
            MLXModelCatalog.displayModels(includingInstalled: []).contains { $0.id == repo }
        )
        XCTAssertTrue(
            MLXModelCatalog.displayModels(includingInstalled: [repo]).contains { $0.id == repo }
        )
        XCTAssertEqual(MLXModelCatalog.capability(for: repo).family, .graniteSpeech)
    }
}
