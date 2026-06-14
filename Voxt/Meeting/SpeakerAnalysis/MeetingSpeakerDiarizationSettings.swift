import Foundation

enum MeetingSpeakerDiarizationSensitivity: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case stable
    case balanced
    case sensitive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable:
            return AppLocalization.localizedString("Stable")
        case .balanced:
            return AppLocalization.localizedString("Balanced")
        case .sensitive:
            return AppLocalization.localizedString("Sensitive")
        }
    }

    var detail: String {
        switch self {
        case .stable:
            return AppLocalization.localizedString("Prefer fewer false speaker switches.")
        case .balanced:
            return AppLocalization.localizedString("Balance speaker recall and label stability.")
        case .sensitive:
            return AppLocalization.localizedString("Detect shorter speaker turns with a higher risk of extra speaker labels.")
        }
    }

    nonisolated static func stored(in defaults: UserDefaults = .standard) -> MeetingSpeakerDiarizationSensitivity {
        let rawValue = defaults.string(forKey: AppPreferenceKey.meetingSpeakerDiarizationSensitivity) ?? ""
        return MeetingSpeakerDiarizationSensitivity(rawValue: rawValue) ?? .balanced
    }

    nonisolated var minimumSpeakerConfidence: Double {
        switch self {
        case .stable:
            return 0.42
        case .balanced:
            return 0.28
        case .sensitive:
            return 0.18
        }
    }

    nonisolated var smootherOptions: MeetingSpeakerTurnSmoother.Options {
        switch self {
        case .stable:
            return .init(minimumTurnDurationSeconds: 1.2, sameSpeakerMergeGapSeconds: 1.8)
        case .balanced:
            return .init(minimumTurnDurationSeconds: 1.0, sameSpeakerMergeGapSeconds: 1.4)
        case .sensitive:
            return .init(minimumTurnDurationSeconds: 0.35, sameSpeakerMergeGapSeconds: 0.5)
        }
    }

    nonisolated var transcriptAssemblyOptions: MeetingSpeakerTranscriptAssembler.Options {
        switch self {
        case .stable:
            return .init(
                dominantSpeakerOverlapRatio: 0.94,
                minimumTurnOverlapSeconds: 0.22,
                minimumSecondarySpeakerOverlapSeconds: 1.4,
                minimumSecondarySpeakerOverlapRatio: 0.18,
                splitsSegmentsOnSpeakerBoundaries: false
            )
        case .balanced:
            return .init(
                dominantSpeakerOverlapRatio: 0.92,
                minimumTurnOverlapSeconds: 0.18,
                minimumSecondarySpeakerOverlapSeconds: 1.0,
                minimumSecondarySpeakerOverlapRatio: 0.14,
                splitsSegmentsOnSpeakerBoundaries: true
            )
        case .sensitive:
            return .init(
                dominantSpeakerOverlapRatio: 0.72,
                minimumTurnOverlapSeconds: 0.08,
                minimumSecondarySpeakerOverlapSeconds: 0.35,
                minimumSecondarySpeakerOverlapRatio: 0.04,
                splitsSegmentsOnSpeakerBoundaries: true
            )
        }
    }

    nonisolated var fluidAudioClusteringThreshold: Float {
        switch self {
        case .stable:
            return 0.82
        case .balanced:
            return 0.72
        case .sensitive:
            return 0.56
        }
    }

    nonisolated var fluidAudioMinimumSpeechDuration: Float {
        switch self {
        case .stable:
            return 1.2
        case .balanced:
            return 0.9
        case .sensitive:
            return 0.35
        }
    }

    nonisolated var fluidAudioMinimumEmbeddingUpdateDuration: Float {
        switch self {
        case .stable:
            return 2.4
        case .balanced:
            return 1.8
        case .sensitive:
            return 0.9
        }
    }

    nonisolated var fluidAudioMinimumActiveFramesCount: Float {
        switch self {
        case .stable:
            return 12.0
        case .balanced:
            return 9.0
        case .sensitive:
            return 4.0
        }
    }

    nonisolated var fluidAudioMinimumSilenceGap: Float {
        switch self {
        case .stable:
            return 1.1
        case .balanced:
            return 0.95
        case .sensitive:
            return 0.5
        }
    }

    nonisolated var fluidAudioOfflineClusteringThreshold: Double {
        switch self {
        case .stable:
            return 0.54
        case .balanced:
            return 0.62
        case .sensitive:
            return 0.70
        }
    }

    nonisolated var fluidAudioOfflineMinimumSegmentDuration: Double {
        switch self {
        case .stable:
            return 1.2
        case .balanced:
            return 0.8
        case .sensitive:
            return 0.45
        }
    }
}

