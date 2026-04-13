import Foundation

extension RemoteLLMRuntimeClient {
    func openAICompatibleMessages(systemPrompt: String, userPrompt: String) -> [[String: String]] {
        let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSystem.isEmpty {
            return [
                ["role": "user", "content": userPrompt]
            ]
        }
        return [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
    }

    func openAICompatibleConversationMessages(
        systemPrompt: String,
        currentUserPrompt: String,
        conversationHistory: [RewriteConversationPromptTurn]
    ) -> [[String: String]] {
        var messages: [[String: String]] = []

        let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystem.isEmpty {
            messages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }

        for turn in conversationHistory {
            let userPrompt = turn.userPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userPrompt.isEmpty {
                messages.append([
                    "role": "user",
                    "content": userPrompt
                ])
            }

            let assistantMessage = composeConversationAssistantMessage(
                title: turn.resultTitle,
                content: turn.resultContent
            )
            if !assistantMessage.isEmpty {
                messages.append([
                    "role": "assistant",
                    "content": assistantMessage
                ])
            }
        }

        messages.append([
            "role": "user",
            "content": currentUserPrompt
        ])

        return messages
    }

    func composeConversationAssistantMessage(title: String, content: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedTitle.isEmpty {
            return trimmedContent
        }
        if trimmedContent.isEmpty {
            return "Topic: \(trimmedTitle)"
        }

        return """
        Topic: \(trimmedTitle)
        Answer: \(trimmedContent)
        """
    }

    func makeResponsesRequest(
        provider: RemoteLLMProvider,
        endpointValue: String,
        model: String,
        systemPrompt: String,
        inputPayload: Any,
        configuration: RemoteProviderConfiguration,
        previousResponseID: String?,
        tuning: RemoteLLMRuntimeClient.GenerationTuning,
        textFormat: [String: Any]?,
        streamingEnabled: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: endpointValue) else {
            throw NSError(
                domain: "Voxt.RemoteLLM",
                code: -300,
                userInfo: [NSLocalizedDescriptionKey: "Invalid remote LLM endpoint URL: \(endpointValue)"]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeoutInterval(for: provider)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")

        let apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var payload: [String: Any] = [
            "model": model,
            "stream": streamingEnabled,
            "max_output_tokens": tuning.maxTokens,
            "temperature": tuning.temperature,
            "top_p": tuning.topP
        ]

        let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystemPrompt.isEmpty {
            payload["instructions"] = trimmedSystemPrompt
        }

        let trimmedPreviousResponseID = previousResponseID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedPreviousResponseID.isEmpty {
            payload["previous_response_id"] = trimmedPreviousResponseID
            payload["input"] = inputPayload
        } else {
            payload["input"] = inputPayload
        }

        if let textFormat {
            payload["text"] = textFormat
        }

        if configuration.searchEnabled && provider.supportsHostedSearch {
            payload["tools"] = [
                [
                    "type": "web_search"
                ]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    func googleSearchToolPayload(for model: String) -> [String: Any] {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedModel.hasPrefix("gemini-1.5") {
            return [
                "google_search_retrieval": [
                    "dynamic_retrieval_config": [
                        "mode": "MODE_DYNAMIC",
                        "dynamic_threshold": 0.0
                    ]
                ]
            ]
        }
        return [
            "google_search": [:]
        ]
    }

    func applyOpenAICompatibleSearchConfiguration(
        to payload: inout [String: Any],
        provider: RemoteLLMProvider,
        configuration: RemoteProviderConfiguration
    ) {
        guard configuration.searchEnabled, provider.supportsHostedSearch else { return }

        switch provider {
        case .zai:
            payload["tools"] = [
                [
                    "type": "web_search",
                    "web_search": [
                        "enable": "True",
                        "search_engine": "search_std"
                    ]
                ]
            ]
        default:
            break
        }
    }

    func responsesInputMessages(
        currentUserInput: String,
        conversationHistory: [RewriteConversationPromptTurn]
    ) -> [[String: Any]] {
        var messages: [[String: Any]] = []

        for turn in conversationHistory {
            let userPrompt = turn.userPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userPrompt.isEmpty {
                messages.append([
                    "role": "user",
                    "content": userPrompt
                ])
            }

            let assistantMessage = composeConversationAssistantMessage(
                title: turn.resultTitle,
                content: turn.resultContent
            )
            if !assistantMessage.isEmpty {
                messages.append([
                    "role": "assistant",
                    "content": assistantMessage
                ])
            }
        }

        messages.append([
            "role": "user",
            "content": currentUserInput
        ])
        return messages
    }

    func responsesStreamingDelta(from object: [String: Any]) -> String? {
        if let type = object["type"] as? String {
            if type == "response.output_text.delta", let delta = object["delta"] as? String, !delta.isEmpty {
                return delta
            }
            if (type == "response.output_text" || type == "response.output_text.done"),
               let text = object["text"] as? String,
               !text.isEmpty {
                return text
            }
            if type == "response.completed",
               let response = object["response"],
               let text = extractPrimaryText(from: response),
               !text.isEmpty {
                return text
            }
        }

        if let delta = object["delta"] as? String, !delta.isEmpty {
            return delta
        }
        if let text = object["text"] as? String, !text.isEmpty {
            return text
        }
        return nil
    }

    func responsesResponseID(from object: [String: Any]) -> String? {
        if let response = object["response"] as? [String: Any],
           let id = response["id"] as? String,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id
        }
        if let id = object["response_id"] as? String,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return id
        }
        if let id = object["id"] as? String,
           !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           (object["type"] as? String)?.hasPrefix("response.") == true {
            return id
        }
        return nil
    }

    func responsesErrorMessage(from object: [String: Any]) -> String? {
        if let type = object["type"] as? String,
           type == "error" || type == "response.failed" {
            if let error = object["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }
            if let message = object["message"] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }
        }
        return nil
    }
}
