import FermanCore
import Foundation
import Observation

/// Maps wall-clock playback to a battle's tick timeline. Owned by whichever
/// SwiftUI screen presents a replay; `BattleScene` only reads it (D13).
///
/// `BattleScene` advances it every display frame, so a SwiftUI view reading anything here would be
/// re-evaluated every frame. Only `fractionalTick` changes that often, and only the scene reads it; the
/// other properties are written only when their value actually changes — `elapsedSeconds` once a
/// second, `isFinished` once — so the screen's chrome can observe those instead.
@Observable
@MainActor
final class ReplayClock {
    let tickCount: Int32
    private(set) var currentTick: Int32 = 0
    /// A continuous tick position for interpolation; `currentTick` is its floor.
    private(set) var fractionalTick: Double = 0
    /// Whole seconds of battle time played — the top bar's clock.
    private(set) var elapsedSeconds = 0
    private(set) var isFinished: Bool
    var isPlaying = true
    var speed: BattleSpeed = .x1

    private static let ticksPerSecond = Double(BattleConfig.ticksPerSecond)

    init(tickCount: Int32) {
        self.tickCount = max(tickCount, 0)
        isFinished = self.tickCount == 0
    }

    func advance(by deltaTime: TimeInterval) {
        guard isPlaying, !isFinished, deltaTime > 0 else { return }
        let advanced = fractionalTick + deltaTime * Self.ticksPerSecond * Double(speed.rawValue)
        move(to: min(advanced, Double(tickCount)))
        if isFinished {
            isPlaying = false
        }
    }

    func seek(to tick: Int32) {
        move(to: Double(min(max(tick, 0), tickCount)))
    }

    func restart() {
        seek(to: 0)
        isPlaying = true
    }

    func togglePlayPause() {
        guard !isFinished else { return }
        isPlaying.toggle()
    }

    /// Compares before writing, so no observer is woken for a value that didn't change.
    private func move(to tick: Double) {
        fractionalTick = tick
        let wholeTick = Int32(tick)
        if wholeTick != currentTick { currentTick = wholeTick }
        let seconds = Int(wholeTick / Int32(BattleConfig.ticksPerSecond))
        if seconds != elapsedSeconds { elapsedSeconds = seconds }
        let finished = wholeTick >= tickCount
        if finished != isFinished { isFinished = finished }
    }
}
