/// Every balance constant of the simulation (FERMAN-PLAN §5).
///
/// Tuning travels inside `BattleConfig`, so a recorded battle replays with the numbers it was fought under even after
/// the defaults change. Values are integers in the unit their name states.
public struct SimulationTuning: Sendable, Hashable, Codable {
    public var flowFieldIntervalTicks: Int
    /// Dijkstra step cost for entering a cell of each passable terrain.
    public var terrainMovementCost: PassableTerrainValues
    public var decisionIntervalTicks: Int
    public var minimumCommitTicks: Int
    /// Radius of `allyCountBelow` and `enemyDensityAbove`.
    public var proximityRadiusCells: Int
    /// How long a rear hit keeps `isFlanked` true.
    public var flankedMemoryTicks: Int
    public var counterDamagePercent: Int
    public var coverRangedDamageReductionPercent: Int
    public var focusFireExtraRangeCells: Int
    public var flankOffsetCells: Int
    public var regroupRadiusCells: Int
    public var coverSearchRadiusCells: Int
    public var guardCommanderDistanceCells: Int
    public var allyDeathMoraleRadiusCells: Int
    public var allyDeathMoralePenalty: Int
    public var commanderDeathMoralePenalty: Int
    public var flankedMoralePenalty: Int
    public var moraleRecoveryPerSecond: Int
    public var moraleRecoveryEnemyFreeRadiusCells: Int
    public var moraleBreakPercent: Int
    public var moraleBrokenTicks: Int
    public var moraleRecoveredPercent: Int
    public var moveSampleIntervalTicks: Int
    public var checksumIntervalTicks: Int
    public var spatialBucketCells: Int
    /// How close two units must be to push each other apart in `Steering`.
    public var steeringSeparationRadiusCells: Int
    /// Relative weights of `Steering`'s five blended terms: order intent, separation, alignment, cohesion, and flow
    /// following. Each term is a unit vector before weighting, so these compare directly; they need not sum to 100.
    public var steeringIntentWeightPercent: Int
    public var steeringSeparationWeightPercent: Int
    public var steeringAlignmentWeightPercent: Int
    public var steeringCohesionWeightPercent: Int
    public var steeringFlowWeightPercent: Int
    public var abilityCooldownTicks: Int
    /// How long `spearWall`, `shieldWall` and `charge`'s speed boost hold once activated; `volley` is instantaneous.
    public var abilityDurationTicks: Int
    public var spearWallDamageTakenReductionPercent: Int
    public var spearWallDamageDealtBonusPercent: Int
    public var shieldWallDamageReductionPercent: Int
    public var chargeSpeedBonusPercent: Int
    public var chargeFirstHitDamageBonusPercent: Int
    public var volleyRadiusCells: Int

