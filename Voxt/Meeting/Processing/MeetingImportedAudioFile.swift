// MeetingImportedAudioFile.swift
// Normalizes imported meeting media and exposes bounded analysis windows.

import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import UniformTypeIdentifiers

enum MeetingFileImportSupport {
    static let allowedContentTypes: [UTType] = [.audio, .movie]
    static let maximumAnalysisDurationSeconds = MeetingFileResourcePolicy.maximumDurationSeconds

    static func isSupportedImportFile(at url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .contentTypeKey])
        if values?.isDirectory == true {
            return false
        }
        if let isRegularFile = values?.isRegularFile, !isRegularFile {
            return false
        }

        if let contentType = values?.contentType,
           conformsToAllowedTypes(contentType) {
            return true
        }

        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !ext.isEmpty, let inferred = UTType(filenameExtension: ext) else {
            return false
        }
        return conformsToAllowedTypes(inferred)
    }

    static func mediaDurationSeconds(at url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.seconds.isFinite,
              duration.seconds > 0
        else {
            return nil
        }
        return duration.seconds
    }

    /// Preserves the system-provided URL object. Do not standardize or rebuild from a
    /// path string before `startAccessingSecurityScopedResource()` — that strips the
    /// sandbox security scope carried by Finder / NSItemProvider drop URLs.
    static func fileURL(fromDropItem item: Any?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let path = item as? String {
            return fileURL(fromPath: path)
        }
        if let path = item as? NSString {
            return fileURL(fromPath: path as String)
        }
        return nil
    }

    private static func fileURL(fromPath path: String) -> URL? {
        if path.hasPrefix("file:") {
            return URL(string: path)
        }
        return URL(fileURLWithPath: path)
    }

    private static func conformsToAllowedTypes(_ type: UTType) -> Bool {
        allowedContentTypes.contains { type.conforms(to: $0) }
    }
}

nonisolated enum MeetingFileTaskStagingError: LocalizedError {
    case sourceUnavailable
    case sourceTooLarge
    case stagingLimitExceeded
    case mediaDurationUnavailable
    case mediaTooLong
    case insufficientDiskSpace

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            return AppLocalization.localizedString("The selected meeting file is no longer available.")
        case .sourceTooLarge:
            return AppLocalization.localizedString("The selected meeting file is too large to stage safely.")
        case .stagingLimitExceeded:
            return AppLocalization.localizedString("The meeting file queue has reached its storage limit.")
        case .mediaDurationUnavailable:
            return AppLocalization.localizedString("The selected meeting file duration could not be read.")
        case .mediaTooLong:
            return AppLocalization.localizedString("The selected meeting file is longer than the supported 12-hour limit.")
        case .insufficientDiskSpace:
            return AppLocalization.localizedString("There is not enough free disk space to safely stage this meeting file.")
        }
    }
}

enum MeetingFileAnalysisStage: Codable, Equatable, Sendable {
    case preparing
    case transcribing
    case identifyingSpeakers
    case saving
}

struct MeetingFileAnalysisProgress: Equatable, Sendable {
    let stage: MeetingFileAnalysisStage
    let fractionCompleted: Double
    let mediaDurationSeconds: TimeInterval?
    let processedMediaDurationSeconds: TimeInterval?
    let historyEntryID: UUID?
    let notice: String?

    init(
        stage: MeetingFileAnalysisStage,
        stageFraction: Double = 0,
        mediaDurationSeconds: TimeInterval? = nil,
        processedMediaDurationSeconds: TimeInterval? = nil,
        historyEntryID: UUID? = nil,
        notice: String? = nil
    ) {
        self.historyEntryID = historyEntryID
        self.notice = notice
        let clampedStageFraction = min(max(stageFraction, 0), 1)
        self.stage = stage
        self.mediaDurationSeconds = Self.validDuration(mediaDurationSeconds)
        self.processedMediaDurationSeconds = Self.validDuration(processedMediaDurationSeconds)
        switch stage {
        case .preparing:
            fractionCompleted = clampedStageFraction * 0.15
        case .transcribing:
            fractionCompleted = 0.15 + clampedStageFraction * 0.63
        case .identifyingSpeakers:
            fractionCompleted = 0.78 + clampedStageFraction * 0.18
        case .saving:
            fractionCompleted = 0.96 + clampedStageFraction * 0.04
        }
    }

