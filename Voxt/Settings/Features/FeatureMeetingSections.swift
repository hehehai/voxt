// FeatureMeetingSections.swift
// Provides Feature Meeting Sections for feature settings.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum MeetingFileUploadState: Equatable {
    case idle
    case analyzing(fileName: String, progress: MeetingFileAnalysisProgress)
    case cancelling(fileName: String)
    case completed(fileName: String)
    case failed(fileName: String, message: String)

    var isAnalyzing: Bool {
        if case .analyzing = self { return true }
        return false
    }

    var isCancelling: Bool {
        if case .cancelling = self { return true }
        return false
    }

    var isBusy: Bool {
        isAnalyzing || isCancelling
    }
}

extension FeatureSettingsView {
    var meetingContent: some View {
        featurePage(
            title: "",
            subtitle: "",
            systemImageName: nil,
            pills: meetingPills
        ) {
            FeatureSettingsCard(title: "") {
                FeatureSettingSection(title: "", detail: "") {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Speech Model"),
                        value: asrSelectionSummary(featureSettings.meeting.asrSelectionID),
                        action: { selectorSheet = .meetingASR }
                    )
                }

                FeatureSettingSection(title: "", detail: "") {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Summary Model"),
                        value: llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID),
                        action: { selectorSheet = .meetingSummary }
                    )
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Hide Floating Window from Screen Sharing"),
                    detail: "",
                    isOn: binding(
                        get: { featureSettings.meeting.hideOverlayFromScreenSharing },
                        set: { featureSettings.meeting.hideOverlayFromScreenSharing = $0 }
                    )
                )

                FeatureToggleRow(
                    title: featureSettingsLocalized("Auto-generate Summary"),
                    detail: "",
                    isOn: binding(
                        get: { featureSettings.meeting.summaryAutoGenerate },
                        set: { featureSettings.meeting.summaryAutoGenerate = $0 }
                    )
                )

