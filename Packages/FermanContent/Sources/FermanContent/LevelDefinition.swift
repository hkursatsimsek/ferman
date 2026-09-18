import FermanCore

/// One campaign fight: a map, the enemy's fixed army (D6 — levels 1–10 are hand-written, no `EnemyAI` yet),
/// what the player is allowed to write, and a `referenceSolution` army that must beat that enemy under `seed`.
///
/// No display title lives here — like `UnitType.id`, the app looks up `level.<id>` in its String Catalog (D19).
public struct LevelDefinition: Sendable, Hashable, Codable {
    public let id: Int
    public let map: MapID
    public let objective: BattleObjective
    public let constraints: RuleConstraints
    /// The total unit cost the player may spend on their own army; independent of `constraints.maxRules` (D4).
    public let playerBudget: Int
    public let seed: UInt64
    public let maxTicks: Int
    public let enemy: TeamSetup
    /// A player army, built within `constraints` and `playerBudget`, that beats `enemy` under `seed`.
    /// `LevelSolvabilityTests` fights it to confirm that; nothing at runtime re-checks it.
    public let referenceSolution: TeamSetup

    public init(
        id: Int, map: MapID, objective: BattleObjective, constraints: RuleConstraints, playerBudget: Int,
        seed: UInt64, maxTicks: Int, enemy: TeamSetup, referenceSolution: TeamSetup
    ) {
        self.id = id
        self.map = map
        self.objective = objective
        self.constraints = constraints
        self.playerBudget = playerBudget
        self.seed = seed
        self.maxTicks = maxTicks
        self.enemy = enemy
        self.referenceSolution = referenceSolution
    }
}

public enum LevelError: Error, Equatable, Sendable {
    case duplicateIdentifier(Int)
    case notSortedByIdentifier(Int)
    case unknownMap(level: Int, map: MapID)
    case unknownUnitType(level: Int, team: Team, unitType: UnitTypeID)
    case placementOutsideZone(level: Int, team: Team, cell: Int)
    case multipleCommanders(level: Int, team: Team)
    case invalidReferenceSolution(level: Int, [RuleValidationError])
    case referenceSolutionOverBudget(level: Int, used: Int, budget: Int)
}

extension LevelDefinition {
    /// Cross-reference checks `ContentCatalog` runs once `units` and `maps` are already known to be valid
    /// themselves: every level points at real content, and its `referenceSolution` is legal and affordable.
    public static func validateCatalog(_ levels: [LevelDefinition], units: [UnitType], maps: [NamedMap])
        throws(LevelError)
    {
        let costByUnitType = Dictionary(uniqueKeysWithValues: units.map { ($0.id, $0.cost) })
        let mapsByID = Dictionary(uniqueKeysWithValues: maps.map { ($0.id, $0.map) })

        for (index, level) in levels.enumerated() {
            if index > 0 {
                let previous = levels[index - 1].id
                guard previous != level.id else {
                    throw .duplicateIdentifier(level.id)
                }
                guard previous < level.id else {
                    throw .notSortedByIdentifier(level.id)
                }
            }
            guard let map = mapsByID[level.map] else {
                throw .unknownMap(level: level.id, map: level.map)
            }
            try level.validate(against: map, costByUnitType: costByUnitType)
        }
    }

    private func validate(against map: BattleMap, costByUnitType: [UnitTypeID: Int]) throws(LevelError) {
        let unitTypeIDs = Set(costByUnitType.keys)
        try Self.validateTeam(enemy, level: id, team: .enemy, zone: map.zone(for: .enemy), unitTypeIDs: unitTypeIDs)
        try Self.validateTeam(
            referenceSolution, level: id, team: .player, zone: map.zone(for: .player), unitTypeIDs: unitTypeIDs)

        let errors = RuleValidator.validate(programs: referenceSolution.programs, constraints: constraints)
        guard errors.isEmpty else {
            throw .invalidReferenceSolution(level: id, errors)
        }

        let spent = referenceSolution.placements.reduce(into: 0) { total, placement in
            total += costByUnitType[placement.type] ?? 0
        }
        guard spent <= playerBudget else {
            throw .referenceSolutionOverBudget(level: id, used: spent, budget: playerBudget)
        }
    }

    private static func validateTeam(
        _ team: TeamSetup, level: Int, team side: Team, zone: [Int], unitTypeIDs: Set<UnitTypeID>
    ) throws(LevelError) {
        let zoneSet = Set(zone)
        var commanderCount = 0
        for placement in team.placements {
            guard unitTypeIDs.contains(placement.type) else {
                throw .unknownUnitType(level: level, team: side, unitType: placement.type)
            }
            guard zoneSet.contains(placement.cell) else {
                throw .placementOutsideZone(level: level, team: side, cell: placement.cell)
            }
            if placement.isCommander {
                commanderCount += 1
            }
        }
        guard commanderCount <= 1 else {
            throw .multipleCommanders(level: level, team: side)
        }
        for program in team.programs {
            guard unitTypeIDs.contains(program.unitType) else {
                throw .unknownUnitType(level: level, team: side, unitType: program.unitType)
            }
        }
    }
}
