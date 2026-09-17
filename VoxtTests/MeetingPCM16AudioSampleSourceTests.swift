import Foundation
import XCTest
@testable import Voxt

#if canImport(FluidAudio)
@MainActor
final class MeetingPCM16AudioSampleSourceTests: XCTestCase {
    func testConcurrentRandomReadsAndTailContract() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("audio.wav")
        let samples = (0..<100_000).map { Float(($0 % 100) - 50) / 100 }
        try MeetingAudioChunkWAVExporter.write(samples: samples, sampleRate: 16_000, to: url)
        let source = try MeetingPCM16AudioSampleSource(url: url)
        XCTAssertEqual(source.sampleCount, samples.count)
        let readers = [0, 32760, 70000].map { offset in
            Task.detached { () throws -> [Float] in
                var output = [Float](repeating: 99, count: 20_000)
                try output.withUnsafeMutableBufferPointer {
                    try source.copySamples(into: $0.baseAddress!, offset: offset, count: $0.count)
                }
                return output
            }
        }
        for (offset, reader) in zip([0, 32760, 70000], readers) {
            let result = try await reader.value
            for index in result.indices {
                XCTAssertEqual(result[index], samples[offset + index], accuracy: 0.0001)
            }
        }
        var tail = [Float](repeating: 99, count: 8)
        try tail.withUnsafeMutableBufferPointer {
            try source.copySamples(into: $0.baseAddress!, offset: samples.count - 2, count: 8)
        }
        XCTAssertEqual(tail[0], samples[samples.count - 2], accuracy: 0.0001)
        XCTAssertEqual(tail[1], samples.last!, accuracy: 0.0001)
        XCTAssertEqual(Array(tail.dropFirst(2)), Array(repeating: Float(99), count: 6))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testReaderDistinguishesResourceDeferralFromUserCancellation() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("audio.wav")
        try MeetingAudioChunkWAVExporter.write(samples: Array(repeating: 0.1, count: 160), sampleRate: 16_000, to: url)
        let source = try MeetingPCM16AudioSampleSource(url: url)
        var output = [Float](repeating: 0, count: 160)
        source.stopForResourcePressure()
        do {
            try output.withUnsafeMutableBufferPointer {
                try source.copySamples(into: $0.baseAddress!, offset: 0, count: 160)
            }
            XCTFail("A constrained reader must not continue producing model input")
        } catch MeetingFileWorkError.resourcesUnavailable {} catch { XCTFail("Unexpected error: \(error)") }
        source.cancel()
        do {
            try output.withUnsafeMutableBufferPointer {
                try source.copySamples(into: $0.baseAddress!, offset: 0, count: 160)
            }
            XCTFail("An explicitly cancelled reader must report cancellation")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testTruncatedSourceThrowsRatherThanReturningUninitializedAudio() throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("audio.wav")
        try MeetingAudioChunkWAVExporter.write(samples: Array(repeating: 0.1, count: 160), sampleRate: 16_000, to: url)
        let source = try MeetingPCM16AudioSampleSource(url: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 44)
        try handle.close()
        var output = [Float](repeating: 0, count: 160)
        XCTAssertThrowsError(try output.withUnsafeMutableBufferPointer {
            try source.copySamples(into: $0.baseAddress!, offset: 0, count: 160)
        })
    }
}
#endif
