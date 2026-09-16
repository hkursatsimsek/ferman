import Testing

@testable import FermanCore

@Suite("BattleSimulator")
struct BattleSimulatorTests {
    @Test func sameConfigProducesTheSameChecksumEveryTime() throws {
        let config = try Self.shortConfig()
        let first = BattleSimulator.run(config)
        for _ in 0..<1_000 {
            let repeated = BattleSimulator.run(config)
            #expect(repeated.checksum == first.checksum)
            #expect(repeated.outcome == first.outcome)
            #expect(repeated.endReason == first.endReason)
            #expect(repeated.tickCount == first.tickCount)
            #expect(repeated.events == first.events)
            #expect(repeated.ruleFireCounts == first.ruleFireCounts)
        }
    }

    @Test func aDifferentSeedCanChangeTheChecksumWhenScatterConsumesTheRNG() throws {
        // The enemy sits to this unit's left; its facing defaults to +x, so every hit lands from behind and
        // breaks it on the very first tick with `flankedMoralePenalty` this high. From tick 1 on it scatters in a
        // direction `DeterministicRNG` draws, which is the only place a battle's outcome depends on the seed.
        let first = BattleSimulator.run(try Self.flankingBreakConfig(seed: 1))
        let second = BattleSimulator.run(try Self.flankingBreakConfig(seed: 2))
        #expect(first.checksum != second.checksum)
    }

    @Test func disablingEventRecordingLeavesTheChecksumUnchanged() throws {
        let config = try Self.shortConfig()
        let withEvents = BattleSimulator.run(config, options: SimulationOptions(recordEvents: true))
        let withoutEvents = BattleSimulator.run(config, options: SimulationOptions(recordEvents: false))
        #expect(withoutEvents.events.isEmpty)
        #expect(!withEvents.events.isEmpty)
        #expect(withEvents.checksum == withoutEvents.checksum)
        #expect(withEvents.outcome == withoutEvents.outcome)
        #expect(withEvents.ruleFireCounts == withoutEvents.ruleFireCounts)
    }

    @Test func theEventStreamOpensWithSpawnsAndClosesWithBattleEnded() throws {
        let result = BattleSimulator.run(try Self.shortConfig())
        let placementCount = 3
        let spawns = result.events.prefix(placementCount)
        #expect(spawns.allSatisfy { if case .spawn = $0.kind { true } else { false } })
        guard case .battleEnded(let outcome, let reason) = result.events.last?.kind else {
            Issue.record("last event was not battleEnded")
            return
        }
        #expect(outcome == result.outcome)
        #expect(reason == result.endReason)
    }

    @Test func ruleFireCountsAreOrderedByTeamThenUnitTypeAndSizedToEachProgram() throws {
        // "kalkan" sorts before "okcu" in UTF-8 byte order, so the player's two programs come back shield-first.
        let config = try Fixtures.config()
        let result = BattleSimulator.run(config)
        #expect(result.ruleFireCounts.map(\.team) == [.player, .player, .enemy])
        #expect(result.ruleFireCounts.map(\.unitType) == [Fixtures.shield, Fixtures.archer, Fixtures.cavalry])
        #expect(result.ruleFireCounts[0].counts.count == 1)
        #expect(result.ruleFireCounts[1].counts.count == 2)
        #expect(result.ruleFireCounts[2].counts.count == 2)
    }

    @Test func theArcherRetreatRuleFiresOnceTheApproachingCavalryClosesWithin2Cells() throws {
        let config = try Fixtures.config()
        let result = BattleSimulator.run(config)
        let archerCounts = result.ruleFireCounts.first { $0.unitType == Fixtures.archer }
        #expect(archerCounts?.counts[0] ?? 0 > 0)
    }

