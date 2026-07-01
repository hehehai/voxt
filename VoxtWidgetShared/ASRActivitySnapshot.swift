// ASRActivitySnapshot.swift
// Shared activity snapshot models for Voxt widgets.

import Foundation

enum ASRActivityConstants {
    static let appGroupIdentifierInfoKey = "VOXTAppGroupIdentifier"
    static let defaultAppGroupIdentifier = "group.com.voxt.Voxt"
    static let snapshotFileName = "asr-activity-24h.json"
    static let widgetKind = "ASRActivityWidget"
    static let supportedHistoryKinds: Set<String> = ["normal", "translation", "rewrite"]

    static var appGroupIdentifier: String {
        let configured = Bundle.main.object(forInfoDictionaryKey: appGroupIdentifierInfoKey) as? String
        let trimmed = configured?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed! : defaultAppGroupIdentifier
    }
}

struct ASRActivityBucket: Codable, Hashable, Identifiable, Sendable {
    let startDate: Date
    let endDate: Date
    let count: Int

    var id: Date { startDate }
}

struct ASRActivitySnapshot: Codable, Hashable, Sendable {
    let generatedAt: Date
    let windowStart: Date
    let windowEnd: Date
    let buckets: [ASRActivityBucket]
    let totalCount: Int
    let highestBucketCount: Int
    let lastActivityAt: Date?

    static func empty(now: Date = Date(), calendar: Calendar = .current) -> ASRActivitySnapshot {
        ASRActivitySnapshotBuilder.makeSnapshot(events: [], now: now, calendar: calendar)
    }
}

struct ASRActivitySnapshotBuilder {
    struct Event: Hashable, Sendable {
        let createdAt: Date
        let kind: String

        init(createdAt: Date, kind: String) {
            self.createdAt = createdAt
            self.kind = kind
        }
    }

    static func windowStart(
        now: Date = Date(),
        calendar: Calendar = .current,
        bucketCount: Int = 24
    ) -> Date {
        let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: -(bucketCount - 1), to: currentHourStart) ?? currentHourStart
    }

    static func makeSnapshot(
        events: [Event],
        now: Date = Date(),
        calendar: Calendar = .current,
        bucketCount: Int = 24
    ) -> ASRActivitySnapshot {
        let safeBucketCount = max(bucketCount, 1)
        let firstBucketStart = windowStart(now: now, calendar: calendar, bucketCount: safeBucketCount)
        let currentHourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let windowEnd = calendar.date(byAdding: .hour, value: 1, to: currentHourStart) ?? now

        var buckets = (0..<safeBucketCount).map { index in
            let start = calendar.date(byAdding: .hour, value: index, to: firstBucketStart) ?? firstBucketStart
            let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
            return ASRActivityBucket(startDate: start, endDate: end, count: 0)
        }

        var latestActivity: Date?
        for event in events where shouldCount(kind: event.kind) {
            guard event.createdAt >= firstBucketStart, event.createdAt < windowEnd else { continue }
            guard let bucketIndex = buckets.firstIndex(where: {
                event.createdAt >= $0.startDate && event.createdAt < $0.endDate
            }) else {
                continue
            }

            let bucket = buckets[bucketIndex]
            buckets[bucketIndex] = ASRActivityBucket(
                startDate: bucket.startDate,
                endDate: bucket.endDate,
                count: bucket.count + 1
            )

            if latestActivity == nil || event.createdAt > latestActivity! {
                latestActivity = event.createdAt
            }
        }

        let totalCount = buckets.reduce(0) { $0 + $1.count }
        let highestBucketCount = buckets.map(\.count).max() ?? 0

        return ASRActivitySnapshot(
            generatedAt: now,
            windowStart: firstBucketStart,
            windowEnd: windowEnd,
            buckets: buckets,
            totalCount: totalCount,
            highestBucketCount: highestBucketCount,
            lastActivityAt: latestActivity
        )
    }

    private static func shouldCount(kind: String) -> Bool {
        ASRActivityConstants.supportedHistoryKinds.contains(kind)
    }
}

enum ASRActivitySnapshotStore {
    static func snapshotURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: ASRActivityConstants.appGroupIdentifier)?
            .appendingPathComponent(ASRActivityConstants.snapshotFileName, isDirectory: false)
    }

    static func load(fileManager: FileManager = .default) -> ASRActivitySnapshot? {
        guard let url = snapshotURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return try? JSONDecoder().decode(ASRActivitySnapshot.self, from: data)
    }

    static func save(_ snapshot: ASRActivitySnapshot, fileManager: FileManager = .default) throws {
        guard let url = snapshotURL(fileManager: fileManager) else {
            throw CocoaError(.fileNoSuchFile)
        }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }
}
