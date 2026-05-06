import AVFoundation
import Combine
import SwiftUI

@MainActor
final class HistoryAudioPlaybackController: ObservableObject {
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false

    private var player: AVAudioPlayer?
    private var timer: Timer?

    init(audioURL: URL?) {
        loadAudio(audioURL)
    }

    deinit {
        timer?.invalidate()
    }

    var isAvailable: Bool {
        player != nil && duration > 0
    }

    func loadAudio(_ audioURL: URL?) {
        stopTimer()
        isPlaying = false
        currentTime = 0
        duration = 0
        player = nil

        guard let audioURL else { return }
        player = try? AVAudioPlayer(contentsOf: audioURL)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(time, duration))
        player.currentTime = clamped
        currentTime = clamped
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct HistoryAudioPlayerView: View {
    @ObservedObject var controller: HistoryAudioPlaybackController
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 10) {
                Button {
                    controller.togglePlayPause()
                } label: {
                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                        .background(
                            Circle()
                                .fill(Color.accentColor.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)

                Text(controller.isPlaying ? String(localized: "Playing") : String(localized: "Ready to play"))
                    .font(.system(size: compact ? 11 : 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text("\(formattedTime(controller.currentTime)) / \(formattedTime(controller.duration))")
                    .font(.system(size: compact ? 10 : 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { controller.currentTime },
                    set: { controller.seek(to: $0) }
                ),
                in: 0...max(controller.duration, 0.1)
            )
            .controlSize(compact ? .small : .regular)
            .disabled(!controller.isAvailable)
        }
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
