import FermanCore
import Testing

@testable import Ferman

@MainActor
struct DebriefModelTests {
    private static let archer: UnitTypeID = "okcu"
    private static let spearman: UnitTypeID = "mizrakci"

    private static let catalog: [UnitType] = [
        UnitType(
            id: archer, cost: 30, maxHP: 70, speedMilliCellsPerSecond: 1_000, rangeMilliCells: 6_000, damage: 10,
            attackIntervalTicks: 36, armor: 0, moraleMax: 90, counters: [], ability: .volley),
        UnitType(
            id: spearman, cost: 25, maxHP: 90, speedMilliCellsPerSecond: 1_100, rangeMilliCells: 1_000, damage: 9,
            attackIntervalTicks: 30, armor: 2, moraleMax: 100, counters: [], ability: .spearWall),
    ]

    private static func map() throws -> BattleMap {
        try BattleMap(terrainRows: ["....", "....", "...."], zoneRows: ["P..E", "P..E", "P..E"])
    }

    private static let archerProgram = RuleProgram(
        unitType: archer,
        rules: [
            Rule(condition: .enemyWithin(cells: 3), action: .retreat),
            Rule(condition: .healthBelow(percent: 35), action: .takeCover),
            Rule(condition: .always, action: .advance),
        ])

    /// Four player archers spawn; three die together at tick 360 (12s @ 30 ticks/s) — a 75% cluster.
    private static func config(playerPrograms: [RuleProgram] = [archerProgram]) throws -> BattleConfig {
        BattleConfig(
            map: try map(), unitCatalog: catalog,
            player: TeamSetup(
                placements: (0..<4).map { UnitPlacement(type: archer, cell: $0) }, programs: playerPrograms),
            enemy: TeamSetup(placements: [UnitPlacement(type: spearman, cell: 3)], programs: []),
            objective: .eliminate, constraints: .unrestricted, seed: 1)
    }

    private static func spawnEvents(team: Team, unitType: UnitTypeID, ids: [UInt32]) -> [BattleEvent] {
        ids.map { BattleEvent(tick: 0, kind: .spawn(UnitID(rawValue: $0), unitType, team, .zero)) }
    }

    private static func defeatResult(ruleFireCounts: [RuleFireCounts]) -> BattleResult {
        let spawns =
            spawnEvents(team: .player, unitType: archer, ids: [0, 1, 2, 3])
            + spawnEvents(team: .enemy, unitType: spearman, ids: [4])
        let deaths: [BattleEvent] = [0, 1, 2].map { BattleEvent(tick: 360, kind: .death(UnitID(rawValue: $0))) }
        return BattleResult(
            outcome: .enemyWin, endReason: .elimination, tickCount: 400, events: spawns + deaths,
            ruleFireCounts: ruleFireCounts, survivorsPlayer: 1, survivorsEnemy: 1, checksum: 0)
    }

    // MARK: - Title

    @Test
    func titleNamesVictoryDefeatAndDraw() {
        #expect(DebriefInsightFormatter.title(for: .playerWin) == "Hat tutuldu.")
        #expect(DebriefInsightFormatter.title(for: .enemyWin) == "Cephe yarıldı.")
        #expect(DebriefInsightFormatter.title(for: .draw) == "Savaş berabere bitti.")
    }

    // MARK: - Diagnosis (golden sentences)

    @Test
    func defeatDiagnosisNamesThePlayersOwnDeathCluster() throws {
        let result = Self.defeatResult(ruleFireCounts: [
            RuleFireCounts(team: .player, unitType: Self.archer, counts: [14, 0, 5])
        ])
        let model = DebriefModel(config: try Self.config(), result: result)

        #expect(model.isVictory == false)
        #expect(model.title == "Cephe yarıldı.")
        #expect(model.diagnosis == "Okçularının %75'i 12. saniyede aynı anda öldü.")
    }

