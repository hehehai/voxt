// ASRActivitySnapshotRefreshService.swift
// Refreshes the shared ASR activity snapshot consumed by the widget extension.

import Foundation
import WidgetKit

protocol ASRActivitySnapshotRefreshing: AnyObject, Sendable {
    func refresh()
}

final class ASRActivitySnapshotRefreshService: ASRActivitySnapshotRefreshing, @unchecked Sendable {
    private let repository: HistoryRepositoryProtocol
    private let calendar: Calendar
    private let queue = DispatchQueue(label: "com.voxt.asr-activity-snapshot", qos: .utility)

    init(repository: HistoryRepositoryProtocol, calendar: Calendar = .current) {
        self.repository = repository
        self.calendar = calendar
    }

    func refresh() {
        let repository = repository
        let calendar = calendar
        queue.async {
            let now = Date()
            let start = ASRActivitySnapshotBuilder.windowStart(now: now, calendar: calendar)
            let entries = (try? repository.activityEntries(since: start)) ?? []
            let events = entries.map {
                ASRActivitySnapshotBuilder.Event(createdAt: $0.createdAt, kind: $0.kind.rawValue)
            }
            let snapshot = ASRActivitySnapshotBuilder.makeSnapshot(
                events: events,
                now: now,
                calendar: calendar
            )

            do {
                try ASRActivitySnapshotStore.save(snapshot)
                WidgetCenter.shared.reloadTimelines(ofKind: ASRActivityConstants.widgetKind)
            } catch {
                VoxtLog.warning("Failed to refresh ASR activity widget snapshot: \(error.localizedDescription)")
            }
        }
    }
}
