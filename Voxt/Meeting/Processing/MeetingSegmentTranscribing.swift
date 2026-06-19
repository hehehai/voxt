// MeetingSegmentTranscribing.swift
// Provides Meeting Segment Transcribing for meeting transcript processing.

import Foundation
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioSTT

protocol MeetingSegmentTranscribing {
    func transcribe(chunk: BufferedMeetingChunk) async -> MeetingTranscriptSegment?
    func cancelPendingWork() async
}

extension MeetingSegmentTranscribing {
    func cancelPendingWork() async {}
}

enum MeetingTranscriptSanitizer {
    static func sanitizedText(
        _ rawText: String,
        prompt: String? = nil,
        contextualPhrases: [String] = [],
        dictionaryEntries: [DictionaryEntry] = []
    ) -> String {
        let withoutContextLeakage = MLXTranscriptionPlanning.removingKnownASRContextLeakage(from: rawText)
        let normalized = MeetingTranscriptTextPostProcessor.normalizedFinalText(withoutContextLeakage)
        let withoutPromptEcho = RecordingSessionSupport.textAfterSuppressingPromptEcho(normalized, prompt: prompt)
        guard !withoutPromptEcho.isEmpty else { return "" }

        if isLikelyHintOnlyEcho(
            withoutPromptEcho,
            contextualPhrases: contextualPhrases,
            dictionaryEntries: dictionaryEntries
        ) {
            return ""
        }

        return withoutPromptEcho
    }

    private static func isLikelyHintOnlyEcho(
        _ text: String,
        contextualPhrases: [String],
        dictionaryEntries: [DictionaryEntry]
    ) -> Bool {
        let textKey = normalizedHintEchoKey(text)
        guard textKey.count >= 6 else { return false }

        let phraseKeys = hintPhraseKeys(
            contextualPhrases: contextualPhrases,
            dictionaryEntries: dictionaryEntries
        )
        guard !phraseKeys.isEmpty else { return false }

        if phraseKeys.contains(textKey), textKey.count >= 12 {
            return true
        }

        var remaining = textKey
        var matchedCount = 0
        var matchedCharacters = 0
        for phraseKey in phraseKeys.sorted(by: { $0.count > $1.count }) {
            guard phraseKey.count >= 3, remaining.contains(phraseKey) else { continue }
            let occurrences = remaining.components(separatedBy: phraseKey).count - 1
            guard occurrences > 0 else { continue }
            matchedCount += occurrences
            matchedCharacters += occurrences * phraseKey.count
            remaining = remaining.replacingOccurrences(of: phraseKey, with: "")
        }

        guard matchedCount >= 2 else { return false }
        let coverage = Double(matchedCharacters) / Double(max(textKey.count, 1))
        return coverage >= 0.72 && remaining.count <= max(6, textKey.count / 4)
    }

    private static func hintPhraseKeys(
        contextualPhrases: [String],
        dictionaryEntries: [DictionaryEntry]
    ) -> Set<String> {
        var keys = Set<String>()

        func insert(_ value: String) {
            let key = normalizedHintEchoKey(value)
            guard key.count >= 2 else { return }
            keys.insert(key)
        }

        contextualPhrases.forEach(insert)
        for entry in dictionaryEntries where entry.status == .active {
            insert(entry.term)
            entry.replacementTerms.map(\.text).forEach(insert)
        }

        return keys
    }

    private static func normalizedHintEchoKey(_ text: String) -> String {
        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
        let dropped = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        return String(normalized.unicodeScalars.filter { !dropped.contains($0) })
    }
}

actor MeetingRemoteTranscriptionGate {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            isBusy = false
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }

    func cancelAll() {
        isBusy = false
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
}

@MainActor
final class MeetingMLXSegmentTranscriber: MeetingSegmentTranscribing {
    private let mlxTranscriber: MLXTranscriber

    init(modelManager: MLXModelManager) {
        self.mlxTranscriber = MLXTranscriber(modelManager: modelManager)
        self.mlxTranscriber.dictionaryEntryProvider = {
            guard let appDelegate = AppDelegate.shared else { return [] }
            return appDelegate.dictionaryStore.activeEntriesForRemoteRequest(
                activeGroupID: appDelegate.activeDictionaryGroupID()
            )
        }
    }

    func transcribe(chunk: BufferedMeetingChunk) async -> MeetingTranscriptSegment? {
        guard let text = await mlxTranscriber.transcribeMeetingChunk(
            samples: chunk.samples,
            sampleRate: chunk.sampleRate
        ) else {
            return nil
        }
        let sanitizedText = MeetingTranscriptSanitizer.sanitizedText(
            text,
            dictionaryEntries: activeMeetingDictionaryEntries()
        )
        guard !sanitizedText.isEmpty else {
            VoxtLog.meetingWarning("Meeting MLX transcription suppressed because it matched ASR prompt or hint guidance.")
            return nil
        }
        return MeetingTranscriptSegment(
            id: chunk.segmentID,
            speaker: chunk.speaker,
            startSeconds: chunk.startSeconds,
            endSeconds: chunk.endSeconds,
            text: sanitizedText,
            preventsAdjacentMerge: chunk.preventsAdjacentMerge
        )
    }
}

