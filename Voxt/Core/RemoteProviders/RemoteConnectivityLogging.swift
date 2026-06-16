// RemoteConnectivityLogging.swift
// Provides Remote Connectivity Logging for remote provider configuration.

import Foundation

enum RemoteProviderConnectivityTestLogging {
    static func sanitizedEndpointForLog(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "<default>" : trimmed
    }

    static func logHTTPRequest(context: String, request: URLRequest, bodyPreview: String) {
        let method = request.httpMethod ?? "GET"
        let url = redactedURLString(request.url)
        let headers = redactedHeaders(request.allHTTPHeaderFields ?? [:])
        VoxtLog.info(
            "Network test request. context=\(context), method=\(method), url=\(url), headers=\(headers), body=\(truncateLogText(bodyPreview, limit: 700))",
            verbose: true
        )
    }

    static func logHTTPResponse(context: String, response: HTTPURLResponse, data: Data) {
        let url = redactedURLString(response.url)
        let headers = redactedHeaders(response.allHeaderFields.reduce(into: [String: String]()) { partialResult, pair in
            partialResult[String(describing: pair.key)] = String(describing: pair.value)
        })
        let payload = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        VoxtLog.info(
            "Network test response. context=\(context), status=\(response.statusCode), url=\(url), headers=\(headers), body=\(truncateLogText(payload, limit: 700))",
            verbose: true
        )
    }

    private static func redactedHeaders(_ headers: [String: String]) -> String {
        let redacted = headers.reduce(into: [String: String]()) { partialResult, pair in
            let key = pair.key
            let lower = key.lowercased()
            if lower == "authorization" || lower == "x-api-key" || lower.contains("token") {
                partialResult[key] = "<redacted>"
            } else {
                partialResult[key] = pair.value
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "\(redacted)"
    }

    private static func redactedURLString(_ url: URL?) -> String {
        guard let url else { return "<nil>" }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.queryItems = components.queryItems?.map { item in
            let lower = item.name.lowercased()
            if lower == "key" || lower == "api_key" || lower.contains("token") {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }
        return components.string ?? url.absoluteString
    }

    private static func truncateLogText(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "...(truncated)"
    }
}
