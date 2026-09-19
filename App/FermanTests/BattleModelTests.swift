import FermanCore
import FermanReplay
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

    @Test
    func triggerRowsCarryTheOrdersWords() async throws {
        let model = BattleModel(
            config: try Fixture.config(), orders: Fixture.orders, phrases: [Fixture.archer: Fixture.orders])
        model.start(reduceMotion: true)
        try await Fixture.waitUntilPlaying(model)

        #expect(model.triggerRows.map(\.condition) == ["düşman 2 kareden yakınsa", "başka durumda"])
        #expect(model.triggerRows.map(\.action) == ["GERİ ÇEKİL", "İLERLE"])
        #expect(model.triggerRows.map(\.isDefault) == [false, true])
    }

    @Test
    func onlyUnitTypesWithAProgramCanBeSelected() async throws {
        let model = BattleModel(config: try Fixture.config(), orders: Fixture.orders)
        model.start(reduceMotion: true)
        try await Fixture.waitUntilPlaying(model)

        #expect(model.playerUnitTypes == [Fixture.archer])
        model.selectUnitType(Fixture.shield)
        #expect(model.selectedUnitType == Fixture.archer)
    }

    /// Seeks to a tick where the fixture's archer is holding (its second order) and pauses there.
    private static func archerHolding(_ model: BattleModel) throws -> UnitID {
        let timeline = try #require(model.timeline)
        let clock = try #require(model.clock)
        clock.isPlaying = false
        let archer = try #require(timeline.frame(at: 1).teams.first { $0.value == .player }?.key)
        let tick = try #require((1..<300).first { timeline.frame(at: Int32($0)).activeRuleIndex[archer] == 1 })
        clock.seek(to: Int32(tick))
        return archer
    }

    /// G13's evaluating pen: tap a unit and the pen reads its orders from the top, passing the ones whose
    /// condition doesn't hold, and rests on the one it's carrying out.
    @Test
    func thePenReadsATappedUnitsOrdersFromTheTop() async throws {
        let model = BattleModel(config: try Fixture.config(), orders: [])
        model.start(reduceMotion: false)
        try await Fixture.waitUntilPlaying(model)
        let archer = try Self.archerHolding(model)

        model.selectUnit(archer)
        #expect(model.evaluation == BattleModel.Evaluation(unit: archer, row: 0, target: 1))
        #expect(model.triggerRows.map { $0.pen } == [.reading, nil])

        let deadline = ContinuousClock.now + .seconds(2)
        while model.evaluation?.row != 1, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.triggerRows.map { $0.pen } == [.passed, .holds])
    }

    @Test
    func underReduceMotionThePenIsAlreadyInPlace() async throws {
        let model = BattleModel(config: try Fixture.config(), orders: [])
        model.start(reduceMotion: true)
        try await Fixture.waitUntilPlaying(model)
        let archer = try Self.archerHolding(model)

        model.selectUnit(archer)
        #expect(model.triggerRows.map { $0.pen } == [.passed, .holds])
    }

    /// Empty sand puts the pen down; so does tapping an enemy, whose orders aren't the player's to read.
    @Test
    func tappingElsewherePutsThePenDown() async throws {
        let model = BattleModel(config: try Fixture.config(), orders: [])
        model.start(reduceMotion: true)
        try await Fixture.waitUntilPlaying(model)
        let archer = try Self.archerHolding(model)
        let timeline = try #require(model.timeline)
        let enemy = try #require(timeline.frame(at: 1).teams.first { $0.value == .enemy }?.key)

        model.selectUnit(archer)
        model.selectUnit(nil)
        #expect(model.evaluation == nil)
        #expect(model.triggerRows.allSatisfy { $0.pen == nil })

        model.selectUnit(archer)
        model.selectUnit(enemy)
        #expect(model.evaluation == nil)
    }

    /// At 4× a burst of orders would buzz continuously; the hand feels at most one every 220 ms.
    @Test
    func orderHapticsAreRateLimited() throws {
        let model = BattleModel(config: try Fixture.config(), orders: [])
        let start = ContinuousClock.now
        model.noteOrderCue(at: start)
        model.noteOrderCue(at: start + .milliseconds(100))
        #expect(model.orderFeedbackPulse == 1)
        model.noteOrderCue(at: start + .milliseconds(250))
        #expect(model.orderFeedbackPulse == 2)
    }

    /// The result slip lands with one strike for how it went — a bowl for a win, a knock for a loss.
    @Test
    func theResultSlipIsHeardWithHowItWent() async throws {
        let audio = RecordingAudio()
        let model = BattleModel(config: try Fixture.config(), orders: [], audio: audio)
        model.start(reduceMotion: true)
        try await Fixture.waitUntilPlaying(model)
        let outcome = try #require(model.result?.outcome)
        model.resultSlipLanded()
        let strike: [SoundEffect] =
            switch outcome {
            case .playerWin: [.victory]
            case .enemyWin: [.defeat]
            case .draw: []
            }
        #expect(audio.played == [.slip] + strike)
    }

    @Test
    func aPlayerUnitsCurrentOrderIsTheOneItLastTookUp() async throws {
        let model = BattleModel(
            config: try Fixture.config(), orders: Fixture.orders, phrases: [Fixture.archer: Fixture.orders])
        model.start(reduceMotion: true)
        try await Fixture.waitUntilPlaying(model)
        let timeline = try #require(model.timeline)
        let clock = try #require(model.clock)
        let firstOrder = try #require(
            timeline.result.events.first {
                if case .ruleActivated(UnitID(rawValue: 0), _) = $0.kind { true } else { false }
            })
        clock.seek(to: firstOrder.tick)

        let current = try #require(model.currentOrder(of: UnitID(rawValue: 0)))
        #expect(Fixture.orders.contains { $0.action == current.action })
        // The enemy's units get no bubble.
        #expect(model.currentOrder(of: UnitID(rawValue: 1)) == nil)
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
