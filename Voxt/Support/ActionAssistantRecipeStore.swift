import Foundation

struct ActionAssistantRecipe: Codable, Identifiable, Hashable {
    struct LearnedMetrics: Codable, Hashable {
        var matchCount: Int
        var successCount: Int
        var failureCount: Int
        var consecutiveFailureCount: Int
        var lastFailureCategory: String?
        var lastMatchedAt: Date?
        var lastSucceededAt: Date?
        var lastFailedAt: Date?

        enum CodingKeys: String, CodingKey {
            case matchCount = "match_count"
            case successCount = "success_count"
            case failureCount = "failure_count"
            case consecutiveFailureCount = "consecutive_failure_count"
            case lastFailureCategory = "last_failure_category"
            case lastMatchedAt = "last_matched_at"
            case lastSucceededAt = "last_succeeded_at"
            case lastFailedAt = "last_failed_at"
        }
    }

    struct Parameter: Codable, Hashable {
        var type: String
        var description: String
        var required: Bool?
    }

    struct Preconditions: Codable, Hashable {
        var appRunning: String?
        var urlContains: String?

        enum CodingKeys: String, CodingKey {
            case appRunning = "app_running"
            case urlContains = "url_contains"
        }
    }

    struct Step: Codable, Hashable, Identifiable {
        private enum RawParameterValue: Decodable, Hashable {
            case string(String)
            case number(Double)
            case bool(Bool)
            case array([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(String.self) {
                    self = .string(value)
                } else if let value = try? container.decode(Double.self) {
                    self = .number(value)
                } else if let value = try? container.decode(Int.self) {
                    self = .number(Double(value))
                } else if let value = try? container.decode(Bool.self) {
                    self = .bool(value)
                } else if let value = try? container.decode([String].self) {
                    self = .array(value)
                } else {
                    throw DecodingError.typeMismatch(
                        RawParameterValue.self,
                        .init(codingPath: decoder.codingPath, debugDescription: "Unsupported parameter value")
                    )
                }
            }

            var stringValue: String {
                switch self {
                case .string(let value):
                    return value
                case .number(let value):
                    return value.rounded(.towardZero) == value ? String(Int(value)) : String(value)
                case .bool(let value):
                    return value ? "true" : "false"
                case .array(let value):
                    return value.joined(separator: ",")
                }
            }
        }

        struct Target: Codable, Hashable {
            struct Criterion: Codable, Hashable {
                var attribute: String
                var value: String
            }

            var criteria: [Criterion]?
            var computedNameContains: String?
        }

        struct WaitCondition: Codable, Hashable {
            var condition: String
            var value: String?
            var timeout: Double?
        }

        let id: Int
        var action: String
        var targetApp: String?
        var target: Target?
        var params: [String: String]?
        var waitAfter: WaitCondition?
        var note: String?
        var onFailure: String?

        enum CodingKeys: String, CodingKey {
            case id, action, target, params, note
            case targetApp = "target_app"
            case waitAfter = "wait_after"
            case onFailure = "on_failure"
        }

        init(
            id: Int,
            action: String,
            targetApp: String? = nil,
            target: Target? = nil,
            params: [String: String]? = nil,
            waitAfter: WaitCondition? = nil,
            note: String? = nil,
            onFailure: String? = nil
        ) {
            self.id = id
            self.action = action
            self.targetApp = targetApp
            self.target = target
            self.params = params
            self.waitAfter = waitAfter
            self.note = note
            self.onFailure = onFailure
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            action = try container.decode(String.self, forKey: .action)
            targetApp = try container.decodeIfPresent(String.self, forKey: .targetApp)
            target = try container.decodeIfPresent(Target.self, forKey: .target)
            if let rawParams = try container.decodeIfPresent([String: RawParameterValue].self, forKey: .params) {
                params = rawParams.mapValues(\.stringValue)
            } else {
                params = nil
            }
            waitAfter = try container.decodeIfPresent(WaitCondition.self, forKey: .waitAfter)
            note = try container.decodeIfPresent(String.self, forKey: .note)
            onFailure = try container.decodeIfPresent(String.self, forKey: .onFailure)
        }
    }

    let id: UUID
    var schemaVersion: Int
    var name: String
    var description: String
    var app: String?
    var enabled: Bool
    var pinned: Bool
    var params: [String: Parameter]?
    var preconditions: Preconditions?
    var steps: [Step]
    var onFailure: String?
    var learnedMetrics: LearnedMetrics?

