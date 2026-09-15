import Testing

@testable import FermanCore

@Suite("BattleMap")
struct BattleMapTests {
    @Test func asciiRowsRoundTrip() throws {
        let map = try Fixtures.map()
        #expect(map.width == 8)
        #expect(map.height == 4)
        #expect(map.cellCount == 32)
        #expect(map.playerZone == [0, 1, 8, 9, 16, 17, 24, 25])
        #expect(map.enemyZone == [6, 7, 14, 15, 22, 23, 30, 31])
        #expect(map.terrainRows == ["........", "..FF..HH", "..FFWW..", "....RR.."])
        #expect(map.zoneRows == ["PP....EE", "PP....EE", "PP....EE", "PP....EE"])
        #expect(try JSON.roundTrip(map) == map)
    }

    @Test func cellGeometry() throws {
        let map = try Fixtures.map()
        #expect(map.cellIndex(column: 3, row: 2) == 19)
        #expect(map.cellIndex(column: 8, row: 0) == nil)
        #expect(map.cellIndex(column: 0, row: -1) == nil)
        #expect(map.coordinates(ofCell: 19) == (column: 3, row: 2))
        #expect(
            map.center(ofCell: 19)
                == FixedVector2(x: Fixed(numerator: 7, denominator: 2), y: Fixed(numerator: 5, denominator: 2)))
        #expect(map.terrain[19] == .forest)
        #expect(map.zone(for: .player) == map.playerZone)
        #expect(map.zone(for: .enemy) == map.enemyZone)
    }

    struct RowsCase: Sendable, CustomTestStringConvertible {
        let terrain: [String]
        let zones: [String]
        let error: BattleMapError
        let testDescription: String
    }

    @Test(arguments: [
        RowsCase(terrain: [], zones: [], error: .empty, testDescription: "no rows"),
        RowsCase(
            terrain: ["...", ".."], zones: ["P.E", "P."],
            error: .raggedRows(row: 1, expectedWidth: 3, actualWidth: 2), testDescription: "ragged terrain"
        ),
        RowsCase(
            terrain: ["..X"], zones: ["P.E"],
            error: .unknownTerrainSymbol("X", row: 0, column: 2), testDescription: "unknown terrain"
        ),
        RowsCase(
            terrain: ["...", "..."], zones: ["P.E"],
            error: .zoneGridMismatch(expectedWidth: 3, expectedHeight: 2), testDescription: "missing zone row"
        ),
        RowsCase(
            terrain: ["..."], zones: ["P.Z"],
            error: .unknownZoneSymbol("Z", row: 0, column: 2), testDescription: "unknown zone"
        ),
        RowsCase(terrain: ["..."], zones: ["..E"], error: .missingZone(.player), testDescription: "no player zone"),
        RowsCase(terrain: ["..."], zones: ["P.."], error: .missingZone(.enemy), testDescription: "no enemy zone"),
        RowsCase(
            terrain: ["W.."], zones: ["P.E"],
            error: .zoneOnImpassableTerrain(.player, cell: 0), testDescription: "zone on water"
        ),
        RowsCase(
            terrain: [String(repeating: ".", count: 129)], zones: ["P" + String(repeating: ".", count: 127) + "E"],
            error: .tooLarge(width: 129, height: 1, maximum: 128), testDescription: "too wide"
        ),
    ])
    func rowsAreValidated(rowsCase: RowsCase) {
        #expect(throws: rowsCase.error) {
            try BattleMap(terrainRows: rowsCase.terrain, zoneRows: rowsCase.zones)
        }
    }

    @Test func explicitZonesAreValidated() {
        let terrain = [Terrain](repeating: .open, count: 4)
        #expect(throws: BattleMapError.terrainCountMismatch(expected: 6, actual: 4)) {
            try BattleMap(width: 3, height: 2, terrain: terrain, playerZone: [0], enemyZone: [1])
        }
        #expect(throws: BattleMapError.zoneCellOutOfBounds(.enemy, cell: 4)) {
            try BattleMap(width: 2, height: 2, terrain: terrain, playerZone: [0], enemyZone: [4])
        }
        #expect(throws: BattleMapError.zoneCellsNotStrictlyIncreasing(.player, cell: 0)) {
            try BattleMap(width: 2, height: 2, terrain: terrain, playerZone: [1, 0], enemyZone: [3])
        }
        #expect(throws: BattleMapError.zoneCellsNotStrictlyIncreasing(.player, cell: 1)) {
            try BattleMap(width: 2, height: 2, terrain: terrain, playerZone: [1, 1], enemyZone: [3])
        }
        #expect(throws: BattleMapError.zonesOverlap(cell: 2)) {
            try BattleMap(width: 2, height: 2, terrain: terrain, playerZone: [0, 2], enemyZone: [2, 3])
        }
    }

    @Test func invalidMapJSONIsADecodingError() {
        #expect(throws: DecodingError.self) {
            try JSON.decode(BattleMap.self, from: #"{"terrain":["..W"],"zones":["P.E"]}"#)
        }
    }
}

