/// What one unit's `currentAction` boils down to for this exact tick: a heading for `Steering`, and — if anything
/// worth hitting is close enough — the target this tick's combat should try to land on.
private struct ActionResolution: Sendable {
    var intent: SteeringIntent = .hold
    /// `Steering`'s separate flow-following term (§5.2.4): nonzero only for `advance` and its "no valid target"
    /// fallbacks, so only those orders pick up the general push toward the enemy. Every other order steers purely
    /// on `intent`, or it would drift even while trying to hold a waypoint, cover, or a guard distance.
    var flowDirection: FixedVector2 = .zero
    var attackTargetID: UnitID?
    /// Set only on the tick `useAbility` actually fires a `volley`; its radius is a tuning constant the combat
    /// phase already has, so only the center needs to travel here.
    var volleyCenter: FixedVector2?
}

/// The tick pipeline (FERMAN-PLAN §5.2): the only place `FermanCore` turns a `BattleConfig` into a `BattleResult`.
/// `run` is a pure function of its arguments — no clock, no ambient randomness, single-threaded — so the same
/// config and seed always produce a bit-identical result (CLAUDE.md rule 2).
public enum BattleSimulator {
    public static func run(_ config: BattleConfig, options: SimulationOptions = SimulationOptions()) -> BattleResult {
        var state = BattleState(config: config)
        var events: [BattleEvent] = []
        var checksum = FNV1a64()

        if options.recordEvents {
            Self.emitSpawnEvents(state: state, into: &events)
        }

        var endResult: (outcome: BattleOutcome, reason: EndReason)?
        var finalTick = config.maxTicks - 1

        tickLoop: for tick in 0..<config.maxTicks {
            state.rebuildFlowFieldsIfNeeded(tick: tick, config: config)
            state.rebuildSpatialGrid(config: config)

            Self.runDecisionPhase(tick: tick, state: &state, config: config, options: options, events: &events)

            var resolutions = [ActionResolution](repeating: ActionResolution(), count: state.units.count)
            for index in state.units.indices where state.units[index].isAlive {
                resolutions[index] = Self.resolveAction(unitIndex: index, state: &state, config: config)
            }

            Self.runSteeringPhase(state: &state, config: config, resolutions: resolutions)
            Self.runCombatAndMoralePhase(
                tick: tick, state: &state, config: config, resolutions: resolutions, options: options, events: &events)

            if options.recordEvents, tick % config.tuning.moveSampleIntervalTicks == 0 {
                Self.emitMoveEvents(tick: tick, state: state, into: &events)
            }

            let isLastPossibleTick = tick == config.maxTicks - 1
            if let outcome = Outcome.afterDeaths(units: state.units) {
                endResult = outcome
                finalTick = tick
                Self.updateChecksum(&checksum, tick: tick, state: state)
                break tickLoop
            }
            if tick % config.tuning.checksumIntervalTicks == 0 || isLastPossibleTick {
                Self.updateChecksum(&checksum, tick: tick, state: state)
            }
        }

        let outcome =
            endResult
            ?? Outcome.atTimeLimit(units: state.units, catalog: config.unitCatalog, objective: config.objective)
        if options.recordEvents {
            events.append(BattleEvent(tick: Int32(finalTick), kind: .battleEnded(outcome.outcome, outcome.reason)))
        }

        return BattleResult(
            outcome: outcome.outcome,
            endReason: outcome.reason,
            tickCount: finalTick + 1,
            events: events,
            ruleFireCounts: state.ruleFireCounts.map {
                RuleFireCounts(team: $0.team, unitType: $0.unitType, counts: $0.counts)
            },
            survivorsPlayer: state.units.filter { $0.team == .player && $0.isAlive }.count,
            survivorsEnemy: state.units.filter { $0.team == .enemy && $0.isAlive }.count,
            checksum: checksum.value
        )
    }
}

// MARK: - Decision (§5.2.3)

