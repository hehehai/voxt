// MeetingImportedAudioFile.swift
// Normalizes imported meeting media and exposes bounded analysis windows.

import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers

enum MeetingFileImportSupport {
    static let allowedContentTypes: [UTType] = [.audio, .movie]
    static let maximumAnalysisDurationSeconds: TimeInterval = 12 * 60 * 60

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

enum MeetingFileTaskStagingError: LocalizedError {
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

    init(
        stage: MeetingFileAnalysisStage,
        stageFraction: Double = 0,
        mediaDurationSeconds: TimeInterval? = nil,
        processedMediaDurationSeconds: TimeInterval? = nil
    ) {
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
        progress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> MeetingImportedAudioFile {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Voxt-Imported-Meeting-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        do {
            let asset = AVURLAsset(url: sourceURL)
            guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                throw MeetingImportedAudioFileError.noAudioTrack
            }
            let durationSeconds = (try? await asset.load(.duration).seconds) ?? 0
            let estimatedSampleCount = durationSeconds.isFinite && durationSeconds > 0
                ? durationSeconds * Double(targetSampleRate)
                : 0
            await progress?(0)

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: targetSampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 32,
                    AVLinearPCMIsFloatKey: true,
                    AVLinearPCMIsBigEndianKey: false
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                throw MeetingImportedAudioFileError.unsupportedMedia
            }
            reader.add(output)

            FileManager.default.createFile(
                atPath: destinationURL.path,
                contents: Data(count: MeetingImportedWAVWriter.headerByteCount)
            )
            let writer = try MeetingImportedWAVWriter(
                destinationURL: destinationURL,
                sampleRate: targetSampleRate
            )

            guard reader.startReading() else {
                throw reader.error ?? MeetingImportedAudioFileError.unableToDecode
            }

            var lastReportedProgress = 0.0
            while let sampleBuffer = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                try writer.append(sampleBuffer: sampleBuffer)
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
        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        let floatByteCount = MemoryLayout<Float32>.size
        guard byteCount >= floatByteCount else { return }
        guard byteCount.isMultiple(of: floatByteCount) else {
            throw MeetingImportedAudioFileError.unableToDecode
        }
        let incomingSampleCount = byteCount / floatByteCount
        guard sampleCount <= Int.max - incomingSampleCount else {
            throw MeetingImportedAudioFileError.fileTooLarge
        }
        _ = try MeetingImportedWAVFormat.dataByteCount(
            sampleCount: sampleCount + incomingSampleCount
        )

        var floatData = Data(count: byteCount)
        let copyStatus = floatData.withUnsafeMutableBytes { bytes in
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

        var pcmData = Data(capacity: incomingSampleCount * MemoryLayout<Int16>.size)
        floatData.withUnsafeBytes { bytes in
            for sample in bytes.bindMemory(to: Float32.self) {
                let clamped = max(-1, min(1, sample))
                var pcmSample = Int16((clamped * Float32(Int16.max)).rounded()).littleEndian
                withUnsafeBytes(of: &pcmSample) { pcmData.append(contentsOf: $0) }
            }
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
