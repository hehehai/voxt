import Foundation
import AppKit

struct ActionAssistantResolvedTargetInfo {
    let label: String?
    let role: String?
    let relativeX: Double?
    let relativeY: Double?
}

extension EmbeddedActionAssistantRuntime {
    func appURL(forDisplayName appName: String) -> URL? {
        let bundleID = switch appName {
        case "Safari": "com.apple.Safari"
        case "Google Chrome": "com.google.Chrome"
        case "Arc": "company.thebrowser.Browser"
        case "Brave Browser": "com.brave.Browser"
        case "Microsoft Edge": "com.microsoft.edgemac"
        case "Finder": "com.apple.finder"
        case "Mail": "com.apple.mail"
        case "Messages": "com.apple.MobileSMS"
        case "Notes": "com.apple.Notes"
        case "Calendar": "com.apple.iCal"
        case "Terminal": "com.apple.Terminal"
        case "System Settings": "com.apple.systempreferences"
        case "Slack": "com.tinyspeck.slackmacgap"
        case "Notion": "notion.id"
        case "Xcode": "com.apple.dt.Xcode"
        default: ""
        }
        guard !bundleID.isEmpty else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func resolvedValue(for value: String?, substitutions: [String: String]?) -> String? {
        guard let value else { return nil }
        guard let substitutions else { return value }

        var resolved = value
        for (key, replacement) in substitutions {
            resolved = resolved.replacingOccurrences(of: "{{\(key)}}", with: replacement)
        }
        return resolved
    }

    func resolvedTargetDescriptor(
        for step: ActionAssistantRecipe.Step,
        substitutions: [String: String]
    ) -> ActionAssistantRecipe.Step.Target? {
        guard let target = step.target else { return nil }
        let criteria = target.criteria?.map {
            ActionAssistantRecipe.Step.Target.Criterion(
                attribute: $0.attribute,
                value: resolvedValue(for: $0.value, substitutions: substitutions) ?? $0.value
            )
        }
        let computedNameContains = resolvedValue(for: target.computedNameContains, substitutions: substitutions)
        return .init(criteria: criteria, computedNameContains: computedNameContains)
    }

    func targetApp(
        for step: ActionAssistantRecipe.Step,
        substitutions: [String: String]
    ) -> NSRunningApplication? {
        let appName = resolvedValue(for: step.params?["app_name"], substitutions: substitutions)
            ?? step.targetApp
            ?? resolvedValue(for: step.params?["app"], substitutions: substitutions)
        guard let appName, !appName.isEmpty else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.localizedCaseInsensitiveContains(appName) == true
        }
    }

    func interactionPoint(
        for step: ActionAssistantRecipe.Step,
        substitutions: [String: String],
        fallbackLabel: String
    ) async throws -> CGPoint {
        if let point = pointFromParams(xKey: "x", yKey: "y", step: step, substitutions: substitutions) {
            return point
        }
        if let point = relativePointFromParams(xKey: "relative_x", yKey: "relative_y", step: step, substitutions: substitutions) {
            return point
        }
        if let target = resolvedTargetDescriptor(for: step, substitutions: substitutions),
           let resolvedTarget = ActionAssistantTargetResolver.resolve(target: target, preferredAppName: step.targetApp),
           let point = elementCenter(resolvedTarget.element) {
            return point
        }
        if let point = await visuallyGroundedPoint(for: step, substitutions: substitutions) {
            return point
        }
        if let point = ActionAssistantTargetResolver.focusedWindowCenter(preferredAppName: step.targetApp) {
            return point
        }
        throw ActionAssistantRuntimeError.targetNotFound(step.target?.computedNameContains ?? step.targetApp ?? fallbackLabel)
    }

