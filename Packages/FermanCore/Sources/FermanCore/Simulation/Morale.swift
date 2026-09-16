/// One unit's morale and, once it has broken, how much longer the forced scatter lasts (§5.2.6).
struct MoraleState: Sendable, Hashable {
    var morale: Int
    var brokenTicksRemaining: Int

    var isBroken: Bool { brokenTicksRemaining > 0 }
}

/// A morale-changing thing that happened to a unit this tick. The caller may repeat a case — two nearby deaths in
/// the same tick are two `allyDiedNearby` entries, and both penalties apply.
enum MoraleEvent: Sendable, Hashable {
    case allyDiedNearby
    case commanderDied
    case flanked
}

enum Morale {
    static func isRegenerationTick(_ tick: Int) -> Bool {
        tick % BattleConfig.ticksPerSecond == 0
    }

    /// One tick of morale (§5.2.6). A broken unit ignores every input but the clock: it stays scattered until
    /// `brokenTicksRemaining` reaches zero, at which point morale is set to `moraleRecoveredPercent` of `moraleMax`
    /// outright, not regenerated gradually up to it.
    static func step(
        _ state: MoraleState, events: [MoraleEvent], noEnemyNearby: Bool, tick: Int, moraleMax: Int,
        tuning: SimulationTuning
    ) -> (state: MoraleState, brokeThisTick: Bool, recoveredThisTick: Bool) {
        if state.isBroken {
            let remaining = state.brokenTicksRemaining - 1
            guard remaining <= 0 else {
                return (MoraleState(morale: state.morale, brokenTicksRemaining: remaining), false, false)
            }
            let recoveredMorale = moraleMax * tuning.moraleRecoveredPercent / 100
            return (MoraleState(morale: recoveredMorale, brokenTicksRemaining: 0), false, true)
        }

        var morale = state.morale
        for event in events {
            morale -= Self.penalty(for: event, tuning: tuning)
        }
        if noEnemyNearby, Self.isRegenerationTick(tick) {
            morale += tuning.moraleRecoveryPerSecond
        }
        morale = Swift.min(Swift.max(morale, 0), moraleMax)

        guard morale * 100 < moraleMax * tuning.moraleBreakPercent else {
            return (MoraleState(morale: morale, brokenTicksRemaining: 0), false, false)
        }
        return (MoraleState(morale: morale, brokenTicksRemaining: tuning.moraleBrokenTicks), true, false)
    }

    private static func penalty(for event: MoraleEvent, tuning: SimulationTuning) -> Int {
        switch event {
        case .allyDiedNearby: tuning.allyDeathMoralePenalty
        case .commanderDied: tuning.commanderDeathMoralePenalty
        case .flanked: tuning.flankedMoralePenalty
        }
    }
}
