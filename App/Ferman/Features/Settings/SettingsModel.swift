import Foundation
import Observation

/// The few choices the player makes about the game itself, kept in `UserDefaults` — per device, not
/// progress (D14 syncs progress; these stay local).
enum GameSettings {
    static let soundKey = "settings.soundEnabled"
    static let speedKey = "settings.defaultSpeed"

    static var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true
    }

    /// The speed a battle starts at; the player can still change it while watching.
    static var defaultSpeed: BattleSpeed {
        BattleSpeed(rawValue: UserDefaults.standard.integer(forKey: speedKey)) ?? .x1
    }
}

/// Ayarlar (design gap list, FERMAN-PLAN §10): minimal on purpose — sound, the speed battles start at,
/// and the first fronts' notes back. Haptics and reduced motion follow the system's own settings.
@Observable
@MainActor
final class SettingsModel {
    private let defaults: UserDefaults
    private let audio: any AudioPlaying

    var soundEnabled: Bool {
        didSet {
            defaults.set(soundEnabled, forKey: GameSettings.soundKey)
            audio.soundSettingDidChange()
        }
    }

    var defaultSpeed: BattleSpeed {
        didSet { defaults.set(defaultSpeed.rawValue, forKey: GameSettings.speedKey) }
    }

    /// The first fronts' pencil notes come back from the next launch (TipKit clears its records only
    /// before it's configured — `TutorialNotes.configure`).
    private(set) var tutorialNotesWillReturn: Bool

    func showTutorialNotesAgain() {
        defaults.set(true, forKey: TutorialNotes.resetKey)
        tutorialNotesWillReturn = true
    }

    init(defaults: UserDefaults = .standard, audio: any AudioPlaying = SilentAudioPlaying()) {
        self.defaults = defaults
        self.audio = audio
        soundEnabled = defaults.object(forKey: GameSettings.soundKey) as? Bool ?? true
        defaultSpeed = BattleSpeed(rawValue: defaults.integer(forKey: GameSettings.speedKey)) ?? .x1
        tutorialNotesWillReturn = defaults.bool(forKey: TutorialNotes.resetKey)
    }
}
