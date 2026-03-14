import Foundation

enum ActionAssistantVisualGrounder {
    static func locateTarget(
        targetDescription: String,
        preferredAppName: String?,
        screenshotPath: String
    ) async -> ActionAssistantVisualGroundingResult? {
        let trimmedTarget = targetDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTarget.isEmpty else { return nil }

        let imageURL = URL(fileURLWithPath: screenshotPath)
        guard FileManager.default.fileExists(atPath: imageURL.path) else { return nil }

        let defaults = UserDefaults.standard
        let provider = RemoteLLMProvider(rawValue: defaults.string(forKey: AppPreferenceKey.remoteLLMSelectedProvider) ?? "")
            ?? .openAI
        let storedConfigurations = RemoteModelConfigurationStore.loadConfigurations(
            from: defaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? ""
        )
        let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: provider,
            stored: storedConfigurations
        )
        guard provider.supportsVisionInput else { return nil }

        let appNameLine = preferredAppName.map { "Preferred app: \($0)" } ?? "Preferred app: unknown"
        let prompt = """
        You are locating a GUI target inside a screenshot of the focused window.

        Return JSON only. No markdown. No explanation.

        Find the most likely clickable or interactive point for this target:
        \(trimmedTarget)

        \(appNameLine)

        Coordinate system:
        - relative_x and relative_y must be normalized between 0.0 and 1.0
        - 0,0 is the top-left of the screenshot
        - 1,1 is the bottom-right of the screenshot
        - bbox x,y,width,height must also be normalized in the same coordinate system

        If the target is not visible, return:
        {"relative_x":-1,"relative_y":-1,"bbox":null,"label":null,"role":null,"confidence":0,"reason":"not visible"}

        JSON schema:
        {
          "relative_x": 0.5,
          "relative_y": 0.5,
          "bbox": {
            "x": 0.45,
            "y": 0.40,
            "width": 0.10,
            "height": 0.06
          },
          "label": "Compose",
          "role": "button",
          "confidence": 0.0,
          "reason": "short reason"
        }
        """

        do {
            let output = try await RemoteLLMRuntimeClient().enhance(
                userPrompt: prompt,
                provider: provider,
                configuration: configuration,
                imageFileURL: imageURL
            )
            guard let data = output.data(using: .utf8),
                  let result = try? JSONDecoder().decode(ActionAssistantVisualGroundingResult.self, from: data),
                  (0...1).contains(result.relativeX),
                  (0...1).contains(result.relativeY),
                  result.bbox.map(isValidBoundingBox(_:)) ?? true else {
                return nil
            }
            return result
        } catch {
            return nil
        }
    }

    private static func isValidBoundingBox(_ bbox: ActionAssistantVisualGroundingResult.BoundingBox) -> Bool {
        guard (0...1).contains(bbox.x),
              (0...1).contains(bbox.y),
              bbox.width >= 0,
              bbox.height >= 0,
              bbox.x + bbox.width <= 1.0001,
              bbox.y + bbox.height <= 1.0001 else {
            return false
        }
        return true
    }

    static func locatePoint(
        targetDescription: String,
        preferredAppName: String?,
        screenshotPath: String
    ) async -> ActionAssistantVisualGroundingResult? {
        await locateTarget(
            targetDescription: targetDescription,
            preferredAppName: preferredAppName,
            screenshotPath: screenshotPath
        )
    }
}
