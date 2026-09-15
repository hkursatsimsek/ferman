/// When an order applies (FERMAN-PLAN §5.3). *Below* is strictly less, *Above* strictly greater, *Within* inclusive.
public enum Condition: Sendable, Hashable {
    case enemyWithin(cells: Int)
    case healthBelow(percent: Int)
    case allyCountBelow(count: Int)
    case isFlanked
    case targetInRange(UnitTypeID)
    case timeAfter(seconds: Int)
    case nearestEnemyType(UnitTypeID)
    case moraleBelow(percent: Int)
    case terrainIs(Terrain)
    case commanderDead
    case enemyDensityAbove(count: Int)
    /// The default order: always matches, sits last and costs no rule budget (D4).
    case always

    public var kind: ConditionKind {
        switch self {
        case .enemyWithin: .enemyWithin
        case .healthBelow: .healthBelow
        case .allyCountBelow: .allyCountBelow
        case .isFlanked: .isFlanked
        case .targetInRange: .targetInRange
        case .timeAfter: .timeAfter
        case .nearestEnemyType: .nearestEnemyType
        case .moraleBelow: .moraleBelow
        case .terrainIs: .terrainIs
        case .commanderDead: .commanderDead
        case .enemyDensityAbove: .enemyDensityAbove
        case .always: .always
        }
    }
}

/// Payload-free mirror of `Condition` for pickers, level locks and the language-model schema (D8).
public enum ConditionKind: String, Sendable, Codable, CaseIterable {
    case enemyWithin
    case healthBelow
    case allyCountBelow
    case isFlanked
    case targetInRange
    case timeAfter
    case nearestEnemyType
    case moraleBelow
    case terrainIs
    case commanderDead
    case enemyDensityAbove
    case always

    public var parameter: ConditionParameter {
        switch self {
        case .enemyWithin: .cells(1...10)
        case .healthBelow: .percent(10...90)
        case .allyCountBelow: .count(1...10)
        case .isFlanked: .none
        case .targetInRange: .unitType
        case .timeAfter: .seconds(1...60)
        case .nearestEnemyType: .unitType
        case .moraleBelow: .percent(10...90)
        case .terrainIs: .terrain
        case .commanderDead: .none
        case .enemyDensityAbove: .count(2...8)
        case .always: .none
        }
    }
}

public enum ConditionParameter: Sendable, Hashable {
    case none
    case cells(ClosedRange<Int>)
    case percent(ClosedRange<Int>)
    case count(ClosedRange<Int>)
    case seconds(ClosedRange<Int>)
    case unitType
    case terrain
}

extension Condition: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case cells
        case percent
        case count
        case seconds
        case unitType
        case terrain
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ConditionKind.self, forKey: .kind) {
        case .enemyWithin:
            self = .enemyWithin(cells: try container.decode(Int.self, forKey: .cells))
        case .healthBelow:
            self = .healthBelow(percent: try container.decode(Int.self, forKey: .percent))
        case .allyCountBelow:
            self = .allyCountBelow(count: try container.decode(Int.self, forKey: .count))
        case .isFlanked:
            self = .isFlanked
        case .targetInRange:
            self = .targetInRange(try container.decode(UnitTypeID.self, forKey: .unitType))
        case .timeAfter:
            self = .timeAfter(seconds: try container.decode(Int.self, forKey: .seconds))
        case .nearestEnemyType:
            self = .nearestEnemyType(try container.decode(UnitTypeID.self, forKey: .unitType))
        case .moraleBelow:
            self = .moraleBelow(percent: try container.decode(Int.self, forKey: .percent))
        case .terrainIs:
            self = .terrainIs(try container.decode(Terrain.self, forKey: .terrain))
        case .commanderDead:
            self = .commanderDead
        case .enemyDensityAbove:
            self = .enemyDensityAbove(count: try container.decode(Int.self, forKey: .count))
        case .always:
            self = .always
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .enemyWithin(let cells):
            try container.encode(cells, forKey: .cells)
        case .healthBelow(let percent), .moraleBelow(let percent):
            try container.encode(percent, forKey: .percent)
        case .allyCountBelow(let count), .enemyDensityAbove(let count):
            try container.encode(count, forKey: .count)
        case .timeAfter(let seconds):
            try container.encode(seconds, forKey: .seconds)
        case .targetInRange(let unitType), .nearestEnemyType(let unitType):
            try container.encode(unitType, forKey: .unitType)
        case .terrainIs(let terrain):
            try container.encode(terrain, forKey: .terrain)
        case .isFlanked, .commanderDead, .always:
            break
        }
    }
}
