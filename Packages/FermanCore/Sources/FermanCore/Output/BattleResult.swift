public enum BattleOutcome: String, Sendable, Codable, CaseIterable {
    case playerWin
    case enemyWin
    case draw
}

public enum EndReason: String, Sendable, Codable, CaseIterable {
    /// A team has no living units.
    case elimination
    /// Every living unit of a team is fleeing with broken morale.
    case rout
    /// `maxTicks` elapsed; the objective decides the outcome.
    case timeLimit
}

/// How often each order of one unit type was activated, indexed like `RuleProgram.rules`.
public struct RuleFireCounts: Sendable, Hashable, Codable {
    public let team: Team
    public let unitType: UnitTypeID
    public let counts: [Int]

    public init(team: Team, unitType: UnitTypeID, counts: [Int]) {
        self.team = team
        self.unitType = unitType
        self.counts = counts
    }
}

public struct BattleResult: Sendable, Hashable, Codable {
    public let outcome: BattleOutcome
    public let endReason: EndReason
    public let tickCount: Int
    /// Empty when the battle ran with `SimulationOptions.recordEvents == false`.
    public let events: [BattleEvent]
    /// Ordered by team, then unit type.
    public let ruleFireCounts: [RuleFireCounts]
    public let survivorsPlayer: Int
    public let survivorsEnemy: Int
    public let checksum: UInt64

    public init(
        outcome: BattleOutcome,
        endReason: EndReason,
        tickCount: Int,
        events: [BattleEvent],
        ruleFireCounts: [RuleFireCounts],
        survivorsPlayer: Int,
        survivorsEnemy: Int,
        checksum: UInt64
    ) {
        self.outcome = outcome
        self.endReason = endReason
        self.tickCount = tickCount
        self.events = events
        self.ruleFireCounts = ruleFireCounts
        self.survivorsPlayer = survivorsPlayer
        self.survivorsEnemy = survivorsEnemy
        self.checksum = checksum
    }
}