                meetingAdvancedSettingsSection
            }

            MeetingFileUploadCard(
                state: meetingFileUploadState,
                onChooseFile: chooseMeetingFileForAnalysis,
                onCancel: cancelMeetingFileAnalysis,
                onImportDroppedFile: importDroppedMeetingFileForAnalysis
            )
        }
    }

    func chooseMeetingFileForAnalysis() {
        guard !meetingFileUploadState.isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = featureSettingsLocalized("Analyze Meeting File")
        panel.prompt = featureSettingsLocalized("Choose File")
        panel.message = featureSettingsLocalized("Choose an audio or video recording to transcribe and analyze.")
        panel.allowedContentTypes = MeetingFileImportSupport.allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }
        startMeetingFileAnalysis(fileURL)
    }

    func importDroppedMeetingFileForAnalysis(_ fileURL: URL?) {
        guard let fileURL else {
            showMeetingFileImportToast(
                featureSettingsLocalized("Unsupported file type. Drop an audio or video recording instead.")
            )
            return
        }

        guard !meetingFileUploadState.isBusy else {
            showMeetingFileImportToast(
                featureSettingsLocalized("Meeting file analysis is already in progress.")
            )
            return
        }

        // Access the scoped drop URL before UTI/resource checks so sandboxed reads succeed.
        let didAccessSecurityScopedResource = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard MeetingFileImportSupport.isSupportedImportFile(at: fileURL) else {
            showMeetingFileImportToast(
                featureSettingsLocalized("Unsupported file type. Drop an audio or video recording instead.")
            )
            return
        }

        startMeetingFileAnalysis(fileURL)
    }

    func showMeetingFileImportToast(_ message: String) {
        NotificationCenter.default.post(
            name: .voxtFeatureSettingsToastRequested,
            object: nil,
            userInfo: ["message": message]
        )
    }

    func startMeetingFileAnalysis(_ fileURL: URL) {
        guard !meetingFileUploadState.isBusy else { return }
        let fileName = fileURL.lastPathComponent
        meetingFileUploadState = .analyzing(
            fileName: fileName,
            progress: MeetingFileAnalysisProgress(stage: .preparing)
        )
        SystemNotificationSupport.requestAuthorizationIfNeeded()
        meetingFileAnalysisTask = Task { @MainActor in
            defer { meetingFileAnalysisTask = nil }
            guard let appDelegate = AppDelegate.shared else {
                let message = featureSettingsLocalized("Voxt is not ready to analyze this file yet.")
                meetingFileUploadState = .failed(
                    fileName: fileName,
                    message: message
                )
                postMeetingFileConversionFailureNotification(fileName: fileName, message: message)
                return
            }

            do {
                let entry = try await appDelegate.analyzeImportedMeetingFile(
                    at: fileURL,
                    progress: { analysisProgress in
                        guard !Task.isCancelled, !meetingFileUploadState.isCancelling else { return }
                        meetingFileUploadState = .analyzing(
                            fileName: fileName,
                            progress: analysisProgress
                        )
                    }
                )
                guard !Task.isCancelled else {
                    meetingFileUploadState = .idle
                    return
                }
                meetingFileUploadState = .completed(fileName: fileName)
                postMeetingFileConversionSuccessNotification(fileName: fileName)
                appDelegate.showMeetingDetailWindow(for: entry)
            } catch is CancellationError {
                meetingFileUploadState = .idle
            } catch {
                meetingFileUploadState = .failed(
                    fileName: fileName,
                    message: error.localizedDescription
                )
                postMeetingFileConversionFailureNotification(
                    fileName: fileName,
                    message: error.localizedDescription
                )
            }
        }
    }

    func postMeetingFileConversionSuccessNotification(fileName: String) {
        SystemNotificationSupport.post(
            title: featureSettingsLocalized("File conversion succeeded"),
            body: AppLocalization.format("%@ has been converted successfully.", fileName)
        )
    }

    func postMeetingFileConversionFailureNotification(fileName: String, message: String) {
        let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = detail.isEmpty ? fileName : "\(fileName): \(detail)"
        SystemNotificationSupport.post(
            title: featureSettingsLocalized("File conversion failed"),
            body: body
        )
    }

    func cancelMeetingFileAnalysis() {
        guard case let .analyzing(fileName, _) = meetingFileUploadState else { return }
        meetingFileUploadState = .cancelling(fileName: fileName)
        meetingFileAnalysisTask?.cancel()
        Task { @MainActor in
            await AppDelegate.shared?.cancelImportedMeetingFileAnalysis()
        }
    }

    var meetingAdvancedSettingsSection: some View {
        GeneralAdvancedCard(isExpanded: $isMeetingAdvancedSettingsExpanded) {
            FeatureSettingSection(title: "", detail: "") {
                FeatureInlinePickerRow(
                    title: featureSettingsLocalized("Segmentation Mode"),
                    detail: meetingChunkingMode.wrappedValue.detail
                ) {
                    SettingsMenuPicker(
                        selection: meetingChunkingMode,
                        options: MeetingChunkingMode.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title)
                        },
                        selectedTitle: meetingChunkingMode.wrappedValue.title,
                        width: 220
                    )
                }

                FeatureInlinePickerRow(
                    title: featureSettingsLocalized("Silero Speech Detection"),
                    detail: meetingSileroVADSensitivity.wrappedValue.detail
                ) {
                    SettingsMenuPicker(
                        selection: meetingSileroVADSensitivity,
                        options: MeetingSileroVADSensitivity.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title)
                        },
                        selectedTitle: meetingSileroVADSensitivity.wrappedValue.title,
                        width: 220
                    )
                }

                FeatureInlinePickerRow(
                    title: featureSettingsLocalized("Speaker Separation Model"),
                    detail: meetingSpeakerDiarizationModelDetailText
                ) {
                    SettingsMenuPicker(
                        selection: meetingSpeakerDiarizationModel,
                        options: MeetingDiarizationMode.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title)
                        },
                        selectedTitle: meetingSpeakerDiarizationModel.wrappedValue.title,
                        width: 220,
                        leadingAccessory: meetingSpeakerDiarizationModelLeadingAccessory,
                        selectedStatusSystemImageName: meetingSpeakerDiarizationModelStatusIconName
                    )
                }
            }
        }
    }

    var meetingPills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(
                title: featureSettingsLocalized("Audio Model"),
                value: shortSummary(asrSelectionSummary(featureSettings.meeting.asrSelectionID), maxLength: 52)
            ),
            FeatureSummaryPill(
                title: featureSettingsLocalized("Summary Model"),
                value: shortSummary(llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID), maxLength: 52)
            ),
            FeatureSummaryPill(
                title: featureSettingsLocalized("Speakers"),
                value: featureSettings.meeting.speakerDiarizationModel.title
            )
        ]
    }

    @ViewBuilder
    var meetingSpeakerDiarizationModelDownloadControl: some View {
        switch meetingDiarizationModelManager.state {
        case .downloaded:
            EmptyView()
        case .notDownloaded:
            ProgressView(value: 0)
                .frame(width: 60)
        case let .downloading(progress, _):
            ProgressView(value: max(0, min(progress, 1)))
                .frame(width: 60)
        case .error:
            Button(featureSettingsLocalized("Retry")) {
                meetingDiarizationModelManager.downloadSelectedModel()
            }
            .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 9, height: 28))
        }
    }

    var meetingSpeakerDiarizationModelDetailText: String {
        switch meetingDiarizationModelManager.state {
        case .downloaded:
            return AppLocalization.format(
                "%@ %@",
                meetingSpeakerDiarizationModel.wrappedValue.title,
                featureSettingsLocalized("model is ready.")
            )
        case .notDownloaded:
            return AppLocalization.format(
                "%@ %@",
                meetingSpeakerDiarizationModel.wrappedValue.detail,
                featureSettingsLocalized("Download the model before meeting details can use speaker separation.")
            )
        case let .downloading(_, detail):
            return detail ?? featureSettingsLocalized("Installing speaker separation model...")
        case let .error(message):
            return AppLocalization.format("Download failed: %@", message)
        }
    }

    var meetingSpeakerDiarizationModelStatusIconName: String? {
        if case .downloaded = meetingDiarizationModelManager.state {
            return "checkmark.circle.fill"
        }
        return nil
    }

    var meetingSpeakerDiarizationModelLeadingAccessory: AnyView? {
        switch meetingDiarizationModelManager.state {
        case .downloaded:
            return nil
        case .notDownloaded, .downloading, .error:
            return AnyView(meetingSpeakerDiarizationModelDownloadControl)
        }
    }

    var meetingChunkingMode: Binding<MeetingChunkingMode> {
        Binding(
            get: {
                featureSettings.meeting.chunkingMode
            },
            set: { mode in
                featureSettings.meeting.chunkingModeRawValue = mode.rawValue
                saveFeatureSettings()
            }
        )
    }

    var meetingSpeakerDiarizationModel: Binding<MeetingDiarizationMode> {
        Binding(
            get: {
                featureSettings.meeting.speakerDiarizationModel
            },
            set: { mode in
                featureSettings.meeting.speakerDiarizationModelRawValue = mode.rawValue
                saveFeatureSettings()
                meetingDiarizationModelManager.refresh()
                meetingDiarizationModelManager.ensureSelectedModelInstalled()
            }
        )
    }

    var meetingSileroVADSensitivity: Binding<MeetingSileroVADSensitivity> {
        Binding(
            get: {
                featureSettings.meeting.sileroVADSensitivity
            },
            set: { sensitivity in
                featureSettings.meeting.sileroVADSensitivityRawValue = sensitivity.rawValue
                saveFeatureSettings()
            }
        )
    }

}

