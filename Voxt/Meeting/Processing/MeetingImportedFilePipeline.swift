import Foundation

/// Resource owner for one file import. It never mutates the live meeting's
/// transcriber, engine selection or model-use fields.
@MainActor
final class MeetingImportedFilePipeline: MeetingImportedFileAnalyzing {
    private let modelManager: MLXModelManager
    private let engineContext: MeetingASREngineContext
    private var transcriber: (any MeetingSegmentTranscribing)?
    private var holdsModelUse = false
    private var preparedAudioURL: URL?

    init(modelManager: MLXModelManager, engineContext: MeetingASREngineContext) {
        self.modelManager = modelManager
        self.engineContext = engineContext
    }

    func analyze(
        at sourceURL: URL,
        progress: @escaping @MainActor @Sendable (MeetingFileAnalysisProgress) -> Void
    ) async throws -> MeetingSessionResult {
        try Task.checkCancellation()
        progress(MeetingFileAnalysisProgress(stage: .preparing))
        do {
            let preparationTask = Task.detached(priority: .utility) {
                try await MeetingImportedAudioFile.prepare(from: sourceURL) { fraction in
                    await progress(
                        MeetingFileAnalysisProgress(
                            stage: .preparing,
                            stageFraction: fraction
                        )
                    )
                }
            }
            let importedAudio = try await withTaskCancellationHandler {
                try await preparationTask.value
            } onCancel: {
                preparationTask.cancel()
            }
            preparedAudioURL = importedAudio.standardizedAudioURL
            try Task.checkCancellation()

            progress(
                MeetingFileAnalysisProgress(
                    stage: .preparing,
                    stageFraction: 1,
                    mediaDurationSeconds: importedAudio.durationSeconds
                )
            )

            progress(MeetingFileAnalysisProgress(stage: .transcribing))
            let importedTranscriber = try makeTranscriber()
            transcriber = importedTranscriber
            try Task.checkCancellation()

            let transcriptSegments = try await MeetingFinalTranscriptionPass.transcribe(
                descriptors: importedAudio.assetDescriptors,
                loadAsset: { descriptor in
                    importedAudio.loadAsset(descriptor)
                },
                transcriber: importedTranscriber,
                requiresCompleteTranscription: true,
                processedDurationProgress: { fraction, processedDuration in
                    await progress(
                        MeetingFileAnalysisProgress(
                            stage: .transcribing,
                            stageFraction: fraction,
                            mediaDurationSeconds: importedAudio.durationSeconds,
                            processedMediaDurationSeconds: processedDuration
                        )
                    )
                }
            )
            try Task.checkCancellation()
            guard !MeetingTranscriptFormatter.meaningfulSegments(for: transcriptSegments).isEmpty else {
                throw MeetingFileAnalysisError.noTranscript
            }

            progress(MeetingFileAnalysisProgress(stage: .identifyingSpeakers))
            let finalSegments: [MeetingTranscriptSegment]
            do {
                finalSegments = try await MeetingLocalInferenceCoordinator.shared.withPermit(.speakerAnalysis) {
                    await MeetingSpeakerAnalysisPipeline.analyzedSegments(
                        from: transcriptSegments,
                        descriptors: importedAudio.assetDescriptors,
                        loadAsset: { descriptor in
                            importedAudio.loadAsset(descriptor)
                        },
                        continuousAudioURL: importedAudio.standardizedAudioURL,
                        options: MeetingSpeakerDiarizationOptions.fromPreferences(),
                        progress: { fraction in
                            await progress(
                                MeetingFileAnalysisProgress(
                                    stage: .identifyingSpeakers,
                                    stageFraction: fraction
                                )
                            )
                        }
                    )
                }
            } catch {
                VoxtLog.meetingWarning(
                    "Imported meeting speaker analysis skipped by device safety policy: \(error.localizedDescription)"
                )
                finalSegments = MeetingTranscriptPostProcessor.process(transcriptSegments)
            }
            try Task.checkCancellation()

            progress(MeetingFileAnalysisProgress(stage: .saving))
            let result = MeetingSessionResult(
                captureMode: .meeting,
                transcriptionEngine: engineContext.engine,
                transcriptionModelDescription: engineContext.historyModelDescription,
                segments: finalSegments,
                visibleSnapshotSegments: finalSegments,
                audioDurationSeconds: importedAudio.durationSeconds,
                archivedAudioURL: importedAudio.standardizedAudioURL
            )
            return result
        } catch {
            if let preparedAudioURL {
                try? FileManager.default.removeItem(at: preparedAudioURL)
            }
            throw error
        }
    }

    private func makeTranscriber() throws -> any MeetingSegmentTranscribing {
        switch engineContext.engine {
        case .mlxAudio:
            modelManager.beginActiveUse()
            holdsModelUse = true
            return MeetingMLXSegmentTranscriber(modelManager: modelManager, strictInferenceWorkClass: .fileASR)
        case .remote:
            return MeetingRemoteASRSegmentTranscriber()
        case .dictation:
            throw NSError(domain: "Voxt.Meeting", code: -1, userInfo: [NSLocalizedDescriptionKey: "Direct Dictation is not supported for Meeting Notes."])
        }
    }

    func cancel() async {
        await transcriber?.cancelPendingWork()
    }

    func finish(keepingResult: Bool) async {
        await transcriber?.cancelPendingWork()
        transcriber = nil
        if holdsModelUse {
            holdsModelUse = false
            modelManager.endActiveUse()
        }
        if !keepingResult || Task.isCancelled, let preparedAudioURL {
            try? FileManager.default.removeItem(at: preparedAudioURL)
            self.preparedAudioURL = nil
        }
    }
}
