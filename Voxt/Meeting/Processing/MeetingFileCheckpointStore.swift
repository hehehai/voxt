// Window-sized atomic commits: an interrupted window is replayed, never half committed.
import CryptoKit
import Foundation

nonisolated struct MeetingFileCheckpoint: Sendable {
    let historyID: UUID
    let completedWindows: Int
    let segments: [MeetingTranscriptSegment]
    let transcriptionEngineRawValue: String?
    let transcriptionModelDescription: String?
}

actor MeetingFileCheckpointStore {
    private struct Manifest: Codable, Sendable {
        let version: Int
        let signature: String
        let sourceBytes: Int
        let sourceModifiedAt: Date
        let historyID: UUID
        let transcriptionEngineRawValue: String?
        let transcriptionModelDescription: String?
    }
    private struct Window: Codable, Sendable {
        let index: Int
        let segments: [MeetingTranscriptSegment]
        // TranscriptSegment's history encoding intentionally omits this transient
        // flag. Checkpoints must retain it to make resumed post-processing identical.
        let preventsAdjacentMergeIDs: [UUID]?
    }

    nonisolated let directoryURL: URL
    private let sourceURL: URL
    private let signature: String
    private let engineRawValue: String?
    private let modelDescription: String?
    private let fileManager = FileManager.default

    init(sourceURL: URL, signature: String, engineRawValue: String? = nil, modelDescription: String? = nil) {
        self.sourceURL = sourceURL
        self.signature = signature
        self.engineRawValue = engineRawValue
        self.modelDescription = modelDescription
        directoryURL = Self.directory(for: sourceURL)
    }

    nonisolated static func directory(for sourceURL: URL) -> URL {
        sourceURL.appendingPathExtension("analysis")
    }

    nonisolated static func signature(parts: [String]) -> String {
        // Length-prefixed JSON prevents delimiter ambiguities. Store only the digest,
        // never provider credentials or dictionary content.
        let data = (try? JSONEncoder().encode(parts)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func load(windowCount: Int) throws -> MeetingFileCheckpoint {
        guard (0...720).contains(windowCount) else { throw MeetingFileWorkError.invalidCheckpoint }
        // URL.resourceValues may reuse cached metadata on repeated loads of the
        // same URL instance, hiding input replacement/modification during a retry.
        let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        guard let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else {
            throw MeetingFileWorkError.invalidCheckpoint
        }
        let sourceBytes = size.intValue
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        var manifest: Manifest
        if fileManager.fileExists(atPath: manifestURL.path) {
            do { manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL)) }
            catch { throw MeetingFileWorkError.invalidCheckpoint }
            guard manifest.version == 1, manifest.sourceBytes == sourceBytes,
                  manifest.sourceModifiedAt == modified else {
                throw MeetingFileWorkError.invalidCheckpoint
            }
        } else {
            manifest = Manifest(version: 1, signature: signature, sourceBytes: sourceBytes,
                                sourceModifiedAt: modified, historyID: UUID(),
                                transcriptionEngineRawValue: engineRawValue, transcriptionModelDescription: modelDescription)
            try write(manifest, to: manifestURL)
        }
        var segments: [MeetingTranscriptSegment] = []
        var completed = 0
        for index in 0..<windowCount {
            try Task.checkCancellation()
            let url = windowURL(index)
            guard fileManager.fileExists(atPath: url.path) else { break }
            let window: Window
            do { window = try JSONDecoder().decode(Window.self, from: Data(contentsOf: url)) }
            catch { throw MeetingFileWorkError.invalidCheckpoint }
            guard window.index == index else { throw MeetingFileWorkError.invalidCheckpoint }
            let mergeProtectedIDs = Set(window.preventsAdjacentMergeIDs ?? [])
            segments.append(contentsOf: window.segments.map { segment in
                guard mergeProtectedIDs.contains(segment.id) else { return segment }
                return MeetingTranscriptSegment(
                    id: segment.id, speaker: segment.speaker,
                    speakerID: segment.speakerID, speakerDisplayName: segment.speakerDisplayName,
                    audioSource: segment.audioSource, speakerConfidence: segment.speakerConfidence,
                    startSeconds: segment.startSeconds, endSeconds: segment.endSeconds,
                    text: segment.text, translatedText: segment.translatedText,
                    isTranslationPending: segment.isTranslationPending,
                    preventsAdjacentMerge: true, isHighlighted: segment.isHighlighted
                )
            })
            completed += 1
        }
        if manifest.signature != signature, completed < windowCount {
            let hasCommittedWindows = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
                .contains { $0.hasPrefix("window-") && $0.hasSuffix(".json") }
            guard !hasCommittedWindows else { throw MeetingFileWorkError.incompatibleCheckpoint }
            // A failed first inference has no reusable results to mix. Let users
            // fix model/provider settings without forcing a second audio import.
            manifest = Manifest(version: 1, signature: signature, sourceBytes: sourceBytes,
                                sourceModifiedAt: modified, historyID: manifest.historyID,
                                transcriptionEngineRawValue: engineRawValue, transcriptionModelDescription: modelDescription)
            try write(manifest, to: manifestURL)
        }
        // Completed ASR can proceed to speaker analysis under different current ASR
        // preferences; retain the original model provenance and do not run more ASR.
        return MeetingFileCheckpoint(
            historyID: manifest.historyID, completedWindows: completed, segments: segments,
            transcriptionEngineRawValue: manifest.transcriptionEngineRawValue,
            transcriptionModelDescription: manifest.transcriptionModelDescription
        )
    }

    func commit(index: Int, segments: [MeetingTranscriptSegment]) throws {
        guard (0..<720).contains(index),
              fileManager.fileExists(atPath: directoryURL.appendingPathComponent("manifest.json").path) else {
            throw MeetingFileWorkError.invalidCheckpoint
        }
        try Task.checkCancellation()
        try MeetingFileResourcePolicy.requireDiskSpace(at: directoryURL)
        try write(Window(
            index: index, segments: segments,
            preventsAdjacentMergeIDs: segments.filter(\.preventsAdjacentMerge).map(\.id)
        ), to: windowURL(index))
    }

    private func windowURL(_ index: Int) -> URL {
        directoryURL.appendingPathComponent(String(format: "window-%05d.json", index))
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