    private static func validDuration(_ value: TimeInterval?) -> TimeInterval? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

enum MeetingFileAnalysisError: LocalizedError {
    case sessionAlreadyActive
    case noTranscript

    var errorDescription: String? {
        switch self {
        case .sessionAlreadyActive:
            return AppLocalization.localizedString("Finish the current recording before analyzing a meeting file.")
        case .noTranscript:
            return AppLocalization.localizedString("No speech could be transcribed from the selected file.")
        }
    }
}

nonisolated struct MeetingImportedAudioFile: Sendable {
    static let targetSampleRate = 16_000
    private static let analysisWindowSeconds: TimeInterval = 60

    let standardizedAudioURL: URL
    let sampleCount: Int

    var durationSeconds: TimeInterval {
        TimeInterval(sampleCount) / TimeInterval(Self.targetSampleRate)
    }

    var assetDescriptors: [MeetingAudioAssetDescriptor] {
        let samplesPerWindow = max(
            Int(Self.analysisWindowSeconds * TimeInterval(Self.targetSampleRate)),
            1
        )
        var descriptors: [MeetingAudioAssetDescriptor] = []
        var startSample = 0
        while startSample < sampleCount {
            let windowSampleCount = min(samplesPerWindow, sampleCount - startSample)
            descriptors.append(
                MeetingAudioAssetDescriptor(
                    source: .mixed,
                    sampleRate: Double(Self.targetSampleRate),
                    startSample: startSample,
                    sampleCount: windowSampleCount
                )
            )
            startSample += windowSampleCount
        }
        return descriptors
    }

    static func prepare(
        from sourceURL: URL,
        destinationURL: URL? = nil,
        progress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> MeetingImportedAudioFile {
        let destinationURL = destinationURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("Voxt-Imported-Meeting-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw CocoaError(.fileWriteFileExists)
        }

        do {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: sourceURL)
            guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                throw MeetingImportedAudioFileError.noAudioTrack
            }
            let durationSeconds = (try? await asset.load(.duration).seconds) ?? 0
            let estimatedSampleCount = durationSeconds.isFinite && durationSeconds > 0
                ? durationSeconds * Double(targetSampleRate)
                : 0
            await progress?(0)

            let estimatedBytes = try MeetingFileResourcePolicy.preparedByteCount(duration: durationSeconds)
            try MeetingFileResourcePolicy.requireDiskSpace(
                at: destinationURL.deletingLastPathComponent(), additionalBytes: estimatedBytes
            )
            try Task.checkCancellation()
            let reader = try AVAssetReader(asset: asset)
            defer { reader.cancelReading() }
            let output = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: targetSampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw MeetingImportedAudioFileError.unsupportedMedia
            }
            reader.add(output)

            guard FileManager.default.createFile(
                    atPath: destinationURL.path,
                    contents: Data(count: MeetingImportedWAVWriter.headerByteCount),
                    attributes: [.posixPermissions: 0o600]
                  ) else {
                throw CocoaError(.fileWriteFileExists)
            }
            let writer = try MeetingImportedWAVWriter(
                destinationURL: destinationURL,
                sampleRate: targetSampleRate
            )

            guard reader.startReading() else {
                throw reader.error ?? MeetingImportedAudioFileError.unableToDecode
            }

            var lastReportedProgress = 0.0
            var lastDiskCheckSample = 0
            while true {
                try Task.checkCancellation()
                let hasBuffer = try autoreleasepool {
                    guard let sampleBuffer = output.copyNextSampleBuffer() else { return false }
                    try writer.append(sampleBuffer: sampleBuffer)
                    return true
                }
                guard hasBuffer else { break }
                guard writer.sampleCount <= Int(MeetingFileResourcePolicy.maximumDurationSeconds) * targetSampleRate else {
                    throw MeetingFileTaskStagingError.mediaTooLong
                }
                if writer.sampleCount - lastDiskCheckSample >= targetSampleRate * 30 {
                    try MeetingFileResourcePolicy.requireDiskSpace(at: destinationURL.deletingLastPathComponent())
                    lastDiskCheckSample = writer.sampleCount
                }
                if estimatedSampleCount > 0 {
                    let currentProgress = min(Double(writer.sampleCount) / estimatedSampleCount, 1)
                    if currentProgress - lastReportedProgress >= 0.01 {
                        lastReportedProgress = currentProgress
                        await progress?(currentProgress)
                    }
                }
            }

            if reader.status == .failed {
                throw reader.error ?? MeetingImportedAudioFileError.unableToDecode
            }
            try Task.checkCancellation()
            try writer.finish()

            guard writer.sampleCount > 0 else {
                throw MeetingImportedAudioFileError.emptyAudio
            }
            await progress?(1)
            return MeetingImportedAudioFile(
                standardizedAudioURL: destinationURL,
                sampleCount: writer.sampleCount
            )
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    /// Only accepts the canonical WAV layout produced by this importer. Other media
    /// must be normalized; a .wav extension alone is not sufficient.
    static func openPrepared(at url: URL) throws -> MeetingImportedAudioFile {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        guard let header = try input.read(upToCount: 44), header.count == 44 else {
            throw MeetingImportedAudioFileError.unsupportedMedia
        }
        func u16(_ offset: Int) -> UInt16 {
            UInt16(header[offset]) | UInt16(header[offset + 1]) << 8
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16
        }
        let byteCount = Int64(u32(40))
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard String(data: header[0..<4], encoding: .ascii) == "RIFF",
              String(data: header[8..<12], encoding: .ascii) == "WAVE",
              String(data: header[12..<16], encoding: .ascii) == "fmt ",
              u32(16) == 16, u16(20) == 1, u16(22) == 1,
              u32(24) == 16_000, u32(28) == 32_000, u16(32) == 2, u16(34) == 16,
              String(data: header[36..<40], encoding: .ascii) == "data",
              byteCount > 0, byteCount.isMultiple(of: 2),
              Int64(u32(4)) == byteCount + 36,
              size.map({ Int64($0) == byteCount + 44 }) == true,
              byteCount <= Int64(MeetingFileResourcePolicy.maximumDurationSeconds * 32_000)
        else { throw MeetingImportedAudioFileError.unsupportedMedia }
        return MeetingImportedAudioFile(standardizedAudioURL: url, sampleCount: Int(byteCount / 2))
    }

    func loadAsset(_ descriptor: MeetingAudioAssetDescriptor) -> MeetingAudioAsset? {
        guard descriptor.sampleRate == Double(Self.targetSampleRate),
              descriptor.startSample >= 0,
              descriptor.sampleCount > 0
        else {
            return nil
        }

        do {
            let file = try AVAudioFile(forReading: standardizedAudioURL)
            file.framePosition = AVAudioFramePosition(descriptor.startSample)
            let availableFrames = max(Int(file.length - file.framePosition), 0)
            let frameCount = min(descriptor.sampleCount, availableFrames)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(frameCount)
                  )
            else {
                return nil
            }
            try file.read(into: buffer, frameCount: AVAudioFrameCount(frameCount))
            guard let samples = AudioLevelMeter.monoSamples(from: buffer), !samples.isEmpty else {
                return nil
            }
            return MeetingAudioAsset(
                source: descriptor.source,
                samples: samples,
                sampleRate: descriptor.sampleRate,
                sessionStartOffset: descriptor.sessionStartOffset
            )
        } catch {
            VoxtLog.meetingWarning(
                "Imported meeting audio window could not be loaded. start=\(descriptor.sessionStartOffset), error=\(error.localizedDescription)"
            )
            return nil
        }
    }
}

