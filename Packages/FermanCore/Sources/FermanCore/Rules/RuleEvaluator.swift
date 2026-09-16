/// Everything a `Condition` can ask about, flattened to one snapshot so `RuleEvaluator` stays a pure function of its
/// arguments. The future `BattleSimulator` fills this in per unit per decision tick from `SpatialGrid`, terrain and
/// unit state; nothing here is retained between calls.
struct RuleEvaluationContext: Sendable, Hashable {
    var ownHP: Int
    var ownMaxHP: Int
    var ownMorale: Int
    var ownMoraleMax: Int
    var ownTerrain: Terrain
    var isFlanked: Bool
    var ownTeamCommanderDead: Bool
    /// Cell distance to the nearest living enemy, or `nil` when none remain.
    var nearestEnemyDistanceCells: Int?
    /// The type of that same nearest living enemy.
    var nearestEnemyType: UnitTypeID?
    /// Enemy types with at least one living member inside this unit's weapon range right now.
    var enemyTypesInRange: [UnitTypeID]
    /// Living allies within `tuning.proximityRadiusCells`, not counting self.
    var nearbyLivingAllyCount: Int
    /// Living enemies within `tuning.proximityRadiusCells`.
    var nearbyLivingEnemyCount: Int
}

/// A unit's standing order and how long it has been committed to it (D9). Carried from one decision tick to the
/// next; the future `BattleState` holds one per unit.
struct RuleDecisionState: Sendable, Hashable {
    /// `nil` means no order is standing in for it: the implicit "advance and fight" applies.
    var activeRuleIndex: Int?
    /// The tick at which this unit is next free to leave `activeRuleIndex` for an equal-or-lower-priority order.
    var committedUntilTick: Int

    static let initial = RuleDecisionState(activeRuleIndex: nil, committedUntilTick: 0)
}

/// The result of one `RuleEvaluator.decide` call.
struct RuleDecision: Sendable, Hashable {
    let state: RuleDecisionState
    /// The order now in effect; `nil` is the implicit "advance and fight".
    let action: Action?
    /// Set only on the tick the standing order actually changes to a concrete rule (D9's edge trigger); this, and
    /// only this, is what increments `RuleFireCounts` and emits `ruleActivated`.
    let activatedRuleIndex: Int?
}

/// Picks a unit's standing order at 5 Hz (30 Hz tick rate ÷ `decisionIntervalTicks`, staggered by `UnitID` so the
/// army doesn't all decide on the same tick) and holds it for `minimumCommitTicks` unless a higher-priority order
/// starts matching (D9).
enum RuleEvaluator {
    static func isDecisionTick(unitID: UnitID, tick: Int, decisionIntervalTicks: Int) -> Bool {
        Int(unitID.rawValue) % decisionIntervalTicks == tick % decisionIntervalTicks
    }

    /// The first rule in priority order whose condition holds, ignoring commitment entirely.
    static func firstMatch(in program: RuleProgram, tick: Int, context: RuleEvaluationContext) -> Int? {
        program.rules.firstIndex { matches($0.condition, tick: tick, context: context) }
    }

    static func matches(_ condition: Condition, tick: Int, context: RuleEvaluationContext) -> Bool {
        switch condition {
        case .enemyWithin(let cells):
            guard let distance = context.nearestEnemyDistanceCells else { return false }
            return distance <= cells
        case .healthBelow(let percent):
            return context.ownHP * 100 < context.ownMaxHP * percent
        case .allyCountBelow(let count):
            return context.nearbyLivingAllyCount < count
        case .isFlanked:
            return context.isFlanked
        case .targetInRange(let unitType):
            return context.enemyTypesInRange.contains(unitType)
        case .timeAfter(let seconds):
            return tick >= seconds * BattleConfig.ticksPerSecond
        case .nearestEnemyType(let unitType):
            return context.nearestEnemyType == unitType
        case .moraleBelow(let percent):
            return context.ownMorale * 100 < context.ownMoraleMax * percent
        case .terrainIs(let terrain):
            return context.ownTerrain == terrain
        case .commanderDead:
            return context.ownTeamCommanderDead
        case .enemyDensityAbove(let count):
            return context.nearbyLivingEnemyCount > count
        case .always:
            return true
        }
    }

    /// Call only on this unit's decision tick (`isDecisionTick`); every other tick, keep executing
    /// `previous.action` unchanged without calling this at all.
    static func decide(
        program: RuleProgram, tick: Int, context: RuleEvaluationContext, previous: RuleDecisionState,
        tuning: SimulationTuning
    ) -> RuleDecision {
        let matchedIndex = firstMatch(in: program, tick: tick, context: context)

        let interrupts =
            previous.activeRuleIndex.flatMap { activeIndex in matchedIndex.map { $0 < activeIndex } } ?? false
        let commitmentElapsed = tick >= previous.committedUntilTick
        guard interrupts || commitmentElapsed else {
            return RuleDecision(
                state: previous, action: previous.activeRuleIndex.map { program.rules[$0].action },
                activatedRuleIndex: nil)
        }

        // A concrete order re-commits for a fresh window; falling back to the implicit behavior holds nothing, so
        // the very next decision tick is free to pick up a newly matching order right away.
        let committedUntilTick = matchedIndex != nil ? tick + tuning.minimumCommitTicks : tick
        let newState = RuleDecisionState(activeRuleIndex: matchedIndex, committedUntilTick: committedUntilTick)
        let changed = matchedIndex != previous.activeRuleIndex
        return RuleDecision(
            state: newState, action: matchedIndex.map { program.rules[$0].action },
            activatedRuleIndex: changed ? matchedIndex : nil)
    }
}
