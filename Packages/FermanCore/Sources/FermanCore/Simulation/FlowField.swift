/// The per-cell movement direction toward the nearest of a set of source cells (§5.2.1): a multi-source Dijkstra
/// over integer terrain costs, rebuilt for each team every `tuning.flowFieldIntervalTicks`.
///
/// Direction is the local downhill gradient of the cost field, not a single shortest-path tree, so units spread
/// around an obstacle instead of funneling onto the same cell-by-cell path.
struct FlowField: Sendable, Hashable {
    struct Cell: Sendable, Hashable {
        /// `nil` when the cell cannot reach any source: water-locked, or off the source's connected component.
        let cost: Int?
        /// Unit vector toward the neighbor that lowers cost the most; `.zero` at a source or an unreachable cell.
        let direction: FixedVector2
    }

    let width: Int
    let height: Int
    private let cells: [Cell]

    /// The eight grid neighbors in a fixed order, so gradient ties never depend on scan order.
    private static let neighborOffsets: [(column: Int, row: Int)] = [
        (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1),
    ]

    init(map: BattleMap, terrainMovementCost: PassableTerrainValues, sourceCells: [Int]) {
        width = map.width
        height = map.height
        let cellCount = map.cellCount

        var cost = [Int?](repeating: nil, count: cellCount)
        var frontier = DijkstraFrontier()
        for source in sourceCells {
            precondition((0..<cellCount).contains(source), "FlowField source cell \(source) is out of bounds")
            guard cost[source] == nil else { continue }
            cost[source] = 0
            frontier.insert(cost: 0, cell: source)
        }

        while let next = frontier.popMinimum() {
            guard cost[next.cell] == next.cost else { continue }  // a cheaper entry already finalized this cell
            let (column, row) = map.coordinates(ofCell: next.cell)
            for offset in Self.neighborOffsets {
                let neighborColumn = column + offset.column
                let neighborRow = row + offset.row
                guard (0..<width).contains(neighborColumn), (0..<height).contains(neighborRow) else { continue }
                let neighbor = neighborRow * width + neighborColumn
                guard let stepCost = terrainMovementCost[map.terrain[neighbor]] else { continue }  // impassable
                let candidate = next.cost + stepCost
                if let existing = cost[neighbor], existing <= candidate {
                    continue
                }
                cost[neighbor] = candidate
                frontier.insert(cost: candidate, cell: neighbor)
            }
        }

        cells = (0..<cellCount).map { cell in Self.makeCell(cell, cost: cost, map: map) }
    }

    private static func makeCell(_ cell: Int, cost: [Int?], map: BattleMap) -> Cell {
        guard let cellCost = cost[cell] else {
            return Cell(cost: nil, direction: .zero)
        }
        guard cellCost > 0 else {
            return Cell(cost: 0, direction: .zero)
        }

        let (column, row) = map.coordinates(ofCell: cell)
        var bestNeighbor: (cell: Int, cost: Int)?
        for offset in Self.neighborOffsets {
            let neighborColumn = column + offset.column
            let neighborRow = row + offset.row
            guard (0..<map.width).contains(neighborColumn), (0..<map.height).contains(neighborRow) else { continue }
            let neighbor = neighborRow * map.width + neighborColumn
            guard let neighborCost = cost[neighbor], neighborCost < cellCost else { continue }
            let isBetter =
                bestNeighbor.map { neighborCost < $0.cost || (neighborCost == $0.cost && neighbor < $0.cell) } ?? true
            if isBetter {
                bestNeighbor = (neighbor, neighborCost)
            }
        }

        guard let bestNeighbor else {
            return Cell(cost: cellCost, direction: .zero)
        }
        let direction = (map.center(ofCell: bestNeighbor.cell) - map.center(ofCell: cell)).normalized()
        return Cell(cost: cellCost, direction: direction)
    }

    subscript(cell: Int) -> Cell { cells[cell] }

    func direction(atCell cell: Int) -> FixedVector2 { cells[cell].direction }

    func cost(atCell cell: Int) -> Int? { cells[cell].cost }
}

/// A binary min-heap over `(cost, cell)`, breaking ties toward the smaller cell index (§5.2.1: "İkili yığın; eşit
/// maliyette küçük hücre indeksi önce").
private struct DijkstraFrontier {
    private var costs: [Int] = []
    private var cells: [Int] = []

    mutating func insert(cost: Int, cell: Int) {
        costs.append(cost)
        cells.append(cell)
        siftUp(from: costs.count - 1)
    }

    mutating func popMinimum() -> (cost: Int, cell: Int)? {
        guard !costs.isEmpty else { return nil }
        let minimum = (cost: costs[0], cell: cells[0])
        let lastIndex = costs.count - 1
        costs[0] = costs[lastIndex]
        cells[0] = cells[lastIndex]
        costs.removeLast()
        cells.removeLast()
        if !costs.isEmpty {
            siftDown(from: 0)
        }
        return minimum
    }

    private func isLess(_ firstIndex: Int, _ secondIndex: Int) -> Bool {
        costs[firstIndex] != costs[secondIndex]
            ? costs[firstIndex] < costs[secondIndex] : cells[firstIndex] < cells[secondIndex]
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            guard isLess(child, parent) else { break }
            swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        while true {
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            var smallest = parent
            if left < costs.count, isLess(left, smallest) { smallest = left }
            if right < costs.count, isLess(right, smallest) { smallest = right }
            guard smallest != parent else { break }
            swapAt(parent, smallest)
            parent = smallest
        }
    }

    private mutating func swapAt(_ firstIndex: Int, _ secondIndex: Int) {
        costs.swapAt(firstIndex, secondIndex)
        cells.swapAt(firstIndex, secondIndex)
    }
}