nonisolated enum MeetingImportedAudioFileError: LocalizedError, Equatable {
    case noAudioTrack
    case unsupportedMedia
    case unableToDecode
    case emptyAudio
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return AppLocalization.localizedString("The selected file does not contain an audio track.")
        case .unsupportedMedia:
            return AppLocalization.localizedString("This audio or video file cannot be analyzed.")
        case .unableToDecode:
            return AppLocalization.localizedString("Voxt could not decode the selected media file.")
        case .emptyAudio:
            return AppLocalization.localizedString("The selected file does not contain usable audio.")
        case .fileTooLarge:
            return AppLocalization.localizedString("The meeting audio is too long to store as a WAV file.")
        }
    }
}

nonisolated enum MeetingImportedWAVFormat {
    static let headerByteCount = 44
    static let riffSizeOverhead: Int64 = 36
    static let maximumDataByteCount = Int64(UInt32.max) - riffSizeOverhead

    static func dataByteCount(sampleCount: Int) throws -> UInt32 {
        let bytesPerSample = Int64(MemoryLayout<Int16>.size)
        guard sampleCount >= 0,
              Int64(sampleCount) <= maximumDataByteCount / bytesPerSample
        else {
            throw MeetingImportedAudioFileError.fileTooLarge
        }
        let dataByteCount = Int64(sampleCount) * bytesPerSample
        return UInt32(dataByteCount)
    }
}

