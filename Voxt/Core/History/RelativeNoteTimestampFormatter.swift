// RelativeNoteTimestampFormatter.swift
// Provides Relative Note Timestamp Formatter for history storage and display support.

import Foundation

enum RelativeNoteTimestampFormatter {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 60 * minute
    private static let day: TimeInterval = 24 * hour
    private static let relativeCutoff: TimeInterval = 15 * day

    static func noteCardTimestamp(for date: Date, now: Date = Date()) -> String? {
        let elapsed = max(0, now.timeIntervalSince(date))
        guard elapsed < relativeCutoff else { return nil }
        return relativeTimestamp(forElapsed: elapsed)
    }

    static func noteHistoryTimestamp(for date: Date, now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < relativeCutoff {
            return relativeTimestamp(forElapsed: elapsed)
        }
        return absoluteTimestamp(for: date)
    }

    private static func relativeTimestamp(forElapsed elapsed: TimeInterval) -> String {
        if elapsed < minute {
            return AppLocalization.localizedString("Just now")
        }

        if elapsed < hour {
            let minutes = max(1, Int(elapsed / minute))
            return localizedCount(
                value: minutes,
                singularKey: "%d min ago",
                pluralKey: "%d mins ago"
            )
        }

        if elapsed < day {
            let hours = max(1, Int(elapsed / hour))
            return localizedCount(
                value: hours,
                singularKey: "%d hr ago",
                pluralKey: "%d hrs ago"
            )
        }

        let days = max(1, Int(elapsed / day))
        return localizedCount(
            value: days,
            singularKey: "%d day ago",
            pluralKey: "%d days ago"
        )
    }

    private static func localizedCount(value: Int, singularKey: String, pluralKey: String) -> String {
        let key = value == 1 ? singularKey : pluralKey
        return AppLocalization.format(key, value)
    }

    private static func absoluteTimestamp(for date: Date) -> String {
        date.formatted(
            .dateTime
                .locale(AppLocalization.locale)
                .year()
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
    }
}
