import SwiftUI
import AppKit

struct DictionaryHeaderMenuAction {
    let title: String
    let handler: () -> Void
}

struct DictionaryHeaderActionMenuButton: NSViewRepresentable {
    let actions: [DictionaryHeaderMenuAction]

    func makeCoordinator() -> Coordinator {
        Coordinator(actions: actions)
    }

    func makeNSView(context: Context) -> DictionaryHeaderActionMenuHostView {
        let hostView = DictionaryHeaderActionMenuHostView()
        hostView.toolTip = AppLocalization.localizedString("More")
        hostView.update(actions: actions, target: context.coordinator)
        return hostView
    }

    func updateNSView(_ nsView: DictionaryHeaderActionMenuHostView, context: Context) {
        context.coordinator.actions = actions
        nsView.update(actions: actions, target: context.coordinator)
    }

    final class Coordinator: NSObject {
        var actions: [DictionaryHeaderMenuAction]

        init(actions: [DictionaryHeaderMenuAction]) {
            self.actions = actions
        }

        @objc
        func performAction(_ sender: NSMenuItem) {
            guard actions.indices.contains(sender.tag) else { return }
            actions[sender.tag].handler()
        }
    }
}

final class DictionaryHeaderActionMenuHostView: NSView {
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

    func update(actions: [DictionaryHeaderMenuAction], target: AnyObject) {
        popupMenu.removeAllItems()
        for (index, action) in actions.enumerated() {
            let item = NSMenuItem(
                title: action.title,
                action: #selector(DictionaryHeaderActionMenuButton.Coordinator.performAction(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.tag = index
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
