import Foundation
import CoreGraphics

struct ActionAssistantVisualTarget: Codable, Hashable {
    struct BoundingBox: Codable, Hashable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    let relativeX: Double
    let relativeY: Double
    let bbox: BoundingBox?
    let label: String?
    let role: String?
    let confidence: Double?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case bbox
        case label
        case role
        case confidence
        case reason
        case relativeX = "relative_x"
        case relativeY = "relative_y"
    }

    var normalizedInteractionPoint: CGPoint {
        if let bbox {
            return CGPoint(
                x: min(max(bbox.x + (bbox.width / 2), 0), 1),
                y: min(max(bbox.y + (bbox.height / 2), 0), 1)
            )
        }

        return CGPoint(
            x: min(max(relativeX, 0), 1),
            y: min(max(relativeY, 0), 1)
        )
    }

    func isVisible(confidenceThreshold: Double = 0.55) -> Bool {
        (confidence ?? 0) >= confidenceThreshold
    }

    func displayLabel(fallback: String) -> String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}

typealias ActionAssistantVisualGroundingResult = ActionAssistantVisualTarget
