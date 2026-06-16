// PagedVerticalList.swift
// Provides Paged Vertical List for settings shell.

import AppKit
import SwiftUI

private let pagedVerticalListColumnIdentifier = NSUserInterfaceItemIdentifier("PagedVerticalListColumn")
private let pagedVerticalListRowIdentifier = NSUserInterfaceItemIdentifier("PagedVerticalListRow")

private final class HostedTableCell: NSTableCellView {
    let hostingView: NSHostingView<AnyView>

    override init(frame frameRect: NSRect) {
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView.setContentHuggingPriority(.defaultLow, for: .vertical)
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PagedVerticalList<Item: Identifiable, Row: View>: NSViewRepresentable {
    let items: [Item]
    let totalCount: Int
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let rowHeightForItem: ((Item) -> CGFloat)?
    let isLoading: Bool
    let onLoadMore: () -> Void
    let row: (Item) -> Row

    init(
        items: [Item],
        totalCount: Int,
        rowHeight: CGFloat,
        rowSpacing: CGFloat = 8,
        rowHeightForItem: ((Item) -> CGFloat)? = nil,
        isLoading: Bool,
        onLoadMore: @escaping () -> Void,
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.items = items
        self.totalCount = totalCount
        self.rowHeight = rowHeight
        self.rowSpacing = rowSpacing
        self.rowHeightForItem = rowHeightForItem
        self.isLoading = isLoading
        self.onLoadMore = onLoadMore
        self.row = row
    }

    private var state: PagedVerticalListState {
        let items = items
        let rowHeight = rowHeight
        let rowHeightForItem = rowHeightForItem
        return PagedVerticalListState(
            itemCount: items.count,
            totalCount: totalCount,
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            rowHeightForIndex: { index in
                guard index >= 0, index < items.count else { return rowHeight }
                return rowHeightForItem?(items[index]) ?? rowHeight
            },
            isLoading: isLoading,
            onLoadMore: onLoadMore,
            row: { index in AnyView(row(items[index])) }
        )
    }

    func makeCoordinator() -> PagedVerticalListCoordinator {
        PagedVerticalListCoordinator(state: state)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.gridStyleMask = []
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: rowSpacing)
        tableView.usesAutomaticRowHeights = false
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        if #available(macOS 11.0, *) {
            tableView.style = .plain
        }

        let column = NSTableColumn(identifier: pagedVerticalListColumnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(state: state)
        guard let tableView = context.coordinator.tableView else { return }
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: rowSpacing)
        tableView.tableColumns.first?.width = scrollView.contentSize.width
        tableView.reloadData()
    }

}

final class PagedVerticalListCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var state: PagedVerticalListState
    weak var tableView: NSTableView?
    weak var scrollView: NSScrollView?
    private var lastLoadMoreItemCount = -1
    private var lastKnownTotalCount = -1

    init(state: PagedVerticalListState) {
        self.state = state
        lastKnownTotalCount = state.totalCount
    }

    func update(state newState: PagedVerticalListState) {
        if newState.itemCount < state.itemCount || newState.totalCount != lastKnownTotalCount {
            lastLoadMoreItemCount = -1
        }
        state = newState
        lastKnownTotalCount = newState.totalCount
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        state.itemCount + (showsFooter ? 1 : 0)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        isFooterRow(row) ? 40 : state.height(for: row)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row rowIndex: Int) -> NSView? {
        if isFooterRow(rowIndex) {
            return hostedCell(
                in: tableView,
                rootView: AnyView(footerView)
            )
        }

        guard rowIndex >= 0, rowIndex < state.itemCount else { return nil }
        requestNextPageIfNeeded(displaying: rowIndex)
        return hostedCell(
            in: tableView,
            rootView: AnyView(
                state.row(rowIndex)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: state.height(for: rowIndex))
            )
        )
    }

    private var showsFooter: Bool {
        state.isLoading || state.itemCount < state.totalCount
    }

    private func isFooterRow(_ rowIndex: Int) -> Bool {
        showsFooter && rowIndex == state.itemCount
    }

    @ViewBuilder
    private var footerView: some View {
        if state.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 36)
        } else {
            Button(AppLocalization.localizedString("Load More")) {
                self.state.onLoadMore()
            }
            .buttonStyle(SettingsPillButtonStyle())
            .frame(maxWidth: .infinity, minHeight: 36)
        }
    }

    private func requestNextPageIfNeeded(displaying rowIndex: Int) {
        guard !state.isLoading, state.itemCount < state.totalCount else { return }
        guard rowIndex >= max(0, state.itemCount - 12) else { return }
        guard lastLoadMoreItemCount != state.itemCount else { return }
        lastLoadMoreItemCount = state.itemCount
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state.onLoadMore()
        }
    }

    private func hostedCell(in tableView: NSTableView, rootView: AnyView) -> HostedTableCell {
        let cell = tableView.makeView(
            withIdentifier: pagedVerticalListRowIdentifier,
            owner: self
        ) as? HostedTableCell ?? HostedTableCell()
        cell.identifier = pagedVerticalListRowIdentifier
        cell.hostingView.rootView = rootView
        return cell
    }
}

struct PagedVerticalListState {
    let itemCount: Int
    let totalCount: Int
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let rowHeightForIndex: (Int) -> CGFloat
    let isLoading: Bool
    let onLoadMore: () -> Void
    let row: (Int) -> AnyView

    func height(for index: Int) -> CGFloat {
        rowHeightForIndex(index)
    }
}
