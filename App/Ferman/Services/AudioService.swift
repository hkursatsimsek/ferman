import AVFoundation
import os

/// One short, wordless effect. Not music, not narration — `.ambient` (F1.13's plan row) so it mixes
/// under whatever else is playing and respects the silent switch, matching a menu/incidental sound
/// rather than gameplay-critical audio.
enum SoundEffect: String, CaseIterable, Sendable {
    /// An order card stamping into the pre-battle stack (`BattleModel`'s choreography, brief §3.5).
    case stamp
    /// An order card settling after a reorder (`RuleEditorModel`, deferred from F1.7).
    case paper
}

@MainActor
protocol AudioPlaying {
    func play(_ effect: SoundEffect)
}

/// Used everywhere a model takes an `AudioPlaying` dependency but no real session should exist —
/// tests, previews, and fixtures that don't drive a real screen.
struct SilentAudioPlaying: AudioPlaying {
    func play(_ effect: SoundEffect) {}
}

/// **`stamp.wav`/`paper.wav` are placeholders**, procedurally generated (short sine thud / filtered
/// noise), not sound design — real SFX assets replace them without touching this type.
@MainActor
final class AudioService: AudioPlaying {
    static let shared = AudioService()

    private static let logger = Logger(subsystem: "com.hksimsek.FERMAN", category: "Audio")
    private var players: [SoundEffect: AVAudioPlayer] = [:]

    private init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Self.logger.error("Could not activate the ambient audio session: \(error, privacy: .public)")
        }
        for effect in SoundEffect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else {
                Self.logger.error("Missing sound asset for \(effect.rawValue, privacy: .public)")
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[effect] = player
            } catch {
                Self.logger.error("Could not load \(effect.rawValue, privacy: .public): \(error, privacy: .public)")
            }
        }
    }

    func play(_ effect: SoundEffect) {
        guard let player = players[effect] else { return }
        player.currentTime = 0
        player.play()
    }
}
