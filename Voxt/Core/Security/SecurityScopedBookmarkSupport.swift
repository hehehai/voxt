// SecurityScopedBookmarkSupport.swift
// Provides Security Scoped Bookmark Support for permissions and secure storage.

import Foundation

enum SecurityScopedBookmarkSupport {
    private static var activeURLs: [String: URL] = [:]

    static func createBookmark(for url: URL) throws -> Data {
        try url.standardizedFileURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolveDirectoryURL(
        bookmarkData: Data?,
        fallbackPath: String
    ) -> URL? {
        if let bookmarkData,
           let resolved = resolveURL(from: bookmarkData) {
            return resolved
        }

        let trimmedPath = fallbackPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmedPath, isDirectory: true)
    }

    static func resolveFileURL(
        bookmarkData: Data?,
        fallbackPath: String
    ) -> URL? {
        if let bookmarkData,
           let resolved = resolveURL(from: bookmarkData) {
            return resolved
        }

        let trimmedPath = fallbackPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmedPath, isDirectory: false)
    }

    private static func resolveURL(from bookmarkData: Data) -> URL? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        let key = resolved.standardizedFileURL.path
        if activeURLs[key] == nil {
            if resolved.startAccessingSecurityScopedResource() {
                activeURLs[key] = resolved
            }
        }

        return activeURLs[key] ?? resolved
    }
}
