import FermanCore
import Testing

@testable import Ferman

@MainActor
struct BattleModelTests {
    @Test
    func skippedStartReachesPlayingWithAResult() async throws {
        let model = BattleModel(config: try Fixture.config(), orders: Fixture.orders)
        model.start(reduceMotion: true)
        try await Fixture.waitUntilPlaying(model)

        #expect(model.phase == .playing)
        #expect(model.clock != nil)
        #expect(model.timeline != nil)
        #expect(!model.triggerRows.isEmpty)
    }

    @Test
    func restartReseeksWithoutResimulating() async throws {
        let model = BattleModel(config: try Fixture.config(), orders: Fixture.orders)
        model.start(reduceMotion: true)
        try await Fixture.waitUntilPlaying(model)
        model.clock?.seek(to: 12)

        let start = ContinuousClock.now
        model.restart()
        let elapsed = start.duration(to: .now)

        #expect(model.clock?.currentTick == 0)
        #expect(elapsed < .milliseconds(100))
    }

    @Test
    func skipFastForwardsThroughTheChoreography() async throws {
        let model = BattleModel(config: try Fixture.config(), orders: Fixture.orders)
        model.start(reduceMotion: false)
        model.skip()
        try await Fixture.waitUntilPlaying(model, timeout: .seconds(1))

        #expect(model.phase == .playing)
    }

    @Test
    func selectingAnEnemyUnitLeavesTheStripUnchanged() async throws {
        let model = BattleModel(config: try Fixture.config(), orders: Fixture.orders)
        model.start(reduceMotion: true)
        try await Fixture.waitUntilPlaying(model)
        let before = model.selectedUnitType

        model.selectUnit(UnitID(rawValue: 999))

        #expect(model.selectedUnitType == before)
    }
}

@MainActor
private enum Fixture {
    static let archer: UnitTypeID = "okcu"
    static let shield: UnitTypeID = "kalkan"

    static let orders: [OrderStack.Item] = [
        .init(priority: 1, condition: "düşman 2 kareden yakınsa", action: "GERİ ÇEKİL", state: .normal),
        .init(priority: 2, condition: "başka durumda", action: "İLERLE", state: .isDefault),
    ]

    static func config() throws -> BattleConfig {
        let catalog: [UnitType] = [
            UnitType(
                id: archer, cost: 30, maxHP: 70, speedMilliCellsPerSecond: 1_000, rangeMilliCells: 6_000,
                damage: 10, attackIntervalTicks: 36, armor: 0, moraleMax: 90, counters: [], ability: .volley),
            UnitType(
                id: shield, cost: 30, maxHP: 160, speedMilliCellsPerSecond: 900, rangeMilliCells: 1_000,
                damage: 8, attackIntervalTicks: 30, armor: 4, moraleMax: 120, counters: [], ability: .shieldWall),
        ]
        let map = try BattleMap(terrainRows: ["...."], zoneRows: ["P..E"])
        return BattleConfig(
            map: map,
            unitCatalog: catalog.sorted { $0.id < $1.id },
            player: TeamSetup(
                placements: [UnitPlacement(type: archer, cell: 0, isCommander: true)],
                programs: [
                    RuleProgram(
                        unitType: archer,
                        rules: [
                            Rule(condition: .enemyWithin(cells: 2), action: .retreat),
                            Rule(condition: .always, action: .hold),
                        ])
                ]
            ),
            enemy: TeamSetup(
                placements: [UnitPlacement(type: shield, cell: 3)],
                programs: [RuleProgram(unitType: shield, rules: [Rule(condition: .always, action: .advance)])]
            ),
            objective: .eliminate,
            constraints: .unrestricted,
            seed: 1,
            maxTicks: 300
        )
    }

    static func waitUntilPlaying(_ model: BattleModel, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now + timeout
        while model.phase != .playing {
            if ContinuousClock.now > deadline {
                Issue.record("timed out waiting for .playing")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
