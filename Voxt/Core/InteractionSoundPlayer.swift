// InteractionSoundPlayer.swift
// Provides Interaction Sound Player for core app behavior.

import AVFoundation
import Foundation

@MainActor
final class InteractionSoundPlayer {
    private let volume: Float = 0.22
    private var activePlayer: AVAudioPlayer?

    @discardableResult
    func playStart() -> TimeInterval {
        let sounds = resolvedSounds(for: currentPreset())
        return play(named: sounds.start)
    }

    @discardableResult
    func playEnd() -> TimeInterval {
        let sounds = resolvedSounds(for: currentPreset())
        return play(named: sounds.end)
    }

    @discardableResult
    func playPreview(preset: InteractionSoundPreset) -> TimeInterval {
        let sounds = resolvedSounds(for: preset)
        return play(named: sounds.start)
    }

    func reset() {
        activePlayer?.stop()
        activePlayer = nil
    }

    private func currentPreset() -> InteractionSoundPreset {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.interactionSoundPreset) ?? ""
        return InteractionSoundPreset(rawValue: raw) ?? .soft
    }

    private func resolvedSounds(for preset: InteractionSoundPreset) -> (start: String, end: String) {
        switch preset {
        case .soft:
            return ("Pop", "Tink")
        case .glass:
            return ("Ping", "Ping")
        case .funk:
            return ("Morse", "Morse")
        case .submarine:
            return ("Submarine", "Submarine")
        case .basso:
            return ("Basso", "Basso")
        case .bottle:
            return ("Bottle", "Bottle")
        case .frog:
            return ("Frog", "Frog")
        case .hero:
            return ("Hero", "Hero")
        case .purr:
            return ("Purr", "Purr")
        case .sosumi:
            return ("Sosumi", "Sosumi")
        }
    }

    private func play(named name: String) -> TimeInterval {
        guard let url = soundURL(named: name) ?? soundURL(named: "Pop") ?? soundURL(named: "Tink") else {
            return 0
        }

        do {
            // Create a fresh player for every cue. NSSound(named:) may return a shared player
            // whose AudioUnit becomes stale after a long idle/sleep period. Calling stop/play on
            // that stale instance can produce kAudioUnitErr_InvalidElement and repeated audio.
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            guard player.play() else { return 0 }
            activePlayer = player
            return player.duration
        } catch {
            VoxtLog.audioWarning("Interaction sound failed to initialize. name=\(name), error=\(error.localizedDescription)")
            activePlayer = nil
            return 0
        }
    }

    private func soundURL(named name: String) -> URL? {
        let systemURL = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
            .appendingPathComponent(name)
            .appendingPathExtension("aiff")
        return FileManager.default.fileExists(atPath: systemURL.path) ? systemURL : nil
    }
}