nonisolated private final class MeetingImportedWAVWriter {
    static let headerByteCount = MeetingImportedWAVFormat.headerByteCount

    private let handle: FileHandle
    private let sampleRate: Int
    private(set) var sampleCount = 0
    private var isFinished = false

    init(destinationURL: URL, sampleRate: Int) throws {
        self.handle = try FileHandle(forWritingTo: destinationURL)
        self.sampleRate = sampleRate
        try handle.seek(toOffset: UInt64(Self.headerByteCount))
    }

    deinit {
        try? handle.close()
    }

    func append(sampleBuffer: CMSampleBuffer) throws {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mSampleRate == Double(sampleRate), format.mChannelsPerFrame == 1,
              format.mBitsPerChannel == 16, format.mBytesPerFrame == 2,
              format.mFormatFlags & kAudioFormatFlagIsFloat == 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 else {
            throw MeetingImportedAudioFileError.unableToDecode
        }
        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        let bytesPerSample = MemoryLayout<Int16>.size
        guard byteCount >= bytesPerSample else { return }
        guard byteCount.isMultiple(of: bytesPerSample) else {
            throw MeetingImportedAudioFileError.unableToDecode
        }
        let incomingSampleCount = byteCount / bytesPerSample
        guard sampleCount <= Int.max - incomingSampleCount else {
            throw MeetingImportedAudioFileError.fileTooLarge
        }
        _ = try MeetingImportedWAVFormat.dataByteCount(
            sampleCount: sampleCount + incomingSampleCount
        )

        // AVFoundation performs resampling/downmix/PCM16 conversion natively.
        // Avoid a Float32 copy and a per-sample Swift quantization/append loop.
        var pcmData = Data(count: byteCount)
        let copyStatus = pcmData.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: byteCount,
                destination: baseAddress
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else {
            throw MeetingImportedAudioFileError.unableToDecode
        }

        try handle.write(contentsOf: pcmData)
        sampleCount += incomingSampleCount
    }

    func finish() throws {
        guard !isFinished else { return }
        isFinished = true
        let dataByteCount = try MeetingImportedWAVFormat.dataByteCount(sampleCount: sampleCount)
        let header = Self.wavHeader(sampleRate: sampleRate, dataByteCount: dataByteCount)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header)
        try handle.synchronize()
        try handle.close()
    }

    private static func wavHeader(sampleRate: Int, dataByteCount: UInt32) -> Data {
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(littleEndianData(36 + dataByteCount))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(littleEndianData(UInt32(16)))
        data.append(littleEndianData(UInt16(1)))
        data.append(littleEndianData(UInt16(1)))
        data.append(littleEndianData(UInt32(sampleRate)))
        data.append(littleEndianData(UInt32(sampleRate * MemoryLayout<Int16>.size)))
        data.append(littleEndianData(UInt16(MemoryLayout<Int16>.size)))
        data.append(littleEndianData(UInt16(16)))
        data.append("data".data(using: .ascii)!)
        data.append(littleEndianData(dataByteCount))
        return data
    }

    private static func littleEndianData<Value: FixedWidthInteger>(_ value: Value) -> Data {
        var littleEndianValue = value.littleEndian
        return Data(bytes: &littleEndianValue, count: MemoryLayout<Value>.size)
    }
}
