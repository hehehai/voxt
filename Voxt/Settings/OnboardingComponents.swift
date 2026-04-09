import SwiftUI
import AVKit

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

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
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
    }
}

struct OnboardingPermissionStatusBadge: View {
    let isGranted: Bool

    var body: some View {
        Text(isGranted ? LocalizedStringKey("Enabled") : LocalizedStringKey("Disabled"))
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill((isGranted ? Color.green : Color.orange).opacity(0.16))
            )
            .foregroundStyle(isGranted ? Color.green : Color.orange)
    }
}

struct OnboardingTabItem<Value: Hashable & Sendable>: Identifiable {
    let value: Value
    let title: LocalizedStringKey

    var id: String { String(describing: value) }
}

struct OnboardingSegmentedTabs<Value: Hashable & Sendable>: View {
    @Binding var selection: Value
    let items: [OnboardingTabItem<Value>]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button {
                    selection = item.value
                } label: {
                    Text(item.title)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(SettingsSegmentedButtonStyle(isSelected: selection == item.value))
            }
        }
        .padding(2)
        .fixedSize(horizontal: true, vertical: false)
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
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
    var showsCardSurface: Bool = true
    var isInstalling: Bool = false
    let installLabel: LocalizedStringKey
    let openLabel: LocalizedStringKey
    var downloadStatus: ModelDownloadStatusSnapshot? = nil
    var errorMessage: String? = nil
    let onChoose: () -> Void
    @ViewBuilder let pickerContent: () -> PickerContent
    let onInstall: () -> Void
    let onOpen: () -> Void
    var onCancel: (() -> Void)? = nil

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
                        .buttonStyle(SettingsPillButtonStyle())
                } else if isInstalling {
                    Text(localized("Downloading"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    if let onCancel {
                        Button(localized("Cancel"), action: onCancel)
                            .buttonStyle(SettingsPillButtonStyle())
                    }
                } else {
                    Text(localized("Not installed"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Button(installLabel, action: onInstall)
                        .buttonStyle(SettingsPillButtonStyle())
                }
            }

            if let downloadStatus {
                ModelDownloadStatusView(status: downloadStatus)
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(LocalModelPickerCardSurfaceModifier(isEnabled: showsCardSurface))
    }
}

private struct LocalModelPickerCardSurfaceModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .padding(12)
                .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
        } else {
            content
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
                Button(localized("Configure"), action: onConfigure)
                    .buttonStyle(SettingsPillButtonStyle())
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .settingsCardSurface(cornerRadius: SettingsUIStyle.compactCornerRadius, fillOpacity: 1)
    }
}
