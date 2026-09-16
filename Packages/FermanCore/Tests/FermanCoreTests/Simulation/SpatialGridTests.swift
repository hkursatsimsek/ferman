import Testing

@testable import FermanCore

@Suite("SpatialGrid")
struct SpatialGridTests {
    private static func entry(_ id: UInt32, _ x: Int, _ y: Int) -> SpatialGrid.Entry {
        SpatialGrid.Entry(id: UnitID(rawValue: id), position: FixedVector2(x: Fixed(x), y: Fixed(y)))
    }

    @Test func unitsLandInTheBucketTheirPositionFallsIn() {
        let grid = SpatialGrid(
            mapWidth: 4, mapHeight: 4, bucketSizeCells: 2,
            entries: [Self.entry(1, 0, 0), Self.entry(2, 3, 3), Self.entry(3, 2, 0)]
        )
        #expect(grid.columns == 2)
        #expect(grid.rows == 2)
        #expect(grid.entries(inBucketColumn: 0, row: 0).map(\.id) == [UnitID(rawValue: 1)])
        #expect(grid.entries(inBucketColumn: 1, row: 1).map(\.id) == [UnitID(rawValue: 2)])
        #expect(grid.entries(inBucketColumn: 1, row: 0).map(\.id) == [UnitID(rawValue: 3)])
        #expect(grid.entries(inBucketColumn: 0, row: 1).isEmpty)
    }

    @Test func bucketContentsAreOrderedByAscendingUnitID() {
        let grid = SpatialGrid(
            mapWidth: 2, mapHeight: 2, bucketSizeCells: 2,
            entries: [Self.entry(5, 0, 0), Self.entry(1, 1, 1), Self.entry(3, 1, 0)]
        )
        #expect(grid.entries(inBucketColumn: 0, row: 0).map(\.id.rawValue) == [1, 3, 5])
    }

    @Test func radiusQueryUsesExactCircularDistanceNotTheBucketBox() {
        // (3, 3) is squared distance 18 from the origin: outside a radius of 4 (squared 16) even though the
        // bucket box at radius 4 would include it, and inside a radius of 5 (squared 25).
        let grid = SpatialGrid(mapWidth: 20, mapHeight: 20, bucketSizeCells: 2, entries: [Self.entry(1, 3, 3)])
        #expect(grid.entries(within: Fixed(4), of: .zero).isEmpty)
        #expect(grid.entries(within: Fixed(5), of: .zero).map(\.id) == [UnitID(rawValue: 1)])
    }

    @Test func radiusQueryFindsUnitsAcrossBucketBoundaries() {
        let grid = SpatialGrid(
            mapWidth: 20, mapHeight: 20, bucketSizeCells: 2,
            entries: [Self.entry(1, 1, 1), Self.entry(2, 2, 1)]
        )
        let found = grid.entries(within: Fixed(2), of: FixedVector2(x: Fixed(1), y: Fixed(1)))
            .map(\.id.rawValue).sorted()
        #expect(found == [1, 2])
    }

    @Test func countMatchesTheNumberOfEntriesFound() {
        let grid = SpatialGrid(
            mapWidth: 10, mapHeight: 10, bucketSizeCells: 2,
            entries: [Self.entry(1, 0, 0), Self.entry(2, 0, 1), Self.entry(3, 9, 9)]
        )
        #expect(grid.count(within: Fixed(2), of: .zero) == 2)
    }

    @Test func emptyGridAnswersEveryQueryWithNothing() {
        let grid = SpatialGrid(mapWidth: 10, mapHeight: 10, bucketSizeCells: 2, entries: [])
        #expect(grid.entries(within: Fixed(50), of: .zero).isEmpty)
        #expect(grid.count(within: Fixed(50), of: .zero) == 0)
    }

    @Test func radiusQueryMatchesABruteForceScanOverRandomArmies() {
        var generator = DeterministicRNG(seed: 901)
        for trial in 0..<50 {
            let width = generator.int(in: 4...40)
            let height = generator.int(in: 4...40)
            let unitCount = generator.int(in: 0...80)
            let entries = (0..<unitCount).map { index in
                SpatialGrid.Entry(
                    id: UnitID(rawValue: UInt32(index)),
                    position: FixedVector2(
                        x: Fixed(generator.int(in: 0...(width - 1))) + generator.fixedUnit(),
                        y: Fixed(generator.int(in: 0...(height - 1))) + generator.fixedUnit()
                    )
                )
            }
            let grid = SpatialGrid(mapWidth: width, mapHeight: height, bucketSizeCells: 2, entries: entries)

            let queryPosition = FixedVector2(
                x: Fixed(generator.int(in: 0...(width - 1))), y: Fixed(generator.int(in: 0...(height - 1))))
            let radius = Fixed(generator.int(in: 0...10))
            let radiusSquared = radius.squared

            let expected = Set(
                entries.filter { $0.position.distanceSquared(to: queryPosition) <= radiusSquared }.map(\.id))
            let actual = Set(grid.entries(within: radius, of: queryPosition).map(\.id))
            #expect(actual == expected, "trial \(trial): width \(width) height \(height) radius \(radius)")
        }
    }
}
