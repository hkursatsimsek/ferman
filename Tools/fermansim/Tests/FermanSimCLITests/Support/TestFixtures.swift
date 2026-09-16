import FermanCore
import Foundation

/// A minimal, valid `BattleConfig` for exercising the CLI without depending on `FermanCoreTests`' fixtures, which
/// are private to that target.
enum TestFixtures {
    static func smallConfig(seed: UInt64 = 1, maxTicks: Int = 30) throws -> BattleConfig {
        let archer = UnitType(
            id: "okcu", cost: 30, maxHP: 70, speedMilliCellsPerSecond: 1_000, rangeMilliCells: 6_000, damage: 10,
            attackIntervalTicks: 36, armor: 0, moraleMax: 90, counters: [], ability: .volley)
        let alwaysHold = RuleProgram(unitType: "okcu", rules: [Rule(condition: .always, action: .hold)])
        return BattleConfig(
            map: try BattleMap(terrainRows: ["...."], zoneRows: ["P..E"]), unitCatalog: [archer],
            player: TeamSetup(placements: [UnitPlacement(type: "okcu", cell: 0)], programs: [alwaysHold]),
            enemy: TeamSetup(placements: [UnitPlacement(type: "okcu", cell: 3)], programs: [alwaysHold]),
            objective: .eliminate, constraints: .unrestricted, seed: seed, maxTicks: maxTicks
        )
    }

    /// A fresh, empty temporary directory the caller should remove when done.
    static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fermansim-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func writeConfigFile(_ config: BattleConfig, in directory: URL, named name: String = "config.json") throws
        -> URL
    {
        let url = directory.appendingPathComponent(name)
        try JSONEncoder().encode(config).write(to: url)
        return url
    }
}
