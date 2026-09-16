import FermanCore
import Foundation
import Observation

/// Maps wall-clock playback to a battle's tick timeline. Owned by whichever
/// SwiftUI screen presents a replay; `BattleScene` only reads it (D13).
@Observable
@MainActor
final class ReplayClock {
    let tickCount: Int32
    private(set) var currentTick: Int32 = 0
    /// A continuous tick position for interpolation; `currentTick` is its floor.
    private(set) var fractionalTick: Double = 0
    var isPlaying = true
    var speed: BattleSpeed = .x1

    private static let ticksPerSecond = Double(BattleConfig.ticksPerSecond)

    init(tickCount: Int32) {
        self.tickCount = max(tickCount, 0)
    }

    var isFinished: Bool { currentTick >= tickCount }

    func advance(by deltaTime: TimeInterval) {
        guard isPlaying, !isFinished, deltaTime > 0 else { return }
        let advanced = fractionalTick + deltaTime * Self.ticksPerSecond * Double(speed.rawValue)
        fractionalTick = min(advanced, Double(tickCount))
        currentTick = Int32(fractionalTick)
        if isFinished {
            isPlaying = false
        }
    }

    func seek(to tick: Int32) {
        let clamped = min(max(tick, 0), tickCount)
        currentTick = clamped
        fractionalTick = Double(clamped)
    }

    func restart() {
        seek(to: 0)
        isPlaying = true
    }

    func togglePlayPause() {
        guard !isFinished else { return }
        isPlaying.toggle()
    }
}
