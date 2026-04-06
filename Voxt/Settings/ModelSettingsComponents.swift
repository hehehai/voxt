import SwiftUI
import AppKit

struct PromptEditorView: View {
    @Binding var text: String
    var height: CGFloat = 100
    var contentPadding: CGFloat = 6

    var body: some View {
        TextEditor(text: $text)
            .settingsPromptEditor(height: height, contentPadding: contentPadding)
    }
}

struct PromptTemplateVariableDescriptor: Identifiable {
    let token: String
    let tipKey: String

    var id: String { token }
}

struct PromptTemplateVariablesView: View {
    let variables: [PromptTemplateVariableDescriptor]

    @State private var copiedToken: String?
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(AppLocalization.localizedString("Supported variables"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(variables) { variable in
                    PromptTemplateVariableChip(
                        variable: variable,
                        isCopied: copiedToken == variable.token,
                        onCopy: { copy(variable.token) }
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func copy(_ token: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(token, forType: .string)
        copiedToken = token
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            if copiedToken == token {
                copiedToken = nil
            }
            resetTask = nil
        }
    }
}

private enum PromptTemplateTooltipPlacement {
    case above
    case below
}

private struct PromptTemplateVariableChip: View {
    let variable: PromptTemplateVariableDescriptor
    let isCopied: Bool
    let onCopy: () -> Void

    @State private var isShowingTip = false
    @State private var isHoveringBadge = false
    @State private var isHoveringTip = false
    @State private var badgeScreenFrame: CGRect = .zero
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 2) {
                Image(systemName: isCopied ? "checkmark.circle.fill" : "document.on.document")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isCopied ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(variable.token)
                    .font(.caption.monospaced())
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 0)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(SettingsUIStyle.controlFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            PromptTemplateBadgeFrameReader { frame in
                badgeScreenFrame = frame
            }
        )
        .onHover { hovering in
            isHoveringBadge = hovering
            if hovering {
                dismissTask?.cancel()
                isShowingTip = true
            } else {
                scheduleTipDismissal()
            }
        }
        .popover(
            isPresented: $isShowingTip,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: tooltipPlacement == .above ? .bottom : .top
        ) {
            Text(AppLocalization.localizedString(variable.tipKey))
                .font(.caption)
                .multilineTextAlignment(.leading)
                .frame(width: 260, alignment: .leading)
                .padding(10)
                .onHover { hovering in
                    isHoveringTip = hovering
                    if hovering {
                        dismissTask?.cancel()
                    } else {
                        scheduleTipDismissal()
                    }
                }
        }
    }

    private var tooltipPlacement: PromptTemplateTooltipPlacement {
        guard
            !badgeScreenFrame.isEmpty,
            let visibleFrame = NSScreen.main?.visibleFrame
        else {
            return .above
        }

        let preferredHeight: CGFloat = 72
        let availableAbove = visibleFrame.maxY - badgeScreenFrame.maxY
        let availableBelow = badgeScreenFrame.minY - visibleFrame.minY

        if availableAbove >= preferredHeight {
            return .above
        }
        if availableBelow >= preferredHeight {
            return .below
        }
        return availableAbove >= availableBelow ? .above : .below
    }

    private func scheduleTipDismissal() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            guard !isHoveringBadge, !isHoveringTip else { return }
            isShowingTip = false
            dismissTask = nil
        }
    }
}

private struct PromptTemplateBadgeFrameReader: NSViewRepresentable {
    let onUpdate: (CGRect) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = FrameReportingView()
        view.onUpdate = onUpdate
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? FrameReportingView else { return }
        view.onUpdate = onUpdate
        DispatchQueue.main.async {
            view.reportFrameIfNeeded()
        }
    }
}

private final class FrameReportingView: NSView {
    var onUpdate: ((CGRect) -> Void)?
    private var lastReportedFrame: CGRect = .zero

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportFrameIfNeeded()
    }

    override func layout() {
        super.layout()
        reportFrameIfNeeded()
    }

    func reportFrameIfNeeded() {
        guard let window else { return }
        let frameInWindow = convert(bounds, to: nil)
        let frameInScreen = window.convertToScreen(frameInWindow)
        guard frameInScreen != lastReportedFrame else { return }
        lastReportedFrame = frameInScreen
        onUpdate?(frameInScreen)
    }
}

struct ModelTableAction {
    let title: LocalizedStringKey
    var role: ButtonRole? = nil
    var isEnabled: Bool = true
    let handler: () -> Void
}

struct ModelTableRow: Identifiable {
    let id: String
    let title: String
    let isActive: Bool
    let status: String
    var badgeText: String? = nil
    var isTitleUnderlined: Bool = false
    var onTapTitle: (() -> Void)? = nil
    let actions: [ModelTableAction]
}

struct ModelTableView: View {
    let title: LocalizedStringKey
    let rows: [ModelTableRow]
    var viewportHeight: CGFloat = 280

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("Actions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Divider()
            }

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    tableRows
                }
            }
            .frame(height: viewportHeight)
        }
        .tableContainerStyle
    }

    @ViewBuilder
    private var tableRows: some View {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let onTapTitle = row.onTapTitle {
                            Button(action: onTapTitle) {
                                rowTitle(row)
                            }
                            .buttonStyle(.plain)
                        } else {
                            rowTitle(row)
                        }
                        Text(row.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        ForEach(Array(row.actions.enumerated()), id: \.offset) { _, action in
                            Button(action.title, role: action.role) {
                                action.handler()
                            }
                            .buttonStyle(
                                SettingsCompactActionButtonStyle(
                                    tone: action.role == .destructive ? .destructive : .neutral
                                )
                            )
                            .disabled(!action.isEnabled)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func rowTitle(_ row: ModelTableRow) -> some View {
        HStack(spacing: 6) {
            Text(row.title)
                .font(.subheadline.weight(row.isActive ? .semibold : .regular))
                .underline(row.isTitleUnderlined)
                .foregroundStyle(row.isTitleUnderlined ? Color.accentColor : Color.primary)
            if let badgeText = row.badgeText {
                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.14))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                    )
            }
        }
    }
}

private extension View {
    var tableContainerStyle: some View {
        background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(SettingsUIStyle.groupedFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SettingsUIStyle.panelBorderColor, lineWidth: 1)
        )
    }
}
