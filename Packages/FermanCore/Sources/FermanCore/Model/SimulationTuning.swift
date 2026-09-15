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
        spatialBucketCells: Int
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
        spatialBucketCells: 2
    )
}
