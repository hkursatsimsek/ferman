import FermanCore

/// Compiles a selector-picked `RuleDraft` into a `Rule`. The whole game must be playable through
/// this alone, with no language model involved (CLAUDE.md rule 3, D18).
public struct ManualCompiler: RuleCompiler<RuleDraft> {
    public init() {}

    public func compile(_ input: RuleDraft, context: CompileContext) async throws(RuleCompileError) -> [Rule] {
        [Rule(condition: try Self.condition(from: input), action: Self.action(from: input))]
    }

    private static func condition(from draft: RuleDraft) throws(RuleCompileError) -> Condition {
        switch draft.conditionKind {
        case .enemyWithin:
            guard let value = draft.conditionNumericValue else {
                throw .missingConditionParameter(.enemyWithin)
            }
            return .enemyWithin(cells: value)
        case .healthBelow:
            guard let value = draft.conditionNumericValue else {
                throw .missingConditionParameter(.healthBelow)
            }
            return .healthBelow(percent: value)
        case .allyCountBelow:
            guard let value = draft.conditionNumericValue else {
                throw .missingConditionParameter(.allyCountBelow)
            }
            return .allyCountBelow(count: value)
        case .isFlanked:
            return .isFlanked
        case .targetInRange:
            guard let unitType = draft.conditionUnitType else {
                throw .missingConditionParameter(.targetInRange)
            }
            return .targetInRange(unitType)
        case .timeAfter:
            guard let value = draft.conditionNumericValue else {
                throw .missingConditionParameter(.timeAfter)
            }
            return .timeAfter(seconds: value)
        case .nearestEnemyType:
            guard let unitType = draft.conditionUnitType else {
                throw .missingConditionParameter(.nearestEnemyType)
            }
            return .nearestEnemyType(unitType)
        case .moraleBelow:
            guard let value = draft.conditionNumericValue else {
                throw .missingConditionParameter(.moraleBelow)
            }
            return .moraleBelow(percent: value)
        case .terrainIs:
            guard let terrain = draft.conditionTerrain else {
                throw .missingConditionParameter(.terrainIs)
            }
            return .terrainIs(terrain)
        case .commanderDead:
            return .commanderDead
        case .enemyDensityAbove:
            guard let value = draft.conditionNumericValue else {
                throw .missingConditionParameter(.enemyDensityAbove)
            }
            return .enemyDensityAbove(count: value)
        case .always:
            return .always
        }
    }

    private static func action(from draft: RuleDraft) -> Action {
        switch draft.actionKind {
        case .advance: .advance
        case .retreat: .retreat
        case .hold: .hold
        case .focusFire: .focusFire(draft.actionUnitType)
        case .flankLeft: .flankLeft
        case .flankRight: .flankRight
        case .regroup: .regroup
        case .useAbility: .useAbility
        case .takeCover: .takeCover
        case .guardCommander: .guardCommander
        case .scatter: .scatter
        }
    }
}
