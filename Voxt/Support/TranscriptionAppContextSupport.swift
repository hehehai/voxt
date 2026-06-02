import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct TranscriptionAppContextCapture: Equatable {
    let textContext: String
    let attachments: [LLMInputAttachment]
}

struct TranscriptionAppContextModelCapabilities: Equatable {
    let supportsTextContext: Bool
    let supportsImageInput: Bool
}

enum TranscriptionAppContextCapabilityResolver {
    static func capabilities(for provider: LLMExecutionProvider) -> TranscriptionAppContextModelCapabilities {
        switch provider {
        case .appleIntelligence:
            return TranscriptionAppContextModelCapabilities(
                supportsTextContext: true,
                supportsImageInput: false
            )
        case .customLLM(let repo):
            return TranscriptionAppContextModelCapabilities(
                supportsTextContext: true,
                supportsImageInput: CustomLLMModelCatalog.supportsImageInput(repo: repo)
            )
        case .remote(let remoteProvider, let configuration):
            return TranscriptionAppContextModelCapabilities(
                supportsTextContext: true,
                supportsImageInput: supportsImageInput(
                    provider: remoteProvider,
                    model: configuration.model
                )
            )
        }
    }

    private static func supportsImageInput(
        provider: RemoteLLMProvider,
        model: String
    ) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        switch provider {
        case .openAI, .codex:
            return normalized.hasPrefix("gpt-5")
                || normalized.hasPrefix("gpt-4.1")
                || normalized.contains("gpt-4o")
                || normalized.hasPrefix("o4-mini")
        case .volcengine:
            return normalized.contains("vision")
                || normalized.hasPrefix("doubao-seed-2-0-pro")
                || normalized.hasPrefix("doubao-seed-2-0-lite")
                || normalized.hasPrefix("doubao-seed-2-0-mini")
                || normalized.hasPrefix("doubao-seed-1-8")
        case .aliyunBailian:
            return normalized.contains("qwen-vl")
                || normalized.contains("qvq")
                || normalized.contains("omni")
                || normalized.contains("qwen3.5-plus")
                || normalized.contains("qwen3.6-plus")
        default:
            return false
        }
    }
}

enum TranscriptionAppContextCaptureService {
    nonisolated static let preferredImageAttachmentLongEdge = 1280
    nonisolated static let minimumImageAttachmentLongEdge = 768
    nonisolated static let maxImageAttachmentBytes = 700_000

    private nonisolated static let imageAttachmentCompressionQualities: [CGFloat] = [0.72, 0.6, 0.5, 0.4]
    private nonisolated static let imageAttachmentLongEdgeFallbacks: [Int] = [1280, 1152, 1024, 896, 768]

    static func capture(
        snapshot: AppDelegate.EnhancementContextSnapshot,
        modelCapabilities: TranscriptionAppContextModelCapabilities,
        settings: TranscriptionAppContextSettings,
        browserURLResolver: ((String?) -> String?)? = nil
    ) async -> TranscriptionAppContextCapture? {
        let allowsTextContext = settings.textEnabled && modelCapabilities.supportsTextContext
        let allowsImageInput = settings.screenshotEnabled && modelCapabilities.supportsImageInput
        guard allowsTextContext || allowsImageInput else { return nil }
        guard let resolvedApp = resolvedRunningApp(from: snapshot) else { return nil }

        let appElement = AXUIElementCreateApplication(resolvedApp.processIdentifier)
        let windowElement = focusedWindow(in: appElement) ?? mainWindow(in: appElement)
        let windowTitle = windowElement.flatMap { stringAttribute(kAXTitleAttribute as String, from: $0) } ?? ""
        let textContext: String
        if allowsTextContext {
            let browserURL = browserURLResolver?(resolvedApp.bundleIdentifier)
            let selectedText = focusedSelectedText(in: appElement)
            let focusedElementSummary = focusedElementSummary(in: appElement)
            let visibleLines = visibleTextLines(in: windowElement, limit: 32)
            textContext = composeTextContext(
                appName: resolvedApp.localizedName ?? snapshot.appName ?? snapshot.bundleID ?? "Unknown App",
                bundleID: resolvedApp.bundleIdentifier ?? snapshot.bundleID ?? "",
                windowTitle: windowTitle,
                browserURL: browserURL,
                focusedElementSummary: focusedElementSummary,
                selectedText: selectedText,
                visibleLines: visibleLines
            )
        } else {
            textContext = ""
        }

        let attachments: [LLMInputAttachment]
        if allowsImageInput,
           let imageAttachment = await captureWindowImageAttachment(
                for: resolvedApp.processIdentifier,
                preferredWindowTitle: windowTitle
           ) {
            attachments = [.image(imageAttachment)]
        } else {
            attachments = []
        }

        guard !textContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else {
            return nil
        }

        return TranscriptionAppContextCapture(
            textContext: textContext,
            attachments: attachments
        )
    }

