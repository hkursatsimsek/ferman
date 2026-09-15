public enum Terrain: String, Sendable, Codable, CaseIterable {
    case open
    case forest
    case hill
    case water
    case rubble

    /// The character that stands for this terrain in ASCII map rows (D19).
    public var symbol: Character {
        switch self {
        case .open: "."
        case .forest: "F"
        case .hill: "H"
        case .water: "W"
        case .rubble: "R"
        }
    }

    public init?(symbol: Character) {
        guard let terrain = Self.allCases.first(where: { $0.symbol == symbol }) else {
            return nil
        }
        self = terrain
    }

    public var isPassable: Bool {
        self != .water
    }

    /// Forest and rubble shield their occupants from ranged damage.
    public var providesCover: Bool {
        self == .forest || self == .rubble
    }
}

/// One integer per passable terrain; water is impassable and therefore has no entry.
public struct PassableTerrainValues: Sendable, Hashable, Codable {
    public var open: Int
    public var forest: Int
    public var hill: Int
    public var rubble: Int

    public init(open: Int, forest: Int, hill: Int, rubble: Int) {
        self.open = open
        self.forest = forest
        self.hill = hill
        self.rubble = rubble
    }

    public subscript(terrain: Terrain) -> Int? {
        switch terrain {
        case .open: open
        case .forest: forest
        case .hill: hill
        case .rubble: rubble
        case .water: nil
        }
    }
}
