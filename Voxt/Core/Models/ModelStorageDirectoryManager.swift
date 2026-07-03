// ModelStorageDirectoryManager.swift
// Provides Model Storage Directory Manager for model catalog and storage support.

import Foundation
import AppKit

enum ModelStorageDirectoryManager {
    struct RootResolution {
        let writeRootURL: URL
        let readableRootURLs: [URL]
        let derivedRootURL: URL
    }

    private struct ResolvedRootCache {
        let bookmarkData: Data?
        let path: String?
        let resolution: RootResolution
    }

    private static let lock = NSLock()
    private static var securityScopedURL: URL?
    private static var resolvedRootCache: ResolvedRootCache?
    private static let fileManager = FileManager.default

    static var defaultRootURL: URL {
        defaultRootURL(fileManager: fileManager)
    }

    static var legacyDefaultRootURL: URL {
        legacyDefaultRootURL(fileManager: fileManager)
    }

    static func resolvedRootURL() -> URL {
        resolvedWriteRootURL(defaults: .standard)
    }

    static func resolvedRootURL(defaults: UserDefaults) -> URL {
        resolvedWriteRootURL(defaults: defaults)
    }

    static func resolvedWriteRootURL(defaults: UserDefaults = .standard) -> URL {
        resolvedRootResolution(defaults: defaults).writeRootURL
    }

    static func resolvedReadableRootURLs(defaults: UserDefaults = .standard) -> [URL] {
        resolvedRootResolution(defaults: defaults).readableRootURLs
    }

    static func resolvedDerivedRootURL(defaults: UserDefaults = .standard) -> URL {
        resolvedRootResolution(defaults: defaults).derivedRootURL
    }

    static func resolvedRootResolution(defaults: UserDefaults = .standard) -> RootResolution {
        let bookmarkData = defaults.data(forKey: AppPreferenceKey.modelStorageRootBookmark)
        let storedPath = normalizedStoredPath(defaults.string(forKey: AppPreferenceKey.modelStorageRootPath))
        lock.lock()
        if let resolvedRootCache,
           resolvedRootCache.bookmarkData == bookmarkData,
           resolvedRootCache.path == storedPath {
            let cachedResolution = resolvedRootCache.resolution
            lock.unlock()
            return cachedResolution
        }
        lock.unlock()

        let resolution: RootResolution
        if let bookmarkData,
           let bookmarkedURL = resolveSecurityScopedURL(from: bookmarkData, defaults: defaults) {
            resolution = RootResolution(
                writeRootURL: bookmarkedURL,
                readableRootURLs: [bookmarkedURL],
                derivedRootURL: derivedRootURL(forWriteRoot: bookmarkedURL)
            )
        } else if let storedPath {
            let rootURL = URL(fileURLWithPath: storedPath, isDirectory: true)
            if rootURL.standardizedFileURL.path == legacyDefaultRootURL.standardizedFileURL.path {
                let writeRootURL = defaultRootURL
                resolution = RootResolution(
                    writeRootURL: writeRootURL,
                    readableRootURLs: uniqueRootURLs([writeRootURL, legacyDefaultRootURL]),
                    derivedRootURL: derivedRootURL(forWriteRoot: writeRootURL)
                )
            } else {
                resolution = RootResolution(
                    writeRootURL: rootURL,
                    readableRootURLs: [rootURL],
                    derivedRootURL: derivedRootURL(forWriteRoot: rootURL)
                )
            }
        } else {
            let writeRootURL = defaultRootURL
            resolution = RootResolution(
                writeRootURL: writeRootURL,
                readableRootURLs: uniqueRootURLs([writeRootURL, legacyDefaultRootURL]),
                derivedRootURL: derivedRootURL(forWriteRoot: writeRootURL)
            )
        }

        updateResolvedRootCache(
            bookmarkData: bookmarkData,
            path: storedPath,
            resolution: resolution
        )
        return resolution
    }

    static func saveUserSelectedRootURL(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        let bookmark = try normalized.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let defaults = UserDefaults.standard
        defaults.set(normalized.path, forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.set(bookmark, forKey: AppPreferenceKey.modelStorageRootBookmark)
        updateResolvedRootCache(
            bookmarkData: bookmark,
            path: normalized.path,
            resolution: RootResolution(
                writeRootURL: normalized,
                readableRootURLs: [normalized],
                derivedRootURL: derivedRootURL(forWriteRoot: normalized)
            )
        )

        _ = resolveSecurityScopedURL(from: bookmark, defaults: defaults)
    }

    static func openRootInFinder() {
        let url = resolvedWriteRootURL()
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func resetForTesting() {
        lock.lock()
        resolvedRootCache = nil
        lock.unlock()
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    private static func resolveSecurityScopedURL(from bookmarkData: Data, defaults: UserDefaults) -> URL? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if securityScopedURL?.path != resolved.path {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            if resolved.startAccessingSecurityScopedResource() {
                securityScopedURL = resolved
            }
        }

        if isStale,
           let refreshed = try? resolved.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
           ) {
            defaults.set(refreshed, forKey: AppPreferenceKey.modelStorageRootBookmark)
            updateResolvedRootCache(
                bookmarkData: refreshed,
                path: normalizedStoredPath(defaults.string(forKey: AppPreferenceKey.modelStorageRootPath)),
                resolution: RootResolution(
                    writeRootURL: resolved,
                    readableRootURLs: [resolved],
                    derivedRootURL: derivedRootURL(forWriteRoot: resolved)
                )
            )
        }

        return resolved
    }

    private static func defaultRootURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("model-storage", isDirectory: true)
    }

    private static func legacyDefaultRootURL(fileManager: FileManager) -> URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
        return caches
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("hub", isDirectory: true)
    }

    private static func normalizedStoredPath(_ path: String?) -> String? {
        guard let path,
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
    }

    private static func uniqueRootURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var uniqueURLs: [URL] = []
        for url in urls {
            let normalizedURL = url.standardizedFileURL
            if seenPaths.insert(normalizedURL.path).inserted {
                uniqueURLs.append(normalizedURL)
            }
        }
        return uniqueURLs
    }

    private static func derivedRootURL(forWriteRoot writeRootURL: URL) -> URL {
        writeRootURL
            .appendingPathComponent(".derived-model-artifacts", isDirectory: true)
    }

    private static func updateResolvedRootCache(bookmarkData: Data?, path: String?, resolution: RootResolution) {
        lock.lock()
        resolvedRootCache = ResolvedRootCache(
            bookmarkData: bookmarkData,
            path: path,
            resolution: resolution
        )
        lock.unlock()
    }
}
