import Foundation
import Combine

@MainActor
final class TranscriptionDetailViewModel: ObservableObject {
    typealias FollowUpStatusProvider = @MainActor (TranscriptionHistoryEntry) -> TranscriptionFollowUpProviderStatus
    typealias FollowUpAnswerer = @MainActor (TranscriptionHistoryEntry, [MeetingSummaryChatMessage], String) async throws -> String
    typealias FollowUpPersistence = @MainActor (UUID, [MeetingSummaryChatMessage]) -> TranscriptionHistoryEntry?

    @Published private(set) var entry: TranscriptionHistoryEntry
    @Published private(set) var audioURL: URL?
    @Published private(set) var chatMessages: [MeetingSummaryChatMessage]
    @Published private(set) var providerStatus: TranscriptionFollowUpProviderStatus
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var draft = ""

    private let followUpStatusProvider: FollowUpStatusProvider
    private let followUpAnswerer: FollowUpAnswerer
    private let followUpPersistence: FollowUpPersistence

    private var sendTask: Task<Void, Never>?

    init(
        entry: TranscriptionHistoryEntry,
        audioURL: URL?,
        followUpStatusProvider: @escaping FollowUpStatusProvider,
        followUpAnswerer: @escaping FollowUpAnswerer,
        followUpPersistence: @escaping FollowUpPersistence
    ) {
        self.entry = entry
        self.audioURL = audioURL
        self.chatMessages = entry.transcriptionChatMessages ?? []
        self.followUpStatusProvider = followUpStatusProvider
        self.followUpAnswerer = followUpAnswerer
        self.followUpPersistence = followUpPersistence
        self.providerStatus = followUpStatusProvider(entry)
    }

    deinit {
        sendTask?.cancel()
    }

    var title: String {
        let trimmedTitle = entry.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        return TranscriptionDetailSupport.title(for: entry.kind)
    }

    var createdAtText: String {
        entry.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    var headerMetaText: String {
        "\(createdAtText) · \(modelText)"
    }

    var modelText: String {
        let enhancementModel = entry.enhancementModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !enhancementModel.isEmpty, enhancementModel != "None" {
            return enhancementModel
        }

        let transcriptionModel = entry.transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcriptionModel.isEmpty {
            return transcriptionModel
        }

        return entry.transcriptionEngine
    }

    var canSend: Bool {
        providerStatus.isAvailable &&
        !isLoading &&
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayMessages: [MeetingSummaryChatMessage] {
        if chatMessages.first?.role == .assistant {
            return chatMessages
        }
        return [seedAssistantMessage] + chatMessages
    }

    func refresh(entry: TranscriptionHistoryEntry) {
        self.entry = entry
        self.chatMessages = entry.transcriptionChatMessages ?? []
        self.providerStatus = followUpStatusProvider(entry)
    }

    func refresh(entry: TranscriptionHistoryEntry, audioURL: URL?) {
        self.entry = entry
        self.audioURL = audioURL
        self.chatMessages = entry.transcriptionChatMessages ?? []
        self.providerStatus = followUpStatusProvider(entry)
    }

    func refreshProviderStatus() {
        providerStatus = followUpStatusProvider(entry)
    }

    func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        guard providerStatus.isAvailable else {
            errorMessage = providerStatus.message
            return
        }

        draft = ""
        errorMessage = nil

        let userMessage = MeetingSummaryChatMessage(role: .user, content: question)
        chatMessages.append(userMessage)
        _ = followUpPersistence(entry.id, chatMessages)
        isLoading = true

        let entrySnapshot = entry
        let historySnapshot = chatMessages

        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let answer = try await followUpAnswerer(
                    entrySnapshot,
                    historySnapshot,
                    question
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let assistantMessage = MeetingSummaryChatMessage(role: .assistant, content: answer)
                    self.chatMessages.append(assistantMessage)
                    self.isLoading = false
                    self.errorMessage = nil
                    _ = self.followUpPersistence(entrySnapshot.id, self.chatMessages)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                    _ = self.followUpPersistence(entrySnapshot.id, self.chatMessages)
                }
            }
        }
    }

    private var seedAssistantMessage: MeetingSummaryChatMessage {
        TranscriptionHistoryConversationSupport.seedMessage(for: entry)
    }
}