    public init(
        flowFieldIntervalTicks: Int,
        terrainMovementCost: PassableTerrainValues,
        decisionIntervalTicks: Int,
        minimumCommitTicks: Int,
        proximityRadiusCells: Int,
        flankedMemoryTicks: Int,
        counterDamagePercent: Int,
        coverRangedDamageReductionPercent: Int,
        focusFireExtraRangeCells: Int,
        flankOffsetCells: Int,
        regroupRadiusCells: Int,
        coverSearchRadiusCells: Int,
        guardCommanderDistanceCells: Int,
        allyDeathMoraleRadiusCells: Int,
        allyDeathMoralePenalty: Int,
        commanderDeathMoralePenalty: Int,
        flankedMoralePenalty: Int,
        moraleRecoveryPerSecond: Int,
        moraleRecoveryEnemyFreeRadiusCells: Int,
        moraleBreakPercent: Int,
        moraleBrokenTicks: Int,
        moraleRecoveredPercent: Int,
        moveSampleIntervalTicks: Int,
        checksumIntervalTicks: Int,
        spatialBucketCells: Int,
        steeringSeparationRadiusCells: Int,
        steeringIntentWeightPercent: Int,
        steeringSeparationWeightPercent: Int,
        steeringAlignmentWeightPercent: Int,
        steeringCohesionWeightPercent: Int,
        steeringFlowWeightPercent: Int,
        abilityCooldownTicks: Int,
        abilityDurationTicks: Int,
        spearWallDamageTakenReductionPercent: Int,
        spearWallDamageDealtBonusPercent: Int,
        shieldWallDamageReductionPercent: Int,
        chargeSpeedBonusPercent: Int,
        chargeFirstHitDamageBonusPercent: Int,
        volleyRadiusCells: Int
    ) {
        self.flowFieldIntervalTicks = flowFieldIntervalTicks
        self.terrainMovementCost = terrainMovementCost
        self.decisionIntervalTicks = decisionIntervalTicks
        self.minimumCommitTicks = minimumCommitTicks
        self.proximityRadiusCells = proximityRadiusCells
        self.flankedMemoryTicks = flankedMemoryTicks
        self.counterDamagePercent = counterDamagePercent
        self.coverRangedDamageReductionPercent = coverRangedDamageReductionPercent
        self.focusFireExtraRangeCells = focusFireExtraRangeCells
        self.flankOffsetCells = flankOffsetCells
        self.regroupRadiusCells = regroupRadiusCells
        self.coverSearchRadiusCells = coverSearchRadiusCells
        self.guardCommanderDistanceCells = guardCommanderDistanceCells
        self.allyDeathMoraleRadiusCells = allyDeathMoraleRadiusCells
        self.allyDeathMoralePenalty = allyDeathMoralePenalty
        self.commanderDeathMoralePenalty = commanderDeathMoralePenalty
        self.flankedMoralePenalty = flankedMoralePenalty
        self.moraleRecoveryPerSecond = moraleRecoveryPerSecond
        self.moraleRecoveryEnemyFreeRadiusCells = moraleRecoveryEnemyFreeRadiusCells
        self.moraleBreakPercent = moraleBreakPercent
        self.moraleBrokenTicks = moraleBrokenTicks
        self.moraleRecoveredPercent = moraleRecoveredPercent
        self.moveSampleIntervalTicks = moveSampleIntervalTicks
        self.checksumIntervalTicks = checksumIntervalTicks
        self.spatialBucketCells = spatialBucketCells
        self.steeringSeparationRadiusCells = steeringSeparationRadiusCells
        self.steeringIntentWeightPercent = steeringIntentWeightPercent
        self.steeringSeparationWeightPercent = steeringSeparationWeightPercent
        self.steeringAlignmentWeightPercent = steeringAlignmentWeightPercent
        self.steeringCohesionWeightPercent = steeringCohesionWeightPercent
        self.steeringFlowWeightPercent = steeringFlowWeightPercent
        self.abilityCooldownTicks = abilityCooldownTicks
        self.abilityDurationTicks = abilityDurationTicks
        self.spearWallDamageTakenReductionPercent = spearWallDamageTakenReductionPercent
        self.spearWallDamageDealtBonusPercent = spearWallDamageDealtBonusPercent
        self.shieldWallDamageReductionPercent = shieldWallDamageReductionPercent
        self.chargeSpeedBonusPercent = chargeSpeedBonusPercent
        self.chargeFirstHitDamageBonusPercent = chargeFirstHitDamageBonusPercent
        self.volleyRadiusCells = volleyRadiusCells
    }

    public static let standard = SimulationTuning(
        flowFieldIntervalTicks: 15,
        terrainMovementCost: PassableTerrainValues(open: 10, forest: 30, hill: 20, rubble: 20),
        decisionIntervalTicks: 6,
        minimumCommitTicks: 15,
        proximityRadiusCells: 3,
        flankedMemoryTicks: 30,
        counterDamagePercent: 150,
        coverRangedDamageReductionPercent: 30,
        focusFireExtraRangeCells: 2,
        flankOffsetCells: 4,
        regroupRadiusCells: 6,
        coverSearchRadiusCells: 5,
        guardCommanderDistanceCells: 2,
        allyDeathMoraleRadiusCells: 3,
        allyDeathMoralePenalty: 10,
        commanderDeathMoralePenalty: 25,
        flankedMoralePenalty: 5,
        moraleRecoveryPerSecond: 1,
        moraleRecoveryEnemyFreeRadiusCells: 4,
        moraleBreakPercent: 20,
        moraleBrokenTicks: 90,
        moraleRecoveredPercent: 35,
        moveSampleIntervalTicks: 3,
        checksumIntervalTicks: 30,
        spatialBucketCells: 2,
        steeringSeparationRadiusCells: 1,
        steeringIntentWeightPercent: 100,
        steeringSeparationWeightPercent: 40,
        steeringAlignmentWeightPercent: 15,
        steeringCohesionWeightPercent: 15,
        steeringFlowWeightPercent: 60,
        abilityCooldownTicks: 300,
        abilityDurationTicks: 45,
        spearWallDamageTakenReductionPercent: 50,
        spearWallDamageDealtBonusPercent: 50,
        shieldWallDamageReductionPercent: 70,
        chargeSpeedBonusPercent: 50,
        chargeFirstHitDamageBonusPercent: 100,
        volleyRadiusCells: 2
    )
}
