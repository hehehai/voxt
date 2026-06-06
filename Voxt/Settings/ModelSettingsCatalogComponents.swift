import SwiftUI
import AppKit

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

enum ModelBadgePresentation {
    private static let recommendedPath = "M21.5599 10.7405L20.1999 9.16055C19.9399 8.86055 19.7299 8.30055 19.7299 7.90055V6.20055C19.7299 5.14055 18.8599 4.27055 17.7999 4.27055H16.0999C15.7099 4.27055 15.1399 4.06055 14.8399 3.80055L13.2599 2.44055C12.5699 1.85055 11.4399 1.85055 10.7399 2.44055L9.16988 3.81055C8.86988 4.06055 8.29988 4.27055 7.90988 4.27055H6.17988C5.11988 4.27055 4.24988 5.14055 4.24988 6.20055V7.91055C4.24988 8.30055 4.03988 8.86055 3.78988 9.16055L2.43988 10.7505C1.85988 11.4405 1.85988 12.5605 2.43988 13.2505L3.78988 14.8405C4.03988 15.1405 4.24988 15.7005 4.24988 16.0905V17.8005C4.24988 18.8605 5.11988 19.7305 6.17988 19.7305H7.90988C8.29988 19.7305 8.86988 19.9405 9.16988 20.2005L10.7499 21.5605C11.4399 22.1505 12.5699 22.1505 13.2699 21.5605L14.8499 20.2005C15.1499 19.9405 15.7099 19.7305 16.1099 19.7305H17.8099C18.8699 19.7305 19.7399 18.8605 19.7399 17.8005V16.1005C19.7399 15.7105 19.9499 15.1405 20.2099 14.8405L21.5699 13.2605C22.1499 12.5705 22.1499 11.4305 21.5599 10.7405ZM16.6799 12.0005L15.5099 15.5605C15.3599 16.1505 14.7299 16.6305 14.0899 16.6305H12.2399C11.9199 16.6305 11.4699 16.5205 11.2699 16.3205L9.79988 15.1705C9.76988 15.8105 9.47988 16.0805 8.76988 16.0805H8.28988C7.54988 16.0805 7.24988 15.7905 7.24988 15.0905V10.3105C7.24988 9.61055 7.54988 9.32055 8.28988 9.32055H8.77988C9.51988 9.32055 9.81988 9.61055 9.81988 10.3105V10.6705L11.7599 7.79055C11.9599 7.48055 12.4699 7.26055 12.8999 7.43055C13.3699 7.59055 13.6699 8.11055 13.5699 8.57055L13.3299 10.1305C13.3099 10.2705 13.3399 10.4005 13.4299 10.5005C13.5099 10.5905 13.6299 10.6505 13.7599 10.6505H15.7099C16.0899 10.6505 16.4099 10.8005 16.5999 11.0705C16.7699 11.3305 16.7999 11.6605 16.6799 12.0005Z"
    private static let recommendedText = AppLocalization.localizedString("Recommended")
    static let recommendedColor = Color(red: 1.0, green: 0.68, blue: 0.22)

    static func isRecommended(_ badgeText: String) -> Bool {
        badgeText == recommendedText
    }

    static var recommendedIcon: some View {
        SVGPathShape(pathData: recommendedPath)
            .fill(recommendedColor)
            .frame(width: 15, height: 15)
            .shadow(color: recommendedColor.opacity(0.35), radius: 3, x: 0, y: 1)
            .accessibilityLabel(Text(recommendedText))
    }
}

struct ModelBadgeView: View {
    let badgeText: String
    var showsCapsuleForText = false

