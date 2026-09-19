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

/// Ayarlar (design gap list, FERMAN-PLAN §10): minimal on purpose — sound, and the speed battles
/// start at. Haptics and reduced motion follow the system's own settings.
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

    init(defaults: UserDefaults = .standard, audio: any AudioPlaying = SilentAudioPlaying()) {
        self.defaults = defaults
        self.audio = audio
        soundEnabled = defaults.object(forKey: GameSettings.soundKey) as? Bool ?? true
        defaultSpeed = BattleSpeed(rawValue: defaults.integer(forKey: GameSettings.speedKey)) ?? .x1
    }
}
