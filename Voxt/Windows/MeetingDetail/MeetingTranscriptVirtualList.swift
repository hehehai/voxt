// MeetingTranscriptVirtualList.swift
// Lazy SwiftUI transcript list with stable spacing and scroll requests.
//
// NSTableView + NSHostingView automatic/manual row heights repeatedly mis-measured
// multi-line SwiftUI Text (extra blank space under wrapped cards). LazyVStack keeps
// visually correct spacing while still deferring off-screen row bodies. Playback and
// search CPU wins come from ViewModel caching + activeSegment-only scroll, not AppKit
// cell reuse.

import SwiftUI

struct MeetingTranscriptVirtualList: View {
    let rows: [MeetingTranscriptVirtualRow]
    let showsTranslation: Bool
    let rowSpacing: CGFloat
    let scrollRequest: MeetingTranscriptScrollRequest?

    init(
        rows: [MeetingTranscriptVirtualRow],
        showsTranslation: Bool,
        rowSpacing: CGFloat = 12,
        scrollRequest: MeetingTranscriptScrollRequest? = nil
    ) {
        self.rows = rows
        self.showsTranslation = showsTranslation
        self.rowSpacing = rowSpacing
        self.scrollRequest = scrollRequest
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: rowSpacing) {
                    ForEach(rows) { row in
                        rowView(for: row)
                            .id(row.id)
                    }
                }
            }
            .onChange(of: scrollRequest?.generation) { _, _ in
                fulfillScrollRequest(using: proxy)
            }
            .onAppear {
                fulfillScrollRequest(using: proxy)
            }
        }
    }

    @ViewBuilder
    private func rowView(for row: MeetingTranscriptVirtualRow) -> some View {
        switch row {
        case .speakerHeader(_, let title, let count):
            MeetingDetailSpeakerHeaderRow(title: title, count: count)
        case .segment(let presentation):
            MeetingDetailSegmentRow(
                segment: presentation.segment,
                speakerTitle: presentation.speakerTitle,
                isActive: presentation.isActive,
                showsTranslation: presentation.showsTranslation || showsTranslation,
                isSearchMatch: presentation.isSearchMatch
            )
            .equatable()
        }
    }

    private func fulfillScrollRequest(using proxy: ScrollViewProxy) {
        guard let scrollRequest else { return }
        let anchor: UnitPoint
        switch scrollRequest.anchor {
        case .top:
            anchor = .top
        case .center:
            anchor = .center
        case .bottom:
            anchor = .bottom
        }
        proxy.scrollTo(scrollRequest.rowID, anchor: anchor)
    }
}