    var body: some View {
        if ModelBadgePresentation.isRecommended(badgeText) {
            ModelBadgePresentation.recommendedIcon
        } else if showsCapsuleForText {
            Text(badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.14))
                )
        } else {
            Text(badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }
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
            [localized("Fast"), localized("Balanced"), localized("Accurate"), localized("Realtime")],
            [localized("Installed"), localized("Configured"), localized("In Use")]
        ]
    }

    static var exclusiveSelectionTags: Set<String> {
        locationTags
    }

    static var statusFilterTags: Set<String> {
        Set([localized("Installed"), localized("Configured"), localized("In Use")])
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

enum ModelCatalogRowSurface {
    case card
    case listItem
}

struct ModelCatalogRow: View {
    let entry: ModelCatalogEntry
    let titleOverride: String?
    let showsEngine: Bool
    let showsTags: Bool
    let showsIcon: Bool
    private let surface: ModelCatalogRowSurface

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

    init(
        entry: ModelCatalogEntry,
        titleOverride: String? = nil,
        showsEngine: Bool = true,
        showsTags: Bool = true,
        showsIcon: Bool = true,
        surface: ModelCatalogRowSurface = .card
    ) {
        self.entry = entry
        self.titleOverride = titleOverride
        self.showsEngine = showsEngine
        self.showsTags = showsTags
        self.showsIcon = showsIcon
        self.surface = surface
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    if showsIcon {
                        ModelLogoView(
                            key: entry.modelLogoKey,
                            fallbackTitle: titleOverride ?? entry.title,
                            size: 18
                        )
                    }

                    Text(titleOverride ?? entry.title)
                        .font(.headline)

                    if showsEngine {
                        Text(entry.engine)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(SettingsUIStyle.groupedFillColor)
                            )
                    }

                    if let badgeText = entry.badgeText {
                        ModelBadgeView(badgeText: badgeText)
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

                if showsTags {
                    ModelRowTagStrip(tags: entry.displayTags)
                }
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
        .modifier(ModelCatalogRowSurfaceModifier(surface: surface, isInUse: isInUse))
    }
}

private struct ModelCatalogRowSurfaceModifier: ViewModifier {
    let surface: ModelCatalogRowSurface
    let isInUse: Bool

    func body(content: Content) -> some View {
        switch surface {
        case .card:
            content
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
                            ? Color.accentColor.opacity(0.20)
                            : SettingsUIStyle.modelCardBorderColor,
                            lineWidth: 1
                        )
                )
        case .listItem:
            content
                .background(Color.clear)
        }
    }
}

struct ModelCatalogGroupCard: View {
    let group: ModelCatalogGroupSection
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    onToggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        ModelLogoView(key: group.modelLogoKey, fallbackTitle: group.title, size: 18)

                        Text(group.title)
                            .font(.headline)

                        Text(group.engine)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(SettingsUIStyle.groupedFillColor)
                            )

                        if let badgeText = group.badgeText {
                            ModelBadgeView(badgeText: badgeText)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                    }

                    HStack(spacing: 12) {
                        ModelMetaText(title: localized("Models"), value: "\(group.entries.count)")
                        ModelMetaText(title: localized("Installed"), value: "\(group.installedCount)/\(group.entries.count)")
                        ModelMetaText(title: localized("Score"), value: group.ratingText)
                        if !group.usageLocations.isEmpty {
                            ModelMetaText(
                                title: localized("Usage"),
                                value: group.usageLocations.joined(separator: " · ")
                            )
                        }
                    }

                    if !group.tags.isEmpty {
                        ModelRowTagStrip(tags: group.tags)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                        ModelCatalogRow(
                            entry: entry,
                            titleOverride: entry.groupedVariantTitle,
                            showsEngine: false,
                            showsTags: false,
                            showsIcon: false,
                            surface: .listItem
                        )

                        if index < group.entries.count - 1 {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(SettingsUIStyle.modelGroupListFillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(SettingsUIStyle.modelCardBorderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipped()
                .transition(.opacity)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SettingsUIStyle.modelGroupFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(SettingsUIStyle.modelCardBorderColor, lineWidth: 1)
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
        let style = tagStyle(for: text)
        return Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(style.foreground)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(style.fill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(style.stroke, lineWidth: 1)
            )
    }

    private func tagStyle(for text: String) -> (foreground: Color, fill: Color, stroke: Color) {
        if text == localized("Supports Primary Language") {
            return (
                foreground: Color.green.opacity(0.85),
                fill: Color.green.opacity(0.08),
                stroke: Color.green.opacity(0.18)
            )
        }

        if text == localized("Does Not Support Primary Language") {
            return (
                foreground: Color.orange.opacity(0.88),
                fill: Color.orange.opacity(0.08),
                stroke: Color.orange.opacity(0.18)
            )
        }

        return (
            foreground: .secondary,
            fill: SettingsUIStyle.groupedFillColor,
            stroke: SettingsUIStyle.subtleBorderColor
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
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected || isHovered ? Color.accentColor.opacity(0.18) : SettingsUIStyle.controlFillColor)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected || isHovered ? Color.accentColor.opacity(0.28) : SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected || isHovered ? Color.accentColor : .primary)
        .onHover { isHovered = $0 }
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