extension BattleSimulator {
    /// Refreshes `currentAction` for every unit whose decision tick this is, and unconditionally forces `.scatter`
    /// on anything broken, bypassing `RuleEvaluator` entirely: "dağılmış birim karar vermez."
    private static func runDecisionPhase(
        tick: Int, state: inout BattleState, config: BattleConfig, options: SimulationOptions,
        events: inout [BattleEvent]
    ) {
        for index in state.units.indices where state.units[index].isAlive {
            if state.units[index].morale.isBroken {
                Self.setCurrentAction(.scatter, forUnitAt: index, state: &state, config: config)
                continue
            }
            guard
                RuleEvaluator.isDecisionTick(
                    unitID: state.units[index].id, tick: tick,
                    decisionIntervalTicks: config.tuning.decisionIntervalTicks)
            else {
                continue
            }
            guard let program = state.units[index].program else {
                Self.setCurrentAction(.advance, forUnitAt: index, state: &state, config: config)
                continue
            }

            let context = Self.evaluationContext(forUnitAt: index, state: state, config: config)
            let decision = RuleEvaluator.decide(
                program: program, tick: tick, context: context, previous: state.units[index].decision,
                tuning: config.tuning)
            state.units[index].decision = decision.state
            Self.setCurrentAction(decision.action ?? .advance, forUnitAt: index, state: &state, config: config)

            if let activatedRuleIndex = decision.activatedRuleIndex {
                let unit = state.units[index]
                state.bumpRuleFireCount(team: unit.team, unitType: unit.type, ruleIndex: activatedRuleIndex)
                if options.recordEvents {
                    events.append(
                        BattleEvent(tick: Int32(tick), kind: .ruleActivated(unit.id, ruleIndex: activatedRuleIndex)))
                }
            }
        }
    }

    /// Sets `currentAction` and, alongside it, whatever sub-state that order needs fresh: `flankLeft`/`flankRight`'s
    /// waypoint (recomputed only when the order changes, so the unit actually arrives instead of chasing a moving
    /// offset forever) and `scatter`'s heading (redrawn only when scattering starts, so a routing unit commits to
    /// one direction instead of jittering).
    private static func setCurrentAction(
        _ action: Action, forUnitAt index: Int, state: inout BattleState, config: BattleConfig
    ) {
        let previousKind = state.units[index].currentAction.kind
        switch action.kind {
        case .flankLeft, .flankRight:
            if previousKind != action.kind || state.units[index].flankWaypoint == nil {
                state.units[index].flankWaypoint = Self.flankWaypoint(
                    forUnitAt: index, isLeft: action.kind == .flankLeft, state: state, config: config)
            }
        default:
            state.units[index].flankWaypoint = nil
        }
        if action.kind == .scatter, previousKind != .scatter {
            state.units[index].scatterDirection = Self.randomDirection(rng: &state.rng)
        }
        state.units[index].currentAction = action
    }

    private static func evaluationContext(forUnitAt index: Int, state: BattleState, config: BattleConfig)
        -> RuleEvaluationContext
    {
        let unit = state.units[index]
        let unitType = config.unitType(unit.type)
        let ownPosition = unit.kinematics.position
        let rangeCells = Fixed(numerator: unitType.rangeMilliCells, denominator: 1_000)
        let proximityRadius = Fixed(config.tuning.proximityRadiusCells)

        let nearestEnemy = Self.nearestLivingUnit(from: ownPosition, team: unit.team.opponent, state: state)
        let nearbyEntries = state.spatialGrid.entries(within: proximityRadius, of: ownPosition)

        return RuleEvaluationContext(
            ownHP: unit.hp, ownMaxHP: unitType.maxHP, ownMorale: unit.morale.morale, ownMoraleMax: unitType.moraleMax,
            ownTerrain: config.map.terrain[config.cell(at: ownPosition)], isFlanked: unit.flankedTicksRemaining > 0,
            ownTeamCommanderDead: unit.team == .player ? state.playerCommanderDied : state.enemyCommanderDied,
            nearestEnemyDistanceCells: nearestEnemy.map { Self.ceilingCells($0.distanceSquared.squareRoot()) },
            nearestEnemyType: nearestEnemy.map { state.units[Int($0.id.rawValue)].type },
            enemyTypesInRange: Self.livingEnemyTypes(
                within: rangeCells, of: ownPosition, enemyTeam: unit.team.opponent, state: state),
            nearbyLivingAllyCount: nearbyEntries.filter {
                $0.id != unit.id && state.units[Int($0.id.rawValue)].team == unit.team
            }
            .count,
            nearbyLivingEnemyCount: nearbyEntries.filter { state.units[Int($0.id.rawValue)].team != unit.team }.count
        )
    }

    /// The integer cell count `N` for which `trueDistance ≤ N` exactly matches `trueDistance ≤ cells` for every
    /// integer `cells`: the ceiling, not a round or a floor. Flooring would let `enemyWithin(2)` match an enemy
    /// that is actually 2.9 cells away.
    private static func ceilingCells(_ distance: Fixed) -> Int {
        let flooredCells = distance.roundedDown()
        return Fixed(flooredCells) == distance ? flooredCells : flooredCells + 1
    }

    private static func livingEnemyTypes(
        within radius: Fixed, of position: FixedVector2, enemyTeam: Team, state: BattleState
    )
        -> [UnitTypeID]
    {
        var types: [UnitTypeID] = []
        for entry in state.spatialGrid.entries(within: radius, of: position) {
            let candidate = state.units[Int(entry.id.rawValue)]
            guard candidate.team == enemyTeam, candidate.isAlive, !types.contains(candidate.type) else { continue }
            types.append(candidate.type)
        }
        return types
    }