@Suite("Model")
struct ModelTests {
    @Test func unitTypeIDsOrderByBytes() {
        let ids: [UnitTypeID] = ["suvari", "okcu", "kalkan", "Zeta", "mizrakci"]
        #expect(ids.sorted().map(\.rawValue) == ["Zeta", "kalkan", "mizrakci", "okcu", "suvari"])
        #expect(UnitTypeID(rawValue: "okcu").description == "okcu")
        #expect(UnitID(rawValue: 3) < UnitID(rawValue: 10))
        #expect(UnitID(rawValue: 3).description == "#3")
    }

    @Test func teamsOpposeEachOther() {
        #expect(Team.player.opponent == .enemy)
        #expect(Team.enemy.opponent == .player)
    }

    @Test(arguments: Terrain.allCases)
    func terrainSymbolsRoundTrip(terrain: Terrain) {
        #expect(Terrain(symbol: terrain.symbol) == terrain)
    }

    @Test func terrainProperties() {
        #expect(Terrain(symbol: "?") == nil)
        #expect(Terrain.allCases.filter(\.providesCover) == [.forest, .rubble])
        #expect(Terrain.allCases.filter { !$0.isPassable } == [.water])

        let values = PassableTerrainValues(open: 1, forest: 2, hill: 3, rubble: 4)
        #expect(Terrain.allCases.map { values[$0] } == [1, 2, 3, nil, 4])
    }

    @Test func conditionParameterRangesMatchThePlan() {
        #expect(ConditionKind.enemyWithin.parameter == .cells(1...10))
        #expect(ConditionKind.healthBelow.parameter == .percent(10...90))
        #expect(ConditionKind.allyCountBelow.parameter == .count(1...10))
        #expect(ConditionKind.timeAfter.parameter == .seconds(1...60))
        #expect(ConditionKind.moraleBelow.parameter == .percent(10...90))
        #expect(ConditionKind.enemyDensityAbove.parameter == .count(2...8))
        #expect(ConditionKind.targetInRange.parameter == .unitType)
        #expect(ConditionKind.nearestEnemyType.parameter == .unitType)
        #expect(ConditionKind.terrainIs.parameter == .terrain)
        #expect([ConditionKind.isFlanked, .commanderDead, .always].allSatisfy { $0.parameter == .none })
        #expect(ActionKind.allCases.filter { $0.parameter == .optionalUnitType } == [.focusFire])
    }

    @Test func configAccessors() throws {
        let config = try Fixtures.config()
        #expect(config.simulationVersion == SimulationVersion.current)
        #expect(config.maxTicks == 1_800)
        #expect(config.tuning == .standard)
        #expect(config.setup(for: .player) == config.player)
        #expect(config.setup(for: .enemy) == config.enemy)
        #expect(config.player.program(for: Fixtures.shield)?.rules.count == 1)
        #expect(config.enemy.program(for: Fixtures.archer) == nil)
        #expect(SimulationOptions().recordEvents)
    }
}
