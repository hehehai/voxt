// Bounded random access to our canonical WAV; no full-session Float32 conversion.
import Foundation
#if canImport(FluidAudio)
import FluidAudio

nonisolated final class MeetingPCM16AudioSampleSource: AudioSampleSource, @unchecked Sendable {
    let sampleCount: Int
    private let handle: FileHandle
    private let lock = NSLock()
    private var isCancelled = false
    private var isResourceConstrained = false

    init(url: URL) throws {
        let prepared = try MeetingImportedAudioFile.openPrepared(at: url)
        sampleCount = prepared.sampleCount
        handle = try FileHandle(forReadingFrom: url)
    }

    deinit { try? handle.close() }

    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
    }

    func stopForResourcePressure() {
        lock.lock()
        isResourceConstrained = true
        lock.unlock()
    }

    func copySamples(into destination: UnsafeMutablePointer<Float>, offset: Int, count: Int) throws {
        // Match FluidAudio's clamped range contract. The caller owns tail padding.
        let start = max(offset, 0)
        guard count > 0, start < sampleCount else { return }
        let available = min(count, sampleCount - start)
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { throw CancellationError() }
        guard !isResourceConstrained else { throw MeetingFileWorkError.resourcesUnavailable }
        try handle.seek(toOffset: UInt64(44 + start * 2))
        var copied = 0
        while copied < available {
            try Task.checkCancellation()
            let samplesToRead = min(32_768, available - copied)
            let data = try handle.read(upToCount: samplesToRead * 2) ?? Data()
            guard data.count == samplesToRead * 2 else { throw CocoaError(.fileReadCorruptFile) }
            data.withUnsafeBytes { bytes in
                let raw = bytes.bindMemory(to: UInt8.self)
                for index in 0..<samplesToRead {
                    let bits = UInt16(raw[index * 2]) | UInt16(raw[index * 2 + 1]) << 8
                    destination[copied + index] = Float(Int16(bitPattern: bits)) / 32_768
                }
            }
            copied += samplesToRead
        }
    }
}
#endif
