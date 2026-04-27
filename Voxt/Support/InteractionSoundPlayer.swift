import AppKit

@MainActor
final class InteractionSoundPlayer {
    private let volume: Float = 0.22

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

    @discardableResult
    func playNote(preset: InteractionSoundPreset) -> TimeInterval {
        playPreview(preset: preset)
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
        let sound = NSSound(named: name) ?? NSSound(named: "Pop") ?? NSSound(named: "Tink")
        sound?.stop()
        sound?.volume = volume
        sound?.play()
        return sound?.duration ?? 0
    }
}