    private static func resolvedRunningApp(
        from snapshot: AppDelegate.EnhancementContextSnapshot
    ) -> NSRunningApplication? {
        if let pid = snapshot.pid,
           let app = NSRunningApplication(processIdentifier: pid),
           !app.isTerminated {
            return app
        }

        guard let bundleID = snapshot.bundleID else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }
    }

    private static func composeTextContext(
        appName: String,
        bundleID: String,
        windowTitle: String,
        browserURL: String?,
        focusedElementSummary: String?,
        selectedText: String?,
        visibleLines: [String]
    ) -> String {
        var sections: [String] = []
        sections.append("App: \(appName)")
        if !bundleID.isEmpty {
            sections.append("Bundle ID: \(bundleID)")
        }
        if !windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Window: \(windowTitle)")
        }
        if let browserURL, !browserURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Browser URL: \(browserURL)")
        }
        if let focusedElementSummary, !focusedElementSummary.isEmpty {
            sections.append("Focused element: \(focusedElementSummary)")
        }
        if let selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("""
            Selected text:
            \(selectedText)
            """)
        }
        if !visibleLines.isEmpty {
            sections.append("""
            Visible text:
            \(visibleLines.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }
        return sections.joined(separator: "\n\n")
    }

    private static func focusedWindow(in appElement: AXUIElement) -> AXUIElement? {
        elementAttribute(kAXFocusedWindowAttribute as String, from: appElement)
    }

    private static func mainWindow(in appElement: AXUIElement) -> AXUIElement? {
        elementAttribute(kAXMainWindowAttribute as String, from: appElement)
    }

    private static func focusedElement(in appElement: AXUIElement) -> AXUIElement? {
        elementAttribute(kAXFocusedUIElementAttribute as String, from: appElement)
    }

    private static func focusedSelectedText(in appElement: AXUIElement) -> String? {
        guard let focusedElement = focusedElement(in: appElement) else { return nil }
        return stringAttribute(kAXSelectedTextAttribute as String, from: focusedElement)
    }

    private static func focusedElementSummary(in appElement: AXUIElement) -> String? {
        guard let focusedElement = focusedElement(in: appElement) else { return nil }
        let role = stringAttribute(kAXRoleAttribute as String, from: focusedElement) ?? "Unknown"
        let title = stringAttribute(kAXTitleAttribute as String, from: focusedElement)
        let value = stringAttribute(kAXValueAttribute as String, from: focusedElement)
        let description = stringAttribute(kAXDescriptionAttribute as String, from: focusedElement)
        let parts = [title, value, description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return role }
        return "\(role) - \(parts.prefix(2).joined(separator: " | "))"
    }

    private static func visibleTextLines(
        in rootElement: AXUIElement?,
        limit: Int
    ) -> [String] {
        guard let rootElement else { return [] }

        var queue: [AXUIElement] = [rootElement]
        var seen = Set<String>()
        var results: [String] = []
        var visitedCount = 0

        while !queue.isEmpty && results.count < limit && visitedCount < 400 {
            let element = queue.removeFirst()
            visitedCount += 1

            for candidate in candidateTextValues(for: element) {
                let normalized = normalizeTextLine(candidate)
                guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
                results.append(normalized)
                if results.count >= limit {
                    break
                }
            }

            if let children = arrayAttribute(kAXChildrenAttribute as String, from: element) {
                queue.append(contentsOf: children.prefix(24))
            }
        }

        return results
    }

    private static func candidateTextValues(for element: AXUIElement) -> [String] {
        let keys = [
            kAXTitleAttribute as String,
            kAXValueAttribute as String,
            kAXDescriptionAttribute as String,
            kAXHelpAttribute as String,
            kAXPlaceholderValueAttribute as String
        ]

        return keys.compactMap { stringAttribute($0, from: element) }
    }

    private static func normalizeTextLine(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private nonisolated static func captureWindowImageAttachment(
        for pid: pid_t,
        preferredWindowTitle: String
    ) async -> LLMImageAttachment? {
        await Task.detached(priority: .userInitiated) {
            captureWindowImageAttachmentSynchronously(
                for: pid,
                preferredWindowTitle: preferredWindowTitle
            )
        }.value
    }

    private nonisolated static func captureWindowImageAttachmentSynchronously(
        for pid: pid_t,
        preferredWindowTitle: String
    ) -> LLMImageAttachment? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let windowInfo = preferredWindowInfo(for: pid, preferredWindowTitle: preferredWindowTitle) else {
            return nil
        }
        guard let imageData = captureWindowImageData(windowID: windowInfo.windowID) else {
            return nil
        }
        return makeImageAttachment(from: imageData, appName: windowInfo.ownerName)
    }

    private nonisolated static func preferredWindowInfo(
        for pid: pid_t,
        preferredWindowTitle: String
    ) -> (windowID: CGWindowID, ownerName: String)? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let normalizedPreferredTitle = preferredWindowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = windows.filter { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid else { return false }
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            let isOnscreen = (window[kCGWindowIsOnscreen as String] as? Int ?? 1) != 0
            return layer == 0 && alpha > 0.01 && isOnscreen
        }

        if let exact = candidates.first(where: { window in
            let title = (window[kCGWindowName as String] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalizedPreferredTitle.isEmpty && title == normalizedPreferredTitle
        }), let windowID = exact[kCGWindowNumber as String] as? CGWindowID {
            return (
                windowID: windowID,
                ownerName: exact[kCGWindowOwnerName as String] as? String ?? "app"
            )
        }

        if let fallback = candidates.first,
           let windowID = fallback[kCGWindowNumber as String] as? CGWindowID {
            return (
                windowID: windowID,
                ownerName: fallback[kCGWindowOwnerName as String] as? String ?? "app"
            )
        }

        return nil
    }

    private nonisolated static func captureWindowImageData(windowID: CGWindowID) -> Data? {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxt-app-context-\(UUID().uuidString)")
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = [
            "-x",
            "-o",
            "-t", "png",
            "-l", String(windowID),
            destinationURL.path
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        return try? Data(contentsOf: destinationURL)
    }

    nonisolated static func makeImageAttachment(
        from data: Data,
        appName: String
    ) -> LLMImageAttachment? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        guard let optimizedImage = optimizedJPEGImage(from: image) else { return nil }

        let sanitizedAppName = appName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        return LLMImageAttachment(
            data: optimizedImage.data,
            mimeType: "image/jpeg",
            detail: optimizedImage.detail,
            filename: sanitizedAppName.isEmpty ? "app-context.jpg" : "\(sanitizedAppName)-context.jpg"
        )
    }

    private nonisolated static func optimizedJPEGImage(from image: CGImage) -> (data: Data, detail: LLMImageAttachmentDetail)? {
        let originalLongEdge = max(image.width, image.height)
        guard originalLongEdge > 0 else { return nil }

        let cappedLongEdge = min(preferredImageAttachmentLongEdge, originalLongEdge)
        var longEdgeCandidates = [cappedLongEdge]
        for fallback in imageAttachmentLongEdgeFallbacks where fallback < cappedLongEdge {
            longEdgeCandidates.append(fallback)
        }
        if longEdgeCandidates.last != minimumImageAttachmentLongEdge,
           minimumImageAttachmentLongEdge < cappedLongEdge {
            longEdgeCandidates.append(minimumImageAttachmentLongEdge)
        }

        var smallestPayload: (data: Data, longEdge: Int)?

        for longEdge in uniqueIntegers(longEdgeCandidates) {
            guard let scaledImage = resizedImage(image, maxLongEdge: longEdge) else { continue }
            let effectiveLongEdge = max(scaledImage.width, scaledImage.height)

            for quality in imageAttachmentCompressionQualities {
                guard let encoded = jpegData(from: scaledImage, quality: quality) else { continue }
                if smallestPayload == nil || encoded.count < smallestPayload!.data.count {
                    smallestPayload = (encoded, effectiveLongEdge)
                }
                if encoded.count <= maxImageAttachmentBytes {
                    return (encoded, imageAttachmentDetail(forLongEdge: effectiveLongEdge, byteCount: encoded.count))
                }
            }
        }

        guard let smallestPayload else { return nil }
        return (
            smallestPayload.data,
            imageAttachmentDetail(
                forLongEdge: smallestPayload.longEdge,
                byteCount: smallestPayload.data.count
            )
        )
    }

    private nonisolated static func resizedImage(_ image: CGImage, maxLongEdge: Int) -> CGImage? {
        let sourceLongEdge = max(image.width, image.height)
        guard sourceLongEdge > 0 else { return nil }
        guard sourceLongEdge > maxLongEdge else { return image }

        let scale = Double(maxLongEdge) / Double(sourceLongEdge)
        let targetWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(image.height) * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return context.makeImage()
    }

    private nonisolated static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [
                kCGImageDestinationLossyCompressionQuality: quality
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private nonisolated static func imageAttachmentDetail(
        forLongEdge longEdge: Int,
        byteCount: Int
    ) -> LLMImageAttachmentDetail {
        if longEdge <= 1024 || byteCount <= 500_000 {
            return .low
        }
        return .auto
    }

    private nonisolated static func uniqueIntegers(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private static func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value
        else {
            return nil
        }

        if let string = value as? String {
            return string
        }
        if CFGetTypeID(value) == AXValueGetTypeID() {
            return nil
        }
        return String(describing: value)
    }

    private static func elementAttribute(_ name: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func arrayAttribute(_ name: String, from element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              let array = value as? [Any]
        else {
            return nil
        }

        return array.compactMap { item in
            guard CFGetTypeID(item as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(item, to: AXUIElement.self)
        }
    }
}
