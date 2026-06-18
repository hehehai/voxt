// TranslationSessionLanguageSwitchTests.swift
// Provides Translation Session Language Switch Tests for Voxt test coverage.

import XCTest
@testable import Voxt

@MainActor
final class TranslationSessionLanguageSwitchTests: XCTestCase {
    func testEffectiveTranslationTargetLanguageUsesSessionOverrideForMicrophoneTranslation() {
        let resolved = AppDelegate.effectiveTranslationTargetLanguage(
            savedTargetLanguage: .english,
            sessionOverride: .japanese,
            isSelectedTextTranslation: false
        )

        XCTAssertEqual(resolved, .japanese)
    }

    func testEffectiveTranslationTargetLanguageKeepsSavedDefaultForSelectedTextFlow() {
        let resolved = AppDelegate.effectiveTranslationTargetLanguage(
            savedTargetLanguage: .english,
            sessionOverride: .japanese,
            isSelectedTextTranslation: true
        )

        XCTAssertEqual(resolved, .english)
    }

    func testAllowsSessionLanguageSwitchingDisablesWhisperDirectSessions() {
        XCTAssertTrue(
            AppDelegate.shouldAllowSessionTranslationLanguageSwitching(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: false,
                sessionUsesWhisperDirectTranslation: false
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldAllowSessionTranslationLanguageSwitching(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: false,
                sessionUsesWhisperDirectTranslation: true
            )
        )
        XCTAssertFalse(
            AppDelegate.shouldAllowSessionTranslationLanguageSwitching(
                sessionOutputMode: .translation,
                isSelectedTextTranslationFlow: true,
                sessionUsesWhisperDirectTranslation: false
            )
        )
    }

    func testLockedSessionProviderResolutionWinsOverChangedTargetLanguage() {
        let locked = TranslationProviderResolution(
            provider: .remoteLLM,
            fallbackProvider: .customLLM,
            usesWhisperDirectTranslation: false,
            fallbackReason: .targetLanguageNotEnglish
        )

        let resolved = AppDelegate.resolvedSessionTranslationProviderResolution(
            lockedResolution: locked,
            selectedProvider: .whisperKit,
            fallbackProvider: .customLLM,
            transcriptionEngine: .whisperKit,
            targetLanguage: .english,
            isSelectedTextTranslation: false,
            whisperModelState: .downloaded
        )

        XCTAssertEqual(resolved, locked)
    }

    func testSelectedTextTranslationIgnoresLockedSessionProviderResolution() {
        let locked = TranslationProviderResolution(
            provider: .remoteLLM,
            fallbackProvider: .customLLM,
            usesWhisperDirectTranslation: false,
            fallbackReason: .targetLanguageNotEnglish
        )

        let resolved = AppDelegate.resolvedSessionTranslationProviderResolution(
            lockedResolution: locked,
            selectedProvider: .customLLM,
            fallbackProvider: .remoteLLM,
            transcriptionEngine: .whisperKit,
            targetLanguage: .english,
            isSelectedTextTranslation: true,
            whisperModelState: .downloaded
        )

        XCTAssertEqual(resolved.provider, .customLLM)
        XCTAssertNil(resolved.fallbackReason)
    }

    func testWaveformViewPillVisibilityRequiresEligibleTranslationRecordingState() {
        XCTAssertFalse(
            WaveformView.shouldShowSessionTranslationLanguagePill(
                displayMode: .recording,
                allowsSwitching: true,
                sessionTranslationTargetLanguage: .japanese,
                isHovering: false,
                isPickerPresented: false
            )
        )

        XCTAssertTrue(
            WaveformView.shouldShowSessionTranslationLanguagePill(
                displayMode: .recording,
                allowsSwitching: true,
                sessionTranslationTargetLanguage: .japanese,
                isHovering: true,
                isPickerPresented: false
            )
        )

        XCTAssertTrue(
            WaveformView.shouldShowSessionTranslationLanguagePill(
                displayMode: .recording,
                allowsSwitching: true,
                sessionTranslationTargetLanguage: .japanese,
                isHovering: false,
                isPickerPresented: true
            )
        )

        XCTAssertFalse(
            WaveformView.shouldShowSessionTranslationLanguagePill(
                displayMode: .processing,
                allowsSwitching: true,
                sessionTranslationTargetLanguage: .japanese,
                isHovering: true,
                isPickerPresented: false
            )
        )

        XCTAssertFalse(
            WaveformView.shouldShowSessionTranslationLanguagePill(
                displayMode: .answer,
                allowsSwitching: true,
                sessionTranslationTargetLanguage: .japanese,
                isHovering: true,
                isPickerPresented: false
            )
        )

        XCTAssertFalse(
            WaveformView.shouldShowSessionTranslationLanguagePill(
                displayMode: .recording,
                allowsSwitching: false,
                sessionTranslationTargetLanguage: .japanese,
                isHovering: true,
                isPickerPresented: false
            )
        )

        XCTAssertFalse(
            WaveformView.shouldShowSessionTranslationLanguagePill(
                displayMode: .recording,
                allowsSwitching: true,
                sessionTranslationTargetLanguage: nil,
                isHovering: true,
                isPickerPresented: false
            )
        )
    }

    func testWaveformViewCompactMetricsStayTight() {
        let visualWidth = WaveformView.waveformVisualWidth()

        XCTAssertEqual(visualWidth, 88.7, accuracy: 0.001)
        XCTAssertLessThan(WaveformView.defaultWaveformSlotWidth, 100)
        XCTAssertGreaterThanOrEqual(WaveformView.defaultWaveformSlotWidth, visualWidth)
        XCTAssertLessThan(WaveformView.defaultSessionLanguagePickerWidth, 210)
    }

    func testWaveformViewVisualWidthHandlesEmptyBarCount() {
        XCTAssertEqual(WaveformView.waveformVisualWidth(barCount: 0), 0)
    }
}
