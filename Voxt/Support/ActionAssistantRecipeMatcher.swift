import Foundation

struct ActionAssistantMatchedRecipe {
    let recipe: ActionAssistantRecipe
    let substitutions: [String: String]
}

enum ActionAssistantRecipeMatcher {
    static func matchRecipe(for text: String) -> ActionAssistantMatchedRecipe? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.contains("open gmail") || text.contains("打开 gmail") || text.contains("打开Gmail") {
            return recipe(named: "open-gmail")
        }

        if normalized.contains("compose gmail")
            || normalized.contains("open gmail compose")
            || normalized.contains("gmail compose")
            || normalized.contains("compose a new email in gmail")
            || normalized.contains("open gmail and compose")
            || text.contains("打开 gmail 写邮件")
            || text.contains("打开Gmail写邮件")
            || text.contains("打开 gmail 撰写")
            || text.contains("打开 Gmail 撰写") {
            return recipe(named: "gmail-compose-window")
        }

        if normalized.contains("open slack") || text.contains("打开 slack") || text.contains("打开Slack") {
            return recipe(named: "open-slack")
        }

        if normalized.contains("open notion") || text.contains("打开 notion") || text.contains("打开Notion") {
            return recipe(named: "open-notion")
        }

        if normalized.contains("open linear") || text.contains("打开 linear") || text.contains("打开Linear") {
            return recipe(named: "open-linear")
        }

        if normalized.contains("open x") || normalized.contains("open twitter") || text.contains("打开 x") || text.contains("打开X") || text.contains("打开推特") {
            return recipe(named: "open-x")
        }

        if normalized.contains("open calendar") || text.contains("打开日历") || text.contains("打开 Calendar") {
            return recipe(named: "open-calendar")
        }

        if normalized.contains("send slack message")
            || normalized.contains("post to slack")
            || text.contains("发 slack 消息")
            || text.contains("发Slack消息")
            || text.contains("发送 slack 消息") {
            let payload = extractSlackMessagePayload(from: text)
            guard let channel = payload.channel, let message = payload.message,
                  !channel.isEmpty, !message.isEmpty else { return nil }
            return recipe(named: "slack-send", substitutions: [
                "channel": channel,
                "message": message
            ])
        }

        if normalized.contains("send email")
            || normalized.contains("draft email")
            || text.contains("发邮件给")
            || text.contains("写邮件给")
            || text.contains("起草邮件给") {
            let payload = extractEmailPayload(from: text)
            guard let recipient = payload.recipient,
                  let subject = payload.subject,
                  let body = payload.body,
                  !recipient.isEmpty, !subject.isEmpty, !body.isEmpty else { return nil }
            let composeURL = buildGmailComposeURL(recipient: recipient, subject: subject, body: body)
            return recipe(named: "gmail-compose", substitutions: [
                "compose_url": composeURL.absoluteString
            ])
        }

        if normalized.contains("create folder") || text.contains("创建文件夹") || text.contains("新建文件夹") {
            let folderName = extractFolderName(from: text)
            guard !folderName.isEmpty else { return nil }
            return recipe(named: "finder-create-folder", substitutions: ["folder_name": folderName])
        }

        if normalized.hasPrefix("search ") || normalized.contains("search google") || text.contains("搜索") || text.contains("搜一下") {
            let query = extractSearchQuery(from: text)
            guard !query.isEmpty else { return nil }
            return recipe(named: "search-google", substitutions: ["query": query])
        }

