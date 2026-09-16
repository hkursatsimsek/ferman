import Testing

@testable import FermanCore

@Suite("Outcome")
struct OutcomeTests {
    @Test func eliminationEndsTheBattleForTheSideWithNoLivingUnits() throws {
        var units = try Self.twoSides()
        units[1].hp = 0
        let result = Outcome.afterDeaths(units: units)
        #expect(result?.outcome == .playerWin)
        #expect(result?.reason == .elimination)
    }

    @Test func routEndsTheBattleWhenEveryLivingUnitIsBroken() throws {
        var units = try Self.twoSides()
        units[1].morale = MoraleState(morale: 10, brokenTicksRemaining: 90)
        let result = Outcome.afterDeaths(units: units)
        #expect(result?.outcome == .playerWin)
        #expect(result?.reason == .rout)
    }

    @Test func aLivingUnbrokenUnitOnBothSidesMeansTheBattleContinues() throws {
        let units = try Self.twoSides()
        #expect(Outcome.afterDeaths(units: units) == nil)
    }

    @Test func simultaneousEliminationIsADraw() throws {
        var units = try Self.twoSides()
        units[0].hp = 0
        units[1].hp = 0
        let result = Outcome.afterDeaths(units: units)
        #expect(result?.outcome == .draw)
        #expect(result?.reason == .elimination)
    }

    @Test func holdLineAlwaysGivesThePlayerTheWinOnceEitherSideEndsIt() throws {
        let units = try Self.twoSides()
        let result = Outcome.atTimeLimit(units: units, catalog: Fixtures.catalog, objective: .holdLine)
        #expect(result.outcome == .playerWin)
        #expect(result.reason == .timeLimit)
    }

    @Test func eliminateComparesRemainingCostWeightedHealth() throws {
        var units = try Self.twoSides()
        // Player: archer at half HP, cost 30, maxHP 70 → 30 * 35 / 70 = 15.
        units[0].hp = Fixtures.unitType(Fixtures.archer).maxHP / 2
        // Enemy: cavalry at full HP, cost 40, maxHP 120 → 40.
        let result = Outcome.atTimeLimit(units: units, catalog: Fixtures.catalog, objective: .eliminate)
        #expect(result.outcome == .enemyWin)
        #expect(result.reason == .timeLimit)
    }

    @Test func eliminateIsADrawOnEqualRemainingValue() throws {
        let archerType = Fixtures.unitType(Fixtures.archer)
        let units = [
            UnitState(
                id: UnitID(rawValue: 0), team: .player, type: archerType, isCommander: false, program: nil,
                position: .zero),
            UnitState(
                id: UnitID(rawValue: 1), team: .enemy, type: archerType, isCommander: false, program: nil,
                position: .zero),
        ]
        let result = Outcome.atTimeLimit(units: units, catalog: Fixtures.catalog, objective: .eliminate)
        #expect(result.outcome == .draw)
    }

    private static func twoSides() throws -> [UnitState] {
        let archerType = Fixtures.unitType(Fixtures.archer)
        let cavalryType = Fixtures.unitType(Fixtures.cavalry)
        let player = UnitState(
            id: UnitID(rawValue: 0), team: .player, type: archerType, isCommander: false, program: nil, position: .zero)
        let enemy = UnitState(
            id: UnitID(rawValue: 1), team: .enemy, type: cavalryType, isCommander: false, program: nil, position: .zero)
        return [player, enemy]
    }
}
