import XCTest
@testable import Voxt

final class MeetingAudioArchiveTests: XCTestCase {
    func testExportWAVPreservesStartOffsetsAcrossSpeakers() async throws {
        let archive = MeetingAudioArchive()
        let oneSecond = [Float](repeating: 1.0, count: 16_000)
        let halfSecond = [Float](repeating: 0.5, count: 16_000)
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingAudioArchiveTests-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        defer {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        await archive.append(samples: oneSecond, sampleRate: 16_000, speaker: .me, startSeconds: 0)
        await archive.append(samples: halfSecond, sampleRate: 16_000, speaker: .them, startSeconds: 1.0)

        let didExport = try await archive.exportWAV(to: destinationURL)
        XCTAssertTrue(didExport)

        let samples = try decodeMono16BitWAVSamples(from: destinationURL)
        XCTAssertEqual(samples.count, 32_000)
        XCTAssertEqual(samples[1_000], 0.5, accuracy: 0.02)
        XCTAssertEqual(samples[20_000], 0.25, accuracy: 0.02)
    }

    private func decodeMono16BitWAVSamples(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let dataRange = try findDataChunk(in: data)
        let pcm = data[dataRange]
        let sampleCount = pcm.count / 2
        var samples: [Float] = []
        samples.reserveCapacity(sampleCount)

        for index in stride(from: 0, to: pcm.count, by: 2) {
            let lower = UInt16(pcm[pcm.startIndex + index])
            let upper = UInt16(pcm[pcm.startIndex + index + 1]) << 8
            let value = Int16(bitPattern: lower | upper)
            samples.append(Float(value) / Float(Int16.max))
        }

        return samples
    }

    private func findDataChunk(in data: Data) throws -> Range<Data.Index> {
        var cursor = 12
        while cursor + 8 <= data.count {
            let chunkID = String(data: data[cursor..<(cursor + 4)], encoding: .ascii)
            let chunkSize = Int(readUInt32LE(from: data, at: cursor + 4))
            let chunkStart = cursor + 8
            let chunkEnd = chunkStart + chunkSize
            guard chunkEnd <= data.count else {
                throw NSError(domain: "MeetingAudioArchiveTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid WAV chunk bounds."])
            }
            if chunkID == "data" {
                return chunkStart..<chunkEnd
            }
            cursor = chunkEnd + (chunkSize % 2)
        }

        throw NSError(domain: "MeetingAudioArchiveTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "WAV data chunk not found."])
    }

    private func readUInt32LE(from data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1]) << 8
        let b2 = UInt32(data[data.startIndex + offset + 2]) << 16
        let b3 = UInt32(data[data.startIndex + offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