enum MeetingSpeakerCountHint: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case auto
    case atLeastTwo
    case maxTwo
    case maxThree
    case maxFour
    case maxFive
    case maxSix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return AppLocalization.localizedString("Auto")
        case .atLeastTwo:
            return AppLocalization.localizedString("At least 2")
        case .maxTwo:
            return AppLocalization.localizedString("Max 2")
        case .maxThree:
            return AppLocalization.localizedString("Max 3")
        case .maxFour:
            return AppLocalization.localizedString("Max 4")
        case .maxFive:
            return AppLocalization.localizedString("Max 5")
        case .maxSix:
            return AppLocalization.localizedString("Max 6")
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .auto:
            return AppLocalization.localizedString("Let speaker analysis estimate the speaker count automatically.")
        case .atLeastTwo:
            return AppLocalization.localizedString("Prefer at least two detected speakers when the meeting has multiple active speakers.")
        case .maxTwo, .maxThree, .maxFour, .maxFive, .maxSix:
            return AppLocalization.localizedString("Use this as a maximum participant count hint. People who do not speak may not appear in the transcript.")
        }
    }

    nonisolated var offlineSpeakerBounds: (min: Int?, max: Int?) {
        switch self {
        case .auto:
            return (nil, nil)
        case .atLeastTwo:
            return (2, nil)
        case .maxTwo:
            return (1, 2)
        case .maxThree:
            return (1, 3)
        case .maxFour:
            return (1, 4)
        case .maxFive:
            return (1, 5)
        case .maxSix:
            return (1, 6)
        }
    }
}

enum MeetingDiarizationMode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case offlineVBx
    case sortformerV2

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sortformerV2:
            return AppLocalization.localizedString("Sortformer v2")
        case .offlineVBx:
            return AppLocalization.localizedString("Offline VBx")
        }
    }

    var detail: String {
        switch self {
        case .offlineVBx:
            return AppLocalization.localizedString("Use Offline VBx for final meeting speaker analysis.")
        case .sortformerV2:
            return AppLocalization.localizedString("Use NVIDIA Sortformer v2 for final meeting speaker analysis.")
        }
    }

    var fallbackRemoteSizeText: String {
        switch self {
        case .offlineVBx:
            return MeetingOfflineVBxModelStorage.fallbackRemoteSizeText
        case .sortformerV2:
            return MeetingVADModelStorage.sortformerFallbackRemoteSizeText
        }
    }

    nonisolated static func stored(in defaults: UserDefaults = .standard) -> MeetingDiarizationMode {
        let rawValue = defaults.string(forKey: AppPreferenceKey.meetingSpeakerDiarizationModel) ?? ""
        return MeetingDiarizationMode(rawValue: rawValue) ?? .offlineVBx
    }
}

struct MeetingSpeakerDiarizationOptions: Equatable, Sendable {
    var minimumAudioDurationSeconds: TimeInterval
    var minimumSpeakerConfidence: Double
    var smoothing: MeetingSpeakerTurnSmoother.Options
    var transcriptAssembly: MeetingSpeakerTranscriptAssembler.Options
    var sensitivity: MeetingSpeakerDiarizationSensitivity
    var speakerCountHint: MeetingSpeakerCountHint
    var debugLoggingEnabled: Bool

    nonisolated init(
        minimumAudioDurationSeconds: TimeInterval = 2.0,
        sensitivity: MeetingSpeakerDiarizationSensitivity = .balanced,
        speakerCountHint: MeetingSpeakerCountHint = .auto,
        minimumSpeakerConfidence: Double? = nil,
        smoothing: MeetingSpeakerTurnSmoother.Options? = nil,
        transcriptAssembly: MeetingSpeakerTranscriptAssembler.Options? = nil,
        debugLoggingEnabled: Bool = false
    ) {
        self.minimumAudioDurationSeconds = minimumAudioDurationSeconds
        self.sensitivity = sensitivity
        self.speakerCountHint = speakerCountHint
        self.minimumSpeakerConfidence = minimumSpeakerConfidence ?? sensitivity.minimumSpeakerConfidence
        self.smoothing = smoothing ?? sensitivity.smootherOptions
        self.transcriptAssembly = transcriptAssembly ?? sensitivity.transcriptAssemblyOptions
        self.debugLoggingEnabled = debugLoggingEnabled
    }

    static func fromPreferences(defaults: UserDefaults = .standard) -> MeetingSpeakerDiarizationOptions {
        let speakerCountHintRawValue = defaults.string(forKey: "meetingSpeakerCountHint") ?? ""
        return MeetingSpeakerDiarizationOptions(
            sensitivity: MeetingSpeakerDiarizationSensitivity.stored(in: defaults),
            speakerCountHint: MeetingSpeakerCountHint(rawValue: speakerCountHintRawValue) ?? .auto,
            debugLoggingEnabled: defaults.bool(forKey: AppPreferenceKey.meetingSpeakerDiarizationDebugEnabled)
        )
    }
}
