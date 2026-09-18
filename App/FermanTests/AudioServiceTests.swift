import Foundation
import Testing

@testable import Ferman

@MainActor
@Suite("Audio service")
struct AudioServiceTests {
    @Test func silentAudioPlayingIsInert() {
        // Only asserts it doesn't throw or crash — there's nothing to observe from outside.
        let audio = SilentAudioPlaying()
        for effect in SoundEffect.allCases {
            audio.play(effect)
        }
    }

    /// Every `SoundEffect` needs a same-named `.wav` bundled with the app, or `AudioService.play(_:)`
    /// silently does nothing (logged, not thrown — SFX is never allowed to break gameplay).
    @Test func everySoundEffectHasABundledAsset() {
        for effect in SoundEffect.allCases {
            #expect(Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") != nil, "\(effect)")
        }
    }
}
