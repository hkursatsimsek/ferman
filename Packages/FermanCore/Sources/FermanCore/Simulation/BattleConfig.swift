/// Everything that determines a battle. The same config always produces a bit-identical `BattleResult`.
///
/// The config is self-contained, including the unit catalog and tuning it was fought under, so a saved battle, an arena
/// report or a duel turn can be re-simulated and verified without the content bundle that produced it (D5, D14).
public struct BattleConfig: Sendable, Hashable, Codable {
    public static let ticksPerSecond = 30
    public static let defaultMaxTicks = 60 * ticksPerSecond

    public let simulationVersion: Int
    public let map: BattleMap
    /// Every unit type either team may field, ordered by `id`.
    public let unitCatalog: [UnitType]
    public let tuning: SimulationTuning
    public let player: TeamSetup
    public let enemy: TeamSetup
    public let objective: BattleObjective
    public let constraints: RuleConstraints
    public let seed: UInt64
    public let maxTicks: Int

    public init(
        simulationVersion: Int = SimulationVersion.current,
        map: BattleMap,
        unitCatalog: [UnitType],
        tuning: SimulationTuning = .standard,
        player: TeamSetup,
        enemy: TeamSetup,
        objective: BattleObjective,
        constraints: RuleConstraints,
        seed: UInt64,
        maxTicks: Int = BattleConfig.defaultMaxTicks
    ) {
        self.simulationVersion = simulationVersion
        self.map = map
        self.unitCatalog = unitCatalog
        self.tuning = tuning
        self.player = player
        self.enemy = enemy
        self.objective = objective
        self.constraints = constraints
        self.seed = seed
        self.maxTicks = maxTicks
    }

    public func setup(for team: Team) -> TeamSetup {
        switch team {
        case .player: player
        case .enemy: enemy
        }
    }
}

public enum BattleObjective: String, Sendable, Codable, CaseIterable {
    /// Destroy or rout the enemy; at the time limit the side with more remaining value wins.
    case eliminate
    /// Survive until the time limit with at least one living unit.
    case holdLine
}

public enum SimulationVersion {
    /// Bumped with every change to simulation semantics; golden files, arena records and duel data carry it.
    public static let current = 1
}

public struct SimulationOptions: Sendable, Hashable {
    /// Batch runs and strategist rollouts skip the event stream; the checksum is computed either way.
    public var recordEvents: Bool

    public init(recordEvents: Bool = true) {
        self.recordEvents = recordEvents
    }
}
