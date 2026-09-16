/// A unit's position and last-tick velocity: the double-buffered state `Steering` reads from and writes to (D10).
/// Velocity is derived from actual displacement, not desired displacement, so a unit blocked by water or the map
/// edge reports zero velocity rather than a phantom heading its neighbors would align to.
struct UnitKinematics: Sendable, Hashable {
    var position: FixedVector2
    var velocity: FixedVector2
}

/// The order-derived pull on a unit this tick (FERMAN-PLAN §5.2.4's "niyet"). Resolving an `Action` to one of these
/// — where the flank waypoint is, where the flow field points for `advance` — is the caller's job; `Steering` only
/// ever sees a direction.
enum SteeringIntent: Sendable, Hashable {
    /// Move toward this heading (need not be normalized).
    case seek(FixedVector2)
    /// Move away from this heading.
    case flee(FixedVector2)
    /// No directional pull from the order itself; the other terms may still move the unit.
    case hold
}

/// A living ally close enough to factor into separation, alignment or cohesion, sampled from the previous tick.
struct SteeringNeighbor: Sendable, Hashable {
    let position: FixedVector2
    let velocity: FixedVector2
}

struct SteeringInputs: Sendable, Hashable {
    let intent: SteeringIntent
    /// Living allies to weigh for separation, alignment and cohesion; self is not included.
    let neighbors: [SteeringNeighbor]
    /// The team's flow field direction at the unit's current cell; `.zero` where the field has no data.
    let flowDirection: FixedVector2
}

/// Blends one unit's order intent with separation, alignment, cohesion and flow following into a single heading,
/// scales it by the unit's speed and the terrain underfoot, and resolves the move against water and the map edge
/// (FERMAN-PLAN §5.2.4, D10).
///
/// `step` is a pure function of its arguments: it only ever reads `previous` and `inputs`, both frozen snapshots of
/// the tick that just ended, and returns a new, independent `UnitKinematics`. Running it for every unit in any
/// order — the whole point of double-buffering — reproduces the exact same result, because every term here is
/// either a table lookup or a sum, and `Fixed` addition is exactly order-independent.
enum Steering {
    static func step(
        previous: UnitKinematics, speedMilliCellsPerSecond: Int, inputs: SteeringInputs, map: BattleMap,
        tuning: SimulationTuning
    ) -> UnitKinematics {
        let intentVector: FixedVector2
        switch inputs.intent {
        case .seek(let direction): intentVector = direction.normalized()
        case .flee(let direction): intentVector = (-direction).normalized()
        case .hold: intentVector = .zero
        }

        let neighborTerms = Self.neighborTerms(
            around: previous.position, neighbors: inputs.neighbors,
            separationRadiusCells: Fixed(tuning.steeringSeparationRadiusCells))

        let blended =
            intentVector * tuning.steeringIntentWeightPercent
            + neighborTerms.separation * tuning.steeringSeparationWeightPercent
            + neighborTerms.alignment * tuning.steeringAlignmentWeightPercent
            + neighborTerms.cohesion * tuning.steeringCohesionWeightPercent
            + inputs.flowDirection * tuning.steeringFlowWeightPercent
        let heading = blended.normalized()

        guard heading != .zero else {
            return UnitKinematics(position: previous.position, velocity: .zero)
        }

        guard
            let currentCell = map.cellIndex(
                column: previous.position.x.roundedDown(), row: previous.position.y.roundedDown())
        else {
            preconditionFailure("Steering.step: unit position \(previous.position) is outside the map")
        }
        let speed =
            Fixed(numerator: speedMilliCellsPerSecond, denominator: 1_000)
            * Self.speedMultiplier(of: map.terrain[currentCell], terrainMovementCost: tuning.terrainMovementCost)
        let displacement = heading * speed / BattleConfig.ticksPerSecond

        let newPosition = Self.resolveCollision(from: previous.position, displacement: displacement, map: map)
        let newVelocity = (newPosition - previous.position) * BattleConfig.ticksPerSecond
        return UnitKinematics(position: newPosition, velocity: newVelocity)
    }

    private static func neighborTerms(
        around position: FixedVector2, neighbors: [SteeringNeighbor], separationRadiusCells: Fixed
    ) -> (separation: FixedVector2, alignment: FixedVector2, cohesion: FixedVector2) {
        guard !neighbors.isEmpty else {
            return (.zero, .zero, .zero)
        }

        let separationRadiusSquared = separationRadiusCells.squared
        var separationSum = FixedVector2.zero
        var velocitySum = FixedVector2.zero
        var positionSum = FixedVector2.zero
        for neighbor in neighbors {
            let offset = position - neighbor.position
            if offset.lengthSquared <= separationRadiusSquared {
                separationSum += offset.normalized()
            }
            velocitySum += neighbor.velocity
            positionSum += neighbor.position
        }

        let centroid = positionSum / neighbors.count
        return (separationSum.normalized(), velocitySum.normalized(), (centroid - position).normalized())
    }

    /// Open terrain (the cheapest to enter, per `terrainMovementCost`) is the speed baseline; costlier terrain
    /// slows a unit in inverse proportion to how much longer it takes to cross.
    private static func speedMultiplier(of terrain: Terrain, terrainMovementCost: PassableTerrainValues) -> Fixed {
        guard let cost = terrainMovementCost[terrain] else {
            preconditionFailure("Steering.step: unit standing on impassable terrain \(terrain)")
        }
        return Fixed(numerator: terrainMovementCost.open, denominator: cost)
    }

    /// The full move if it lands on passable ground inside the map; otherwise an axis-only slide along whichever
    /// axis stays clear, or no move at all if neither does (FERMAN-PLAN §5.2.4).
    private static func resolveCollision(from position: FixedVector2, displacement: FixedVector2, map: BattleMap)
        -> FixedVector2
    {
        let fullMove = position + displacement
        if Self.isPassable(fullMove, map: map) {
            return fullMove
        }
        let xOnly = FixedVector2(x: fullMove.x, y: position.y)
        if Self.isPassable(xOnly, map: map) {
            return xOnly
        }
        let yOnly = FixedVector2(x: position.x, y: fullMove.y)
        if Self.isPassable(yOnly, map: map) {
            return yOnly
        }
        return position
    }

    private static func isPassable(_ position: FixedVector2, map: BattleMap) -> Bool {
        guard let cell = map.cellIndex(column: position.x.roundedDown(), row: position.y.roundedDown()) else {
            return false
        }
        return map.terrain[cell].isPassable
    }
}
