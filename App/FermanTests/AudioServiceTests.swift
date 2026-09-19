import AVFoundation
import FermanCore
import Testing

@testable import Ferman

/// Records what a model asked to hear, in order.
@MainActor
final class RecordingAudio: AudioPlaying {
    private(set) var played: [SoundEffect] = []
    private(set) var ambience: [Bool] = []
    private(set) var settingChanges = 0

    func play(_ effect: SoundEffect, pan: Float, volume: Float) {
        played.append(effect)
    }

    func setAmbience(_ playing: Bool) {
        ambience.append(playing)
    }

    func soundSettingDidChange() {
        settingChanges += 1
    }
}

@MainActor
@Suite("Audio service")
struct AudioServiceTests {
    @Test func silentAudioPlayingIsInert() {
        // Only asserts it doesn't throw or crash — there's nothing to observe from outside.
        let audio = SilentAudioPlaying()
        for effect in SoundEffect.allCases {
            audio.play(effect)
        }
        audio.setAmbience(true)
        audio.soundSettingDidChange()
    }

    /// Every variant of every sound is bundled, short, and in the one format all voices share — a missing
    /// or odd file would be skipped (logged, never thrown: sound is never allowed to break the game).
    @Test(arguments: SoundEffect.allCases)
    func everySoundIsBundledInTheVoicesFormat(effect: SoundEffect) throws {
        #expect(effect.fileNames.count == effect.variantCount)
        for name in effect.fileNames {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "wav"), "missing \(name).wav")
            let file = try AVAudioFile(forReading: url)
            #expect(file.processingFormat.channelCount == 1, "\(name)")
            #expect(file.processingFormat.sampleRate == 44_100, "\(name)")
            #expect(Double(file.length) / file.processingFormat.sampleRate < 1.5, "\(name)")
        }
    }

    @Test func theRoomsAmbienceIsALongLoop() throws {
        let url = try #require(Bundle.main.url(forResource: AudioService.ambienceFileName, withExtension: "wav"))
        let file = try AVAudioFile(forReading: url)
        #expect(Double(file.length) / file.processingFormat.sampleRate >= 10)
    }

    /// ART-DIRECTION §7: paper is soft, the seal medium, metal rigid — and the rest is heard, not felt.
    @Test func hapticsFollowWhatTheSoundIsMadeOf() {
        #expect(SoundEffect.paper.feel == .soft)
        #expect(SoundEffect.order.feel == .soft)
        #expect(SoundEffect.stamp.feel == .medium)
        #expect(SoundEffect.slip.feel == .medium)
        #expect(SoundEffect.place.feel == .rigid)
        for effect: SoundEffect in [.hit, .fall, .release, .land, .rout, .advance, .retreat, .charge] {
            #expect(effect.feel == nil, "\(effect)")
        }
    }

    /// "Close your eyes and still understand": every order has a sound of its own. The two flanks share
    /// one, panned to their side; `useAbility` is heard as the ability itself.
    @Test func everyActionSoundsDifferent() {
        #expect(SoundEffect.action(.useAbility) == nil)
        #expect(SoundEffect.action(.flankLeft) == SoundEffect.action(.flankRight))
        let sounds = ActionKind.allCases.filter { $0 != .useAbility && $0 != .flankRight }.compactMap(SoundEffect.action)
        #expect(sounds.count == ActionKind.allCases.count - 2)
        #expect(Set(sounds).count == sounds.count)
    }

    @Test func turningSoundOffInSettingsTellsTheAudio() {
        let defaults = UserDefaults(suiteName: "AudioServiceTests") ?? .standard
        defer { defaults.removePersistentDomain(forName: "AudioServiceTests") }
        let audio = RecordingAudio()
        let settings = SettingsModel(defaults: defaults, audio: audio)
        settings.soundEnabled = false
        #expect(audio.settingChanges == 1)
    }
}