    @Test
    func victoryDiagnosisNamesTheEnemysDeathClusterWithAPrefix() throws {
        let spawns =
            Self.spawnEvents(team: .player, unitType: Self.archer, ids: [0, 1, 2, 3])
            + Self.spawnEvents(team: .enemy, unitType: Self.spearman, ids: [4, 5, 6, 7])
        let deaths: [BattleEvent] = [4, 5, 6].map { BattleEvent(tick: 300, kind: .death(UnitID(rawValue: $0))) }
        let result = BattleResult(
            outcome: .playerWin, endReason: .elimination, tickCount: 400, events: spawns + deaths,
            ruleFireCounts: [RuleFireCounts(team: .player, unitType: Self.archer, counts: [10, 2, 1])],
            survivorsPlayer: 3, survivorsEnemy: 0, checksum: 0)

        let model = DebriefModel(config: try Self.config(), result: result)

        #expect(model.isVictory == true)
        #expect(model.diagnosis == "Düşman Mızrakçılarının %75'i 10. saniyede aynı anda öldü.")
    }

    @Test(
        arguments: [
            (BattleOutcome.playerWin, EndReason.elimination, "Düşman ordusu yok edildi."),
            (BattleOutcome.playerWin, EndReason.rout, "Düşman ordusu dağıldı."),
            (BattleOutcome.playerWin, EndReason.timeLimit, "Hat, süre sonunda tutuldu."),
            (BattleOutcome.enemyWin, EndReason.elimination, "Ordun yok edildi."),
            (BattleOutcome.enemyWin, EndReason.rout, "Ordun dağıldı."),
            (BattleOutcome.enemyWin, EndReason.timeLimit, "Hat, süre sonunda yarıldı."),
            (BattleOutcome.draw, EndReason.timeLimit, "Savaş berabere bitti."),
        ] as [(BattleOutcome, EndReason, String)]
    )
    func diagnosisFallsBackToAGenericSentenceWithoutAClusterFinding(
        arguments: (outcome: BattleOutcome, endReason: EndReason, expected: String)
    ) throws {
        let result = BattleResult(
            outcome: arguments.outcome, endReason: arguments.endReason, tickCount: 10, events: [],
            ruleFireCounts: [], survivorsPlayer: 1, survivorsEnemy: 1, checksum: 0)

        let model = DebriefModel(config: try Self.config(), result: result)

        #expect(model.diagnosis == arguments.expected)
    }

    // MARK: - Order rows

    @Test
    func rowsCarryFireCountsInProgramOrderWithShareOfTotalFraction() throws {
        let result = Self.defeatResult(
            ruleFireCounts: [RuleFireCounts(team: .player, unitType: Self.archer, counts: [14, 0, 5])])
        let model = DebriefModel(config: try Self.config(), result: result)

        #expect(model.sections.count == 1)
        let rows = model.sections[0].rows
        #expect(rows.map(\.priority) == [1, 2, 3])
        #expect(rows.map(\.fireCount) == [14, 0, 5])
        #expect(rows[0].fraction == 14.0 / 19.0)
        #expect(rows[0].condition == "düşman 3 kareden yakınsa")
        #expect(rows[0].action == "GERİ ÇEKİL")
    }

    @Test
    func aRuleThatNeverFiredIsFlagged() throws {
        let result = Self.defeatResult(
            ruleFireCounts: [RuleFireCounts(team: .player, unitType: Self.archer, counts: [14, 0, 5])])
        let model = DebriefModel(config: try Self.config(), result: result)

        let rows = model.sections[0].rows
        #expect(rows[1].neverFired == true)
        #expect(rows[0].neverFired == false)
        #expect(rows[2].neverFired == false)
    }

    @Test
    func missingRuleFireCountsEntryTreatsEveryRuleAsNeverFired() throws {
        let result = Self.defeatResult(ruleFireCounts: [])
        let model = DebriefModel(config: try Self.config(), result: result)

        #expect(model.sections[0].rows.allSatisfy { $0.neverFired })
    }

    @Test
    func oneSectionPerPlayerProgramInOrder() throws {
        let spearmanProgram = RuleProgram(unitType: Self.spearman, rules: [Rule(condition: .always, action: .advance)])
        let config = try Self.config(playerPrograms: [Self.archerProgram, spearmanProgram])
        let result = Self.defeatResult(ruleFireCounts: [])

        let model = DebriefModel(config: config, result: result)

        #expect(model.sections.map(\.unitType) == [Self.archer, Self.spearman])
        #expect(model.sections.map(\.displayName) == ["Okçu", "Mızrakçı"])
    }
}