private struct MeetingFileUploadCard: View {
    let state: MeetingFileUploadState
    let onChooseFile: () -> Void
    let onCancel: () -> Void
    let onImportDroppedFile: (URL?) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(featureSettingsLocalized("Analyze a Meeting Recording"))
                        .font(.headline.weight(.semibold))
                    Text(featureSettingsLocalized("Upload a recording to create a transcript, identify speakers, and open the full meeting analysis."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if state.isBusy {
                    Button(
                        featureSettingsLocalized(state.isCancelling ? "Cancelling…" : "Cancel"),
                        action: onCancel
                    )
                    .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 13, height: 30))
                    .disabled(state.isCancelling)
                } else {
                    Button(featureSettingsLocalized("Upload File"), action: onChooseFile)
                        .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 13, height: 30))
                }
            }

            Button(action: onChooseFile) {
                uploadPlaceholder
            }
            .buttonStyle(.plain)
            .disabled(state.isBusy)
            .accessibilityLabel(featureSettingsLocalized("Upload a meeting audio or video file"))
        }
        .padding(16)
        .settingsPanelSurface()
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    @ViewBuilder
    private var uploadPlaceholder: some View {
        VStack(spacing: 9) {
            switch state {
            case .idle:
                Image(systemName: isDropTargeted ? "arrow.down.doc" : "arrow.up.doc")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text(
                    featureSettingsLocalized(
                        isDropTargeted
                            ? "Drop to analyze this recording"
                            : "Click to choose or drag in a meeting recording"
                    )
                )
                    .font(.subheadline.weight(.medium))
                supportedFormats
            case let .analyzing(fileName, progress):
                HStack(spacing: 12) {
                    Text(progress.stage.title)
                        .font(.subheadline.weight(.medium))

                    Spacer(minLength: 12)

                    Text(progress.percentageText)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 360)

                ProgressView(value: progress.fractionCompleted, total: 1)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .frame(maxWidth: 360)
                    .accessibilityLabel(Text(progress.stage.title))
                    .accessibilityValue(Text(progress.percentageText))

                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case let .cancelling(fileName):
                ProgressView()
                    .controlSize(.small)
                Text(featureSettingsLocalized("Cancelling…"))
                    .font(.subheadline.weight(.medium))
                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case let .completed(fileName):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.green)
                Text(featureSettingsLocalized("Analysis complete. Opening Meeting Details…"))
                    .font(.subheadline.weight(.medium))
                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case let .failed(fileName, message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.orange)
                Text(featureSettingsLocalized("File analysis failed"))
                    .font(.subheadline.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(fileName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 104)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .fill(
                    isDropTargeted
                        ? Color.accentColor.opacity(0.08)
                        : SettingsUIStyle.groupedFillColor.opacity(0.55)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .stroke(
                    (state.isAnalyzing || isDropTargeted)
                        ? Color.accentColor.opacity(isDropTargeted ? 0.72 : 0.42)
                        : SettingsUIStyle.controlHoverBorderColor,
                    style: StrokeStyle(lineWidth: isDropTargeted ? 1.5 : 1, dash: [6, 5])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
    }

    private var supportedFormats: some View {
        Text(featureSettingsLocalized("Supports MP3, MP4, M4A, WAV, AAC, MOV, and other common audio or video formats."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let fileURL = MeetingFileImportSupport.fileURL(fromDropItem: item)
            Task { @MainActor in
                onImportDroppedFile(fileURL)
            }
        }
        return true
    }
}

private extension MeetingFileAnalysisStage {
    var title: String {
        switch self {
        case .preparing:
            return featureSettingsLocalized("Preparing audio…")
        case .transcribing:
            return featureSettingsLocalized("Transcribing meeting…")
        case .identifyingSpeakers:
            return featureSettingsLocalized("Identifying speakers…")
        case .saving:
            return featureSettingsLocalized("Saving analysis…")
        }
    }
}

private extension MeetingFileAnalysisProgress {
    var percentageText: String {
        "\(Int((fractionCompleted * 100).rounded()))%"
    }
}
