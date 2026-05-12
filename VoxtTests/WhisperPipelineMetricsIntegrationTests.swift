import XCTest
@testable import Voxt

@MainActor
final class WhisperPipelineMetricsIntegrationTests: XCTestCase {
    private struct ReplayMetrics {
        let clipCount: Int
        let previewPublishedRate: Double
        let previewReuseEligibleRate: Double
        let meanPreviewFinalDiffRate: Double
        let maxPreviewFinalDiffRate: Double
        let lateCoverageRate: Double
    }

    private func skipIfCI() throws {
        let env = ProcessInfo.processInfo.environment
        if env["CI"] == "true" || env["GITHUB_ACTIONS"] == "true" {
            throw XCTSkip("Whisper pipeline metrics regression is local-only and is skipped on CI.")
        }
    }

    private func officialFixtureDirectoryURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Audio/qwen-official", isDirectory: true)
    }

    private func fixtureURL(named fileName: String) throws -> URL {
        let url = officialFixtureDirectoryURL().appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Missing official audio fixture: \(fileName)")
        }
        return url
    }

    private func officialLongFixtureURLs() throws -> [URL] {
        [
            try fixtureURL(named: "qwen_audio_long_en_composite.wav"),
            try fixtureURL(named: "qwen_audio_long_zh_composite.wav")
        ]
    }

    private func resolvedModelManager() throws -> (modelID: String, manager: WhisperKitModelManager) {
        let defaults = UserDefaults.standard
        defaults.set("/Users/guanwei/x/models", forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)
        let hubURL = defaults.bool(forKey: AppPreferenceKey.useHfMirror)
            ? MLXModelManager.mirrorHubBaseURL
            : MLXModelManager.defaultHubBaseURL
        let preferredModelID = defaults.string(forKey: AppPreferenceKey.whisperModelID) ?? WhisperKitModelManager.defaultModelID
        let candidateModelIDs = [preferredModelID, "large-v3", "small", "base"] + WhisperKitModelManager.availableModels.map(\.id)
        let probeManager = WhisperKitModelManager(modelID: preferredModelID, hubBaseURL: hubURL)
        guard let chosenModelID = candidateModelIDs
            .map(WhisperKitModelManager.canonicalModelID(_:))
            .first(where: { probeManager.isModelDownloaded(id: $0) }) else {
            throw XCTSkip("No downloaded Whisper model is available for pipeline metrics regression.")
        }
        return (chosenModelID, WhisperKitModelManager(modelID: chosenModelID, hubBaseURL: hubURL))
    }

    private func normalizedMetricText(_ text: String) -> [Character] {
        Array(
            text.lowercased()
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                .replacingOccurrences(
                    of: "[，。！？、；：,.!?;:\"'“”‘’（）()\\-]",
                    with: "",
                    options: .regularExpression
                )
        )
    }

    private func levenshteinDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        for (leftIndex, leftChar) in lhs.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(rhs.count + 1)

            for (rightIndex, rightChar) in rhs.enumerated() {
                let substitutionCost = leftChar == rightChar ? 0 : 1
                current.append(
                    min(
                        current[rightIndex] + 1,
                        previous[rightIndex + 1] + 1,
                        previous[rightIndex] + substitutionCost
                    )
                )
            }
            previous = current
        }

        return previous[rhs.count]
    }

    private func normalizedDiffRate(_ lhs: String, _ rhs: String) -> Double {
        let left = normalizedMetricText(lhs)
        let right = normalizedMetricText(rhs)
        let baseline = max(left.count, right.count, 1)
        return Double(levenshteinDistance(left, right)) / Double(baseline)
    }

    private func isPreviewReuseEligible(
        previewText: String,
        finalText: String,
        diffRate: Double
    ) -> Bool {
        let maxTrustedPreviewCount = finalText.count + max(24, finalText.count / 8)
        return previewText.count <= maxTrustedPreviewCount && diffRate <= 0.45
    }

    private func computeMetrics(from diagnosticsList: [WhisperRealtimeReplayDiagnostics]) -> ReplayMetrics {
        var previewCount = 0
        var previewReuseEligibleCount = 0
        var diffRates: [Double] = []
        var lateCoverageCount = 0

        for diagnostics in diagnosticsList {
            guard let finalEvent = diagnostics.events.last(where: { $0.isFinal }) else { continue }
            let liveEvents = diagnostics.events.filter { !$0.isFinal }
            if let previewEvent = liveEvents.last {
                previewCount += 1
                let diffRate = normalizedDiffRate(previewEvent.text, finalEvent.text)
                diffRates.append(diffRate)
                if isPreviewReuseEligible(
                    previewText: previewEvent.text,
                    finalText: finalEvent.text,
                    diffRate: diffRate
                ) {
                    previewReuseEligibleCount += 1
                }
            }
            let latestLiveTime = max(
                liveEvents.map(\.elapsedSeconds).max() ?? 0,
                latestNonFinalTraceActivitySeconds(in: diagnostics.trace) ?? 0
            )
            if latestLiveTime >= finalEvent.elapsedSeconds * 0.75 {
                lateCoverageCount += 1
            }
        }

        let clipCount = diagnosticsList.count
        let previewPublishedRate = clipCount > 0 ? Double(previewCount) / Double(clipCount) : 0
        let previewReuseEligibleRate = clipCount > 0 ? Double(previewReuseEligibleCount) / Double(clipCount) : 0
        let meanDiffRate = diffRates.isEmpty ? 1.0 : diffRates.reduce(0, +) / Double(diffRates.count)
        let maxDiffRate = diffRates.max() ?? 1.0
        let lateCoverageRate = clipCount > 0 ? Double(lateCoverageCount) / Double(clipCount) : 0

        return ReplayMetrics(
            clipCount: clipCount,
            previewPublishedRate: previewPublishedRate,
            previewReuseEligibleRate: previewReuseEligibleRate,
            meanPreviewFinalDiffRate: meanDiffRate,
            maxPreviewFinalDiffRate: maxDiffRate,
            lateCoverageRate: lateCoverageRate
        )
    }

    private func latestNonFinalTraceActivitySeconds(in trace: [String]) -> Double? {
        trace
            .filter { !$0.contains("final/") }
            .compactMap(Self.parseTraceSeconds)
            .max()
    }

    private static func parseTraceSeconds(from entry: String) -> Double? {
        guard entry.hasPrefix("["),
              let endBracket = entry.firstIndex(of: "]") else {
            return nil
        }
        let secondsToken = entry[entry.index(after: entry.startIndex)..<endBracket]
            .replacingOccurrences(of: "s", with: "")
        return Double(secondsToken)
    }

    func testRealtimeOfficialLongFixtureMetricsStayWithinDiagnosticEnvelope() async throws {
        try skipIfCI()
        let resolved = try resolvedModelManager()
        let transcriber = WhisperKitTranscriber(modelManager: resolved.manager)
        let diagnosticsList = try await officialLongFixtureURLs().asyncMap {
            try await transcriber.debugReplayRealtimeAudioFileWithTrace($0, stepSeconds: 4.0)
        }
        let metrics = computeMetrics(from: diagnosticsList)

        print(
            "ASR_METRICS provider=whisper model=\(resolved.modelID) pipeline=liveDisplay " +
            "clips=\(metrics.clipCount) previewPublishedRate=\(metrics.previewPublishedRate) " +
            "previewReuseEligibleRate=\(metrics.previewReuseEligibleRate) " +
            "meanPreviewFinalDiffRate=\(metrics.meanPreviewFinalDiffRate) " +
            "maxPreviewFinalDiffRate=\(metrics.maxPreviewFinalDiffRate) " +
            "lateCoverageRate=\(metrics.lateCoverageRate)"
        )

        XCTAssertEqual(metrics.clipCount, 2)
        XCTAssertGreaterThanOrEqual(
            metrics.previewPublishedRate,
            1.0,
            "Whisper long-form replay should publish at least one live preview for every official long fixture."
        )
        XCTAssertGreaterThanOrEqual(
            metrics.previewReuseEligibleRate,
            0.5,
            "At least half of the Whisper official long fixtures should keep the latest live preview close enough to the final transcript to be reuse-eligible."
        )
        XCTAssertGreaterThanOrEqual(
            metrics.lateCoverageRate,
            0.75,
            "Whisper long-form replay should keep publishing into the later portion of most official long fixtures."
        )
        XCTAssertLessThanOrEqual(
            metrics.meanPreviewFinalDiffRate,
            0.55,
            "Whisper preview vs final divergence is too high on average."
        )
        XCTAssertLessThanOrEqual(
            metrics.maxPreviewFinalDiffRate,
            0.8,
            "At least one Whisper preview diverged too far from the final transcript."
        )
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        for element in self {
            let transformed = try await transform(element)
            results.append(transformed)
        }
        return results
    }
}