    init(
        id: UUID = UUID(),
        schemaVersion: Int = 1,
        name: String,
        description: String,
        app: String? = nil,
        enabled: Bool = true,
        pinned: Bool = false,
        params: [String: Parameter]? = nil,
        preconditions: Preconditions? = nil,
        steps: [Step],
        onFailure: String? = nil,
        learnedMetrics: LearnedMetrics? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.name = name
        self.description = description
        self.app = app
        self.enabled = enabled
        self.pinned = pinned
        self.params = params
        self.preconditions = preconditions
        self.steps = steps
        self.onFailure = onFailure
        self.learnedMetrics = learnedMetrics
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, app, enabled, pinned, params, preconditions, steps, learnedMetrics
        case schemaVersion = "schema_version"
        case onFailure = "on_failure"
    }
}

struct ActionAssistantRecipeRunResult: Hashable {
    struct StepResult: Hashable, Identifiable {
        let id = UUID()
        var stepID: Int
        var action: String
        var success: Bool
        var durationMs: Int
        var error: String?
        var note: String?
        var targetApp: String?
        var targetLabel: String?
        var targetRole: String?
        var relativeX: Double?
        var relativeY: Double?
        var resolvedTargetLabel: String?
        var resolvedTargetRole: String?
        var resolvedRelativeX: Double?
        var resolvedRelativeY: Double?
        var diagnosisCategory: String?
        var diagnosisReason: String?
    }

    var recipeName: String
    var success: Bool
    var stepsCompleted: Int
    var totalSteps: Int
    var stepResults: [StepResult]
    var error: String?
}

enum ActionAssistantRecipeStore {
    private static let learnedRecipePrefix = "Learned - "

    static var recipesDirectoryURL: URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("ActionAssistant", isDirectory: true)
            .appendingPathComponent("Recipes", isDirectory: true)
    }

