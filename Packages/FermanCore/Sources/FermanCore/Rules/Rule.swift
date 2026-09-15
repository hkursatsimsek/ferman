/// A single order: "when `condition`, do `action`".
///
/// Rules carry no identity and no priority. Priority is the position in `RuleProgram.rules` (D7); UI identity lives in
/// the app's `EditableRule` wrapper so it never reaches equality or encoded battles.
public struct Rule: Sendable, Hashable, Codable {
    public var condition: Condition
    public var action: Action

    public init(condition: Condition, action: Action) {
        self.condition = condition
        self.action = action
    }
}

/// The ordered orders of one unit type. The first matching rule wins; the last rule is the `.always` default.
public struct RuleProgram: Sendable, Hashable, Codable {
    public let unitType: UnitTypeID
    public var rules: [Rule]

    public init(unitType: UnitTypeID, rules: [Rule]) {
        self.unitType = unitType
        self.rules = rules
    }
}

/// What a level allows the player to write (D4).
public struct RuleConstraints: Sendable, Hashable, Codable {
    /// Army-wide budget R(n): the total across every program, not counting each program's default rule.
    public let maxRules: Int
    public let availableConditions: [ConditionKind]
    public let availableActions: [ActionKind]

    public init(maxRules: Int, availableConditions: [ConditionKind], availableActions: [ActionKind]) {
        self.maxRules = maxRules
        self.availableConditions = availableConditions
        self.availableActions = availableActions
    }

    /// The ceiling of the difficulty curve with the full vocabulary; used by tools and tests.
    public static let unrestricted = RuleConstraints(
        maxRules: 12,
        availableConditions: ConditionKind.allCases,
        availableActions: ActionKind.allCases
    )
}
