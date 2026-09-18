import FermanCore
import Testing

@testable import FermanContent

/// Every level's `referenceSolution` must actually win, and from level 2 on the player must need more than the
/// untouched default order to do it (FERMAN-PLAN §6, F1.12's definition of done).
@Suite("Level solvability")
struct LevelSolvabilityTests {
    let catalog: ContentCatalog

    init() throws {
        catalog = try ContentCatalog.bundled()
    }

    @Test(arguments: 1...8)
    func referenceSolutionWins(levelID: Int) throws {
        let level = try #require(catalog.level(levelID))
        let result = BattleSimulator.run(try battleConfig(for: level, player: level.referenceSolution))
        #expect(result.outcome == .playerWin, "level \(levelID)")
    }

    /// "Yalnız varsayılan emirle" (D4): every unit type reduced to the single rule a fresh, untouched order stack
    /// starts with — `.always` → `.advance`, the same fallback `BattleSimulator` uses for a unit with no program
    /// at all. Level 1 is deliberately excluded: its whole point is that this untouched default already wins.
    @Test(arguments: 2...8)
    func defaultOrderAloneLoses(levelID: Int) throws {
        let level = try #require(catalog.level(levelID))
        let untouched = TeamSetup(
            placements: level.referenceSolution.placements,
            programs: Self.unitTypes(in: level.referenceSolution).map {
                RuleProgram(unitType: $0, rules: [Rule(condition: .always, action: .advance)])
            }
        )
        let result = BattleSimulator.run(try battleConfig(for: level, player: untouched))
        #expect(result.outcome != .playerWin, "level \(levelID)")
    }

    private static func unitTypes(in team: TeamSetup) -> [UnitTypeID] {
        Array(Set(team.placements.map(\.type))).sorted()
    }

    private func battleConfig(for level: LevelDefinition, player: TeamSetup) throws -> BattleConfig {
        BattleConfig(
            map: try #require(catalog.map(level.map)),
            unitCatalog: catalog.units,
            player: player,
            enemy: level.enemy,
            objective: level.objective,
            constraints: level.constraints,
            seed: level.seed,
            maxTicks: level.maxTicks
        )
    }
}
