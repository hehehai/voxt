// ASRActivityWidget.swift
// Shows recent Voxt ASR activity in a desktop widget.

import SwiftUI
import WidgetKit

struct ASRActivityEntry: TimelineEntry {
    let date: Date
    let snapshot: ASRActivitySnapshot
}

struct ASRActivityTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ASRActivityEntry {
        ASRActivityEntry(date: Date(), snapshot: ASRActivitySnapshot.empty())
    }

    func getSnapshot(in context: Context, completion: @escaping (ASRActivityEntry) -> Void) {
        let now = Date()
        completion(ASRActivityEntry(date: now, snapshot: loadSnapshot(now: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ASRActivityEntry>) -> Void) {
        let now = Date()
        let entry = ASRActivityEntry(date: now, snapshot: loadSnapshot(now: now))
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func loadSnapshot(now: Date) -> ASRActivitySnapshot {
        ASRActivitySnapshotStore.load() ?? ASRActivitySnapshot.empty(now: now)
    }
}

struct ASRActivityWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: ASRActivityEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            heatmap
            footer
        }
        .containerBackground(.background, for: .widget)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Voxt")
                    .font(.headline.weight(.semibold))
                Text("Last 24 hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(entry.snapshot.totalCount)")
                .font(.system(size: family == .systemSmall ? 28 : 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
        }
    }

    private var heatmap: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: columnCount)

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(entry.snapshot.buckets) { bucket in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color(for: bucket.count))
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityLabel(accessibilityLabel(for: bucket))
            }
        }
        .frame(maxHeight: family == .systemSmall ? 80 : 120)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(lastActivityText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 6)
            Text("ASR")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var columnCount: Int {
        switch family {
        case .systemSmall:
            return 6
        default:
            return 12
        }
    }

    private var lastActivityText: String {
        guard let lastActivityAt = entry.snapshot.lastActivityAt else {
            return "No activity yet"
        }
        return "Last \(lastActivityAt.formatted(date: .omitted, time: .shortened))"
    }

    private func color(for count: Int) -> Color {
        guard count > 0, entry.snapshot.highestBucketCount > 0 else {
            return Color.secondary.opacity(0.14)
        }

        let ratio = Double(count) / Double(entry.snapshot.highestBucketCount)
        switch ratio {
        case 0..<0.25:
            return Color.teal.opacity(0.34)
        case 0..<0.5:
            return Color.teal.opacity(0.52)
        case 0..<0.75:
            return Color.teal.opacity(0.74)
        default:
            return Color.teal
        }
    }

    private func accessibilityLabel(for bucket: ASRActivityBucket) -> Text {
        Text("\(bucket.count) ASR sessions from \(bucket.startDate.formatted(date: .omitted, time: .shortened))")
    }
}

struct ASRActivityWidget: Widget {
    let kind = ASRActivityConstants.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ASRActivityTimelineProvider()) { entry in
            ASRActivityWidgetView(entry: entry)
        }
        .configurationDisplayName("Voxt Activity")
        .description("Track successful Voxt ASR sessions over the last 24 hours.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct VoxtWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ASRActivityWidget()
    }
}
