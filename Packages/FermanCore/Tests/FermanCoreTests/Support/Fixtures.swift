import Foundation

@testable import FermanCore

/// Small, readable battle ingredients shared by tests. Balance numbers here are placeholders, not content.
enum Fixtures {
    static let spearman: UnitTypeID = "mizrakci"
    static let archer: UnitTypeID = "okcu"
    static let cavalry: UnitTypeID = "suvari"
    static let shield: UnitTypeID = "kalkan"

    static let catalog: [UnitType] = [
        UnitType(
            id: shield, cost: 30, maxHP: 160, speedMilliCellsPerSecond: 900, rangeMilliCells: 1_000, damage: 8,
            attackIntervalTicks: 30, armor: 4, moraleMax: 100, counters: [archer], ability: .shieldWall
        ),
        UnitType(
            id: spearman, cost: 25, maxHP: 110, speedMilliCellsPerSecond: 1_100, rangeMilliCells: 1_500, damage: 12,
            attackIntervalTicks: 27, armor: 2, moraleMax: 100, counters: [cavalry], ability: .spearWall
        ),
        UnitType(
            id: archer, cost: 30, maxHP: 70, speedMilliCellsPerSecond: 1_000, rangeMilliCells: 6_000, damage: 10,
            attackIntervalTicks: 36, armor: 0, moraleMax: 90, counters: [spearman], ability: .volley
        ),
        UnitType(
            id: cavalry, cost: 40, maxHP: 120, speedMilliCellsPerSecond: 2_400, rangeMilliCells: 1_000, damage: 14,
            attackIntervalTicks: 24, armor: 1, moraleMax: 110, counters: [archer], ability: .charge
        ),
    ]

    static func map() throws -> BattleMap {
        try BattleMap(
            terrainRows: [
                "........",
                "..FF..HH",
                "..FFWW..",
                "....RR..",
            ],
            zoneRows: [
                "PP....EE",
                "PP....EE",
                "PP....EE",
                "PP....EE",
            ]
        )
    }

    static func config(seed: UInt64 = 7) throws -> BattleConfig {
        BattleConfig(
            map: try map(),
            unitCatalog: catalog.sorted { $0.id < $1.id },
            player: TeamSetup(
                placements: [
                    UnitPlacement(type: archer, cell: 8),
                    UnitPlacement(type: shield, cell: 9, isCommander: true),
                ],
                programs: [
                    RuleProgram(
                        unitType: archer,
                        rules: [
                            Rule(condition: .enemyWithin(cells: 2), action: .retreat),
                            Rule(condition: .always, action: .hold),
                        ]
                    ),
                    RuleProgram(unitType: shield, rules: [Rule(condition: .always, action: .advance)]),
                ]
            ),
            enemy: TeamSetup(
                placements: [UnitPlacement(type: cavalry, cell: 15)],
                programs: [
                    RuleProgram(
                        unitType: cavalry,
                        rules: [
                            Rule(condition: .targetInRange(archer), action: .focusFire(archer)),
                            Rule(condition: .always, action: .advance),
                        ]
                    )
                ]
            ),
            objective: .eliminate,
            constraints: .unrestricted,
            seed: seed
        )
    }
}

enum JSON {
    static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from text: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }

    static func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: try JSONEncoder().encode(value))
    }
}
