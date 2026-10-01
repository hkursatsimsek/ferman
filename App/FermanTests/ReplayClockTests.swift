import FermanCore
import Observation
import Testing

@testable import Ferman

/// The battle screen's chrome observes the clock while `BattleScene` advances it every frame (G16): the
/// values the chrome reads must change — and notify — only when they really change.
@MainActor
struct ReplayClockTests {
    private static let ticksPerSecond = Int32(BattleConfig.ticksPerSecond)

    @Test
    func elapsedSecondsAndFinishFollowTheTicks() {
        let clock = ReplayClock(tickCount: Self.ticksPerSecond * 3)
        #expect(clock.elapsedSeconds == 0)
        #expect(!clock.isFinished)

        clock.advance(by: 1.5)
        #expect(clock.currentTick == Self.ticksPerSecond * 3 / 2)
        #expect(clock.elapsedSeconds == 1)

        clock.advance(by: 10)
        #expect(clock.isFinished)
        #expect(!clock.isPlaying)
        #expect(clock.elapsedSeconds == 3)

        clock.restart()
        #expect(!clock.isFinished)
        #expect(clock.isPlaying)
        #expect(clock.elapsedSeconds == 0)
    }

    @Test
    func anEmptyReplayStartsFinished() {
        #expect(ReplayClock(tickCount: 0).isFinished)
    }

    /// A frame that doesn't cross a second must not wake whatever shows the time.
    @Test
    func aFrameWithinTheSameSecondDoesNotNotifyTheTimeReaders() {
        let clock = ReplayClock(tickCount: Self.ticksPerSecond * 10)
        clock.advance(by: 0.2)
        let notified = Flag()
        withObservationTracking {
            _ = clock.elapsedSeconds
            _ = clock.isFinished
        } onChange: {
            // Called synchronously from the write, which happens on the main actor below.
            MainActor.assumeIsolated { notified.value = true }
        }

        clock.advance(by: 1.0 / 60)
        #expect(!notified.value)

        clock.advance(by: 1)
        #expect(notified.value)
    }

    @MainActor
    private final class Flag {
        var value = false
    }
}
