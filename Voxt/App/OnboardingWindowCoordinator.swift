// OnboardingWindowCoordinator.swift
// Provides Onboarding Window Coordinator for app lifecycle and routing.

import SwiftUI
import AppKit

private struct OnboardingGuideWindowRoot: View {
    @State private var currentStep: OnboardingGuideStep

    @ObservedObject var mlxModelManager: MLXModelManager
    @ObservedObject var customLLMManager: CustomLLMModelManager

    let onClose: () -> Void
    let onFinish: () -> Void

    init(
        initialStep: OnboardingGuideStep,
        mlxModelManager: MLXModelManager,
        customLLMManager: CustomLLMModelManager,
        onClose: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        _currentStep = State(initialValue: initialStep)
        self.mlxModelManager = mlxModelManager
        self.customLLMManager = customLLMManager
        self.onClose = onClose
        self.onFinish = onFinish
    }

    var body: some View {
        OnboardingGuideView(
            currentStep: $currentStep,
            mlxModelManager: mlxModelManager,
            customLLMManager: customLLMManager,
            onClose: onClose,
            onFinish: onFinish
        )
    }
}

extension AppDelegate {
    private var onboardingWindowContentSize: NSSize {
        NSSize(width: 880, height: 600)
    }

    func openOnboardingWindow(step requestedStep: OnboardingGuideStep? = nil) {
        let initialStep = requestedStep
            ?? OnboardingPreferenceManager.savedLastGuideStep()
            ?? .permissions
        OnboardingPreferenceManager.saveLastGuideStep(initialStep)

        if let window = onboardingWindowController?.window {
            if !window.isVisible {
                window.center()
            }
            AppBehaviorController.bringUserInvokedWindowToFront(window)
            scheduleOnboardingTrafficLightButtonPositionUpdate(for: window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: onboardingWindowContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = AppLocalization.localizedString("Setup Guide")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        window.isOpaque = true
        window.backgroundColor = SettingsUIStyle.windowBackgroundNSColor
        window.contentMinSize = onboardingWindowContentSize
        window.contentMaxSize = onboardingWindowContentSize
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.level = .normal
        window.collectionBehavior = []
        window.delegate = self

        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = false
        onboardingWindowController = controller

        let contentView = OnboardingGuideWindowRoot(
            initialStep: initialStep,
            mlxModelManager: mlxModelManager,
            customLLMManager: customLLMManager,
            onClose: { [weak self, weak window] in
                window?.close()
                self?.onboardingWindowController = nil
            },
            onFinish: { [weak self, weak window] in
                OnboardingPreferenceManager.markCompleted()
                window?.close()
                self?.onboardingWindowController = nil
            }
        )

        window.contentViewController = NSHostingController(rootView: contentView)
        window.setContentSize(onboardingWindowContentSize)
        window.center()
        AppBehaviorController.bringUserInvokedWindowToFront(window)
        scheduleOnboardingTrafficLightButtonPositionUpdate(for: window)
    }

    private func positionOnboardingTrafficLightButtons(_ window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let miniaturizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let container = closeButton.superview
        else {
            return
        }

        let leftInset: CGFloat = 15
        let topInset: CGFloat = 21
        let spacing: CGFloat = 6

        let buttonSize = closeButton.frame.size
        let y = container.bounds.height - topInset - buttonSize.height
        let closeX = leftInset
        let miniaturizeX = closeX + buttonSize.width + spacing
        let zoomX = miniaturizeX + buttonSize.width + spacing

        closeButton.translatesAutoresizingMaskIntoConstraints = true
        miniaturizeButton.translatesAutoresizingMaskIntoConstraints = true
        zoomButton.translatesAutoresizingMaskIntoConstraints = true

        closeButton.setFrameOrigin(CGPoint(x: closeX, y: y))
        miniaturizeButton.setFrameOrigin(CGPoint(x: miniaturizeX, y: y))
        zoomButton.setFrameOrigin(CGPoint(x: zoomX, y: y))
    }

    private func scheduleOnboardingTrafficLightButtonPositionUpdate(for window: NSWindow) {
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.positionOnboardingTrafficLightButtons(window)
        }
    }
}
