import Darwin
import Foundation

nonisolated enum MeetingFileArchiveCopy {
    static func stagingURL(root: URL, entryID: UUID) throws -> URL {
        let directory = root.appendingPathComponent(".file-analysis-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(entryID.uuidString).appendingPathExtension("wav")
        // These are uncommitted archive candidates, never published history audio.
        if let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            for url in urls where url != destination && url.pathExtension == "wav" {
                guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = values.contentModificationDate, modified < cutoff else { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }
        return destination
    }

    /// Preserve the queue's immutable input until history persistence commits.
    /// APFS clone is cheap; fallback is bounded and budgeted on the destination volume.
    static func create(from source: URL, to destination: URL) throws {
        try Task.checkCancellation()
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        if clonefile(source.path, destination.path, 0) == 0 {
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            return
        }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try MeetingFileResourcePolicy.requireDiskSpace(at: destination.deletingLastPathComponent(), additionalBytes: Int64(size))
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            var copied: Int64 = 0
            while true {
                try Task.checkCancellation()
                let byteCount = try autoreleasepool {
                    guard let data = try input.read(upToCount: 1_048_576), !data.isEmpty else { return 0 }
                    guard Int64(data.count) <= Int64(size) - copied else { throw CocoaError(.fileReadCorruptFile) }
                    try output.write(contentsOf: data)
                    return data.count
                }
                guard byteCount > 0 else { break }
                copied += Int64(byteCount)
                if copied.isMultiple(of: 32 * 1_048_576) {
                    try MeetingFileResourcePolicy.requireDiskSpace(at: destination.deletingLastPathComponent())
                }
            }
            guard copied == Int64(size) else { throw CocoaError(.fileReadCorruptFile) }
            try output.synchronize()
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