@MainActor
final class MeetingRemoteASRSegmentTranscriber: MeetingSegmentTranscribing {
    private let transcriptionGate = MeetingRemoteTranscriptionGate()
    private let remoteTranscriber: RemoteASRTranscriber = {
        let transcriber = RemoteASRTranscriber()
        transcriber.doubaoDictionaryEntryProvider = {
            guard let appDelegate = AppDelegate.shared else { return [] }
            return appDelegate.dictionaryStore.activeEntriesForRemoteRequest(
                activeGroupID: appDelegate.activeDictionaryGroupID()
            )
        }
        return transcriber
    }()
    private var isCancelled = false

    func cancelPendingWork() async {
        isCancelled = true
        await transcriptionGate.cancelAll()
    }

    func transcribe(chunk: BufferedMeetingChunk) async -> MeetingTranscriptSegment? {
        guard !isCancelled else { return nil }
        await transcriptionGate.acquire()
        defer {
            Task {
                await transcriptionGate.release()
            }
        }
        guard !isCancelled else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Voxt-Meeting-Chunk-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        do {
            try MeetingAudioChunkWAVExporter.write(
                samples: chunk.samples,
                sampleRate: Int(chunk.sampleRate.rounded()),
                to: tempURL
            )
            let text = try await transcribeWithRetry(tempURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: tempURL)
            let hintPayload = currentHintPayload()
            let sanitizedText = MeetingTranscriptSanitizer.sanitizedText(
                text,
                prompt: hintPayload.prompt,
                contextualPhrases: hintPayload.contextualPhrases,
                dictionaryEntries: activeMeetingDictionaryEntries()
            )
            guard !sanitizedText.isEmpty else {
                VoxtLog.meetingWarning("Meeting Remote ASR transcription suppressed because it matched ASR prompt or hint guidance.")
                return nil
            }
            return MeetingTranscriptSegment(
                id: chunk.segmentID,
                speaker: chunk.speaker,
                startSeconds: chunk.startSeconds,
                endSeconds: chunk.endSeconds,
                text: sanitizedText,
                preventsAdjacentMerge: chunk.preventsAdjacentMerge
            )
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            VoxtLog.meetingError("Meeting Remote ASR transcription failed: \(error)")
            return nil
        }
    }

    private func transcribeWithRetry(_ fileURL: URL) async throws -> String {
        let configuration = remoteTranscriber.currentMeetingConfiguration()
        let retryLimit = configuration.provider == .doubaoASR ? 2 : 1
        var attempt = 0
        var lastError: Error?

        while attempt < retryLimit {
            try Task.checkCancellation()
            if isCancelled {
                throw CancellationError()
            }
            do {
                return try await remoteTranscriber.transcribeMeetingAudioFile(fileURL)
            } catch {
                if error is CancellationError || isCancelled || Task.isCancelled {
                    throw CancellationError()
                }
                lastError = error
                attempt += 1
                guard attempt < retryLimit, shouldRetry(error, provider: configuration.provider) else {
                    throw error
                }
                VoxtLog.meetingWarning(
                    "Meeting Remote ASR chunk retry scheduled. provider=\(configuration.provider.rawValue), attempt=\(attempt + 1)"
                )
                try? await Task.sleep(for: .milliseconds(220))
            }
        }

        throw lastError ?? NSError(
            domain: "Voxt.Meeting",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Meeting Remote ASR transcription failed."]
        )
    }

    private func shouldRetry(_ error: Error, provider: RemoteASRProvider) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == 57 {
            return true
        }

        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorTimedOut
            ].contains(nsError.code)
        }

        if provider == .doubaoASR {
            let description = nsError.localizedDescription.lowercased()
            return description.contains("socket is not connected")
        }

        return false
    }

    private func currentHintPayload() -> ResolvedASRHintPayload {
        let meetingConfiguration = remoteTranscriber.currentMeetingConfiguration()
        let settings = ASRHintSettingsStore.resolvedSettings(
            for: ASRHintTarget.from(engine: .remote, remoteProvider: meetingConfiguration.provider),
            rawValue: UserDefaults.standard.string(forKey: AppPreferenceKey.asrHintSettings)
        )
        let userLanguageCodes = UserMainLanguageOption.storedSelection(
            from: UserDefaults.standard.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
        return ASRHintResolver.resolve(
            target: ASRHintTarget.from(engine: .remote, remoteProvider: meetingConfiguration.provider),
            settings: settings,
            userLanguageCodes: userLanguageCodes,
            mlxModelRepo: meetingConfiguration.configuration.model,
            dictionaryTerms: DictionaryEntryCollection.asrPromptTermsText(from: activeMeetingDictionaryEntries())
        )
    }
}

@MainActor
private func activeMeetingDictionaryEntries() -> [DictionaryEntry] {
    guard let appDelegate = AppDelegate.shared else { return [] }
    return appDelegate.dictionaryStore.activeEntriesForRemoteRequest(
        activeGroupID: appDelegate.activeDictionaryGroupID()
    )
}
