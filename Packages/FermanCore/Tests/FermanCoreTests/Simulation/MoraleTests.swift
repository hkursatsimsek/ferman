import Testing

@testable import FermanCore

@Suite("Morale")
struct MoraleTests {
    private static let moraleMax = 100
    private static let full = MoraleState(morale: 100, brokenTicksRemaining: 0)

    @Test func anAllyDeathNearbyAppliesItsPenalty() {
        let result = Morale.step(
            Self.full, events: [.allyDiedNearby], noEnemyNearby: false, tick: 1, moraleMax: Self.moraleMax,
            tuning: .standard)
        #expect(result.state.morale == 100 - SimulationTuning.standard.allyDeathMoralePenalty)
        #expect(!result.brokeThisTick)
    }

    @Test func repeatedEventsInOneTickStack() {
        let result = Morale.step(
            Self.full, events: [.allyDiedNearby, .allyDiedNearby, .flanked], noEnemyNearby: false, tick: 1,
            moraleMax: Self.moraleMax, tuning: .standard)
        let expectedPenalty =
            2 * SimulationTuning.standard.allyDeathMoralePenalty + SimulationTuning.standard.flankedMoralePenalty
        #expect(result.state.morale == 100 - expectedPenalty)
    }

    @Test func commanderDeathAppliesItsPenalty() {
        let result = Morale.step(
            Self.full, events: [.commanderDied], noEnemyNearby: false, tick: 1, moraleMax: Self.moraleMax,
            tuning: .standard)
        #expect(result.state.morale == 100 - SimulationTuning.standard.commanderDeathMoralePenalty)
    }

    @Test func moraleRegeneratesOnlyOnSecondBoundariesWhenSafe() {
        let damaged = MoraleState(morale: 50, brokenTicksRemaining: 0)
        let onTheSecond = Morale.step(
            damaged, events: [], noEnemyNearby: true, tick: 30, moraleMax: Self.moraleMax, tuning: .standard)
        #expect(onTheSecond.state.morale == 50 + SimulationTuning.standard.moraleRecoveryPerSecond)

        let offTheSecond = Morale.step(
            damaged, events: [], noEnemyNearby: true, tick: 31, moraleMax: Self.moraleMax, tuning: .standard)
        #expect(offTheSecond.state.morale == 50)
    }

    @Test func moraleDoesNotRegenerateWithAnEnemyNearby() {
        let damaged = MoraleState(morale: 50, brokenTicksRemaining: 0)
        let result = Morale.step(
            damaged, events: [], noEnemyNearby: false, tick: 30, moraleMax: Self.moraleMax, tuning: .standard)
        #expect(result.state.morale == 50)
    }

    @Test func moraleClampsToTheValidRangeInBothDirections() {
        let atMax = MoraleState(morale: Self.moraleMax, brokenTicksRemaining: 0)
        let stillAtMax = Morale.step(
            atMax, events: [], noEnemyNearby: true, tick: 30, moraleMax: Self.moraleMax, tuning: .standard)
        #expect(stillAtMax.state.morale == Self.moraleMax)

        let nearZero = MoraleState(morale: 2, brokenTicksRemaining: 0)
        var tuning = SimulationTuning.standard
        tuning.moraleBreakPercent = 0  // never breaks, so the floor is the only thing under test
        let events = Array(repeating: MoraleEvent.commanderDied, count: 5)
        let floored = Morale.step(
            nearZero, events: events, noEnemyNearby: false, tick: 1, moraleMax: Self.moraleMax, tuning: tuning)
        #expect(floored.state.morale == 0)
    }

    @Test func droppingStrictlyBelowTheBreakThresholdBreaksTheUnit() {
        // moraleMax 100, break 20%: morale exactly 20 is the boundary and must not break; 19 must.
        let atBoundary = MoraleState(morale: 25, brokenTicksRemaining: 0)
        let stillFine = Morale.step(
            atBoundary, events: [.flanked], noEnemyNearby: false, tick: 1, moraleMax: Self.moraleMax, tuning: .standard)
        #expect(stillFine.state.morale == 20)
        #expect(!stillFine.brokeThisTick)

        let overTheEdge = MoraleState(morale: 24, brokenTicksRemaining: 0)
        let broke = Morale.step(
            overTheEdge, events: [.flanked], noEnemyNearby: false, tick: 1, moraleMax: Self.moraleMax, tuning: .standard
        )
        #expect(broke.state.morale == 19)
        #expect(broke.brokeThisTick)
        #expect(broke.state.brokenTicksRemaining == SimulationTuning.standard.moraleBrokenTicks)
    }

    @Test func aBrokenUnitIgnoresEventsAndJustCountsDown() {
        let broken = MoraleState(morale: 15, brokenTicksRemaining: 3)
        let result = Morale.step(
            broken, events: [.commanderDied, .flanked], noEnemyNearby: true, tick: 30, moraleMax: Self.moraleMax,
            tuning: .standard)
        #expect(result.state.morale == 15)
        #expect(result.state.brokenTicksRemaining == 2)
        #expect(!result.brokeThisTick)
        #expect(!result.recoveredThisTick)
    }

    @Test func recoveryFiresOnceTheBrokenCounterReachesZero() {
        let aboutToRecover = MoraleState(morale: 3, brokenTicksRemaining: 1)
        let result = Morale.step(
            aboutToRecover, events: [], noEnemyNearby: false, tick: 1, moraleMax: Self.moraleMax, tuning: .standard)
        #expect(result.state.morale == Self.moraleMax * SimulationTuning.standard.moraleRecoveredPercent / 100)
        #expect(result.state.brokenTicksRemaining == 0)
        #expect(!result.state.isBroken)
        #expect(result.recoveredThisTick)
        #expect(!result.brokeThisTick)
    }
}
