import SwiftUI
import AVKit

struct OnboardingVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        view.videoGravity = .resizeAspect
        view.updatesNowPlayingInfoCenter = false
        player.pause()
        player.actionAtItemEnd = .pause
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        player.rate = 0
    }
}

struct OnboardingStatusBadge: View {
    let status: OnboardingStepStatus
    let isSelected: Bool

    var body: some View {
        Text(status.titleKey)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill((isSelected ? Color.white : status.tint).opacity(isSelected ? 0.16 : 0.12))
            )
            .foregroundStyle(isSelected ? Color.white : status.tint)
    }
}

struct OnboardingSummaryCard: View {
    let title: LocalizedStringKey
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))

            ForEach(lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct OnboardingExampleRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct LocalModelPickerCard<PickerContent: View>: View {
    let title: LocalizedStringKey
    let selectionTitle: String
    let selectionDescription: String
    let isInstalled: Bool
    let installLabel: LocalizedStringKey
    let openLabel: LocalizedStringKey
    let onChoose: () -> Void
    @ViewBuilder let pickerContent: () -> PickerContent
    let onInstall: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            pickerContent()

            Text(selectionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if isInstalled {
                    Text(selectionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Button(openLabel, action: onOpen)
                        .controlSize(.small)
                } else {
                    Text("Not installed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Button(installLabel, action: onInstall)
                        .controlSize(.small)
                }
            }
        }
    }
}

struct ProviderStatusRow: View {
    let title: String
    let status: String
    let onConfigure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Configure", action: onConfigure)
                    .controlSize(.small)
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}
