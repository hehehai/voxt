import Foundation

actor ActionAssistantVisualLocatorCache {
    static let shared = ActionAssistantVisualLocatorCache()

    private var cachedTargets: [String: ActionAssistantVisualTarget] = [:]

    func value(for key: String) -> ActionAssistantVisualTarget? {
        cachedTargets[key]
    }

    func store(_ target: ActionAssistantVisualTarget, for key: String) {
        cachedTargets[key] = target
    }
}

enum ActionAssistantVisualLocator {
    static func locate(
        targetDescription: String,
        preferredAppName: String?,
        screenshotPath: String
    ) async -> ActionAssistantVisualTarget? {
        let cacheKey = makeCacheKey(
            targetDescription: targetDescription,
            preferredAppName: preferredAppName,
            screenshotPath: screenshotPath
        )
        if let cached = await ActionAssistantVisualLocatorCache.shared.value(for: cacheKey) {
            return cached
        }

        guard let grounded = await ActionAssistantVisualGrounder.locateTarget(
            targetDescription: targetDescription,
            preferredAppName: preferredAppName,
            screenshotPath: screenshotPath
        ) else {
            return nil
        }

        if grounded.confidence ?? 0 >= 0.45 {
            await ActionAssistantVisualLocatorCache.shared.store(grounded, for: cacheKey)
        }
        return grounded
    }

    private static func makeCacheKey(
        targetDescription: String,
        preferredAppName: String?,
        screenshotPath: String
    ) -> String {
        let normalizedTarget = targetDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedApp = preferredAppName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return "\(screenshotPath)|\(normalizedApp)|\(normalizedTarget)"
    }
}
