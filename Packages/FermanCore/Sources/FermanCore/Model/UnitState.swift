/// One unit's mutable runtime state during a battle: everything besides its static `UnitType` (FERMAN-PLAN §5).
///
/// `id` doubles as this unit's index into `BattleState.units`, so lookups by `UnitID` are array subscripts, not
/// searches.
struct UnitState: Sendable, Hashable {
    let id: UnitID
    let team: Team
    let type: UnitTypeID
    let isCommander: Bool
    /// This unit type's orders, or `nil` when the team fields it with no program: it always falls back to the
    /// implicit advance-and-fight behavior and never touches `RuleFireCounts`.
    let program: RuleProgram?

    var kinematics: UnitKinematics
    /// The heading combat resolves flanking against; holds its last nonzero value while the unit stands still.
    var facing: FixedVector2
    var hp: Int
    var morale: MoraleState
    var attackCooldown: Cooldown
    var ability: AbilityState
    var decision: RuleDecisionState
    /// The order actually in effect right now: `decision`'s action, the implicit advance-and-fight fallback, or a
    /// forced `.scatter` while `morale.isBroken` (which skips `RuleEvaluator` entirely).
    var currentAction: Action
    var flankedTicksRemaining: Int
    /// `flankLeft`/`flankRight`'s waypoint, fixed when the order is chosen so the unit actually arrives instead of
    /// chasing a target that keeps moving; `nil` outside those two orders.
    var flankWaypoint: FixedVector2?
    /// `scatter`'s heading, redrawn only when scattering starts so a routing unit commits to one direction.
    var scatterDirection: FixedVector2

    var isAlive: Bool { hp > 0 }

    init(id: UnitID, team: Team, type: UnitType, isCommander: Bool, program: RuleProgram?, position: FixedVector2) {
        self.id = id
        self.team = team
        self.type = type.id
        self.isCommander = isCommander
        self.program = program
        kinematics = UnitKinematics(position: position, velocity: .zero)
        facing = FixedVector2(x: .one, y: .zero)
        hp = type.maxHP
        morale = MoraleState(morale: type.moraleMax, brokenTicksRemaining: 0)
        attackCooldown = .ready
        ability = .initial
        decision = .initial
        currentAction = .advance
        flankedTicksRemaining = 0
        flankWaypoint = nil
        scatterDirection = FixedVector2(x: .one, y: .zero)
    }
}
