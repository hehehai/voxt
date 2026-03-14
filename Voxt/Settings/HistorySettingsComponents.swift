import SwiftUI
import AppKit

struct HistoryListSection: View {
    let historyEnabled: Bool
    let entries: [TranscriptionHistoryEntry]
    let hasMore: Bool
    let copiedEntryID: UUID?
    let onClearAll: () -> Void
    let onCopy: (TranscriptionHistoryEntry) -> Void
    let onDelete: (UUID) -> Void
    let onLoadNextPage: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("History")
                        .font(.headline)
                    Spacer()
                    Button("Clean All", role: .destructive, action: onClearAll)
                        .controlSize(.small)
                        .disabled(!historyEnabled || entries.isEmpty)
                }

                if !historyEnabled {
                    Text("History is currently disabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if entries.isEmpty {
                    Text("No history yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(entries) { entry in
                                HistoryRow(
                                    entry: entry,
                                    isCopied: copiedEntryID == entry.id,
                                    onCopy: { onCopy(entry) },
                                    onDelete: { onDelete(entry.id) }
                                )
                                .onAppear {
                                    if entry.id == entries.last?.id {
                                        onLoadNextPage()
                                    }
                                }
                            }

                            if hasMore {
                                Button("Load More", action: onLoadNextPage)
                                    .controlSize(.small)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct HistoryRow: View {
    @Environment(\.locale) private var locale

    let entry: TranscriptionHistoryEntry
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var showModelInfo = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onCopy) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(primaryDisplayText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(entry.kind == .assistant ? 2 : 3)

                    if let secondaryDisplayText, !secondaryDisplayText.isEmpty {
                        Text(secondaryDisplayText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        historyBadge
                        Text(metadataText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCopied {
                Text("Copied")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button {
                showModelInfo.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showModelInfo, arrowEdge: .trailing) {
                HistoryEntryDetailsPopover(entry: entry)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private var metadataText: String {
        let dateText = entry.createdAt.formatted(
            .dateTime
                .locale(locale)
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
        guard let audioDuration = formattedDuration(entry.audioDurationSeconds) else {
            return dateText
        }
        let format = NSLocalizedString("%@ · Audio: %@", comment: "")
        return String(format: format, locale: locale, dateText, audioDuration)
    }

    private var primaryDisplayText: String {
        if entry.kind == .assistant,
           let summary = entry.assistantSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }
        return entry.text
    }

    private var secondaryDisplayText: String? {
        guard entry.kind == .assistant else { return nil }
        let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = entry.assistantSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed != summary else { return nil }
        return AppLocalization.format("Spoken: %@", trimmed)
    }

    private var historyBadge: some View {
        Group {
            if entry.kind == .translation {
                Text("Translation")
            } else if entry.kind == .rewrite {
                Text("Rewrite")
            } else if entry.kind == .assistant {
                Text("Assistant")
            } else {
                Text("Normal")
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule(style: .continuous).fill(historyBadgeColor.opacity(0.16)))
        .foregroundStyle(historyBadgeColor)
    }

    private var historyBadgeColor: Color {
        switch entry.kind {
        case .normal:
            return .secondary
        case .translation:
            return .blue
        case .rewrite:
            return .orange
        case .assistant:
            return .green
        }
    }

    private func formattedDuration(_ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        if seconds < 1 {
            let format = NSLocalizedString("%d ms", comment: "")
            return String(format: format, locale: locale, Int(seconds * 1000))
        }
        if seconds < 60 {
            let format = NSLocalizedString("%.1f s", comment: "")
            return String(format: format, locale: locale, seconds)
        }
        let minutes = Int(seconds) / 60
        let remain = Int(seconds) % 60
        let format = NSLocalizedString("%dm %ds", comment: "")
        return String(format: format, locale: locale, minutes, remain)
    }
}

private struct HistoryEntryDetailsPopover: View {
    let entry: TranscriptionHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcription Details")
                .font(.headline)
            Text("Model Details")
                .font(.caption)
                .foregroundStyle(.secondary)
            detailLine(labelKey: "Engine", value: entry.transcriptionEngine)
            detailLine(labelKey: "Model", value: entry.transcriptionModel)
            optionalDetailLine(labelKey: "Remote ASR Provider", value: entry.remoteASRProvider)
            optionalDetailLine(labelKey: "Remote ASR Model", value: entry.remoteASRModel)
            optionalDetailLine(labelKey: "Remote ASR Endpoint", value: entry.remoteASREndpoint)
            detailLine(labelKey: "Enhancement", value: entry.enhancementMode)
            detailLine(labelKey: "Enhancer Model", value: entry.enhancementModel)
            optionalDetailLine(labelKey: "Remote LLM Provider", value: entry.remoteLLMProvider)
            optionalDetailLine(labelKey: "Remote LLM Model", value: entry.remoteLLMModel)
            optionalDetailLine(labelKey: "Remote LLM Endpoint", value: entry.remoteLLMEndpoint)
            optionalDetailLine(labelKey: "ASR Processing", value: formattedDuration(entry.transcriptionProcessingDurationSeconds))
            optionalDetailLine(labelKey: "LLM Duration", value: formattedDuration(entry.llmDurationSeconds))
            Divider()
            optionalDetailLine(labelKey: "Focused App", value: entry.focusedAppName)
            optionalDetailLine(labelKey: "App Group", value: entry.matchedAppGroupName)
            optionalDetailLine(labelKey: "URL Group", value: entry.matchedURLGroupName)
            optionalDetailLine(labelKey: "Assistant Summary", value: entry.assistantSummary)
            optionalDetailLine(labelKey: "Assistant Actions", value: entry.assistantActions?.joined(separator: "\n"))
            optionalDetailLine(labelKey: "Assistant Snapshot", value: entry.assistantSnapshotPath)
            if let snapshotURL {
                Button("Open Snapshot") {
                    NSWorkspace.shared.open(snapshotURL)
                }
                .controlSize(.small)
            }
            if let steps = entry.assistantStructuredSteps, !steps.isEmpty {
                assistantStepDetailsSection(steps)
            }
            if entry.kind == .assistant {
                Button("Create Recipe Draft") {
                    if let recipeName = try? ActionAssistantRecipeStore.createRecipeTemplate(
                        fromAssistantSummary: entry.assistantSummary ?? "",
                        spokenText: entry.text,
                        actions: entry.assistantActions ?? [],
                        structuredSteps: entry.assistantStructuredSteps ?? [],
                        focusedAppName: entry.focusedAppName
                    ) {
                        NSWorkspace.shared.open(ActionAssistantRecipeStore.recipeURL(named: recipeName))
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: 360)
    }

    private var snapshotURL: URL? {
        let trimmed = entry.assistantSnapshotPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let url = URL(fileURLWithPath: trimmed)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func detailLine(labelKey: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(labelKey)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private func optionalDetailLine(labelKey: LocalizedStringKey, value: String?) -> some View {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            detailLine(labelKey: labelKey, value: trimmed)
        }
    }

    private func assistantStepDetailsSection(_ steps: [AssistantHistoryStep]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assistant Steps")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(stepAccentColor(for: step))
                            .frame(width: 8, height: 8)
                        Rectangle()
                            .fill(Color.secondary.opacity(index == steps.count - 1 ? 0 : 0.2))
                            .frame(width: 1)
                    }
                    .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(index + 1). \(step.title)")
                            .font(.subheadline.weight(.medium))

                        if let action = step.action, !action.isEmpty {
                            detailLine(labelKey: "Action", value: action)
                        }

                        if let plannedTarget = plannedTargetSummary(for: step) {
                            detailLine(labelKey: "Planned Target", value: plannedTarget)
                        }

                        if let resolvedTarget = resolvedTargetSummary(for: step) {
                            detailLine(labelKey: "Resolved Target", value: resolvedTarget)
                        }

                        if let execution = executionSummary(for: step) {
                            detailLine(labelKey: "Execution", value: execution)
                        }

                        if let diagnosis = diagnosisSummary(for: step) {
                            detailLine(labelKey: "Diagnosis", value: diagnosis)
                        }

                        if let note = step.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                            detailLine(labelKey: "Step Note", value: note)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func plannedTargetSummary(for step: AssistantHistoryStep) -> String? {
        var parts: [String] = []
        if let targetApp = step.targetApp?.trimmingCharacters(in: .whitespacesAndNewlines), !targetApp.isEmpty {
            parts.append(AppLocalization.format("App: %@", targetApp))
        }
        if let targetLabel = step.targetLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !targetLabel.isEmpty {
            parts.append(AppLocalization.format("Label: %@", targetLabel))
        }
        if let targetRole = step.targetRole?.trimmingCharacters(in: .whitespacesAndNewlines), !targetRole.isEmpty {
            parts.append(AppLocalization.format("Role: %@", targetRole))
        }
        if let relativeX = step.relativeX, let relativeY = step.relativeY {
            parts.append(AppLocalization.format("Point: %.3f, %.3f", relativeX, relativeY))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func executionSummary(for step: AssistantHistoryStep) -> String? {
        var parts: [String] = []
        if let success = step.success {
            parts.append(success ? AppLocalization.localizedString("Success") : AppLocalization.localizedString("Failed"))
        }
        if let durationMs = step.durationMs {
            parts.append(AppLocalization.format("%d ms", durationMs))
        }
        if let error = step.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
            parts.append(error)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func diagnosisSummary(for step: AssistantHistoryStep) -> String? {
        var parts: [String] = []
        if let category = step.diagnosisCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
            parts.append(AppLocalization.format("Category: %@", category))
        }
        if let reason = step.diagnosisReason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            parts.append(reason)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func resolvedTargetSummary(for step: AssistantHistoryStep) -> String? {
        var parts: [String] = []
        if let targetLabel = step.resolvedTargetLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !targetLabel.isEmpty {
            parts.append(AppLocalization.format("Label: %@", targetLabel))
        }
        if let targetRole = step.resolvedTargetRole?.trimmingCharacters(in: .whitespacesAndNewlines), !targetRole.isEmpty {
            parts.append(AppLocalization.format("Role: %@", targetRole))
        }
        if let relativeX = step.resolvedRelativeX, let relativeY = step.resolvedRelativeY {
            parts.append(AppLocalization.format("Point: %.3f, %.3f", relativeX, relativeY))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func formattedDuration(_ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        if seconds < 1 {
            return AppLocalization.format("%d ms", Int(seconds * 1000))
        }
        if seconds < 60 {
            let format = NSLocalizedString("%.1f s", comment: "")
            return String(format: format, seconds)
        }
        return AppLocalization.format("%dm %ds", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func stepAccentColor(for step: AssistantHistoryStep) -> Color {
        if step.success == false {
            return .red
        }
        if step.success == true {
            return .green
        }
        return .secondary
    }
}
