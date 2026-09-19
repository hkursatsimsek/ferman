import CoreGraphics
import FermanCore
import FermanReplay

/// The battle's sound, worked out once from the result (ART-DIRECTION §7) — like the figures' motion
/// (D27), it's a function of replay time: `cues(after:through:)` says what the replay passed over between
/// two instants, and the scene plays it. Seeking skips over sounds rather than replaying them.
///
/// What's heard: every order the player wrote, taking effect — a paper "tık" and the action's own sound;
/// arrows released and landing; blows, falls, a line breaking, walls and charges. The enemy's orders are
/// silent, as they're spark-less (brief §3.2): the player listens to their own logic.
nonisolated struct BattleSoundscape: Sendable {
    struct Cue: Equatable, Sendable {
        let effect: SoundEffect
        /// -1 (the table's left edge) … 1 (its right edge).
        let pan: Float
        let volume: Float
        /// The paper tick of one of the player's own orders — the only battle sound that is also felt.
        var isPlayerOrder = false
    }

    private struct Timed: Sendable {
        let tick: Double
        let cue: Cue
    }

    /// A window longer than this is a seek or a stall, not playback, and stays silent.
    static let longestHeardWindowTicks: Double = 12
    /// At most this many of one sound per window — a crowded frame at 4× shouldn't stack twelve blows.
    static let perEffectLimit = 2

    private let timeline: [Timed]

    init(result: BattleResult, config: BattleConfig, motion: FigureMotion, projection: BoardProjection) {
        let width = max(projection.boardSize.width, 1)
        func pan(_ point: CGPoint) -> Float {
            Float((point.x / width) * 2 - 1) * 0.7
        }
        func pan(of unit: UnitID, at tick: Int32) -> Float {
            motion.figures[unit].map { pan($0.groundPoint(atTick: Double(tick))) } ?? 0
        }

        var teams: [UnitID: Team] = [:]
        var types: [UnitID: UnitTypeID] = [:]
        var timed: [Timed] = []
        for event in result.events {
            let tick = Double(event.tick)
            switch event.kind {
            case .spawn(let unit, let type, let team, _):
                teams[unit] = team
                types[unit] = type
            case .ruleActivated(let unit, let ruleIndex):
                guard teams[unit] == .player, let type = types[unit],
                    let rule = config.player.program(for: type)?.rules[safe: ruleIndex]
                else { continue }
                let position = pan(of: unit, at: event.tick)
                timed.append(Timed(tick: tick, cue: Cue(effect: .order, pan: position, volume: 0.8, isPlayerOrder: true)))
                if let effect = SoundEffect.action(rule.action.kind) {
                    // A flank is heard toward its side.
                    let lean: Float =
                        switch rule.action {
                        case .flankLeft: -0.4
                        case .flankRight: 0.4
                        default: 0
                        }
                    timed.append(
                        Timed(tick: tick, cue: Cue(effect: effect, pan: max(-1, min(1, position + lean)), volume: 0.7)))
                }
            case .attack(let attacker, let target, _):
                // Ranged blows are heard as their arrows (below); these are the melee ones.
                guard !(motion.figures[attacker]?.isRanged ?? false) else { continue }
                timed.append(Timed(tick: tick, cue: Cue(effect: .hit, pan: pan(of: target, at: event.tick), volume: 0.75)))
            case .abilityUsed(let unit, let ability):
                guard let effect = SoundEffect.ability(ability) else { continue }
                timed.append(Timed(tick: tick, cue: Cue(effect: effect, pan: pan(of: unit, at: event.tick), volume: 0.8)))
            case .death(let unit):
                timed.append(Timed(tick: tick, cue: Cue(effect: .fall, pan: pan(of: unit, at: event.tick), volume: 0.9)))
            case .moraleBroken(let unit):
                timed.append(Timed(tick: tick, cue: Cue(effect: .rout, pan: pan(of: unit, at: event.tick), volume: 0.7)))
            case .move, .moraleRecovered, .battleEnded:
                continue
            }
        }
        for flight in motion.flights {
            timed.append(Timed(tick: flight.launchTick, cue: Cue(effect: .release, pan: pan(flight.from), volume: 0.55)))
            timed.append(Timed(tick: flight.landTick, cue: Cue(effect: .land, pan: pan(flight.to), volume: 0.65)))
        }
        // Stable: cues of one tick keep the event stream's order.
        timeline = timed.enumerated().sorted { ($0.element.tick, $0.offset) < ($1.element.tick, $1.offset) }.map(\.element)
    }

    /// The cues in `(from, to]`, fractional replay ticks, at most `limit` of each sound. Empty when the
    /// window runs backwards or is too long to be playback.
    func cues(after from: Double, through to: Double, limit: Int = Self.perEffectLimit) -> [Cue] {
        guard to > from, to - from <= Self.longestHeardWindowTicks else { return [] }
        var low = 0
        var high = timeline.count
        while low < high {
            let middle = (low + high) / 2
            if timeline[middle].tick <= from { low = middle + 1 } else { high = middle }
        }
        var heard: [SoundEffect: Int] = [:]
        var result: [Cue] = []
        var index = low
        while index < timeline.count, timeline[index].tick <= to {
            let cue = timeline[index].cue
            index += 1
            guard heard[cue.effect, default: 0] < limit else { continue }
            heard[cue.effect, default: 0] += 1
            result.append(cue)
        }
        return result
    }
}

extension Array {
    nonisolated fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
