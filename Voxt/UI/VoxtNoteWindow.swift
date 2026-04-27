import AppKit
import SwiftUI
import Combine
import QuartzCore

@MainActor
final class VoxtNoteWindowManager {
    private let store: VoxtNoteStore
    private var controller: VoxtNoteWindowController?
    private var itemsCancellable: AnyCancellable?

    init(store: VoxtNoteStore) {
        self.store = store
        itemsCancellable = store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                guard let self else { return }
                if items.allSatisfy(\.isCompleted) {
                    self.hide()
                }
            }
    }

    func show() {
        guard !store.incompleteItems.isEmpty else { return }
        let controller = resolvedController()
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        controller.updateFrame(animated: false)
    }

    func hide() {
        controller?.window?.orderOut(nil)
    }

    private func resolvedController() -> VoxtNoteWindowController {
        if let controller {
            return controller
        }

        let controller = VoxtNoteWindowController(
            store: store,
            onRequestClose: { [weak self] in
                self?.hide()
            }
        )
        self.controller = controller
        return controller
    }
}

@MainActor
final class VoxtNoteWindowController: NSWindowController {
    private static let collapsedSize = NSSize(width: 270, height: 72)
    private static let expandedSize = NSSize(width: 270, height: 346)
    private static let leftInset: CGFloat = 20

    private var hostingView: NSHostingView<VoxtNoteWindowView>?
    private var isExpanded = false
    private let store: VoxtNoteStore
    private let onRequestClose: () -> Void

    init(store: VoxtNoteStore, onRequestClose: @escaping () -> Void) {
        self.store = store
        self.onRequestClose = onRequestClose

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)

        let rootView = VoxtNoteWindowView(
            store: store,
            onComplete: { [weak self] noteID in
                _ = self?.store.updateCompletion(true, for: noteID)
            },
            onDelete: { [weak self] noteID in
                self?.store.delete(id: noteID)
            },
            onRequestClose: onRequestClose,
            onExpansionChanged: { [weak self] expanded in
                self?.setExpanded(expanded)
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView
        self.hostingView = hostingView
        updateFrame(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        updateFrame(animated: true)
    }

    func updateFrame(animated: Bool) {
        guard let window else { return }
        let size = isExpanded ? Self.expandedSize : Self.collapsedSize
        let frame = resolvedFrame(for: size)
        guard !frame.isEmpty else { return }

        if animated, window.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }

    private func resolvedFrame(for size: NSSize) -> CGRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        guard !visibleFrame.isEmpty else {
            return CGRect(origin: .zero, size: size)
        }

        return CGRect(
            x: visibleFrame.minX + Self.leftInset,
            y: visibleFrame.minY + overlayScreenEdgeInset,
            width: size.width,
            height: size.height
        )
    }

    private var overlayScreenEdgeInset: CGFloat {
        let storedValue = UserDefaults.standard.object(forKey: AppPreferenceKey.overlayScreenEdgeInset) as? Int ?? 30
        return CGFloat(min(max(storedValue, 0), 120))
    }
}