    private static func randomDirection(rng: inout DeterministicRNG) -> FixedVector2 {
        let angle = FixedAngle(raw: Int32(rng.int(in: 0...(Int(FixedAngle.unitsPerTurn) - 1))))
        return FixedMath.direction(angle)
    }

    private static func flankWaypoint(forUnitAt index: Int, isLeft: Bool, state: BattleState, config: BattleConfig)
        -> FixedVector2?
    {
        let unit = state.units[index]
        guard
            let nearest = Self.nearestLivingUnit(from: unit.kinematics.position, team: unit.team.opponent, state: state)
        else {
            return nil
        }
        let enemyPosition = state.units[Int(nearest.id.rawValue)].kinematics.position
        var advanceDirection = state.flowField(for: unit.team).direction(
            atCell: config.cell(at: unit.kinematics.position))
        if advanceDirection == .zero {
            advanceDirection = FixedVector2(x: .one, y: .zero)
        }
        // A 90° rotation is exact integer algebra — swap the axes and negate one — so it needs no trig table.
        let perpendicular =
            isLeft
            ? FixedVector2(x: -advanceDirection.y, y: advanceDirection.x)
            : FixedVector2(x: advanceDirection.y, y: -advanceDirection.x)
        return enemyPosition + perpendicular.normalized() * Fixed(config.tuning.flankOffsetCells)
    }
}

// MARK: - Action resolution: `currentAction` → a heading and an attack target, every tick (§5.4)

extension BattleSimulator {
    private static func resolveAction(unitIndex: Int, state: inout BattleState, config: BattleConfig)
        -> ActionResolution
    {
        state.units[unitIndex].ability = Abilities.afterTick(state.units[unitIndex].ability)
        let unit = state.units[unitIndex]
        let unitType = config.unitType(unit.type)
        let ownPosition = unit.kinematics.position
        let rangeCells = Fixed(numerator: unitType.rangeMilliCells, denominator: 1_000)
        let opponent = unit.team.opponent
        let flowDirection = state.flowField(for: unit.team).direction(atCell: config.cell(at: ownPosition))

        switch unit.currentAction {
        case .advance:
            let attackTarget = Self.inRangeAttackTarget(
                near: ownPosition, ownPosition: ownPosition, rangeCells: rangeCells, enemyTeam: opponent, state: state)
            return ActionResolution(intent: .hold, flowDirection: flowDirection, attackTargetID: attackTarget)

        case .retreat:
            return ActionResolution(intent: .flee(flowDirection), attackTargetID: nil)

        case .hold:
            let attackTarget = Self.inRangeAttackTarget(
                near: ownPosition, ownPosition: ownPosition, rangeCells: rangeCells, enemyTeam: opponent, state: state)
            return ActionResolution(intent: .hold, attackTargetID: attackTarget)

        case .focusFire(let preferredType):
            return Self.resolveFocusFire(
                preferredType, ownPosition: ownPosition, rangeCells: rangeCells, opponent: opponent,
                flowDirection: flowDirection,
                state: state, config: config)

        case .flankLeft, .flankRight:
            return Self.resolveFlank(
                unit: unit, ownPosition: ownPosition, flowDirection: flowDirection, opponent: opponent,
                rangeCells: rangeCells,
                state: state)

        case .regroup:
            return Self.resolveRegroup(
                unit: unit, ownPosition: ownPosition, rangeCells: rangeCells, opponent: opponent, state: state,
                config: config)

        case .useAbility:
            return Self.resolveUseAbility(
                unitIndex: unitIndex, unitType: unitType, ownPosition: ownPosition, rangeCells: rangeCells,
                opponent: opponent,
                tuning: config.tuning, state: &state)

        case .takeCover:
            return Self.resolveTakeCover(
                ownPosition: ownPosition, rangeCells: rangeCells, opponent: opponent, state: state, config: config)

        case .guardCommander:
            return Self.resolveGuardCommander(
                unit: unit, ownPosition: ownPosition, rangeCells: rangeCells, opponent: opponent, tuning: config.tuning,
                state: state)

        case .scatter:
            return ActionResolution(intent: .seek(unit.scatterDirection), attackTargetID: nil)
        }
    }

