import Foundation
import Testing

@testable import FermanCore

@Suite("FlowField")
struct FlowFieldTests {
    private static let openCost = SimulationTuning.standard.terrainMovementCost

    @Test func costGrowsByTheStepCostAlongAnOpenCorridor() throws {
        let map = try BattleMap(terrainRows: ["....."], zoneRows: ["P...E"])
        let field = FlowField(map: map, terrainMovementCost: Self.openCost, sourceCells: [0])

        #expect((0..<5).map { field.cost(atCell: $0) } == [0, 10, 20, 30, 40])
        #expect(field.direction(atCell: 3) == FixedVector2(x: -Fixed.one, y: .zero))
        #expect(field.direction(atCell: 0) == .zero)
    }

    @Test func aFullHeightWaterColumnMakesTheFarSideUnreachable() throws {
        let map = try BattleMap(
            terrainRows: ["..W..", "..W..", "..W.."],
            zoneRows: ["P...E", "P...E", "P...E"]
        )
        let field = FlowField(map: map, terrainMovementCost: Self.openCost, sourceCells: [0])

        let farCell = map.cellIndex(column: 4, row: 1)
        try #require(farCell != nil)
        let nearCell = map.cellIndex(column: 1, row: 2)
        try #require(nearCell != nil)
        if let farCell {
            #expect(field.cost(atCell: farCell) == nil)
            #expect(field.direction(atCell: farCell) == .zero)
        }
        if let nearCell {
            #expect(field.cost(atCell: nearCell) != nil)
        }
    }

    /// 3×3 map, source at the middle-left cell, forest in the center. Going straight through the forest costs
    /// 0 + 30 (enter forest) + 10 (leave it) = 40; going around through the open corner costs 0 + 10 + 10 = 20.
    /// The field must find the cheaper detour and point toward it, not at the forest.
    @Test func aCostlyTerrainCellIsRoutedAroundWhenACheaperPathExists() throws {
        let map = try BattleMap(
            terrainRows: ["...", ".F.", "..."],
            zoneRows: ["P..", "...", "..E"]
        )
        let source = try #require(map.cellIndex(column: 0, row: 1))
        let forest = try #require(map.cellIndex(column: 1, row: 1))
        let target = try #require(map.cellIndex(column: 2, row: 1))
        let detour = try #require(map.cellIndex(column: 1, row: 0))

        let field = FlowField(map: map, terrainMovementCost: Self.openCost, sourceCells: [source])

        #expect(field.cost(atCell: forest) == 30)
        #expect(field.cost(atCell: target) == 20)
        #expect(
            field.direction(atCell: target) == (map.center(ofCell: detour) - map.center(ofCell: target)).normalized())
    }

    @Test func multipleSourcesEachClaimTheirNearerCells() throws {
        let map = try BattleMap(terrainRows: ["........."], zoneRows: ["P.......E"])
        let field = FlowField(map: map, terrainMovementCost: Self.openCost, sourceCells: [0, 8])

        #expect((0..<9).map { field.cost(atCell: $0) } == [0, 10, 20, 30, 40, 30, 20, 10, 0])
        #expect(field.direction(atCell: 3) == FixedVector2(x: -Fixed.one, y: .zero))
        #expect(field.direction(atCell: 5) == FixedVector2(x: Fixed.one, y: .zero))
    }

    @Test func costsMatchABruteForceRelaxationOverRandomTerrain() throws {
        var generator = DeterministicRNG(seed: 1_337)
        let terrainChoices: [Terrain] = [.open, .open, .open, .forest, .hill, .rubble, .water]

        for trial in 0..<30 {
            let width = generator.int(in: 3...8)
            let height = generator.int(in: 3...8)
            var terrain: [Terrain] = []
            terrain.reserveCapacity(width * height)
            for _ in 0..<(width * height) {
                terrain.append(terrainChoices[generator.int(in: 0...(terrainChoices.count - 1))])
            }
            let passableCells = terrain.indices.filter { terrain[$0].isPassable }
            guard passableCells.count >= 2 else { continue }

            var playerZone = [passableCells[0]]
            var enemyZone = [passableCells[passableCells.count - 1]]
            if playerZone == enemyZone {
                enemyZone = [passableCells[passableCells.count > 1 ? passableCells.count - 2 : 0]]
            }
            playerZone.sort()
            enemyZone.sort()
            guard playerZone != enemyZone else { continue }

            let map = try BattleMap(
                width: width, height: height, terrain: terrain, playerZone: playerZone, enemyZone: enemyZone)

            let sourceCount = generator.int(in: 1...3)
            let sourceCells = (0..<sourceCount).map { _ in
                passableCells[generator.int(in: 0...(passableCells.count - 1))]
            }

            let field = FlowField(map: map, terrainMovementCost: Self.openCost, sourceCells: sourceCells)
            let expected = Self.bruteForceCost(map: map, terrainMovementCost: Self.openCost, sourceCells: sourceCells)

            let actual = (0..<map.cellCount).map { field.cost(atCell: $0) }
            #expect(actual == expected, "trial \(trial): \(width)x\(height)")
        }
    }

    @Test func buildsQuicklyOnTheLargestMapWithManyUnits() throws {
        let dimension = BattleMap.maximumDimension
        let terrainRows = Array(repeating: String(repeating: ".", count: dimension), count: dimension)
        var zoneRows = Array(repeating: String(repeating: ".", count: dimension), count: dimension)
        zoneRows[0] = "P" + String(repeating: ".", count: dimension - 2) + "E"
        let map = try BattleMap(terrainRows: terrainRows, zoneRows: zoneRows)

        var generator = DeterministicRNG(seed: 4_242)
        let sourceCells = (0..<50).map { _ in generator.int(in: 0...(map.cellCount - 1)) }
        let entries = (0..<150).map { index in
            SpatialGrid.Entry(
                id: UnitID(rawValue: UInt32(index)),
                position: FixedVector2(
                    x: Fixed(generator.int(in: 0...(dimension - 1))), y: Fixed(generator.int(in: 0...(dimension - 1))))
            )
        }

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = FlowField(map: map, terrainMovementCost: Self.openCost, sourceCells: sourceCells)
            _ = SpatialGrid(mapWidth: dimension, mapHeight: dimension, bucketSizeCells: 2, entries: entries)
        }
        #expect(elapsed < .seconds(2))
    }

    private static func bruteForceCost(map: BattleMap, terrainMovementCost: PassableTerrainValues, sourceCells: [Int])
        -> [Int?]
    {
        let cellCount = map.cellCount
        var cost = [Int?](repeating: nil, count: cellCount)
        for source in sourceCells where cost[source] == nil {
            cost[source] = 0
        }
        let offsets = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]

        var changed = true
        while changed {
            changed = false
            for cell in 0..<cellCount {
                guard let currentCost = cost[cell] else { continue }
                let (column, row) = map.coordinates(ofCell: cell)
                for offset in offsets {
                    let neighborColumn = column + offset.0
                    let neighborRow = row + offset.1
                    guard (0..<map.width).contains(neighborColumn), (0..<map.height).contains(neighborRow) else {
                        continue
                    }
                    let neighbor = neighborRow * map.width + neighborColumn
                    guard let stepCost = terrainMovementCost[map.terrain[neighbor]] else { continue }
                    let candidate = currentCost + stepCost
                    if let existing = cost[neighbor] {
                        if candidate < existing {
                            cost[neighbor] = candidate
                            changed = true
                        }
                    } else {
                        cost[neighbor] = candidate
                        changed = true
                    }
                }
            }
        }
        return cost
    }
}
