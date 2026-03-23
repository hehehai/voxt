import Foundation

enum MeetingLiveSessionState: Equatable, Sendable {
    case connecting
    case active
    case paused
    case stopping
    case failed
}

struct MeetingLiveSessionPolicy: Equatable, Sendable {
    let idleKeepaliveEnabled: Bool
    let idleKeepaliveInterval: TimeInterval
    let idleKeepaliveFrameDuration: TimeInterval
    let providerIdleTimeoutSafetyWindow: TimeInterval
    let autoReconnectOnUnexpectedClose: Bool
    let prebufferDuration: TimeInterval
    let segmentSilenceSplitThreshold: TimeInterval

    static func resolved(
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> MeetingLiveSessionPolicy {
        switch provider {
        case .doubaoASR:
            return MeetingLiveSessionPolicy(
                idleKeepaliveEnabled: true,
                idleKeepaliveInterval: 3.0,
                idleKeepaliveFrameDuration: 0.2,
                providerIdleTimeoutSafetyWindow: 2.0,
                autoReconnectOnUnexpectedClose: true,
                prebufferDuration: 1.0,
                segmentSilenceSplitThreshold: 1.2
            )
        case .aliyunBailianASR:
            let isRealtimeModel = RemoteASRRealtimeSupport.isAliyunRealtimeModel(configuration.model)
            return MeetingLiveSessionPolicy(
                idleKeepaliveEnabled: isRealtimeModel,
                idleKeepaliveInterval: 3.0,
                idleKeepaliveFrameDuration: 0.2,
                providerIdleTimeoutSafetyWindow: 2.0,
                autoReconnectOnUnexpectedClose: isRealtimeModel,
                prebufferDuration: 1.0,
                segmentSilenceSplitThreshold: isRealtimeModel ? 1.2 : 0
            )
        case .openAIWhisper, .glmASR:
            return MeetingLiveSessionPolicy(
                idleKeepaliveEnabled: false,
                idleKeepaliveInterval: 0,
                idleKeepaliveFrameDuration: 0,
                providerIdleTimeoutSafetyWindow: 0,
                autoReconnectOnUnexpectedClose: false,
                prebufferDuration: 0,
                segmentSilenceSplitThreshold: 0
            )
        }
    }
}

struct MeetingLiveTranscriptState: Equatable, Sendable {
    private(set) var frozenTranscriptPrefix = ""
    private(set) var currentItemRawText: String?

    mutating func normalizedVisibleText(for incomingRawText: String) -> String {
        let trimmed = incomingRawText.trimmingCharacters(in: .whitespacesAndNewlines)
        currentItemRawText = trimmed.isEmpty ? nil : trimmed
        guard !trimmed.isEmpty else { return "" }

        if frozenTranscriptPrefix.isEmpty {
            return trimmed
        }

        if trimmed.hasPrefix(frozenTranscriptPrefix) {
            let suffixStart = trimmed.index(trimmed.startIndex, offsetBy: frozenTranscriptPrefix.count)
            return trimmedDuplicatePrefix(from: String(trimmed[suffixStart...]))
        }

        let canonicalFrozen = canonicalTranscriptPrefix(frozenTranscriptPrefix)
        let canonicalIncoming = canonicalTranscriptPrefix(trimmed)
        guard !canonicalFrozen.isEmpty,
              canonicalIncoming.hasPrefix(canonicalFrozen),
              let suffix = suffixAfterCanonicalPrefix(in: trimmed, canonicalPrefix: canonicalFrozen)
        else {
            return trimmed
        }
        return trimmedDuplicatePrefix(from: suffix)
    }

    mutating func freezeCurrentItem(text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            frozenTranscriptPrefix += trimmed
        }
        currentItemRawText = nil
    }

    mutating func resetCurrentItem() {
        currentItemRawText = nil
    }

    private func trimmedDuplicatePrefix(from rawSuffix: String) -> String {
        rawSuffix.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，。！？；：,.!?;:、"))
        )
    }

    private func canonicalTranscriptPrefix(_ text: String) -> String {
        let disallowed = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，。！？；：,.!?;:、\"'“”‘’()[]{}<>《》【】"))
        return text.unicodeScalars
            .filter { !disallowed.contains($0) }
            .map { CharacterSet.uppercaseLetters.contains($0) ? String($0).lowercased() : String($0) }
            .joined()
    }

    private func suffixAfterCanonicalPrefix(
        in text: String,
        canonicalPrefix: String
    ) -> String? {
        var matchedCount = 0
        let targetCount = canonicalPrefix.count
        guard targetCount > 0 else { return text }

        for index in text.indices {
            let character = String(text[index])
            let canonicalCharacter = canonicalTranscriptPrefix(character)
            if !canonicalCharacter.isEmpty {
                matchedCount += canonicalCharacter.count
            }
            if matchedCount >= targetCount {
                let nextIndex = text.index(after: index)
                return String(text[nextIndex...])
            }
        }

        return ""
    }
}

struct MeetingLiveProviderTranscriptUnit: Equatable, Sendable {
    let key: String?
    let startSeconds: TimeInterval?
    let endSeconds: TimeInterval?
    let text: String
    let isFinal: Bool
}

struct MeetingLiveProviderPacket: Equatable, Sendable {
    let units: [MeetingLiveProviderTranscriptUnit]
    let fallbackText: String?
    let isFinal: Bool
    let sequence: Int32?
}

struct MeetingLiveAudioPrebuffer: Sendable {
    struct Frame: Sendable {
        let samples: [Float]
        let sampleRate: Double

        var duration: TimeInterval {
            guard sampleRate > 0 else { return 0 }
            return Double(samples.count) / sampleRate
        }
    }

    private(set) var frames: [Frame] = []
    private(set) var maxDuration: TimeInterval

    init(maxDuration: TimeInterval) {
        self.maxDuration = max(0, maxDuration)
    }

    mutating func append(samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty, sampleRate > 0, maxDuration > 0 else { return }
        frames.append(Frame(samples: samples, sampleRate: sampleRate))
        trimIfNeeded()
    }

    mutating func removeAll() {
        frames.removeAll(keepingCapacity: false)
    }

    func snapshot() -> [Frame] {
        frames
    }

    private mutating func trimIfNeeded() {
        var duration = frames.reduce(0) { $0 + $1.duration }
        while duration > maxDuration, !frames.isEmpty {
            duration -= frames.removeFirst().duration
        }
    }
}