    private static func resolveFocusFire(
        _ preferredType: UnitTypeID?, ownPosition: FixedVector2, rangeCells: Fixed, opponent: Team,
        flowDirection: FixedVector2,
        state: BattleState, config: BattleConfig
    ) -> ActionResolution {
        let searchRadius = rangeCells + Fixed(config.tuning.focusFireExtraRangeCells)
        var candidate: UnitID?
        if let preferredType,
            let match = Self.nearestLivingUnit(
                from: ownPosition, team: opponent, state: state, where: { $0.type == preferredType }),
            match.distanceSquared <= searchRadius.squared
        {
            candidate = match.id
        } else if let weakest = Self.weakestLivingEnemy(
            within: searchRadius, of: ownPosition, enemyTeam: opponent, state: state)
        {
            candidate = weakest
        }

        guard let candidate else {
            let attackTarget = Self.inRangeAttackTarget(
                near: ownPosition, ownPosition: ownPosition, rangeCells: rangeCells, enemyTeam: opponent, state: state)
            return ActionResolution(intent: .hold, flowDirection: flowDirection, attackTargetID: attackTarget)
        }

        let targetPosition = state.units[Int(candidate.rawValue)].kinematics.position
        guard ownPosition.distanceSquared(to: targetPosition) <= rangeCells.squared else {
            return ActionResolution(intent: .seek(targetPosition - ownPosition), attackTargetID: nil)
        }
        return ActionResolution(intent: .hold, attackTargetID: candidate)
    }

    private static func resolveFlank(
        unit: UnitState, ownPosition: FixedVector2, flowDirection: FixedVector2, opponent: Team, rangeCells: Fixed,
        state: BattleState
    ) -> ActionResolution {
        guard let waypoint = unit.flankWaypoint else {
            // No enemy existed when the order was chosen, so there was nothing to flank around: falls back to
            // advancing until one appears.
            let attackTarget = Self.inRangeAttackTarget(
                near: ownPosition, ownPosition: ownPosition, rangeCells: rangeCells, enemyTeam: opponent, state: state)
            return ActionResolution(intent: .hold, flowDirection: flowDirection, attackTargetID: attackTarget)
        }
        guard ownPosition.distanceSquared(to: waypoint) <= Fixed.one.squared else {
            return ActionResolution(intent: .seek(waypoint - ownPosition), attackTargetID: nil)
        }
        let attackTarget = Self.inRangeAttackTarget(
            near: ownPosition, ownPosition: ownPosition, rangeCells: rangeCells, enemyTeam: opponent, state: state)
        return ActionResolution(intent: .hold, flowDirection: flowDirection, attackTargetID: attackTarget)
    }

    private static func resolveRegroup(
        unit: UnitState, ownPosition: FixedVector2, rangeCells: Fixed, opponent: Team, state: BattleState,
        config: BattleConfig
    ) -> ActionResolution {
        let attackTarget = Self.inRangeAttackTarget(
            near: ownPosition, ownPosition: ownPosition, rangeCells: rangeCells, enemyTeam: opponent, state: state)
        let allyPositions = Self.nearbyAlliesOfSameType(
            type: unit.type, excluding: unit.id, team: unit.team, within: Fixed(config.tuning.regroupRadiusCells),
            of: ownPosition, state: state)
        guard !allyPositions.isEmpty else {
            return ActionResolution(intent: .hold, attackTargetID: attackTarget)
        }
        let centroid = allyPositions.reduce(FixedVector2.zero, +) / allyPositions.count
        return ActionResolution(intent: .seek(centroid - ownPosition), attackTargetID: attackTarget)
    }

    private static func resolveUseAbility(
        unitIndex: Int, unitType: UnitType, ownPosition: FixedVector2, rangeCells: Fixed, opponent: Team,
        tuning: SimulationTuning,
        state: inout BattleState
    ) -> ActionResolution {
        let wasReady = state.units[unitIndex].ability.cooldown.isReady
        state.units[unitIndex].ability = Abilities.activate(
            state.units[unitIndex].ability, ability: unitType.ability, tuning: tuning)

        let attackTarget = Self.inRangeAttackTarget(
            near: ownPosition, ownPosition: ownPosition, rangeCells: rangeCells, enemyTeam: opponent, state: state)
        let volleyFired = wasReady && unitType.ability == .volley
        return ActionResolution(
            intent: .hold,
            attackTargetID: volleyFired ? nil : attackTarget,
            volleyCenter: volleyFired ? attackTarget.map { state.units[Int($0.rawValue)].kinematics.position } : nil
        )
    }

    private static func resolveTakeCover(
        ownPosition: FixedVector2, rangeCells: Fixed, opponent: Team, state: BattleState, config: BattleConfig
    ) -> ActionResolution {
        guard
            let coverCell = Self.nearestCoverCell(
                from: ownPosition, withinCells: config.tuning.coverSearchRadiusCells, map: config.map)
        else {
            let attackTarget = Self.inRangeAttackTarget(
                near: ownPosition, ownPosition: ownPosition, rangeCells: rangeCells, enemyTeam: opponent, state: state)
            return ActionResolution(intent: .hold, attackTargetID: attackTarget)
        }
        let coverPosition = config.map.center(ofCell: coverCell)
        guard ownPosition.distanceSquared(to: coverPosition) > Fixed.half.squared else {
            return ActionResolution(intent: .hold, attackTargetID: nil)
        }
        return ActionResolution(intent: .seek(coverPosition - ownPosition), attackTargetID: nil)
    }

