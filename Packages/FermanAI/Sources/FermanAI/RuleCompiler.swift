import FermanCore

/// Why an input couldn't become orders. Caught here, before `RuleValidator` ever sees them.
public enum RuleCompileError: Error, Sendable, Equatable {
    /// A parameter never filled in — a selector left at its placeholder, a language model that
    /// didn't supply one, or typed text that names the condition but not its number
    /// ("düşman yaklaşırsa geri çekil": how many cells?).
    case missingConditionParameter(ConditionKind)
    /// Nothing in the text read as an order.
    case noOrderRecognized
    /// A condition with no action before or after it.
    case missingAction(ConditionKind)
    /// Text that is clearly a condition ("düşman görünce…") but not one the game has.
    case unrecognizedCondition
    /// A comparison the condition can't express: health and morale only compare *below*,
    /// enemy distance only *closer than* ("canım %40'ın üstündeyse").
    case unsupportedComparison(ConditionKind)
    /// Two different default orders in one text ("ilerle … başka durumda geri çekil").
    case conflictingDefaultOrders
    /// Two actions in one clause ("10 saniye bekle sonra ilerle"): splitting them is a guess.
    case multipleActions
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

/// Turns a typed or spoken order into drafts the player reviews before they become orders (F2.4,
/// D29). Unlike `RuleCompiler`, a draft may leave a condition's number or unit type empty when the
/// words didn't give it — the editor shows that as a blank on the slip, filled in with the dial,
/// instead of refusing the whole sentence. Everything else that can't be read is still an error.
public protocol RuleDrafter: Sendable {
    func drafts(from text: String, context: CompileContext) async throws(RuleCompileError) -> [RuleDraft]
}
