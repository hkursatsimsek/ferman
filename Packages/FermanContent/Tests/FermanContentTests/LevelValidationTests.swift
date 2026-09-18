import FermanCore
import Testing

@testable import FermanContent

@Suite("Level validation")
struct LevelValidationTests {
    static func minimalLevel(id: Int = 1) -> LevelDefinition {
        LevelDefinition(
            id: id,
            map: "alan",
            objective: .eliminate,
            constraints: RuleConstraints(maxRules: 0, availableConditions: [.always], availableActions: [.advance]),
            playerBudget: 25,
            seed: 1,
            maxTicks: 1_800,
            enemy: TeamSetup(
                placements: [UnitPlacement(type: "suvari", cell: 23)],
                programs: [RuleProgram(unitType: "suvari", rules: [Rule(condition: .always, action: .advance)])]
            ),
            referenceSolution: TeamSetup(
                placements: [UnitPlacement(type: "mizrakci", cell: 0)],
                programs: [RuleProgram(unitType: "mizrakci", rules: [Rule(condition: .always, action: .advance)])]
            )
        )
    }

    static func error(_ levels: [LevelDefinition]) throws -> LevelError? {
        let bundled = try ContentCatalog.bundled()
        do {
            _ = try ContentCatalog(units: bundled.units, maps: bundled.maps, levels: levels)
            return nil
        } catch .invalidLevelCatalog(let error) {
            return error
        }
    }

    @Test func validLevelLoads() throws {
        let catalog = try ContentCatalog(
            units: try ContentCatalog.bundled().units, maps: try ContentCatalog.bundled().maps,
            levels: [Self.minimalLevel()])
        #expect(catalog.levels.map(\.id) == [1])
        #expect(catalog.level(1) != nil)
        #expect(catalog.level(2) == nil)
    }

    @Test func duplicateIdentifier() throws {
        #expect(try Self.error([Self.minimalLevel(id: 1), Self.minimalLevel(id: 1)]) == .duplicateIdentifier(1))
    }

    /// `ContentCatalog` sorts by `id` before validating (as it does for units), so this only reaches
    /// `LevelDefinition.validateCatalog` directly — the same way `UnitCatalogValidationTests` exercises
    /// `UnitType.validateCatalog`'s equivalent case.
    @Test func notSortedByIdentifier() throws {
        let bundled = try ContentCatalog.bundled()
        #expect(throws: LevelError.notSortedByIdentifier(1)) {
            try LevelDefinition.validateCatalog(
                [Self.minimalLevel(id: 2), Self.minimalLevel(id: 1)], units: bundled.units, maps: bundled.maps)
        }
    }

    @Test func unknownMap() throws {
        var level = Self.minimalLevel()
        level = LevelDefinition(
            id: level.id, map: "yok", objective: level.objective, constraints: level.constraints,
            playerBudget: level.playerBudget, seed: level.seed, maxTicks: level.maxTicks, enemy: level.enemy,
            referenceSolution: level.referenceSolution)
        #expect(try Self.error([level]) == .unknownMap(level: 1, map: "yok"))
    }

    @Test func unknownUnitType() throws {
        let level = Self.minimalLevel()
        let brokenReference = TeamSetup(
            placements: [UnitPlacement(type: "fil", cell: 0)],
            programs: [RuleProgram(unitType: "fil", rules: [Rule(condition: .always, action: .advance)])]
        )
        let broken = LevelDefinition(
            id: level.id, map: level.map, objective: level.objective, constraints: level.constraints,
            playerBudget: level.playerBudget, seed: level.seed, maxTicks: level.maxTicks, enemy: level.enemy,
            referenceSolution: brokenReference)
        #expect(try Self.error([broken]) == .unknownUnitType(level: 1, team: .player, unitType: "fil"))
    }

    @Test func placementOutsideZone() throws {
        let level = Self.minimalLevel()
        let brokenReference = TeamSetup(
            placements: [UnitPlacement(type: "mizrakci", cell: 23)],
            programs: level.referenceSolution.programs
        )
        let broken = LevelDefinition(
            id: level.id, map: level.map, objective: level.objective, constraints: level.constraints,
            playerBudget: level.playerBudget, seed: level.seed, maxTicks: level.maxTicks, enemy: level.enemy,
            referenceSolution: brokenReference)
        #expect(try Self.error([broken]) == .placementOutsideZone(level: 1, team: .player, cell: 23))
    }

    @Test func multipleCommanders() throws {
        let level = Self.minimalLevel()
        let brokenReference = TeamSetup(
            placements: [
                UnitPlacement(type: "mizrakci", cell: 0, isCommander: true),
                UnitPlacement(type: "mizrakci", cell: 1, isCommander: true),
            ],
            programs: level.referenceSolution.programs
        )
        let broken = LevelDefinition(
            id: level.id, map: level.map, objective: level.objective, constraints: level.constraints,
            playerBudget: level.playerBudget, seed: level.seed, maxTicks: level.maxTicks, enemy: level.enemy,
            referenceSolution: brokenReference)
        #expect(try Self.error([broken]) == .multipleCommanders(level: 1, team: .player))
    }

    @Test func invalidReferenceSolution() throws {
        let level = Self.minimalLevel()
        let brokenReference = TeamSetup(
            placements: level.referenceSolution.placements,
            programs: [
                RuleProgram(
                    unitType: "mizrakci",
                    rules: [
                        Rule(condition: .enemyWithin(cells: 3), action: .retreat),
                        Rule(condition: .always, action: .advance),
                    ])
            ]
        )
        let broken = LevelDefinition(
            id: level.id, map: level.map, objective: level.objective, constraints: level.constraints,
            playerBudget: level.playerBudget, seed: level.seed, maxTicks: level.maxTicks, enemy: level.enemy,
            referenceSolution: brokenReference)
        guard case .invalidReferenceSolution(let levelID, let errors) = try Self.error([broken]) else {
            Issue.record("expected invalidReferenceSolution")
            return
        }
        #expect(levelID == 1)
        #expect(errors.contains(.conditionNotAvailable(unitType: "mizrakci", ruleIndex: 0, kind: .enemyWithin)))
    }

    @Test func referenceSolutionOverBudget() throws {
        let level = Self.minimalLevel()
        let broken = LevelDefinition(
            id: level.id, map: level.map, objective: level.objective, constraints: level.constraints,
            playerBudget: 1, seed: level.seed, maxTicks: level.maxTicks, enemy: level.enemy,
            referenceSolution: level.referenceSolution)
        #expect(try Self.error([broken]) == .referenceSolutionOverBudget(level: 1, used: 25, budget: 1))
    }
}