    private static func resolveGuardCommander(
        unit: UnitState, ownPosition: FixedVector2, rangeCells: Fixed, opponent: Team, tuning: SimulationTuning,
        state: BattleState
    ) -> ActionResolution {
        guard
            let commander = Self.nearestLivingUnit(
                from: ownPosition, team: unit.team, state: state, where: \.isCommander)
        else {
            let attackTarget = Self.inRangeAttackTarget(
                near: ownPosition, ownPosition: ownPosition, rangeCells: rangeCells, enemyTeam: opponent, state: state)
            return ActionResolution(intent: .hold, attackTargetID: attackTarget)
        }
        let commanderPosition = state.units[Int(commander.id.rawValue)].kinematics.position
        let attackTarget = Self.inRangeAttackTarget(
            near: commanderPosition, ownPosition: ownPosition, rangeCells: rangeCells, enemyTeam: opponent, state: state
        )
        guard ownPosition.distanceSquared(to: commanderPosition) > Fixed(tuning.guardCommanderDistanceCells).squared
        else {
            return ActionResolution(intent: .hold, attackTargetID: attackTarget)
        }
        return ActionResolution(intent: .seek(commanderPosition - ownPosition), attackTargetID: attackTarget)
    }
}

// MARK: - Shared spatial queries, all with an explicit distance-then-`UnitID` tie-break (D10)

extension BattleSimulator {
    private static func nearestLivingUnit(
        from position: FixedVector2, team: Team, state: BattleState,
        where predicate: (UnitState) -> Bool = { _ in true }
    ) -> (id: UnitID, distanceSquared: FixedSquared)? {
        var best: (id: UnitID, distanceSquared: FixedSquared)?
        for unit in state.units where unit.team == team && unit.isAlive && predicate(unit) {
            let distance = position.distanceSquared(to: unit.kinematics.position)
            guard let current = best else {
                best = (unit.id, distance)
                continue
            }
            if distance < current.distanceSquared || (distance == current.distanceSquared && unit.id < current.id) {
                best = (unit.id, distance)
            }
        }
        return best
    }

    /// The nearest living enemy to `referencePosition`, kept only if it is within `ownRangeCells` of
    /// `ownPosition` — the two positions differ for orders like `guardCommander` that aim from the commander's
    /// side but still need the attack to land within the attacker's own weapon range.
    private static func inRangeAttackTarget(
        near referencePosition: FixedVector2, ownPosition: FixedVector2, rangeCells: Fixed, enemyTeam: Team,
        state: BattleState
    ) -> UnitID? {
        guard let nearest = Self.nearestLivingUnit(from: referencePosition, team: enemyTeam, state: state) else {
            return nil
        }
        let ownDistanceSquared = ownPosition.distanceSquared(
            to: state.units[Int(nearest.id.rawValue)].kinematics.position)
        return ownDistanceSquared <= rangeCells.squared ? nearest.id : nil
    }

    private static func weakestLivingEnemy(
        within radius: Fixed, of position: FixedVector2, enemyTeam: Team, state: BattleState
    )
        -> UnitID?
    {
        var best: (id: UnitID, hp: Int, distanceSquared: FixedSquared)?
        for entry in state.spatialGrid.entries(within: radius, of: position) {
            let candidate = state.units[Int(entry.id.rawValue)]
            guard candidate.team == enemyTeam, candidate.isAlive else { continue }
            let distance = position.distanceSquared(to: entry.position)
            guard let current = best else {
                best = (candidate.id, candidate.hp, distance)
                continue
            }
            let isBetter =
                candidate.hp < current.hp
                || (candidate.hp == current.hp && distance < current.distanceSquared)
                || (candidate.hp == current.hp && distance == current.distanceSquared && candidate.id < current.id)
            if isBetter {
                best = (candidate.id, candidate.hp, distance)
            }
        }
        return best?.id
    }

    private static func nearbyAlliesOfSameType(
        type: UnitTypeID, excluding selfID: UnitID, team: Team, within radius: Fixed, of position: FixedVector2,
        state: BattleState
    ) -> [FixedVector2] {
        state.spatialGrid.entries(within: radius, of: position).compactMap { entry -> FixedVector2? in
            guard entry.id != selfID else { return nil }
            let candidate = state.units[Int(entry.id.rawValue)]
            guard candidate.team == team, candidate.isAlive, candidate.type == type else { return nil }
            return entry.position
        }
    }

