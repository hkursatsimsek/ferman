/// A uniform grid that buckets living units by position, so a neighbor search only scans nearby units instead of
/// the whole army (§5.2.2). Rebuilt every tick from the current unit positions; nothing here survives past one tick.
struct SpatialGrid: Sendable, Hashable {
    struct Entry: Sendable, Hashable {
        let id: UnitID
        let position: FixedVector2
    }

    let mapWidth: Int
    let mapHeight: Int
    let bucketSizeCells: Int
    let columns: Int
    let rows: Int

    /// CSR-style offsets into `sortedEntries`: bucket `b` holds `sortedEntries[bucketOffsets[b]..<bucketOffsets[b+1]]`.
    private let bucketOffsets: [Int]
    /// Grouped by bucket; ascending `UnitID` within each bucket, where D10's distance-then-id tie-break starts.
    private let sortedEntries: [Entry]

    init(mapWidth: Int, mapHeight: Int, bucketSizeCells: Int, entries: [Entry]) {
        precondition(mapWidth > 0 && mapHeight > 0, "SpatialGrid requires a non-empty map")
        precondition(bucketSizeCells > 0, "SpatialGrid bucket size must be positive")

        let columns = (mapWidth + bucketSizeCells - 1) / bucketSizeCells
        let rows = (mapHeight + bucketSizeCells - 1) / bucketSizeCells
        let bucketCount = columns * rows

        let grouped =
            entries
            .map { entry in
                (
                    bucket: Self.bucketIndex(
                        of: entry.position, bucketSizeCells: bucketSizeCells, columns: columns, rows: rows),
                    entry: entry
                )
            }
            .sorted { $0.bucket != $1.bucket ? $0.bucket < $1.bucket : $0.entry.id < $1.entry.id }

        var offsets = [Int](repeating: 0, count: bucketCount + 1)
        for (bucket, _) in grouped {
            offsets[bucket + 1] += 1
        }
        for bucket in 0..<bucketCount {
            offsets[bucket + 1] += offsets[bucket]
        }

        self.mapWidth = mapWidth
        self.mapHeight = mapHeight
        self.bucketSizeCells = bucketSizeCells
        self.columns = columns
        self.rows = rows
        self.bucketOffsets = offsets
        self.sortedEntries = grouped.map(\.entry)
    }

    private static func bucketIndex(of position: FixedVector2, bucketSizeCells: Int, columns: Int, rows: Int) -> Int {
        let column = clampToGrid(position.x.roundedDown() / bucketSizeCells, upperBound: columns - 1)
        let row = clampToGrid(position.y.roundedDown() / bucketSizeCells, upperBound: rows - 1)
        return row * columns + column
    }

    func entries(inBucketColumn column: Int, row: Int) -> ArraySlice<Entry> {
        let bucket = row * columns + column
        return sortedEntries[bucketOffsets[bucket]..<bucketOffsets[bucket + 1]]
    }

    /// Units within `radiusCells` of `position`, by exact circular distance. Only the buckets overlapping the
    /// query's bounding box are scanned, so cost tracks local density rather than army size.
    func entries(within radiusCells: Fixed, of position: FixedVector2) -> [Entry] {
        precondition(radiusCells >= .zero, "SpatialGrid query radius must not be negative")
        let radiusSquared = radiusCells.squared
        let minColumn = clampToGrid((position.x - radiusCells).roundedDown() / bucketSizeCells, upperBound: columns - 1)
        let maxColumn = clampToGrid((position.x + radiusCells).roundedDown() / bucketSizeCells, upperBound: columns - 1)
        let minRow = clampToGrid((position.y - radiusCells).roundedDown() / bucketSizeCells, upperBound: rows - 1)
        let maxRow = clampToGrid((position.y + radiusCells).roundedDown() / bucketSizeCells, upperBound: rows - 1)

        var found: [Entry] = []
        for row in minRow...maxRow {
            for column in minColumn...maxColumn {
                for entry in entries(inBucketColumn: column, row: row)
                where entry.position.distanceSquared(to: position) <= radiusSquared {
                    found.append(entry)
                }
            }
        }
        return found
    }

    func count(within radiusCells: Fixed, of position: FixedVector2) -> Int {
        entries(within: radiusCells, of: position).count
    }
}

private func clampToGrid(_ value: Int, upperBound: Int) -> Int {
    Swift.min(Swift.max(value, 0), upperBound)
}
