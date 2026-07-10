// VoxtNotificationStore.swift
// Provides app notification loading for the home screen.

import Foundation
import Combine

struct VoxtAppNotification: Identifiable, Equatable {
    let id: String
    let title: String
    let content: String
    let coverImageURL: URL?
    let version: String
    let publishedAt: Date
}

@MainActor
final class VoxtNotificationStore: ObservableObject {
    @Published private(set) var notifications: [VoxtAppNotification] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var viewedNotificationIDs: Set<String>

    private let endpointURL: URL
    private let sessionProvider: @MainActor () -> URLSession
    private let userDefaults: UserDefaults
    private static let viewedNotificationIDsKey = "VoxtNotificationStore.viewedNotificationIDs"

    init(
        endpointURL: URL = URL(string: "http://localhost:3002/api/app/notifications")!,
        sessionProvider: @escaping @MainActor () -> URLSession = { VoxtNetworkSession.active },
        userDefaults: UserDefaults = .standard
    ) {
        self.endpointURL = endpointURL
        self.sessionProvider = sessionProvider
        self.userDefaults = userDefaults
        self.viewedNotificationIDs = Set(userDefaults.stringArray(forKey: Self.viewedNotificationIDsKey) ?? [])
    }

    var latestNotification: VoxtAppNotification? {
        notifications.first
    }

    var hasUnreadLatestNotification: Bool {
        guard let latestNotification else { return false }
        return !viewedNotificationIDs.contains(latestNotification.id)
    }

    func markAsViewed(_ notification: VoxtAppNotification?) {
        guard let notification else { return }
        guard !viewedNotificationIDs.contains(notification.id) else { return }
        var updatedViewedNotificationIDs = viewedNotificationIDs
        updatedViewedNotificationIDs.insert(notification.id)
        viewedNotificationIDs = updatedViewedNotificationIDs
        userDefaults.set(Array(viewedNotificationIDs), forKey: Self.viewedNotificationIDsKey)
    }

    func refreshIfNeeded() async {
        guard notifications.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            notifications = try await Self.fetchNotifications(
                endpointURL: endpointURL,
                session: sessionProvider()
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            VoxtLog.warning("Failed to load app notifications. error=\(error.localizedDescription)")
        }
    }

    private static func fetchNotifications(
        endpointURL: URL,
        session: URLSession
    ) async throws -> [VoxtAppNotification] {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            let fractionalISO8601Formatter = ISO8601DateFormatter()
            fractionalISO8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalISO8601Formatter.date(from: value) ?? iso8601Formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)"
            )
        }

        let payload = try decoder.decode(ResponsePayload.self, from: data)
        return payload.notifications
            .map(\.notification)
            .sorted { $0.publishedAt > $1.publishedAt }
    }

}

private struct ResponsePayload: Decodable {
    let notifications: [RemoteNotification]
}

private struct RemoteNotification: Decodable {
    let id: String
    let title: String
    let content: String
    let coverImage: URL?
    let version: String
    let publishedAt: Date

    var notification: VoxtAppNotification {
        VoxtAppNotification(
            id: id,
            title: title,
            content: content,
            coverImageURL: coverImage,
            version: version,
            publishedAt: publishedAt
        )
    }
}
