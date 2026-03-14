import Foundation

extension ActionAssistantPlanner {
    static func recipe(from plan: ActionAssistantPlan) -> ActionAssistantRecipe {
        ActionAssistantRecipe(
            name: "planned-action",
            description: plan.summary,
            app: plan.app,
            preconditions: plan.preconditions,
            steps: plan.steps,
            onFailure: plan.onFailure
        )
    }

    static func decodePlan(from output: String) -> ActionAssistantPlan? {
        guard let plan = decodeJSON(output, as: ActionAssistantPlan.self) else {
            return nil
        }
        return normalized(plan)
    }

    static func decodeOutcomeAssessment(from output: String) -> ActionAssistantOutcomeAssessment? {
        decodeJSON(output, as: ActionAssistantOutcomeAssessment.self)
    }

    static func prettyJSONString<T: Encodable>(from value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    static func normalized(_ plan: ActionAssistantPlan) -> ActionAssistantPlan {
        let normalizedSteps = plan.steps.enumerated().map { index, step in
            var normalizedParams = step.params
            if let hotkey = normalizedParams?["hotkey"], normalizedParams?["keys"] == nil {
                normalizedParams?["keys"] = hotkey
                normalizedParams?.removeValue(forKey: "hotkey")
            }
            let normalizedID = step.id > 0 ? step.id : index + 1
            return ActionAssistantRecipe.Step(
                id: normalizedID,
                action: step.action,
                targetApp: step.targetApp,
                target: step.target,
                params: normalizedParams,
                waitAfter: step.waitAfter,
                note: step.note,
                onFailure: step.onFailure
            )
        }
        return ActionAssistantPlan(
            summary: plan.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            app: plan.app?.trimmingCharacters(in: .whitespacesAndNewlines),
            expectedOutcome: plan.expectedOutcome?.trimmingCharacters(in: .whitespacesAndNewlines),
            preconditions: plan.preconditions,
            onFailure: plan.onFailure?.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: normalizedSteps
        )
    }

    static func decodeJSON<T: Decodable>(_ output: String, as type: T.Type) -> T? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoder = JSONDecoder()

        if let directData = trimmed.data(using: .utf8),
           let direct = try? decoder.decode(type, from: directData) {
            return direct
        }

        guard let json = extractFirstJSONObject(in: trimmed),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(type, from: data)
    }

    static func extractFirstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false

        for index in text[start...].indices {
            let character = text[index]
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == "\"" {
                inString.toggle()
                continue
            }
            if inString {
                continue
            }
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }

        return nil
    }
}
