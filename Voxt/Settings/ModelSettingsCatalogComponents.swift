import SwiftUI
import AppKit

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

enum ModelCatalogTab: String, CaseIterable, Identifiable {
    case asr
    case llm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .asr:
            return "ASR"
        case .llm:
            return "LLM"
        }
    }
}

enum ModelCatalogTag {
    static var locationTags: Set<String> {
        Set([localized("Local"), localized("Remote")])
    }

    static var groups: [[String]] {
        [
            [localized("Local"), localized("Remote")],
            [localized("Fast"), localized("Accurate"), localized("Realtime"), localized("Multilingual")],
            [localized("Installed"), localized("Configured"), localized("In Use")]
        ]
    }

    static var exclusiveSelectionTags: Set<String> {
        locationTags
    }

    static var priority: [String] {
        groups.flatMap { $0 }
    }
}

struct ModelCatalogTabPicker: View {
    @Binding var selectedTab: ModelCatalogTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ModelCatalogTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(SettingsSegmentedButtonStyle(isSelected: selectedTab == tab))
            }
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
    }
}

struct ModelCatalogEntry: Identifiable {
    let id: String
    let title: String
    let engine: String
    let sizeText: String
    let ratingText: String
    let filterTags: [String]
    let displayTags: [String]
    let statusText: String
    let usageLocations: [String]
    let badgeText: String?
    let primaryAction: ModelTableAction?
    let secondaryActions: [ModelTableAction]
}

struct ModelCatalogRow: View {
    let entry: ModelCatalogEntry

    private var trimmedStatusText: String {
        let trimmed = entry.statusText
            .replacingOccurrences(of: "\n", with: " · ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !isInUse && trimmed == localized("Not configured") {
            return ""
        }

        return trimmed
    }

    private var isInUse: Bool {
        !entry.usageLocations.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    Text(entry.title)
                        .font(.headline)

                    Text(entry.engine)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(SettingsUIStyle.groupedFillColor)
                        )

                    if let badgeText = entry.badgeText {
                        Text(badgeText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    if !trimmedStatusText.isEmpty {
                        Text(trimmedStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    ModelMetaText(title: localized("Size"), value: entry.sizeText)
                    ModelMetaText(title: localized("Score"), value: entry.ratingText)
                    if !entry.usageLocations.isEmpty {
                        ModelMetaText(
                            title: localized("Usage"),
                            value: entry.usageLocations.joined(separator: " · ")
                        )
                    }
                }

                ModelRowTagStrip(tags: entry.displayTags)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if let primaryAction = entry.primaryAction {
                    Button(primaryAction.title, role: primaryAction.role) {
                        primaryAction.handler()
                    }
                    .buttonStyle(
                        SettingsCompactActionButtonStyle(
                            tone: primaryAction.role == .destructive ? .destructive : .neutral
                        )
                    )
                    .disabled(!primaryAction.isEnabled)
                }

                if !entry.secondaryActions.isEmpty {
                    ModelRowActionMenuButton(actions: entry.secondaryActions)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    isInUse
                    ? Color.accentColor.opacity(0.055)
                    : SettingsUIStyle.controlFillColor.opacity(0.94)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isInUse
                    ? Color.accentColor.opacity(0.26)
                    : SettingsUIStyle.panelBorderColor,
                    lineWidth: 1
                )
        )
    }
}

private struct ModelRowActionMenuButton: NSViewRepresentable {
    let actions: [ModelTableAction]

    func makeCoordinator() -> Coordinator {
        Coordinator(actions: actions)
    }

    func makeNSView(context: Context) -> ModelRowActionMenuHostView {
        let hostView = ModelRowActionMenuHostView()
        hostView.toolTip = localized("More")
        hostView.update(actions: actions, target: context.coordinator)
        return hostView
    }

    func updateNSView(_ nsView: ModelRowActionMenuHostView, context: Context) {
        context.coordinator.actions = actions
        nsView.update(actions: actions, target: context.coordinator)
    }

    final class Coordinator: NSObject {
        var actions: [ModelTableAction]

        init(actions: [ModelTableAction]) {
            self.actions = actions
        }

        @objc
        func performAction(_ sender: NSMenuItem) {
            guard actions.indices.contains(sender.tag) else { return }
            let action = actions[sender.tag]
            guard action.isEnabled else { return }
            action.handler()
        }
    }
}

private final class ModelRowActionMenuHostView: NSView {
    private let popupMenu = NSMenu()
    private let iconView = NSImageView()
    private var trackingAreaRef: NSTrackingArea?
    private var cachedSignature = ""
    private var isHovered = false {
        didSet { updateAppearance() }
    }
    private var isPressed = false {
        didSet { updateAppearance() }
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 28, height: 28)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        popupMenu.autoenablesItems = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        iconView.imageScaling = .scaleProportionallyDown

        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12)
        ])

        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = 9
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        guard !popupMenu.items.isEmpty else { return }
        isPressed = true
        let anchorPoint = NSPoint(x: 0, y: bounds.height + 6)
        _ = popupMenu.popUp(positioning: nil, at: anchorPoint, in: self)
        isPressed = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func update(actions: [ModelTableAction], target: AnyObject) {
        let signature = actions.map { action in
            let roleMarker = action.role == .destructive ? "destructive" : "neutral"
            return "\(action.title)|\(action.isEnabled)|\(roleMarker)"
        }.joined(separator: "||")

        if signature != cachedSignature {
            popupMenu.removeAllItems()
            for (index, action) in actions.enumerated() {
                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(ModelRowActionMenuButton.Coordinator.performAction(_:)),
                    keyEquivalent: ""
                )
                item.target = target
                item.tag = index
                item.isEnabled = action.isEnabled
                popupMenu.addItem(item)
            }
            cachedSignature = signature
        }
    }

    private func updateAppearance() {
        let fillColor: NSColor
        if isPressed {
            fillColor = SettingsUIStyle.subtleFillNSColor.blended(withFraction: 0.18, of: .labelColor) ?? SettingsUIStyle.subtleFillNSColor
        } else if isHovered {
            fillColor = SettingsUIStyle.subtleFillNSColor.blended(withFraction: 0.08, of: .labelColor) ?? SettingsUIStyle.subtleFillNSColor
        } else {
            fillColor = SettingsUIStyle.subtleFillNSColor
        }

        layer?.backgroundColor = fillColor.cgColor
        layer?.borderColor = SettingsUIStyle.subtleBorderNSColor.cgColor
        layer?.borderWidth = 1
        iconView.contentTintColor = isPressed ? .labelColor : .secondaryLabelColor
    }
}

private struct ModelRowTagStrip: View {
    let tags: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    tagChip(tag)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(Array(tags.prefix(5)), id: \.self) { tag in
                    tagChip(tag)
                }
                if tags.count > 5 {
                    tagChip("+\(tags.count - 5)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tagChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(SettingsUIStyle.groupedFillColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
            )
    }
}

private struct ModelMetaText: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }
}

struct ModelTagChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : SettingsUIStyle.controlFillColor)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.28) : SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : .primary)
    }
}

struct ModelEmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(localized("No models match the selected tags."))
                .font(.subheadline.weight(.semibold))
            Text(localized("Clear one or more filters to view more models."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                .fill(SettingsUIStyle.groupedFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUIStyle.panelCornerRadius, style: .continuous)
                .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
        )
    }
}
