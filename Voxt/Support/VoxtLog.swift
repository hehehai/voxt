import Foundation

enum VoxtLog {
    struct ExportPayload {
        let filename: String
        let content: String
    }

    private enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    nonisolated(unsafe) static var verboseEnabled = false

    nonisolated static func info(_ message: @autoclosure () -> String, verbose: Bool = false) {
        log(message(), level: .info, verbose: verbose)
    }

    nonisolated static func hotkey(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.hotkeyDebugLoggingEnabled) else { return }
        log(message(), level: .info)
    }

    nonisolated static func llm(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.llmDebugLoggingEnabled) else { return }
        log(message(), level: .info)
    }

    nonisolated static func model(_ message: @autoclosure () -> String) {
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.llmDebugLoggingEnabled) else { return }
        log(message(), level: .info)
    }

    nonisolated static func llmPreview(_ text: String, limit: Int = 1200) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "<empty>" }
        guard normalized.count > limit else { return normalized }
        let endIndex = normalized.index(normalized.startIndex, offsetBy: limit)
        return "\(normalized[..<endIndex])…"
    }

    nonisolated static func warning(_ message: @autoclosure () -> String) {
        log(message(), level: .warning)
    }

    nonisolated static func error(_ message: @autoclosure () -> String) {
        log(message(), level: .error)
    }

    nonisolated static func latestLogUpdateDate() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: logFileURL.path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    nonisolated static func latestLogExportPayload(limit: Int = 2000) -> ExportPayload {
        lock.lock()
        defer { lock.unlock() }
        loadCacheIfNeeded()

        let resolvedLimit = max(1, limit)
        let selectedLines = logLines.suffix(resolvedLimit)
        let content = selectedLines.joined(separator: "\n")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "voxt-log-\(formatter.string(from: Date())).log"
        return ExportPayload(filename: filename, content: content)
    }

    nonisolated static func exportLatestLogs(limit: Int = 2000) throws -> URL {
        let payload = latestLogExportPayload(limit: limit)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(payload.filename)
        try payload.content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private nonisolated static let lock = NSLock()
    private nonisolated static let maxStoredLines = 10000
    private nonisolated(unsafe) static var didLoadCache = false
    private nonisolated(unsafe) static var logLines: [String] = []
    private nonisolated(unsafe) static let lineDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated static var logFileURL: URL {
        let supportDirectory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = supportDirectory ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("voxt.log")
    }

    private nonisolated static func log(_ message: String, level: Level, verbose: Bool = false) {
        guard !verbose || verboseEnabled else { return }
        let line = formatLine(message: message, level: level)
        print(line)
        persist(line: line)
    }

    private nonisolated static func formatLine(message: String, level: Level) -> String {
        let dateText = lineDateFormatter.string(from: Date())
        return "[Voxt] \(dateText) [\(level.rawValue)] \(message)"
    }

    private nonisolated static func persist(line: String) {
        lock.lock()
        defer { lock.unlock() }
        loadCacheIfNeeded()
        logLines.append(line)
        trimIfNeeded()
        writeAllLines()
    }

    private nonisolated static func loadCacheIfNeeded() {
        guard !didLoadCache else { return }
        didLoadCache = true
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8), !content.isEmpty else {
            logLines = []
            return
        }
        logLines = content
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        trimIfNeeded()
    }

    private nonisolated static func trimIfNeeded() {
        guard logLines.count > maxStoredLines else { return }
        logLines = Array(logLines.suffix(maxStoredLines))
    }

    private nonisolated static func writeAllLines() {
        do {
            try FileManager.default.createDirectory(
                at: logFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let text = logLines.joined(separator: "\n")
            try text.write(to: logFileURL, atomically: true, encoding: .utf8)
        } catch {
            // Keep logging non-fatal.
        }
    }
}