    @Test func eliminatingEveryEnemyUnitEndsTheBattleWithElimination() throws {
        // A lone, harmless shield-bearer that never attacks cannot survive a full army of archers volleying it.
        let map = try BattleMap(terrainRows: ["...."], zoneRows: ["P..E"])
        let config = BattleConfig(
            map: map, unitCatalog: Fixtures.catalog.sorted { $0.id < $1.id },
            player: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.archer, cell: 0)],
                programs: [RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .hold)])]),
            enemy: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.shield, cell: 3)],
                programs: [RuleProgram(unitType: Fixtures.shield, rules: [Rule(condition: .always, action: .hold)])]),
            objective: .eliminate, constraints: .unrestricted, seed: 1
        )
        let result = BattleSimulator.run(config)
        #expect(result.outcome == .playerWin)
        #expect(result.endReason == .elimination)
        #expect(result.survivorsEnemy == 0)
        #expect(result.survivorsPlayer == 1)
    }

    @Test func flankLeftHeadsForAWaypointOffsetFromTheEnemyRatherThanStraightAtIt() throws {
        let width = 14
        let height = 12
        let map = try BattleMap(
            terrainRows: Array(repeating: String(repeating: ".", count: width), count: height),
            zoneRows: ["P" + String(repeating: ".", count: width - 2) + "E"]
                + Array(repeating: String(repeating: ".", count: width), count: height - 1)
        )
        let playerCell = 6 * 14 + 10
        let enemyCell = 6 * 14 + 3
        let config = BattleConfig(
            map: map, unitCatalog: Fixtures.catalog.sorted { $0.id < $1.id },
            player: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.archer, cell: playerCell)],
                programs: [
                    RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .flankLeft)])
                ]),
            enemy: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.archer, cell: enemyCell)],
                programs: [RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .hold)])]),
            objective: .eliminate, constraints: .unrestricted, seed: 1, maxTicks: 150
        )
        let result = BattleSimulator.run(config)
        let positions = Self.movePositions(of: UnitID(rawValue: 0), in: result.events)
        let first = try #require(positions.first)
        let last = try #require(positions.last)
        // Straight advance would only close the gap in x; flanking also pulls the unit off that line in y.
        #expect(last.x < first.x)
        #expect(last.y < first.y)
    }

    @Test func regroupHeadsForTheCentroidOfNearbySameTypeAllies() throws {
        let map = try BattleMap(
            terrainRows: [String(repeating: ".", count: 20)], zoneRows: ["P" + String(repeating: ".", count: 18) + "E"])
        let config = BattleConfig(
            map: map, unitCatalog: Fixtures.catalog.sorted { $0.id < $1.id },
            player: TeamSetup(
                placements: [
                    UnitPlacement(type: Fixtures.archer, cell: 2), UnitPlacement(type: Fixtures.archer, cell: 7),
                ],
                programs: [
                    RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .regroup)])
                ]),
            enemy: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.archer, cell: 19)],
                programs: [RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .hold)])]),
            objective: .eliminate, constraints: .unrestricted, seed: 1, maxTicks: 60
        )
        let result = BattleSimulator.run(config)
        // Both player archers share one program, so unit 1 also "regroups" — toward unit 0, its only same-type
        // ally within radius — but it started closer to the ally-free enemy and so drifts less; unit 0 is the
        // clean signal.
        let positions = Self.movePositions(of: UnitID(rawValue: 0), in: result.events)
        let first = try #require(positions.first)
        let last = try #require(positions.last)
        #expect(last.x > first.x)
    }

    @Test func takeCoverHoldsInPlaceWhenNoCoverIsInReach() throws {
        let map = try BattleMap(
            terrainRows: [String(repeating: ".", count: 12)], zoneRows: ["P" + String(repeating: ".", count: 10) + "E"])
        let config = BattleConfig(
            map: map, unitCatalog: Fixtures.catalog.sorted { $0.id < $1.id },
            player: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.archer, cell: 2)],
                programs: [
                    RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .takeCover)])
                ]),
            enemy: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.archer, cell: 11)],
                programs: [RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .hold)])]),
            objective: .eliminate, constraints: .unrestricted, seed: 1, maxTicks: 60
        )
        let result = BattleSimulator.run(config)
        #expect(Self.movePositions(of: UnitID(rawValue: 0), in: result.events).isEmpty)
    }

    @Test func takeCoverWalksToTheNearestCoverCellAndStopsThere() throws {
        var terrain = Array(repeating: Character("."), count: 12)
        terrain[5] = "F"
        let map = try BattleMap(
            terrainRows: [String(terrain)], zoneRows: ["P" + String(repeating: ".", count: 10) + "E"])
        let config = BattleConfig(
            map: map, unitCatalog: Fixtures.catalog.sorted { $0.id < $1.id },
            player: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.archer, cell: 2)],
                programs: [
                    RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .takeCover)])
                ]),
            enemy: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.archer, cell: 11)],
                programs: [RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .hold)])]),
            objective: .eliminate, constraints: .unrestricted, seed: 1, maxTicks: 150
        )
        let result = BattleSimulator.run(config)
        let last = try #require(Self.movePositions(of: UnitID(rawValue: 0), in: result.events).last)
        let forestCenter = FixedVector2(x: Fixed(5) + .half, y: .half)
        // `.move` only samples every 3 ticks, so the last recorded step can land shortly before the unit actually
        // settles inside its half-cell arrival radius; allow for that gap rather than pinning the exact radius.
        #expect(last.distanceSquared(to: forestCenter) <= Fixed(1).squared)
    }

    @Test func guardCommanderClosesInOnTheCommander() throws {
        let map = try BattleMap(
            terrainRows: [String(repeating: ".", count: 20)], zoneRows: ["P" + String(repeating: ".", count: 18) + "E"])
        let config = BattleConfig(
            map: map, unitCatalog: Fixtures.catalog.sorted { $0.id < $1.id },
            player: TeamSetup(
                placements: [
                    UnitPlacement(type: Fixtures.shield, cell: 15, isCommander: true),
                    UnitPlacement(type: Fixtures.archer, cell: 2),
                ],
                programs: [
                    RuleProgram(unitType: Fixtures.shield, rules: [Rule(condition: .always, action: .hold)]),
                    RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .guardCommander)]),
                ]),
            enemy: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.archer, cell: 19)],
                programs: [RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .hold)])]),
            objective: .eliminate, constraints: .unrestricted, seed: 1, maxTicks: 150
        )
        let result = BattleSimulator.run(config)
        let positions = Self.movePositions(of: UnitID(rawValue: 1), in: result.events)
        let first = try #require(positions.first)
        let last = try #require(positions.last)
        #expect(last.x > first.x)
    }

    @Test func useAbilityFiresAOneTimeVolleyThatHitsEveryEnemyInItsRadius() throws {
        let map = try BattleMap(terrainRows: [String(repeating: ".", count: 8)], zoneRows: ["P.....EE"])
        let config = BattleConfig(
            map: map, unitCatalog: Fixtures.catalog.sorted { $0.id < $1.id },
            player: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.archer, cell: 0)],
                programs: [
                    RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .useAbility)])
                ]),
            enemy: TeamSetup(
                placements: [
                    UnitPlacement(type: Fixtures.archer, cell: 6), UnitPlacement(type: Fixtures.archer, cell: 7),
                ],
                programs: [RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .hold)])]),
            objective: .eliminate, constraints: .unrestricted, seed: 1, maxTicks: 5
        )
        let result = BattleSimulator.run(config)
        let tickZeroPlayerEvents = result.events.filter { $0.tick == 0 }
        let attackTargets = tickZeroPlayerEvents.compactMap { event -> UnitID? in
            guard case .attack(UnitID(rawValue: 0), let target, _) = event.kind else { return nil }
            return target
        }
        #expect(Set(attackTargets) == Set([UnitID(rawValue: 1), UnitID(rawValue: 2)]))
        #expect(tickZeroPlayerEvents.contains { $0.kind == .abilityUsed(UnitID(rawValue: 0), .volley) })
    }

    @Test func focusFirePicksTheWeakestEnemyInReachWhenNoTypeIsPreferred() throws {
        let config = try Self.focusFireConfig(preferredType: nil)
        let result = BattleSimulator.run(config)
        let firstTarget = result.events.compactMap { event -> UnitID? in
            guard case .attack(UnitID(rawValue: 0), let target, _) = event.kind else { return nil }
            return target
        }.first
        // "okcu" (archer, 70 HP) is the weakest of the three enemy types present, even though it is the farthest.
        #expect(firstTarget == UnitID(rawValue: 3))
    }

    @Test func focusFirePrefersItsNamedTypeOverTheWeakestEnemy() throws {
        let config = try Self.focusFireConfig(preferredType: Fixtures.shield)
        let result = BattleSimulator.run(config)
        let firstTarget = result.events.compactMap { event -> UnitID? in
            guard case .attack(UnitID(rawValue: 0), let target, _) = event.kind else { return nil }
            return target
        }.first
        #expect(firstTarget == UnitID(rawValue: 1))
    }

    @Test func holdLineRewardsThePlayerForSurvivingToTheTimeLimit() throws {
        let map = try BattleMap(terrainRows: ["...................."], zoneRows: ["P..................E"])
        let config = BattleConfig(
            map: map, unitCatalog: Fixtures.catalog.sorted { $0.id < $1.id },
            player: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.shield, cell: 0)],
                programs: [RuleProgram(unitType: Fixtures.shield, rules: [Rule(condition: .always, action: .hold)])]),
            enemy: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.shield, cell: 19)],
                programs: [RuleProgram(unitType: Fixtures.shield, rules: [Rule(condition: .always, action: .hold)])]),
            objective: .holdLine, constraints: .unrestricted, seed: 1, maxTicks: 30
        )
        let result = BattleSimulator.run(config)
        #expect(result.outcome == .playerWin)
        #expect(result.endReason == .timeLimit)
        #expect(result.tickCount == 30)
    }

    private static func movePositions(of id: UnitID, in events: [BattleEvent]) -> [FixedVector2] {
        events.compactMap { event -> FixedVector2? in
            guard case .move(id, let position) = event.kind else { return nil }
            return position
        }
    }

    /// One player archer facing three enemy types at different distances, all within `focusFire`'s search radius
    /// (range + 2) and its actual range: "kalkan" (shield, 160 HP) closest, then "suvari" (cavalry, 120 HP), then
    /// "okcu" (archer, 70 HP) farthest but weakest.
    private static func focusFireConfig(preferredType: UnitTypeID?) throws -> BattleConfig {
        BattleConfig(
            map: try BattleMap(terrainRows: [String(repeating: ".", count: 8)], zoneRows: ["P..EEE.E"]),
            unitCatalog: Fixtures.catalog.sorted { $0.id < $1.id },
            player: TeamSetup(
                placements: [UnitPlacement(type: Fixtures.archer, cell: 0)],
                programs: [
                    RuleProgram(
                        unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .focusFire(preferredType))])
                ]),
            enemy: TeamSetup(
                placements: [
                    UnitPlacement(type: Fixtures.shield, cell: 3), UnitPlacement(type: Fixtures.cavalry, cell: 4),
                    UnitPlacement(type: Fixtures.archer, cell: 5),
                ],
                programs: [
                    RuleProgram(unitType: Fixtures.shield, rules: [Rule(condition: .always, action: .hold)]),
                    RuleProgram(unitType: Fixtures.cavalry, rules: [Rule(condition: .always, action: .hold)]),
                    RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .hold)]),
                ]),
            objective: .eliminate, constraints: .unrestricted, seed: 1, maxTicks: 1
        )
    }

    private static func shortConfig(seed: UInt64 = 7) throws -> BattleConfig {
        try Fixtures.config(seed: seed).with(maxTicks: 120)
    }

    private static func flankingBreakConfig(seed: UInt64) throws -> BattleConfig {
        var tuning = SimulationTuning.standard
        tuning.flankedMoralePenalty = 1_000
        let alwaysHold = RuleProgram(unitType: Fixtures.archer, rules: [Rule(condition: .always, action: .hold)])
        return BattleConfig(
            // A second player archer sits at cell 9, 9 cells from the enemy — outside its range-6 reach — so it
            // never breaks. Without it, the lone flanked archer breaking would rout the whole player team on
            // tick 0, ending the battle before scatter ever gets to draw from the RNG.
            map: try BattleMap(terrainRows: [String(repeating: ".", count: 10)], zoneRows: ["E..P.....P"]),
            unitCatalog: Fixtures.catalog.sorted { $0.id < $1.id }, tuning: tuning,
            player: TeamSetup(
                placements: [
                    UnitPlacement(type: Fixtures.archer, cell: 3), UnitPlacement(type: Fixtures.archer, cell: 9),
                ],
                programs: [alwaysHold]),
            enemy: TeamSetup(placements: [UnitPlacement(type: Fixtures.archer, cell: 0)], programs: [alwaysHold]),
            objective: .eliminate, constraints: .unrestricted, seed: seed, maxTicks: 40
        )
    }
}

extension BattleConfig {
    fileprivate func with(maxTicks: Int) -> BattleConfig {
        BattleConfig(
            simulationVersion: simulationVersion, map: map, unitCatalog: unitCatalog, tuning: tuning, player: player,
            enemy: enemy, objective: objective, constraints: constraints, seed: seed, maxTicks: maxTicks)
    }
}
