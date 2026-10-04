import FermanCore

/// An order not yet finished: a condition kind and whichever one of its parameter slots that kind
/// uses, then the same for an action kind. A selector sheet (F1.7) builds one; a typed or spoken
/// order (F2.4) becomes one too, with a slot left empty when the words didn't say it
/// ("düşman yaklaşırsa geri çekil": how many cells?) — the player fills it in before the order is
/// sealed. `rule()` is the one way from here to a `Rule`.
public struct RuleDraft: Sendable, Hashable {
    public var conditionKind: ConditionKind
    /// Used by conditions whose parameter is `.cells`, `.percent`, `.count` or `.seconds`.
    public var conditionNumericValue: Int?
    /// Used by conditions whose parameter is `.unitType`.
    public var conditionUnitType: UnitTypeID?
    /// Used by conditions whose parameter is `.terrain`.
    public var conditionTerrain: Terrain?
    public var actionKind: ActionKind
    /// `focusFire`'s optional target; `nil` means "weakest enemy nearby" (`Action.focusFire`).
    public var actionUnitType: UnitTypeID?

    public init(
        conditionKind: ConditionKind,
        conditionNumericValue: Int? = nil,
        conditionUnitType: UnitTypeID? = nil,
        conditionTerrain: Terrain? = nil,
        actionKind: ActionKind,
        actionUnitType: UnitTypeID? = nil
    ) {
        self.conditionKind = conditionKind
        self.conditionNumericValue = conditionNumericValue
        self.conditionUnitType = conditionUnitType
        self.conditionTerrain = conditionTerrain
        self.actionKind = actionKind
        self.actionUnitType = actionUnitType
    }

    public init(_ rule: Rule) {
        self.init(conditionKind: rule.condition.kind, actionKind: rule.action.kind)
        switch rule.condition {
        case .enemyWithin(let value), .healthBelow(let value), .allyCountBelow(let value), .timeAfter(let value),
            .moraleBelow(let value), .enemyDensityAbove(let value):
            conditionNumericValue = value
        case .targetInRange(let unitType), .nearestEnemyType(let unitType):
            conditionUnitType = unitType
        case .terrainIs(let terrain):
            conditionTerrain = terrain
        case .isFlanked, .commanderDead, .always:
            break
        }
        if case .focusFire(let target) = rule.action {
            actionUnitType = target
        }
    }

    /// Whether the slot this draft's condition needs is still empty.
    public var isMissingConditionParameter: Bool {
        switch conditionKind.parameter {
        case .none: false
        case .cells, .percent, .count, .seconds: conditionNumericValue == nil
        case .unitType: conditionUnitType == nil
        case .terrain: conditionTerrain == nil
        }
    }

    public func rule() throws(RuleCompileError) -> Rule {
        Rule(condition: try condition(), action: action)
    }

    private func condition() throws(RuleCompileError) -> Condition {
        guard !isMissingConditionParameter else {
            throw .missingConditionParameter(conditionKind)
        }
        let number = conditionNumericValue ?? 0
        let unitType = conditionUnitType ?? ""
        switch conditionKind {
        case .enemyWithin: return .enemyWithin(cells: number)
        case .healthBelow: return .healthBelow(percent: number)
        case .allyCountBelow: return .allyCountBelow(count: number)
        case .isFlanked: return .isFlanked
        case .targetInRange: return .targetInRange(unitType)
        case .timeAfter: return .timeAfter(seconds: number)
        case .nearestEnemyType: return .nearestEnemyType(unitType)
        case .moraleBelow: return .moraleBelow(percent: number)
        case .terrainIs: return .terrainIs(conditionTerrain ?? .open)
        case .commanderDead: return .commanderDead
        case .enemyDensityAbove: return .enemyDensityAbove(count: number)
        case .always: return .always
        }
    }

    public var action: Action {
        switch actionKind {
        case .advance: .advance
        case .retreat: .retreat
        case .hold: .hold
        case .focusFire: .focusFire(actionUnitType)
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