    private static func nearestCoverCell(from position: FixedVector2, withinCells radius: Int, map: BattleMap) -> Int? {
        let ownCell = map.cellIndex(column: position.x.roundedDown(), row: position.y.roundedDown())
        guard let ownCell else {
            preconditionFailure("nearestCoverCell: position \(position) is outside the map")
        }
        let (column, row) = map.coordinates(ofCell: ownCell)
        let radiusSquared = Fixed(radius).squared

        var best: (cell: Int, distanceSquared: FixedSquared)?
        for rowOffset in -radius...radius {
            for columnOffset in -radius...radius {
                let candidateColumn = column + columnOffset
                let candidateRow = row + rowOffset
                guard (0..<map.width).contains(candidateColumn), (0..<map.height).contains(candidateRow) else {
                    continue
                }
                let cell = candidateRow * map.width + candidateColumn
                guard map.terrain[cell].providesCover else { continue }
                let distanceSquared = position.distanceSquared(to: map.center(ofCell: cell))
                guard distanceSquared <= radiusSquared else { continue }
                guard let current = best else {
                    best = (cell, distanceSquared)
                    continue
                }
                if distanceSquared < current.distanceSquared
                    || (distanceSquared == current.distanceSquared && cell < current.cell)
                {
                    best = (cell, distanceSquared)
                }
            }
        }
        return best?.cell
    }
}

// MARK: - Steering (§5.2.4, D10)

extension BattleSimulator {
    private static func runSteeringPhase(
        state: inout BattleState, config: BattleConfig, resolutions: [ActionResolution]
    ) {
        let previousKinematics = state.units.map(\.kinematics)
        let proximityRadius = Fixed(config.tuning.proximityRadiusCells)

        for index in state.units.indices where state.units[index].isAlive {
            let unit = state.units[index]
            let unitType = config.unitType(unit.type)
            let neighbors = Self.steeringNeighbors(
                around: unit.kinematics.position, selfID: unit.id, team: unit.team, radius: proximityRadius,
                state: state,
                previousKinematics: previousKinematics)
            let speed = Self.effectiveSpeed(of: unit, unitType: unitType, tuning: config.tuning)
            let inputs = SteeringInputs(
                intent: resolutions[index].intent, neighbors: neighbors, flowDirection: resolutions[index].flowDirection
            )

            let newKinematics = Steering.step(
                previous: unit.kinematics, speedMilliCellsPerSecond: speed, inputs: inputs, map: config.map,
                tuning: config.tuning)
            state.units[index].kinematics = newKinematics
            if newKinematics.velocity != .zero {
                state.units[index].facing = newKinematics.velocity.normalized()
            }
        }
    }

    /// Same-team units within the general "nearby" radius, read from the tick's *previous* kinematics (D10):
    /// otherwise a unit processed earlier this tick would already have moved by the time a later unit samples it,
    /// making the result depend on iteration order.
    private static func steeringNeighbors(
        around position: FixedVector2, selfID: UnitID, team: Team, radius: Fixed, state: BattleState,
        previousKinematics: [UnitKinematics]
    ) -> [SteeringNeighbor] {
        state.spatialGrid.entries(within: radius, of: position).compactMap { entry -> SteeringNeighbor? in
            guard entry.id != selfID, state.units[Int(entry.id.rawValue)].team == team else { return nil }
            let kinematics = previousKinematics[Int(entry.id.rawValue)]
            return SteeringNeighbor(position: kinematics.position, velocity: kinematics.velocity)
        }
    }

    private static func effectiveSpeed(of unit: UnitState, unitType: UnitType, tuning: SimulationTuning) -> Int {
        guard unit.ability.isActive, unitType.ability == .charge else {
            return unitType.speedMilliCellsPerSecond
        }
        return unitType.speedMilliCellsPerSecond * (100 + tuning.chargeSpeedBonusPercent) / 100
    }
}

// MARK: - Combat and morale (§5.2.5–6)

extension BattleSimulator {
    private struct PendingAttack {
        let target: UnitID
        let damage: Int
        let isFlanking: Bool
    }

