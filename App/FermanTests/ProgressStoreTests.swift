import FermanCore
import SwiftData
import Testing

@testable import Ferman

@MainActor
struct ProgressStoreTests {
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

    private static func config(playerPlacements: Int = 2, seed: UInt64 = 1) throws -> BattleConfig {
        BattleConfig(
            map: try map(), unitCatalog: catalog,
            player: TeamSetup(
                placements: (0..<playerPlacements).map { UnitPlacement(type: archer, cell: $0) },
                programs: [RuleProgram(unitType: archer, rules: [Rule(condition: .always, action: .advance)])]),
            enemy: TeamSetup(placements: [UnitPlacement(type: spearman, cell: 3)], programs: []),
            objective: .eliminate, constraints: .unrestricted, seed: seed)
    }

    private static func result(outcome: BattleOutcome, checksum: UInt64 = 0) -> BattleResult {
        BattleResult(
            outcome: outcome, endReason: outcome == .playerWin ? .elimination : .rout, tickCount: 100, events: [],
            ruleFireCounts: [], survivorsPlayer: outcome == .playerWin ? 2 : 0,
            survivorsEnemy: outcome == .playerWin ? 0 : 1, checksum: checksum)
    }

    // MARK: - Level progress

    @Test
    func unrecordedLevelHasNoProgress() throws {
        let store = try ProgressStore(inMemory: true)
        #expect(store.progress(forLevel: 1) == nil)
    }

    @Test
    func firstWinRecordsAttemptAndWinningProgram() throws {
        let store = try ProgressStore(inMemory: true)
        let config = try Self.config()
        let progress = try store.recordBattle(levelID: 3, config: config, result: Self.result(outcome: .playerWin))

        #expect(progress.levelID == 3)
        #expect(progress.attempts == 1)
        #expect(progress.bestOutcome == .playerWin)
        #expect(progress.winningArmy == config.player.placements)
        #expect(progress.winningPrograms == config.player.programs)
        #expect(progress.lastEnemyPlan == config.enemy)
    }

    /// `bestOutcome` tracks the best result ever reached, not the most recent one — a level stays
    /// "won" even if the player loses on a later, sloppier attempt.
    @Test
    func bestOutcomeNeverRegressesAfterALaterLoss() throws {
        let store = try ProgressStore(inMemory: true)
        _ = try store.recordBattle(levelID: 3, config: try Self.config(), result: Self.result(outcome: .playerWin))
        let progress = try store.recordBattle(
            levelID: 3, config: try Self.config(playerPlacements: 1), result: Self.result(outcome: .enemyWin))

        #expect(progress.attempts == 2)
        #expect(progress.bestOutcome == .playerWin)
        #expect(progress.winningArmy?.count == 2)
    }

    /// Unlike `bestOutcome`, the saved winning army/programs move forward to the latest win — the
    /// point is to hand a mirrored level (F3.7) the player's current approach, not their first one.
    @Test
    func winningProgramReflectsTheMostRecentWin() throws {
        let store = try ProgressStore(inMemory: true)
        _ = try store.recordBattle(
            levelID: 5, config: try Self.config(playerPlacements: 1), result: Self.result(outcome: .playerWin))
        let secondConfig = try Self.config(playerPlacements: 4)
        let progress = try store.recordBattle(
            levelID: 5, config: secondConfig, result: Self.result(outcome: .playerWin))

        #expect(progress.winningArmy?.count == 4)
    }

    @Test
    func recordBattleAlwaysAppendsABattleRecord() throws {
        let store = try ProgressStore(inMemory: true)
        _ = try store.recordBattle(
            levelID: 7, config: try Self.config(), result: Self.result(outcome: .playerWin, checksum: 111))
        _ = try store.recordBattle(
            levelID: 7, config: try Self.config(), result: Self.result(outcome: .enemyWin, checksum: 222))

        let records = store.battleRecords(forLevel: 7)
        #expect(records.count == 2)
        #expect(Set(records.map(\.checksum)) == [111, 222])
    }

    @Test
    func recordBattleReusesTheSameLevelProgressRowAcrossCalls() throws {
        let store = try ProgressStore(inMemory: true)
        _ = try store.recordBattle(levelID: 9, config: try Self.config(), result: Self.result(outcome: .enemyWin))
        _ = try store.recordBattle(levelID: 9, config: try Self.config(), result: Self.result(outcome: .enemyWin))
        _ = try store.recordBattle(levelID: 9, config: try Self.config(), result: Self.result(outcome: .enemyWin))

        #expect(store.progress(forLevel: 9)?.attempts == 3)
    }

    // MARK: - Saved order sets

    @Test
    func savedOrderSetRoundTrips() throws {
        let store = try ProgressStore(inMemory: true)
        let config = try Self.config()
        let saved = try store.saveOrderSet(
            name: "Kum Sırtı açılışı", tag: "okçu", army: config.player.placements, programs: config.player.programs)

        #expect(saved.name == "Kum Sırtı açılışı")
        #expect(saved.tag == "okçu")
        #expect(saved.usageCount == 0)
        #expect(store.savedOrderSets().map(\.id) == [saved.id])
    }

    @Test
    func markingAnOrderSetUsedIncrementsItsCount() throws {
        let store = try ProgressStore(inMemory: true)
        let config = try Self.config()
        let saved = try store.saveOrderSet(
            name: "Set", tag: nil, army: config.player.placements, programs: config.player.programs)

        try store.markOrderSetUsed(saved.id)
        try store.markOrderSetUsed(saved.id)

        #expect(store.savedOrderSets().first?.usageCount == 2)
    }

    @Test
    func deletingAnOrderSetRemovesIt() throws {
        let store = try ProgressStore(inMemory: true)
        let config = try Self.config()
        let saved = try store.saveOrderSet(
            name: "Set", tag: nil, army: config.player.placements, programs: config.player.programs)

        try store.deleteOrderSet(saved.id)

        #expect(store.savedOrderSets().isEmpty)
    }

    @Test
    func unknownOrderSetIDsAreANoOp() throws {
        let store = try ProgressStore(inMemory: true)
        let config = try Self.config()
        let saved = try store.saveOrderSet(
            name: "Set", tag: nil, army: config.player.placements, programs: config.player.programs)
        try store.deleteOrderSet(saved.id)

        try store.markOrderSetUsed(saved.id)
        try store.deleteOrderSet(saved.id)
        #expect(store.savedOrderSets().isEmpty)
    }

    // MARK: - Schema

    @Test
    func migrationPlanHasNoStagesForTheFirstSchema() {
        #expect(FermanMigrationPlan.stages.isEmpty)
        #expect(FermanMigrationPlan.schemas.count == 1)
        #expect(FermanSchemaV1.models.count == 3)
    }

    /// Proves the container the store hands out is actually observable the way ARCHITECTURE commits
    /// to (§9: "Modeller liste değişikliklerini iOS 27 `ResultsObserver` ile izler") — `ResultsObserver`
    /// updates asynchronously off the save notification, so this polls briefly instead of asserting
    /// immediately after `save()`.
    @Test
    func liveResultsObserverSeesInsertedOrderSets() async throws {
        let store = try ProgressStore(inMemory: true)
        let observer = try ResultsObserver<FermanSchemaV1.SavedOrderSet, Never>(modelContainer: store.container)
        #expect(observer.results.isEmpty)

        let config = try Self.config()
        _ = try store.saveOrderSet(
            name: "Set", tag: nil, army: config.player.placements, programs: config.player.programs)

        for _ in 0..<50 where observer.results.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(observer.results.count == 1)
    }
}
