import FermanCore

/// A parameter a draft never filled in — a selector left at its placeholder, or a language model
/// that didn't supply one. Caught here, before `RuleValidator` ever sees the order.
public enum RuleCompileError: Error, Sendable, Equatable {
    case missingConditionParameter(ConditionKind)
}

/// What a compiler needs beyond its own input: which unit type the order is for, what the level
/// allows, and how much of the army-wide rule budget (D4) is left.
public struct CompileContext: Sendable {
    public let unitType: UnitTypeID
    public let constraints: RuleConstraints
    public let availableUnitTypes: [UnitTypeID]
    public let remainingRuleBudget: Int

    public init(
        unitType: UnitTypeID,
        constraints: RuleConstraints,
        availableUnitTypes: [UnitTypeID],
        remainingRuleBudget: Int
    ) {
        self.unitType = unitType
        self.constraints = constraints
        self.availableUnitTypes = availableUnitTypes
        self.remainingRuleBudget = remainingRuleBudget
    }
}

/// Turns some input into orders (D18). The language model is never one of these deciding a battle's
/// outcome directly — every `Rule` any `RuleCompiler`, human or model, produces still passes through
/// `RuleValidator` and is shown to the player before a battle starts (CLAUDE.md rule 3).
///
/// The whole game is playable through `ManualCompiler` (`Input == RuleDraft`) alone. The text- and
/// speech-driven compilers arriving in Faz 2 (`Input == String`) are a convenience, not a dependency.
public protocol RuleCompiler<Input>: Sendable {
    associatedtype Input: Sendable
    func compile(_ input: Input, context: CompileContext) async throws(RuleCompileError) -> [Rule]
}
