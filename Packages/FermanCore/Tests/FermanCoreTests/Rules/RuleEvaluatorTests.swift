import Testing

@testable import FermanCore

@Suite("RuleEvaluator")
struct RuleEvaluatorTests {
    private static let archer: UnitTypeID = "okcu"
    private static let spearman: UnitTypeID = "mizrakci"

    private static let baseContext = RuleEvaluationContext(
        ownHP: 100, ownMaxHP: 100, ownMorale: 100, ownMoraleMax: 100, ownTerrain: .open, isFlanked: false,
        ownTeamCommanderDead: false, nearestEnemyDistanceCells: nil, nearestEnemyType: nil, enemyTypesInRange: [],
        nearbyLivingAllyCount: 0, nearbyLivingEnemyCount: 0
    )

    // MARK: - Condition boundaries (§5.3: Below is strict, Within is inclusive)

    @Test(arguments: [(4, 5, true), (5, 5, true), (6, 5, false)] as [(Int, Int, Bool)])
    func enemyWithinMatchesAtOrInsideTheDistance(distance: Int, cells: Int, expected: Bool) {
        var context = Self.baseContext
        context.nearestEnemyDistanceCells = distance
        #expect(RuleEvaluator.matches(.enemyWithin(cells: cells), tick: 0, context: context) == expected)
    }

    @Test func enemyWithinNeverMatchesWithNoLivingEnemy() {
        #expect(RuleEvaluator.matches(.enemyWithin(cells: 10), tick: 0, context: Self.baseContext) == false)
    }

    @Test(arguments: [(51, 50, false), (50, 50, false), (49, 50, true)] as [(Int, Int, Bool)])
    func healthBelowIsStrictlyLess(hp: Int, percent: Int, expected: Bool) {
        var context = Self.baseContext
        context.ownHP = hp
        context.ownMaxHP = 100
        #expect(RuleEvaluator.matches(.healthBelow(percent: percent), tick: 0, context: context) == expected)
    }

    @Test(arguments: [(51, 50, false), (50, 50, false), (49, 50, true)] as [(Int, Int, Bool)])
    func moraleBelowIsStrictlyLess(morale: Int, percent: Int, expected: Bool) {
        var context = Self.baseContext
        context.ownMorale = morale
        context.ownMoraleMax = 100
        #expect(RuleEvaluator.matches(.moraleBelow(percent: percent), tick: 0, context: context) == expected)
    }

    @Test(arguments: [(4, 3, false), (3, 3, false), (2, 3, true)] as [(Int, Int, Bool)])
    func allyCountBelowIsStrictlyLess(nearbyAllies: Int, count: Int, expected: Bool) {
        var context = Self.baseContext
        context.nearbyLivingAllyCount = nearbyAllies
        #expect(RuleEvaluator.matches(.allyCountBelow(count: count), tick: 0, context: context) == expected)
    }

    @Test(arguments: [(3, 4, false), (4, 4, false), (5, 4, true)] as [(Int, Int, Bool)])
    func enemyDensityAboveIsStrictlyGreater(nearbyEnemies: Int, count: Int, expected: Bool) {
        var context = Self.baseContext
        context.nearbyLivingEnemyCount = nearbyEnemies
        #expect(RuleEvaluator.matches(.enemyDensityAbove(count: count), tick: 0, context: context) == expected)
    }

    @Test(arguments: [(89, 3, false), (90, 3, true), (91, 3, true)] as [(Int, Int, Bool)])
    func timeAfterMatchesFromTheExactTick(tick: Int, seconds: Int, expected: Bool) {
        #expect(RuleEvaluator.matches(.timeAfter(seconds: seconds), tick: tick, context: Self.baseContext) == expected)
    }

    @Test func booleanAndIdentityConditionsReadDirectlyFromTheContext() {
        var context = Self.baseContext
        context.isFlanked = true
        context.ownTeamCommanderDead = true
        context.ownTerrain = .forest
        context.nearestEnemyType = Self.spearman
        context.enemyTypesInRange = [Self.spearman]

        #expect(RuleEvaluator.matches(.isFlanked, tick: 0, context: context))
        #expect(RuleEvaluator.matches(.commanderDead, tick: 0, context: context))
        #expect(RuleEvaluator.matches(.terrainIs(.forest), tick: 0, context: context))
        #expect(!RuleEvaluator.matches(.terrainIs(.open), tick: 0, context: context))
        #expect(RuleEvaluator.matches(.nearestEnemyType(Self.spearman), tick: 0, context: context))
        #expect(!RuleEvaluator.matches(.nearestEnemyType(Self.archer), tick: 0, context: context))
        #expect(RuleEvaluator.matches(.targetInRange(Self.spearman), tick: 0, context: context))
        #expect(!RuleEvaluator.matches(.targetInRange(Self.archer), tick: 0, context: context))
        #expect(RuleEvaluator.matches(.always, tick: 0, context: Self.baseContext))
    }

    // MARK: - Decision cadence (D9)

    @Test(
        arguments: [
            (UnitID(rawValue: 0), 0, true), (UnitID(rawValue: 0), 1, false), (UnitID(rawValue: 0), 6, true),
            (UnitID(rawValue: 7), 1, true), (UnitID(rawValue: 7), 0, false), (UnitID(rawValue: 7), 13, true),
        ] as [(UnitID, Int, Bool)]
    )
    func decisionTicksAreStaggeredByUnitIDModuloTheInterval(unitID: UnitID, tick: Int, isDecisionTick: Bool) {
        #expect(RuleEvaluator.isDecisionTick(unitID: unitID, tick: tick, decisionIntervalTicks: 6) == isDecisionTick)
    }

