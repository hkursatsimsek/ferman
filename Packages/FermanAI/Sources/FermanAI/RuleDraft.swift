import FermanCore

/// The state behind a selector-based order editor (F1.7): a condition kind and whichever one of
/// its parameter slots that kind actually uses, then the same for an action kind. `ManualCompiler`
/// is the only thing that reads this shape — nothing else needs to know how the picker sheet works.
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
}
