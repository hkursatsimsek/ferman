/// A rectangular grid of terrain cells with the placement zones of both teams.
///
/// A map that exists is structurally valid: every initializer, including decoding, rejects inconsistent data. In JSON
/// the grid is written as ASCII rows so maps stay readable and diffable (D19):
///
///     { "terrain": ["..FF..", "..HH.."], "zones": ["P....E", "P....E"] }
///
/// Terrain symbols are listed on `Terrain.symbol`; zone rows use `P` (player), `E` (enemy) and `.` (neither).
public struct BattleMap: Sendable, Hashable {
    /// Bounds per-tick work on mobile hardware and keeps squared distances far inside `FixedSquared`.
    public static let maximumDimension = 128

    public static let playerZoneSymbol: Character = "P"
    public static let enemyZoneSymbol: Character = "E"
    public static let neutralZoneSymbol: Character = "."

    public let width: Int
    public let height: Int
    /// Row-major: the cell at column `x`, row `y` has index `y * width + x`.
    public let terrain: [Terrain]
    /// Placeable cell indices, strictly increasing.
    public let playerZone: [Int]
    public let enemyZone: [Int]

    public init(
        width: Int,
        height: Int,
        terrain: [Terrain],
        playerZone: [Int],
        enemyZone: [Int]
    ) throws(BattleMapError) {
        guard width > 0, height > 0 else {
            throw .empty
        }
        guard width <= Self.maximumDimension, height <= Self.maximumDimension else {
            throw .tooLarge(width: width, height: height, maximum: Self.maximumDimension)
        }
        guard terrain.count == width * height else {
            throw .terrainCountMismatch(expected: width * height, actual: terrain.count)
        }
        for (team, zone) in [(Team.player, playerZone), (Team.enemy, enemyZone)] {
            guard !zone.isEmpty else {
                throw .missingZone(team)
            }
            for (position, cell) in zone.enumerated() {
                guard terrain.indices.contains(cell) else {
                    throw .zoneCellOutOfBounds(team, cell: cell)
                }
                guard position == 0 || zone[position - 1] < cell else {
                    throw .zoneCellsNotStrictlyIncreasing(team, cell: cell)
                }
                guard terrain[cell].isPassable else {
                    throw .zoneOnImpassableTerrain(team, cell: cell)
                }
            }
        }
        if let shared = Self.firstSharedCell(playerZone, enemyZone) {
            throw .zonesOverlap(cell: shared)
        }

        self.width = width
        self.height = height
        self.terrain = terrain
        self.playerZone = playerZone
        self.enemyZone = enemyZone
    }

    public init(terrainRows: [String], zoneRows: [String]) throws(BattleMapError) {
        let width = terrainRows.first?.count ?? 0
        var terrain: [Terrain] = []
        terrain.reserveCapacity(width * terrainRows.count)
        for (row, text) in terrainRows.enumerated() {
            guard text.count == width else {
                throw .raggedRows(row: row, expectedWidth: width, actualWidth: text.count)
            }
            for (column, symbol) in text.enumerated() {
                guard let cellTerrain = Terrain(symbol: symbol) else {
                    throw .unknownTerrainSymbol(symbol, row: row, column: column)
                }
                terrain.append(cellTerrain)
            }
        }

        guard zoneRows.count == terrainRows.count, zoneRows.allSatisfy({ $0.count == width }) else {
            throw .zoneGridMismatch(expectedWidth: width, expectedHeight: terrainRows.count)
        }
        var playerZone: [Int] = []
        var enemyZone: [Int] = []
        for (row, text) in zoneRows.enumerated() {
            for (column, symbol) in text.enumerated() {
                switch symbol {
                case Self.playerZoneSymbol:
                    playerZone.append(row * width + column)
                case Self.enemyZoneSymbol:
                    enemyZone.append(row * width + column)
                case Self.neutralZoneSymbol:
                    break
                default:
                    throw .unknownZoneSymbol(symbol, row: row, column: column)
                }
            }
        }

        try self.init(
            width: width,
            height: terrainRows.count,
            terrain: terrain,
            playerZone: playerZone,
            enemyZone: enemyZone
        )
    }

    public var cellCount: Int {
        terrain.count
    }

    public func cellIndex(column: Int, row: Int) -> Int? {
        guard (0..<width).contains(column), (0..<height).contains(row) else {
            return nil
        }
        return row * width + column
    }

    public func coordinates(ofCell cell: Int) -> (column: Int, row: Int) {
        (cell % width, cell / width)
    }

    /// The centre of a cell in cell-space coordinates.
    public func center(ofCell cell: Int) -> FixedVector2 {
        let (column, row) = coordinates(ofCell: cell)
        return FixedVector2(x: Fixed(column) + .half, y: Fixed(row) + .half)
    }

    public func zone(for team: Team) -> [Int] {
        switch team {
        case .player: playerZone
        case .enemy: enemyZone
        }
    }

    public var terrainRows: [String] {
        (0..<height).map { row in
            String(terrain[(row * width)..<((row + 1) * width)].map(\.symbol))
        }
    }

    public var zoneRows: [String] {
        var symbols = [Character](repeating: Self.neutralZoneSymbol, count: cellCount)
        for cell in playerZone {
            symbols[cell] = Self.playerZoneSymbol
        }
        for cell in enemyZone {
            symbols[cell] = Self.enemyZoneSymbol
        }
        return (0..<height).map { row in
            String(symbols[(row * width)..<((row + 1) * width)])
        }
    }

    private static func firstSharedCell(_ lhs: [Int], _ rhs: [Int]) -> Int? {
        var left = 0
        var right = 0
        while left < lhs.count && right < rhs.count {
            if lhs[left] == rhs[right] {
                return lhs[left]
            }
            if lhs[left] < rhs[right] {
                left += 1
            } else {
                right += 1
            }
        }
        return nil
    }
}

public enum BattleMapError: Error, Equatable, Sendable {
    case empty
    case tooLarge(width: Int, height: Int, maximum: Int)
    case raggedRows(row: Int, expectedWidth: Int, actualWidth: Int)
    case unknownTerrainSymbol(Character, row: Int, column: Int)
    case zoneGridMismatch(expectedWidth: Int, expectedHeight: Int)
    case unknownZoneSymbol(Character, row: Int, column: Int)
    case terrainCountMismatch(expected: Int, actual: Int)
    case missingZone(Team)
    case zoneCellOutOfBounds(Team, cell: Int)
    case zoneCellsNotStrictlyIncreasing(Team, cell: Int)
    case zoneOnImpassableTerrain(Team, cell: Int)
    case zonesOverlap(cell: Int)
}

extension BattleMap: Codable {
    private enum CodingKeys: String, CodingKey {
        case terrain
        case zones
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let terrainRows = try container.decode([String].self, forKey: .terrain)
        let zoneRows = try container.decode([String].self, forKey: .zones)
        do {
            try self.init(terrainRows: terrainRows, zoneRows: zoneRows)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .terrain,
                in: container,
                debugDescription: "invalid battle map: \(error)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(terrainRows, forKey: .terrain)
        try container.encode(zoneRows, forKey: .zones)
    }
}