    private static func runCombatAndMoralePhase(
        tick: Int, state: inout BattleState, config: BattleConfig, resolutions: [ActionResolution],
        options: SimulationOptions,
        events: inout [BattleEvent]
    ) {
        var pending: [PendingAttack] = []
        Self.collectOrdinaryAttacks(
            tick: tick, state: &state, config: config, resolutions: resolutions, options: options, events: &events,
            into: &pending)
        Self.collectVolleyAttacks(
            tick: tick, state: state, config: config, resolutions: resolutions, options: options, events: &events,
            into: &pending)

        var flankedThisTick = [Bool](repeating: false, count: state.units.count)
        for attack in pending {
            state.units[Int(attack.target.rawValue)].hp -= attack.damage
            if attack.isFlanking {
                flankedThisTick[Int(attack.target.rawValue)] = true
            }
        }

        var deaths: [UnitID] = []
        for attack in pending where state.units[Int(attack.target.rawValue)].hp <= 0 && !deaths.contains(attack.target)
        {
            deaths.append(attack.target)
        }
        if options.recordEvents {
            for id in deaths {
                events.append(BattleEvent(tick: Int32(tick), kind: .death(id)))
            }
        }

        let playerCommanderJustDied =
            !state.playerCommanderDied
            && deaths.contains {
                state.units[Int($0.rawValue)].team == .player && state.units[Int($0.rawValue)].isCommander
            }
        let enemyCommanderJustDied =
            !state.enemyCommanderDied
            && deaths.contains {
                state.units[Int($0.rawValue)].team == .enemy && state.units[Int($0.rawValue)].isCommander
            }
        if playerCommanderJustDied { state.playerCommanderDied = true }
        if enemyCommanderJustDied { state.enemyCommanderDied = true }

        Self.runMoralePhase(
            tick: tick, state: &state, config: config, deaths: deaths, flankedThisTick: flankedThisTick,
            playerCommanderJustDied: playerCommanderJustDied, enemyCommanderJustDied: enemyCommanderJustDied,
            options: options,
            events: &events)
    }

    private static func collectOrdinaryAttacks(
        tick: Int, state: inout BattleState, config: BattleConfig, resolutions: [ActionResolution],
        options: SimulationOptions,
        events: inout [BattleEvent], into pending: inout [PendingAttack]
    ) {
        for index in state.units.indices where state.units[index].isAlive && !state.units[index].morale.isBroken {
            state.units[index].attackCooldown = state.units[index].attackCooldown.afterTick()
            guard state.units[index].attackCooldown.isReady, let targetID = resolutions[index].attackTargetID else {
                continue
            }
            let targetIndex = Int(targetID.rawValue)
            guard state.units[targetIndex].isAlive else { continue }

            let attackerType = config.unitType(state.units[index].type)
            let defenderType = config.unitType(state.units[targetIndex].type)

            var attackerAbility = AttackerAbilityState(
                spearWallActive: state.units[index].ability.isActive && attackerType.ability == .spearWall)
            if attackerType.ability == .charge, state.units[index].ability.isActive {
                let (bonusApplies, newAbility) = Abilities.consumingChargeBonus(state.units[index].ability)
                attackerAbility.chargeBonusApplies = bonusApplies
                state.units[index].ability = newAbility
            }
            let defenderAbility = DefenderAbilityState(
                spearWallActive: state.units[targetIndex].ability.isActive && defenderType.ability == .spearWall,
                shieldWallActive: state.units[targetIndex].ability.isActive && defenderType.ability == .shieldWall)
            let defenderTerrain = config.map.terrain[config.cell(at: state.units[targetIndex].kinematics.position)]

            let damage = Combat.damage(
                attacker: attackerType, defender: defenderType, defenderTerrain: defenderTerrain,
                attackerAbility: attackerAbility,
                defenderAbility: defenderAbility, tuning: config.tuning)
            let attackDirection =
                (state.units[index].kinematics.position - state.units[targetIndex].kinematics.position)
                .normalized()
            let isFlanking = Combat.isFlankingHit(
                defenderFacing: state.units[targetIndex].facing, attackDirection: attackDirection)

            pending.append(PendingAttack(target: targetID, damage: damage, isFlanking: isFlanking))
            state.units[index].attackCooldown = Cooldown(ticksRemaining: attackerType.attackIntervalTicks)
            if options.recordEvents {
                events.append(
                    BattleEvent(
                        tick: Int32(tick), kind: .attack(state.units[index].id, target: targetID, damage: damage)))
            }
        }
    }

