extension BattleConfig {
    /// The catalog entry for `id`. Every `UnitTypeID` a `BattleConfig` references — placements, rule conditions and
    /// actions — is guaranteed present by content validation before a battle ever runs.
    func unitType(_ id: UnitTypeID) -> UnitType {
        guard let type = unitCatalog.first(where: { $0.id == id }) else {
            preconditionFailure("BattleConfig.unitType: catalog has no unit type \(id)")
        }
        return type
    }

    /// The map cell a live position sits in. Positions only ever come from cell centers moved by `Steering`, which
    /// keeps them inside the map by construction, so a miss here means a caller broke that invariant.
    func cell(at position: FixedVector2) -> Int {
        guard let cell = map.cellIndex(column: position.x.roundedDown(), row: position.y.roundedDown()) else {
            preconditionFailure("BattleConfig.cell: position \(position) is outside the map")
        }
        return cell
    }
}

/// How often each order of one unit type has fired so far, accumulated during the run and copied into
/// `BattleResult.ruleFireCounts` at the end.
struct ProgramFireCounts: Sendable {
    let team: Team
    let unitType: UnitTypeID
    var counts: [Int]
}

/// Everything that changes during one battle: per-unit runtime state plus the whole-army bookkeeping the tick
/// pipeline reads and writes each phase (FERMAN-PLAN §5.2). Built once from a `BattleConfig` and mutated in place
/// for the rest of `BattleSimulator.run`.
struct BattleState: Sendable {
    /// Indexed by `UnitID.rawValue`; player units first, then enemy, each in that team's placement order (D7).
    var units: [UnitState]
    var rng: DeterministicRNG
    /// The field player units follow: sources are living enemy cells, so its gradient points toward the enemy.
    var playerFlowField: FlowField
    /// The field enemy units follow: sources are living player cells.
    var enemyFlowField: FlowField
    var spatialGrid: SpatialGrid
    /// Set once, on the tick either team's commander first dies, so that team's morale penalty (§5.2.6) fires
    /// exactly one time no matter how many ticks the corpse spends on the field afterward.
    var playerCommanderDied = false
    var enemyCommanderDied = false
    var ruleFireCounts: [ProgramFireCounts]

    init(config: BattleConfig) {
        var units: [UnitState] = []
        units.reserveCapacity(config.player.placements.count + config.enemy.placements.count)
        for (team, setup) in [(Team.player, config.player), (Team.enemy, config.enemy)] {
            for placement in setup.placements {
                let type = config.unitType(placement.type)
                units.append(
                    UnitState(
                        id: UnitID(rawValue: UInt32(units.count)), team: team, type: type,
                        isCommander: placement.isCommander, program: setup.program(for: placement.type),
                        position: config.map.center(ofCell: placement.cell)
                    ))
            }
        }
        self.units = units
        rng = DeterministicRNG(seed: config.seed)
        spatialGrid = Self.buildSpatialGrid(units: units, config: config)
        playerFlowField = Self.buildFlowField(for: .player, units: units, config: config)
        enemyFlowField = Self.buildFlowField(for: .enemy, units: units, config: config)
        ruleFireCounts =
            (config.player.programs.map { (Team.player, $0) } + config.enemy.programs.map { (Team.enemy, $0) })
            .sorted { $0.1.unitType < $1.1.unitType }
            .map {
                ProgramFireCounts(
                    team: $0.0, unitType: $0.1.unitType, counts: [Int](repeating: 0, count: $0.1.rules.count))
            }
    }

    mutating func rebuildSpatialGrid(config: BattleConfig) {
        spatialGrid = Self.buildSpatialGrid(units: units, config: config)
    }

    /// A no-op on every tick but the start of a `flowFieldIntervalTicks` window (§5.2.1).
    mutating func rebuildFlowFieldsIfNeeded(tick: Int, config: BattleConfig) {
        guard tick % config.tuning.flowFieldIntervalTicks == 0 else { return }
        playerFlowField = Self.buildFlowField(for: .player, units: units, config: config)
        enemyFlowField = Self.buildFlowField(for: .enemy, units: units, config: config)
    }

    func flowField(for team: Team) -> FlowField {
        team == .player ? playerFlowField : enemyFlowField
    }

    mutating func bumpRuleFireCount(team: Team, unitType: UnitTypeID, ruleIndex: Int) {
        guard let entryIndex = ruleFireCounts.firstIndex(where: { $0.team == team && $0.unitType == unitType }) else {
            return
        }
        ruleFireCounts[entryIndex].counts[ruleIndex] += 1
    }

    private static func buildSpatialGrid(units: [UnitState], config: BattleConfig) -> SpatialGrid {
        SpatialGrid(
            mapWidth: config.map.width, mapHeight: config.map.height, bucketSizeCells: config.tuning.spatialBucketCells,
            entries: units.filter(\.isAlive).map { SpatialGrid.Entry(id: $0.id, position: $0.kinematics.position) })
    }

    private static func buildFlowField(for team: Team, units: [UnitState], config: BattleConfig) -> FlowField {
        let sources =
            units
            .filter { $0.team == team.opponent && $0.isAlive }
            .map { config.cell(at: $0.kinematics.position) }
        return FlowField(map: config.map, terrainMovementCost: config.tuning.terrainMovementCost, sourceCells: sources)
    }
}