    static func listRecipes() -> [ActionAssistantRecipe] {
        let fileManager = FileManager.default
        createRecipesDirectoryIfNeeded()

        guard let files = try? fileManager.contentsOfDirectory(at: recipesDirectoryURL, includingPropertiesForKeys: nil) else {
            return []
        }

        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { fileURL in
                guard let data = try? Data(contentsOf: fileURL) else { return nil }
                do {
                    return try decoder.decode(ActionAssistantRecipe.self, from: data)
                } catch {
                    VoxtLog.warning("Failed to decode Action Assistant recipe at \(fileURL.lastPathComponent): \(error)")
                    return nil
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func ensureBuiltInRecipesInstalled() {
        createRecipesDirectoryIfNeeded()
        for recipe in ActionAssistantBuiltInRecipes.all {
            let url = recipeURL(named: recipe.name)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try saveRecipe(recipe)
            } catch {
                VoxtLog.warning("Failed to seed Action Assistant recipe '\(recipe.name)': \(error)")
            }
        }
    }

    static func restoreBuiltInRecipes() {
        createRecipesDirectoryIfNeeded()
        for recipe in ActionAssistantBuiltInRecipes.all {
            do {
                try saveRecipe(recipe)
            } catch {
                VoxtLog.warning("Failed to restore Action Assistant recipe '\(recipe.name)': \(error)")
            }
        }
    }

    static func loadRecipe(named name: String) -> ActionAssistantRecipe? {
        let url = recipeURL(named: name)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(ActionAssistantRecipe.self, from: data)
        } catch {
            VoxtLog.warning("Failed to decode Action Assistant recipe '\(name)': \(error)")
            return nil
        }
    }

    static func saveRecipe(_ recipe: ActionAssistantRecipe) throws {
        createRecipesDirectoryIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(recipe)
        try data.write(to: recipeURL(named: recipe.name), options: .atomic)
    }

    static func saveLearnedRecipe(from plan: ActionAssistantPlan, userRequest: String) throws -> String? {
        let trimmedSummary = plan.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRequest = userRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty,
              trimmedSummary.lowercased() != "unsupported",
              plan.steps.count >= 2 else {
            return nil
        }

        let baseName = learnedRecipePrefix + trimmedSummary
        let recipeName = nextUniqueRecipeName(startingWith: baseName)
        let descriptionSource = trimmedRequest.isEmpty ? trimmedSummary : trimmedRequest
        let recipe = ActionAssistantRecipe(
            name: recipeName,
            description: descriptionSource,
            app: plan.app,
            preconditions: plan.preconditions,
            steps: plan.steps,
            onFailure: plan.onFailure,
            learnedMetrics: .empty
        )
        try saveRecipe(recipe)
        return recipe.name
    }

    static func recordLearnedRecipeUsage(named name: String, succeeded: Bool, diagnosisCategory: String? = nil) {
        updateRecipe(named: name) { recipe in
            guard isLearnedRecipe(recipe) else { return }
            var metrics = recipe.learnedMetrics ?? .empty
            let now = Date()
            metrics.matchCount += 1
            metrics.lastMatchedAt = now
            if succeeded {
                metrics.successCount += 1
                metrics.consecutiveFailureCount = 0
                metrics.lastFailureCategory = nil
                metrics.lastSucceededAt = now
            } else {
                metrics.failureCount += 1
                metrics.consecutiveFailureCount += 1
                metrics.lastFailureCategory = diagnosisCategory
                metrics.lastFailedAt = now
            }
            recipe.learnedMetrics = metrics
        }
    }

    static func resetLearnedRecipeMetrics(named name: String) {
        updateRecipe(named: name) { recipe in
            guard isLearnedRecipe(recipe) else { return }
            resetMetrics(for: &recipe)
        }
    }

    static func resetAllLearnedRecipeMetrics() {
        let learnedRecipes = listRecipes().filter { recipe in
            isLearnedRecipe(recipe)
        }
        for var recipe in learnedRecipes {
            resetMetrics(for: &recipe)
            try? saveRecipe(recipe)
        }
    }

    static func setRecipePinned(named name: String, pinned: Bool) {
        updateRecipe(named: name) { recipe in
            recipe.pinned = pinned
        }
    }

    static func setRecipeEnabled(named name: String, enabled: Bool) {
        updateRecipe(named: name) { recipe in
            recipe.enabled = enabled
        }
    }

    static func createRecipeTemplate() throws -> String {
        let recipeName = nextUniqueRecipeName(startingWith: "Custom Recipe")
        let recipe = ActionAssistantRecipeDraftFactory.makeBlankRecipe(named: recipeName)
        try saveRecipe(recipe)
        return recipe.name
    }

    static func createRecipeTemplate(
        fromAssistantSummary summary: String,
        spokenText: String,
        actions: [String],
        structuredSteps: [AssistantHistoryStep],
        focusedAppName: String?
    ) throws -> String {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseNameSource = trimmedSummary.isEmpty ? "Recipe From History" : trimmedSummary
        let recipeName = nextUniqueRecipeName(startingWith: "Draft - " + baseNameSource)
        let recipe = ActionAssistantRecipeDraftFactory.makeHistoryDraftRecipe(
            named: recipeName,
            summary: summary,
            spokenText: spokenText,
            actions: actions,
            structuredSteps: structuredSteps,
            focusedAppName: focusedAppName
        )
        try saveRecipe(recipe)
        return recipe.name
    }

    static func duplicateRecipe(named name: String) throws -> String? {
        guard var recipe = loadRecipe(named: name) else { return nil }
        let copyBaseName = recipe.name + " Copy"
        recipe = ActionAssistantRecipe(
            name: nextUniqueRecipeName(startingWith: copyBaseName),
            description: recipe.description,
            app: recipe.app,
            enabled: recipe.enabled,
            pinned: false,
            params: recipe.params,
            preconditions: recipe.preconditions,
            steps: recipe.steps,
            onFailure: recipe.onFailure,
            learnedMetrics: recipe.learnedMetrics
        )
        try saveRecipe(recipe)
        return recipe.name
    }

    static func saveRecipeJSON(_ jsonString: String) throws -> String {
        guard let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "ActionAssistantRecipeStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid recipe JSON string."])
        }
        let recipe = try JSONDecoder().decode(ActionAssistantRecipe.self, from: data)
        try saveRecipe(recipe)
        return recipe.name
    }

    static func deleteRecipe(named name: String) throws {
        let url = recipeURL(named: name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func recipeURL(named name: String) -> URL {
        let sanitized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        return recipesDirectoryURL.appendingPathComponent("\(sanitized).json")
    }

    static func isLearnedRecipe(_ recipe: ActionAssistantRecipe) -> Bool {
        isLearnedRecipeName(recipe.name)
    }

    static func isLearnedRecipeName(_ name: String) -> Bool {
        name.hasPrefix(learnedRecipePrefix)
    }

    static func needsReview(_ recipe: ActionAssistantRecipe) -> Bool {
        guard isLearnedRecipe(recipe), let metrics = recipe.learnedMetrics else { return false }
        return metrics.consecutiveFailureCount >= 3
    }
}