    // MARK: - Selection, hysteresis and edge-triggered counting (D9)

    /// index 0 (highest priority) commander-dead, 1 low-health, 2 enemy-nearby, 3 the `always` default.
    private static func program() -> RuleProgram {
        RuleProgram(
            unitType: Self.archer,
            rules: [
                Rule(condition: .commanderDead, action: .guardCommander),
                Rule(condition: .healthBelow(percent: 50), action: .retreat),
                Rule(condition: .enemyWithin(cells: 5), action: .hold),
                Rule(condition: .always, action: .advance),
            ]
        )
    }

    @Test func firstDecisionAdoptsTheHighestPriorityMatchAndFiresAnEvent() {
        var context = Self.baseContext
        context.nearestEnemyDistanceCells = 3

        let decision = RuleEvaluator.decide(
            program: Self.program(), tick: 0, context: context, previous: .initial, tuning: .standard)

        #expect(decision.state.activeRuleIndex == 2)
        #expect(decision.state.committedUntilTick == 15)
        #expect(decision.action == .hold)
        #expect(decision.activatedRuleIndex == 2)
    }

    @Test func withinTheCommitWindowALowerPriorityChangeIsIgnored() {
        var context = Self.baseContext
        context.nearestEnemyDistanceCells = 3
        let first = RuleEvaluator.decide(
            program: Self.program(), tick: 0, context: context, previous: .initial, tuning: .standard)

        context.nearestEnemyDistanceCells = nil  // now only the `always` default matches: lower priority than rule 2
        let second = RuleEvaluator.decide(
            program: Self.program(), tick: 6, context: context, previous: first.state, tuning: .standard)

        #expect(second.state == first.state)
        #expect(second.action == .hold)
        #expect(second.activatedRuleIndex == nil)
    }

    @Test func aHigherPriorityMatchInterruptsCommitmentEarly() {
        var context = Self.baseContext
        context.nearestEnemyDistanceCells = 3
        let first = RuleEvaluator.decide(
            program: Self.program(), tick: 0, context: context, previous: .initial, tuning: .standard)

        context.ownHP = 40  // rule 1 now also matches, and it outranks the active rule 2
        let second = RuleEvaluator.decide(
            program: Self.program(), tick: 6, context: context, previous: first.state, tuning: .standard)

        #expect(second.state.activeRuleIndex == 1)
        #expect(second.state.committedUntilTick == 21)
        #expect(second.action == .retreat)
        #expect(second.activatedRuleIndex == 1)
    }

    @Test func onceTheWindowElapsesALowerPriorityMatchTakesOver() {
        var context = Self.baseContext
        context.nearestEnemyDistanceCells = 3
        let first = RuleEvaluator.decide(
            program: Self.program(), tick: 0, context: context, previous: .initial, tuning: .standard)

        context.nearestEnemyDistanceCells = nil  // only `always` matches now
        let second = RuleEvaluator.decide(
            program: Self.program(), tick: 15, context: context, previous: first.state, tuning: .standard)

        #expect(second.state.activeRuleIndex == 3)
        #expect(second.state.committedUntilTick == 30)
        #expect(second.action == .advance)
        #expect(second.activatedRuleIndex == 3)
    }

    @Test func reselectingTheSameRuleAfterTheWindowElapsesRefreshesTheWindowWithoutFiring() {
        var context = Self.baseContext
        context.nearestEnemyDistanceCells = 3
        let first = RuleEvaluator.decide(
            program: Self.program(), tick: 0, context: context, previous: .initial, tuning: .standard)

        let second = RuleEvaluator.decide(
            program: Self.program(), tick: 15, context: context, previous: first.state, tuning: .standard)

        #expect(second.state.activeRuleIndex == 2)
        #expect(second.state.committedUntilTick == 30)
        #expect(second.activatedRuleIndex == nil)
    }

    @Test func fallingBackToTheImplicitOrderNeitherFiresNorCommits() {
        let programWithoutDefault = RuleProgram(
            unitType: Self.archer, rules: [Rule(condition: .enemyWithin(cells: 5), action: .hold)])

        let decision = RuleEvaluator.decide(
            program: programWithoutDefault, tick: 0, context: Self.baseContext, previous: .initial, tuning: .standard)

        #expect(decision.state.activeRuleIndex == nil)
        #expect(decision.state.committedUntilTick == 0)
        #expect(decision.action == nil)
        #expect(decision.activatedRuleIndex == nil)

        // Nothing was committed, so the very next decision tick is free to pick up a fresh match immediately.
        var context = Self.baseContext
        context.nearestEnemyDistanceCells = 2
        let next = RuleEvaluator.decide(
            program: programWithoutDefault, tick: 1, context: context, previous: decision.state, tuning: .standard)
        #expect(next.state.activeRuleIndex == 0)
        #expect(next.activatedRuleIndex == 0)
    }

    @Test func leavingAConcreteRuleForTheImplicitOrderDoesNotFire() {
        let programWithoutDefault = RuleProgram(
            unitType: Self.archer, rules: [Rule(condition: .enemyWithin(cells: 5), action: .hold)])
        var context = Self.baseContext
        context.nearestEnemyDistanceCells = 2
        let first = RuleEvaluator.decide(
            program: programWithoutDefault, tick: 0, context: context, previous: .initial, tuning: .standard)
        #expect(first.state.activeRuleIndex == 0)

        context.nearestEnemyDistanceCells = nil
        let second = RuleEvaluator.decide(
            program: programWithoutDefault, tick: 15, context: context, previous: first.state, tuning: .standard)

        #expect(second.state.activeRuleIndex == nil)
        #expect(second.action == nil)
        #expect(second.activatedRuleIndex == nil)
    }
}
