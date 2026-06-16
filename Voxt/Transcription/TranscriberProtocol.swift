// TranscriberProtocol.swift
// Provides Transcriber Protocol for transcription engines.

import Foundation
import Combine

/// Protocol that both SpeechTranscriber (Direct Dictation) and MLXTranscriber conform to.
/// Provides a unified interface for the AppDelegate to interact with either engine.
@MainActor
protocol TranscriberProtocol: ObservableObject {
    var isRecording: Bool { get }
    var audioLevel: Float { get }
    var transcribedText: String { get }
    var isEnhancing: Bool { get set }
    var isFinalizingTranscription: Bool { get }

    var onTranscriptionFinished: ((String) -> Void)? { get set }

    func requestPermissions() async -> Bool
    func startRecording()
    func stopRecording()
}