    func pointFromParams(
        xKey: String,
        yKey: String,
        step: ActionAssistantRecipe.Step,
        substitutions: [String: String]
    ) -> CGPoint? {
        guard let xString = resolvedValue(for: step.params?[xKey], substitutions: substitutions),
              let yString = resolvedValue(for: step.params?[yKey], substitutions: substitutions),
              let x = Double(xString),
              let y = Double(yString) else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    func relativePointFromParams(
        xKey: String,
        yKey: String,
        step: ActionAssistantRecipe.Step,
        substitutions: [String: String]
    ) -> CGPoint? {
        guard let xString = resolvedValue(for: step.params?[xKey], substitutions: substitutions),
              let yString = resolvedValue(for: step.params?[yKey], substitutions: substitutions),
              let normalizedX = Double(xString),
              let normalizedY = Double(yString),
              let frame = ActionAssistantPerception.focusedWindowFrame(preferredAppName: step.targetApp) else {
            return nil
        }

        let clampedX = min(max(normalizedX, 0), 1)
        let clampedY = min(max(normalizedY, 0), 1)
        return CGPoint(
            x: frame.origin.x + (frame.size.width * clampedX),
            y: frame.origin.y + (frame.size.height * (1 - clampedY))
        )
    }

    func dragDestination(
        for step: ActionAssistantRecipe.Step,
        substitutions: [String: String]
    ) async -> CGPoint? {
        if let point = pointFromParams(xKey: "to_x", yKey: "to_y", step: step, substitutions: substitutions) {
            return point
        }
        if let point = relativePointFromParams(xKey: "to_relative_x", yKey: "to_relative_y", step: step, substitutions: substitutions) {
            return point
        }

        if let targetName = resolvedValue(for: step.params?["to_target_name"], substitutions: substitutions) {
            let target = ActionAssistantRecipe.Step.Target(criteria: nil, computedNameContains: targetName)
            let preferredApp = resolvedValue(for: step.params?["to_target_app"], substitutions: substitutions) ?? step.targetApp
            if let resolvedTarget = ActionAssistantTargetResolver.resolve(target: target, preferredAppName: preferredApp),
               let point = elementCenter(resolvedTarget.element) {
                return point
            }
        }
        if let hint = resolvedValue(for: step.params?["to_target_name"], substitutions: substitutions),
           let point = await visuallyGroundedPoint(
            targetDescription: hint,
            preferredAppName: resolvedValue(for: step.params?["to_target_app"], substitutions: substitutions) ?? step.targetApp
           ) {
            return point
        }

        return ActionAssistantTargetResolver.focusedWindowCenter(preferredAppName: step.targetApp)
    }

    func visuallyGroundedPoint(
        for step: ActionAssistantRecipe.Step,
        substitutions: [String: String]
    ) async -> CGPoint? {
        let label = resolvedValue(for: step.params?["target_hint"], substitutions: substitutions)
            ?? resolvedValue(for: step.target?.computedNameContains, substitutions: substitutions)
            ?? step.note
        return await visuallyGroundedPoint(targetDescription: label, preferredAppName: step.targetApp)
    }

    func visuallyGroundedPoint(
        targetDescription: String?,
        preferredAppName: String?
    ) async -> CGPoint? {
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.actionAssistantVisualSnapshotsEnabled),
              let targetDescription,
              !targetDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let visualContext = await ActionAssistantPerception.focusedWindowVisualContext(preferredAppName: preferredAppName),
              let screenshotPath = visualContext.screenshotPath,
              let grounded = await ActionAssistantVisualLocator.locate(
                targetDescription: targetDescription,
                preferredAppName: preferredAppName,
                screenshotPath: screenshotPath
              ) else {
            return nil
        }

        let normalizedPoint = grounded.normalizedInteractionPoint
        return CGPoint(
            x: visualContext.windowFrame.origin.x + (visualContext.windowFrame.size.width * normalizedPoint.x),
            y: visualContext.windowFrame.origin.y + (visualContext.windowFrame.size.height * (1 - normalizedPoint.y))
        )
    }

    func resolvedTargetInfo(
        for step: ActionAssistantRecipe.Step,
        substitutions: [String: String]
    ) async -> ActionAssistantResolvedTargetInfo? {
        if let target = resolvedTargetDescriptor(for: step, substitutions: substitutions),
           let resolvedTarget = ActionAssistantTargetResolver.resolve(target: target, preferredAppName: step.targetApp) {
            let relativePoint = relativeCoordinate(for: resolvedTarget.element, appName: step.targetApp)
            return ActionAssistantResolvedTargetInfo(
                label: elementStringAttribute(kAXTitleAttribute, for: resolvedTarget.element)
                    ?? elementStringAttribute(kAXDescriptionAttribute, for: resolvedTarget.element)
                    ?? target.computedNameContains,
                role: elementStringAttribute(kAXRoleAttribute, for: resolvedTarget.element)
                    ?? target.criteria?.first(where: { $0.attribute == "AXRole" })?.value,
                relativeX: relativePoint.map { Double($0.x) },
                relativeY: relativePoint.map { Double($0.y) }
            )
        }

        if let point = relativePointFromParams(xKey: "relative_x", yKey: "relative_y", step: step, substitutions: substitutions),
           let normalized = normalizedPoint(point, appName: step.targetApp) {
            return ActionAssistantResolvedTargetInfo(
                label: resolvedValue(for: step.target?.computedNameContains, substitutions: substitutions),
                role: step.target?.criteria?.first(where: { $0.attribute == "AXRole" })?.value,
                relativeX: Double(normalized.x),
                relativeY: Double(normalized.y)
            )
        }

        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.actionAssistantVisualSnapshotsEnabled),
              let targetDescription = resolvedValue(for: step.params?["target_hint"], substitutions: substitutions)
                ?? resolvedValue(for: step.target?.computedNameContains, substitutions: substitutions)
                ?? step.note,
              !targetDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let visualContext = await ActionAssistantPerception.focusedWindowVisualContext(preferredAppName: step.targetApp),
              let screenshotPath = visualContext.screenshotPath,
              let grounded = await ActionAssistantVisualLocator.locate(
                targetDescription: targetDescription,
                preferredAppName: step.targetApp,
                screenshotPath: screenshotPath
              ) else {
            return nil
        }

        let normalizedPoint = grounded.normalizedInteractionPoint
        return ActionAssistantResolvedTargetInfo(
            label: grounded.label,
            role: grounded.role,
            relativeX: Double(normalizedPoint.x),
            relativeY: Double(normalizedPoint.y)
        )
    }

    private func elementStringAttribute(_ attribute: String, for element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func relativeCoordinate(for element: AXUIElement, appName: String?) -> CGPoint? {
        guard let center = elementCenter(element) else { return nil }
        return normalizedPoint(center, appName: appName)
    }

    private func normalizedPoint(_ point: CGPoint, appName: String?) -> CGPoint? {
        guard let frame = ActionAssistantPerception.focusedWindowFrame(preferredAppName: appName),
              frame.width > 0,
              frame.height > 0 else {
            return nil
        }

        return CGPoint(
            x: min(max((point.x - frame.origin.x) / frame.width, 0), 1),
            y: min(max(1 - ((point.y - frame.origin.y) / frame.height), 0), 1)
        )
    }

    func assignReadValue(
        _ value: String,
        for step: ActionAssistantRecipe.Step,
        substitutions: inout [String: String]
    ) {
        let key = step.params?["assign"] ?? step.params?["var"] ?? step.params?["output"]
        if let key, !key.isEmpty {
            substitutions[key] = value
        }
    }
}