        return nil
    }

    static func matchLearnedRecipe(for text: String, snapshot: ActionAssistantPerceptionSnapshot) -> ActionAssistantMatchedRecipe? {
        let normalizedText = normalize(text)
        guard !normalizedText.isEmpty else { return nil }

        let candidates = ActionAssistantRecipeStore
            .listRecipes()
            .filter { recipe in
                ActionAssistantRecipeStore.isLearnedRecipe(recipe)
            }
            .filter(\.enabled)

        var bestMatch: (recipe: ActionAssistantRecipe, score: Double)?
        for recipe in candidates {
            let score = learnedRecipeScore(for: normalizedText, recipe: recipe, snapshot: snapshot)
            guard score >= 0.6 else { continue }
            if let currentBest = bestMatch {
                if score > currentBest.score {
                    bestMatch = (recipe, score)
                }
            } else {
                bestMatch = (recipe, score)
            }
        }

        guard let bestMatch else { return nil }
        return ActionAssistantMatchedRecipe(recipe: bestMatch.recipe, substitutions: [:])
    }

    private static func recipe(named name: String, substitutions: [String: String] = [:]) -> ActionAssistantMatchedRecipe? {
        ActionAssistantRecipeStore.loadRecipe(named: name).map {
            ActionAssistantMatchedRecipe(recipe: $0, substitutions: substitutions)
        }
    }

    private static func extractSearchQuery(from text: String) -> String {
        var query = text
        let replacements = [
            "search google for", "search for", "search", "google",
            "搜索一下", "搜索", "搜一下", "帮我搜索"
        ]
        for item in replacements {
            query = query.replacingOccurrences(of: item, with: "", options: [.caseInsensitive])
        }
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractFolderName(from text: String) -> String {
        var value = text
        let replacements = [
            "create folder called", "create folder named", "create folder",
            "新建文件夹叫", "创建文件夹叫", "新建文件夹", "创建文件夹"
        ]
        for item in replacements {
            value = value.replacingOccurrences(of: item, with: "", options: [.caseInsensitive])
        }
        return value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func extractSlackMessagePayload(from text: String) -> (channel: String?, message: String?) {
        if let match = text.range(
            of: #"(?i)send slack message to\s+([#\w\-.]+)\s+(?:saying|message|that says)\s+(.+)$"#,
            options: .regularExpression
        ) {
            let matched = String(text[match])
            let cleaned = matched.replacingOccurrences(of: #"(?i)^send slack message to\s+"#, with: "", options: .regularExpression)
            let parts = cleaned.components(separatedBy: " saying ")
            if parts.count == 2 {
                return (sanitizeSlackChannel(parts[0]), parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        let normalized = text
            .replacingOccurrences(of: "发Slack消息到", with: "发 slack 消息到")
            .replacingOccurrences(of: "发送Slack消息到", with: "发送 slack 消息到")
        if let range = normalized.range(of: "消息到") ?? normalized.range(of: "message to") {
            let tail = normalized[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let separators = [" 内容 ", " 说 ", " ：", ": "]
            for separator in separators {
                let parts = tail.components(separatedBy: separator)
                if parts.count >= 2 {
                    let channel = sanitizeSlackChannel(parts[0])
                    let message = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
                    return (channel, message)
                }
            }
        }
        return (nil, nil)
    }

    private static func sanitizeSlackChannel(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .replacingOccurrences(of: "#", with: "")
    }

    private static func extractEmailPayload(from text: String) -> (recipient: String?, subject: String?, body: String?) {
        if let range = text.range(
            of: #"(?i)(?:send|draft)\s+email\s+to\s+([^\s]+)\s+subject\s+(.+?)\s+body\s+(.+)$"#,
            options: .regularExpression
        ) {
            let matched = String(text[range])
            let stripped = matched.replacingOccurrences(
                of: #"(?i)^(?:send|draft)\s+email\s+to\s+"#,
                with: "",
                options: .regularExpression
            )
            if let subjectRange = stripped.range(of: " subject ", options: .caseInsensitive),
               let bodyRange = stripped.range(of: " body ", options: .caseInsensitive) {
                let recipient = String(stripped[..<subjectRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let subject = String(stripped[subjectRange.upperBound..<bodyRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let body = String(stripped[bodyRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (recipient, subject, body)
            }
        }

        if let recipientRange = text.range(of: "发邮件给") ?? text.range(of: "写邮件给") ?? text.range(of: "起草邮件给") {
            let tail = text[recipientRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let subjectRange = tail.range(of: "主题"),
               let bodyRange = tail.range(of: "内容") {
                let recipient = String(tail[..<subjectRange.lowerBound]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                let subject = String(tail[subjectRange.upperBound..<bodyRange.lowerBound]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                let body = String(tail[bodyRange.upperBound...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                return (recipient, subject, body)
            }
        }

        return (nil, nil, nil)
    }

    private static func buildGmailComposeURL(recipient: String, subject: String, body: String) -> URL {
        var components = URLComponents(string: "https://mail.google.com/mail/")!
        components.queryItems = [
            .init(name: "view", value: "cm"),
            .init(name: "fs", value: "1"),
            .init(name: "to", value: recipient),
            .init(name: "su", value: subject),
            .init(name: "body", value: body)
        ]
        return components.url ?? URL(string: "https://mail.google.com/mail/")!
    }

    static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

}
