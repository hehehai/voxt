// MeetingImportedAudioFileTests.swift
// Covers imported meeting media normalization and bounded asset loading.

import XCTest
@testable import Voxt

@MainActor
final class MeetingImportedAudioFileTests: XCTestCase {
    func testAnalysisProgressMapsStageProgressToMonotonicOverallProgress() {
        let samples = [
            MeetingFileAnalysisProgress(stage: .preparing, stageFraction: 0),
            MeetingFileAnalysisProgress(stage: .preparing, stageFraction: 1),
            MeetingFileAnalysisProgress(stage: .transcribing, stageFraction: 0.5),
            MeetingFileAnalysisProgress(stage: .identifyingSpeakers, stageFraction: 1),
            MeetingFileAnalysisProgress(stage: .saving, stageFraction: 1),
        ]

        for (actual, expected) in zip(samples.map(\.fractionCompleted), [0, 0.15, 0.465, 0.96, 1]) {
            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
        }
        XCTAssertEqual(samples.map(\.stage), [.preparing, .preparing, .transcribing, .identifyingSpeakers, .saving])
    }

    func testPrepareNormalizesAudioAndCreatesBoundedDescriptors() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Voxt-Meeting-Import-Test-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let sourceSampleRate = 8_000
        let durationSeconds = 61
        let samples = (0..<(sourceSampleRate * durationSeconds)).map { index in
            Float(sin(Double(index) * 2 * .pi * 220 / Double(sourceSampleRate))) * 0.2
        }
        try MeetingAudioChunkWAVExporter.write(
            samples: samples,
            sampleRate: sourceSampleRate,
            to: sourceURL
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let imported = try await MeetingImportedAudioFile.prepare(from: sourceURL)
        defer { try? FileManager.default.removeItem(at: imported.standardizedAudioURL) }

        XCTAssertEqual(imported.durationSeconds, 61, accuracy: 0.05)
        XCTAssertEqual(imported.assetDescriptors.count, 2)
        XCTAssertEqual(imported.assetDescriptors[0].durationSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(imported.assetDescriptors[1].sessionStartOffset, 60, accuracy: 0.001)
        XCTAssertEqual(imported.assetDescriptors[1].durationSeconds, 1, accuracy: 0.05)

        let finalAsset = try XCTUnwrap(imported.loadAsset(imported.assetDescriptors[1]))
        XCTAssertEqual(finalAsset.sampleRate, 16_000)
        XCTAssertEqual(finalAsset.sessionStartOffset, 60, accuracy: 0.001)
        XCTAssertEqual(finalAsset.durationSeconds, 1, accuracy: 0.05)
        XCTAssertTrue(finalAsset.samples.contains { abs($0) > 0.01 })
    }

    func testWAVDataByteCountRejectsValuesThatOverflowRIFFChunkSize() throws {
        let maximumSampleCount = Int(MeetingImportedWAVFormat.maximumDataByteCount) /
            MemoryLayout<Int16>.size

        let acceptedByteCount = try MeetingImportedWAVFormat.dataByteCount(
            sampleCount: maximumSampleCount
        )
        XCTAssertLessThanOrEqual(
            UInt64(acceptedByteCount) + UInt64(MeetingImportedWAVFormat.riffSizeOverhead),
            UInt64(UInt32.max)
        )
        XCTAssertThrowsError(
            try MeetingImportedWAVFormat.dataByteCount(sampleCount: maximumSampleCount + 1)
        ) { error in
            XCTAssertEqual(error as? MeetingImportedAudioFileError, .fileTooLarge)
        }
    }
}
