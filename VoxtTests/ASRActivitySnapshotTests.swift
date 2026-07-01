// ASRActivitySnapshotTests.swift
// Covers the shared ASR activity widget snapshot builder.

import XCTest
@testable import Voxt

final class ASRActivitySnapshotTests: XCTestCase {
    func testSnapshotBuildsTwentyFourHourlyBucketsAndCountsSupportedKinds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_704_117_660) // 2024-01-01 15:21 UTC
        let currentHour = calendar.dateInterval(of: .hour, for: now)!.start
        let previousHour = calendar.date(byAdding: .hour, value: -1, to: currentHour)!
        let outsideWindow = calendar.date(byAdding: .hour, value: -24, to: currentHour)!

        let snapshot = ASRActivitySnapshotBuilder.makeSnapshot(
            events: [
                .init(createdAt: currentHour.addingTimeInterval(60), kind: "normal"),
                .init(createdAt: currentHour.addingTimeInterval(120), kind: "translation"),
                .init(createdAt: previousHour.addingTimeInterval(30), kind: "rewrite"),
                .init(createdAt: currentHour.addingTimeInterval(180), kind: "transcript"),
                .init(createdAt: outsideWindow, kind: "normal")
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.buckets.count, 24)
        XCTAssertEqual(snapshot.totalCount, 3)
        XCTAssertEqual(snapshot.highestBucketCount, 2)
        XCTAssertEqual(snapshot.buckets[22].count, 1)
        XCTAssertEqual(snapshot.buckets[23].count, 2)
        XCTAssertEqual(snapshot.lastActivityAt, currentHour.addingTimeInterval(120))
    }

    func testSnapshotIgnoresFutureEventsAndKeepsEmptyBuckets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_704_117_660)
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: calendar.dateInterval(of: .hour, for: now)!.start)!

        let snapshot = ASRActivitySnapshotBuilder.makeSnapshot(
            events: [.init(createdAt: nextHour, kind: "normal")],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.totalCount, 0)
        XCTAssertEqual(snapshot.highestBucketCount, 0)
        XCTAssertNil(snapshot.lastActivityAt)
        XCTAssertTrue(snapshot.buckets.allSatisfy { $0.count == 0 })
    }
}