    private static func collectVolleyAttacks(
        tick: Int, state: BattleState, config: BattleConfig, resolutions: [ActionResolution],
        options: SimulationOptions,
        events: inout [BattleEvent], into pending: inout [PendingAttack]
    ) {
        for index in state.units.indices where state.units[index].isAlive {
            guard let center = resolutions[index].volleyCenter else { continue }
            let attackerType = config.unitType(state.units[index].type)
            let radiusSquared = Fixed(config.tuning.volleyRadiusCells).squared

            for targetIndex in state.units.indices
            where state.units[targetIndex].isAlive && state.units[targetIndex].team != state.units[index].team
                && center.distanceSquared(to: state.units[targetIndex].kinematics.position) <= radiusSquared
            {
                let defenderType = config.unitType(state.units[targetIndex].type)
                let defenderAbility = DefenderAbilityState(
                    spearWallActive: state.units[targetIndex].ability.isActive && defenderType.ability == .spearWall,
                    shieldWallActive: state.units[targetIndex].ability.isActive && defenderType.ability == .shieldWall)
                let defenderTerrain = config.map.terrain[config.cell(at: state.units[targetIndex].kinematics.position)]
                let damage = Combat.damage(
                    attacker: attackerType, defender: defenderType, defenderTerrain: defenderTerrain,
                    defenderAbility: defenderAbility, tuning: config.tuning)
                pending.append(PendingAttack(target: state.units[targetIndex].id, damage: damage, isFlanking: false))
                if options.recordEvents {
                    events.append(
                        BattleEvent(
                            tick: Int32(tick),
                            kind: .attack(state.units[index].id, target: state.units[targetIndex].id, damage: damage)))
                }
            }
            if options.recordEvents {
                events.append(BattleEvent(tick: Int32(tick), kind: .abilityUsed(state.units[index].id, .volley)))
            }
        }
    }

    private static func runMoralePhase(
        tick: Int, state: inout BattleState, config: BattleConfig, deaths: [UnitID], flankedThisTick: [Bool],
        playerCommanderJustDied: Bool, enemyCommanderJustDied: Bool, options: SimulationOptions,
        events: inout [BattleEvent]
    ) {
        for index in state.units.indices where state.units[index].isAlive {
            var unit = state.units[index]
            var moraleEvents: [MoraleEvent] = []

            if flankedThisTick[index] {
                moraleEvents.append(.flanked)
                unit.flankedTicksRemaining = config.tuning.flankedMemoryTicks
            } else {
                unit.flankedTicksRemaining = Swift.max(0, unit.flankedTicksRemaining - 1)
            }
            if (unit.team == .player && playerCommanderJustDied) || (unit.team == .enemy && enemyCommanderJustDied) {
                moraleEvents.append(.commanderDied)
            }
            for deadID in deaths where state.units[Int(deadID.rawValue)].team == unit.team {
                let deadPosition = state.units[Int(deadID.rawValue)].kinematics.position
                if unit.kinematics.position.distanceSquared(to: deadPosition)
                    <= Fixed(config.tuning.allyDeathMoraleRadiusCells).squared
                {
                    moraleEvents.append(.allyDiedNearby)
                }
            }

            let noEnemyNearby = !state.spatialGrid.entries(
                within: Fixed(config.tuning.moraleRecoveryEnemyFreeRadiusCells), of: unit.kinematics.position
            ).contains { state.units[Int($0.id.rawValue)].team != unit.team }

            let unitType = config.unitType(unit.type)
            let (newMorale, broke, recovered) = Morale.step(
                unit.morale, events: moraleEvents, noEnemyNearby: noEnemyNearby, tick: tick,
                moraleMax: unitType.moraleMax,
                tuning: config.tuning)
            unit.morale = newMorale
            state.units[index] = unit

            if options.recordEvents {
                if broke {
                    events.append(BattleEvent(tick: Int32(tick), kind: .moraleBroken(unit.id)))
                }
                if recovered {
                    events.append(BattleEvent(tick: Int32(tick), kind: .moraleRecovered(unit.id)))
                }
            }
        }
    }
}

// MARK: - Events and checksum (§5.2.7)

extension BattleSimulator {
    private static func emitSpawnEvents(state: BattleState, into events: inout [BattleEvent]) {
        for unit in state.units {
            events.append(BattleEvent(tick: 0, kind: .spawn(unit.id, unit.type, unit.team, unit.kinematics.position)))
        }
    }

    private static func emitMoveEvents(tick: Int, state: BattleState, into events: inout [BattleEvent]) {
        for unit in state.units where unit.isAlive && unit.kinematics.velocity != .zero {
            events.append(BattleEvent(tick: Int32(tick), kind: .move(unit.id, unit.kinematics.position)))
        }
    }

    /// FNV-1a over every unit's raw fields, in `UnitID` order, prefixed by the tick.
    private static func updateChecksum(_ checksum: inout FNV1a64, tick: Int, state: BattleState) {
        checksum.combine(Int32(tick))
        for unit in state.units {
            checksum.combine(unit.kinematics.position)
            checksum.combine(unit.kinematics.velocity)
            checksum.combine(Int32(unit.hp))
            checksum.combine(Int32(unit.morale.morale))
            checksum.combine(Int32(unit.attackCooldown.ticksRemaining))
            checksum.combine(Int32(unit.decision.activeRuleIndex ?? -1))
            checksum.combine(unit.morale.isBroken)
            checksum.combine(unit.flankedTicksRemaining > 0)
        }
    }
}
