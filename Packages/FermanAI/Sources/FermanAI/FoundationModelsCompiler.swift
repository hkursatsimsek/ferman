import FermanCore
import Foundation
import FoundationModels

/// Turns a typed or spoken order into drafts with Apple's on-device language model (F2.3, D17).
/// The model only ever fills in a schema the level allows — conditions and actions this front locks
/// aren't in it, so it can't produce them — and everything it returns is shown to the player as
/// unsealed slips before anything reaches a battle (CLAUDE.md rule 3).
///
/// Every compile opens a fresh session with no history, so one order can't colour the next. When the
/// model can't answer — Apple Intelligence off, the language unsupported, the request too long, a
/// refusal — it throws `.modelUnavailable` and `CompilerChain` falls back to `TemplateCompiler`.
///
/// This is the only file that imports FoundationModels (CLAUDE.md rule 3): its public surface takes
/// and returns FermanAI's own types.
public struct FoundationModelsCompiler: RuleCompiler<String>, RuleDrafter {
    /// Instructions, schema and prompt together stay under this (D17): the order is one sentence,
    /// and a session that needs more is a session that has gone wrong.
    static let tokenBudget = 800

    private let sessions: SessionSource
    private let model: SystemLanguageModel?
    private let locale: Locale

    /// The system model. Check `isAvailable(for:)` before relying on it.
    public init(locale: Locale = .current) {
        self.init(model: .default, locale: locale)
    }

    init(model: SystemLanguageModel, locale: Locale) {
        let instructions = Self.instructions(locale: locale)
        self.model = model
        self.locale = locale
        sessions = SessionSource { LanguageModelSession(model: model, instructions: instructions) }
    }

    /// Any model behind the same session API — a fake one in tests (D17). No availability check
    /// and no token counting: those belong to the system model.
    init(
        locale: Locale = Locale(identifier: "tr_TR"), makeSession: @escaping @Sendable (String) -> LanguageModelSession
    ) {
        let instructions = Self.instructions(locale: locale)
        model = nil
        self.locale = locale
        sessions = SessionSource { makeSession(instructions) }
    }

    /// Whether the on-device model can take orders in this language right now.
    public static func isAvailable(for locale: Locale = .current) -> Bool {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return false }
        return model.supportsLocale(locale)
    }

    /// Loads the model ahead of the first order (D17: when the editor opens).
    public func prewarm() async {
        if let model {
            guard case .available = model.availability, model.supportsLocale(locale) else { return }
        }
        await sessions.prewarm()
    }

    public func compile(_ input: String, context: CompileContext) async throws(RuleCompileError) -> [Rule] {
        var rules: [Rule] = []
        for draft in try await drafts(from: input, context: context) {
            rules.append(try draft.rule())
        }
        return rules
    }

    public func drafts(from text: String, context: CompileContext) async throws(RuleCompileError) -> [RuleDraft] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .noOrderRecognized }
        if let model {
            guard case .available = model.availability, model.supportsLocale(locale) else {
                throw .modelUnavailable
            }
        }
        let schema: GenerationSchema
        do {
            schema = try OrderSchema.make(constraints: context.constraints, unitTypes: context.availableUnitTypes)
        } catch {
            throw .modelUnavailable
        }
        let session = await sessions.take()
        let content: GeneratedContent
        do {
            if let model {
                let tokens =
                    try await model.tokenCount(for: Instructions(Self.instructions(locale: locale)))
                    + model.tokenCount(for: Prompt(trimmed))
                guard tokens < min(Self.tokenBudget, model.contextSize) else { throw RuleCompileError.modelUnavailable }
            }
            // The schema still constrains every token; the instructions describe it in fewer tokens
            // and with examples, which a small model follows better than a raw schema.
            content = try await session.respond(
                to: trimmed, schema: schema, includeSchemaInPrompt: false,
                options: GenerationOptions(samplingMode: .greedy)
            ).content
        } catch {
            throw .modelUnavailable
        }
        Task { await sessions.prewarm() }
        return try OrderReading(content).drafts()
    }

    // MARK: Instructions

    /// Starts with Apple's exact locale sentence (D17). Kept short: the schema rides along in the
    /// same token budget.
    static func instructions(locale: Locale) -> String {
        """
        The person's locale is \(locale.identifier).
        Turn a player's battle order (Turkish or English) into JSON orders for one unit type, in the \
        order written. Each order: `when`, its parameter if any, `action`. An action with no \
        condition, or after "başka durumda", "yoksa", "aksi halde", "otherwise", "else", is \
        when=otherwise and goes last.
        `when`: enemyCloserThan (number=cells), healthBelow (number=percent), moraleBelow \
        (number=percent), alliesFewerThan (number), enemiesNearMoreThan (number), afterSeconds \
        (number=seconds; a minute is 60), targetInRange (unit), nearestEnemyIs (unit), standingOn \
        (terrain: open, forest, hill, water, rubble), flanked, commanderDown, otherwise.
        Omit number when the player gave none; never guess it.
        Units: okcu=okçu/archer, mizrakci=mızrakçı/spearman, suvari=süvari/cavalry, kalkan=kalkanlı/shield.
        `action`: advance, retreat, hold, flankLeft, flankRight, regroup, takeCover, guardCommander, \
        scatter, useAbility (special ability: volley, spear wall, shield wall, charge, yaylım, \
        mızrak duvarı, kalkan duvarı, hücum), focusFire (attack), "focusFire <unit>" when a unit is \
        named as the target, none when no action is given.
        `problem` is none, except: notAnOrder (no order at all), unknownCondition (a condition not \
        listed), oppositeComparison (health or morale "above"/"üstünde", enemy "farther"/"uzak"), \
        twoActionsInOneClause (actions chained in time, "önce … sonra …").
        Write only the orders the player wrote; never add one.
        Examples:
        "geri dön" → {"orders":[{"when":"otherwise","action":"retreat"}],"problem":"none"}
        "düşman yaklaşırsa dağıl" → {"orders":[{"when":"enemyCloserThan","action":"scatter"}],\
        "problem":"none"}
        "moralim yüzde 15'e inince toplan, başka durumda sağdan kuşat" → {"orders":[{"when":\
        "moraleBelow","number":15,"action":"regroup"},{"when":"otherwise","action":"flankRight"}],\
        "problem":"none"}
        "if spearmen are in range, shoot the spearmen" → {"orders":[{"when":"targetInRange",\
        "unit":"mizrakci","action":"focusFire mizrakci"}],"problem":"none"}
        "charge after 45 seconds" → {"orders":[{"when":"afterSeconds","number":45,\
        "action":"useAbility"}],"problem":"none"}
        "suda isem komutanı koru" → {"orders":[{"when":"standingOn","terrain":"water",\
        "action":"guardCommander"}],"problem":"none"}
        "moralim %70'in üzerindeyse saldır" → {"orders":[],"problem":"oppositeComparison"}
        "önce toplan sonra saldır" → {"orders":[],"problem":"twoActionsInOneClause"}
        "selam" → {"orders":[],"problem":"notAnOrder"}
        """
    }
}

/// Keeps one session warm for the next order, and never hands the same one out twice.
private actor SessionSource {
    private let make: @Sendable () -> LanguageModelSession
    private var warm: LanguageModelSession?

    init(make: @escaping @Sendable () -> LanguageModelSession) {
        self.make = make
    }

    func prewarm() {
        guard warm == nil else { return }
        let session = make()
        session.prewarm(promptPrefix: nil)
        warm = session
    }

    func take() -> LanguageModelSession {
        defer { warm = nil }
        return warm ?? make()
    }
}

// MARK: - Mirrors

/// The model's names for `ConditionKind` — words it reads well, not FermanCore's. Each core kind has
/// exactly one (`FoundationModelsCompilerTests` checks the count against `allCases`).
enum ConditionMirror: String, CaseIterable {
    case enemyCloserThan
    case healthBelow
    case alliesFewerThan
    case flanked
    case targetInRange
    case afterSeconds
    case nearestEnemyIs
    case moraleBelow
    case standingOn
    case commanderDown
    case enemiesNearMoreThan
    case otherwise

    init(_ kind: ConditionKind) {
        switch kind {
        case .enemyWithin: self = .enemyCloserThan
        case .healthBelow: self = .healthBelow
        case .allyCountBelow: self = .alliesFewerThan
        case .isFlanked: self = .flanked
        case .targetInRange: self = .targetInRange
        case .timeAfter: self = .afterSeconds
        case .nearestEnemyType: self = .nearestEnemyIs
        case .moraleBelow: self = .moraleBelow
        case .terrainIs: self = .standingOn
        case .commanderDead: self = .commanderDown
        case .enemyDensityAbove: self = .enemiesNearMoreThan
        case .always: self = .otherwise
        }
    }

    var kind: ConditionKind {
        switch self {
        case .enemyCloserThan: .enemyWithin
        case .healthBelow: .healthBelow
        case .alliesFewerThan: .allyCountBelow
        case .flanked: .isFlanked
        case .targetInRange: .targetInRange
        case .afterSeconds: .timeAfter
        case .nearestEnemyIs: .nearestEnemyType
        case .moraleBelow: .moraleBelow
        case .standingOn: .terrainIs
        case .commanderDown: .commanderDead
        case .enemiesNearMoreThan: .enemyDensityAbove
        case .otherwise: .always
        }
    }
}

/// `ActionKind`'s mirror, one name each.
enum ActionMirror: String, CaseIterable {
    case advance
    case retreat
    case hold
    case focusFire
    case flankLeft
    case flankRight
    case regroup
    case useAbility
    case takeCover
    case guardCommander
    case scatter

    /// Not an action: the player named a condition and stopped.
    static let none = "none"

    init(_ kind: ActionKind) {
        switch kind {
        case .advance: self = .advance
        case .retreat: self = .retreat
        case .hold: self = .hold
        case .focusFire: self = .focusFire
        case .flankLeft: self = .flankLeft
        case .flankRight: self = .flankRight
        case .regroup: self = .regroup
        case .useAbility: self = .useAbility
        case .takeCover: self = .takeCover
        case .guardCommander: self = .guardCommander
        case .scatter: self = .scatter
        }
    }

    var kind: ActionKind {
        switch self {
        case .advance: .advance
        case .retreat: .retreat
        case .hold: .hold
        case .focusFire: .focusFire
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

/// Why the text isn't (only) orders — the refusals `TemplateCompiler` gives, in the model's words.
enum ProblemMirror: String, CaseIterable {
    case none
    case notAnOrder
    case unknownCondition
    case oppositeComparison
    case twoActionsInOneClause
}

// MARK: - Schema

/// The answer's shape, built per level: locked conditions and actions are left out (D17). Each
/// condition is its own shape carrying only the parameter it takes, and a targeted focus fire is
/// its own action ("focusFire okcu") — a small model fills every optional field it's offered, so
/// none is offered that doesn't belong.
enum OrderSchema {
    static let conditionKey = "when"
    static let numberKey = "number"
    static let unitKey = "unit"
    static let terrainKey = "terrain"
    static let actionKey = "action"
    static let ordersKey = "orders"
    static let problemKey = "problem"
    static let maximumOrders = 8
    static let targetSeparator = " "

    /// The conditions the level allows; `otherwise` (the default order) always.
    static func conditionChoices(constraints: RuleConstraints) -> [ConditionMirror] {
        ConditionMirror.allCases.filter { $0.kind == .always || constraints.availableConditions.contains($0.kind) }
    }

    static func make(constraints: RuleConstraints, unitTypes: [UnitTypeID]) throws -> GenerationSchema {
        let conditions = conditionChoices(constraints: constraints)
        let action = DynamicGenerationSchema(
            name: "Action", anyOf: actionNames(constraints: constraints, unitTypes: unitTypes) + [ActionMirror.none])
        let unit = DynamicGenerationSchema(name: "Unit", anyOf: unitTypes.map(\.rawValue))
        let variants = conditions.compactMap { condition -> DynamicGenerationSchema? in
            var properties: [DynamicGenerationSchema.Property] = [
                .init(
                    name: conditionKey,
                    schema: DynamicGenerationSchema(name: "When_\(condition.rawValue)", anyOf: [condition.rawValue]))
            ]
            switch condition.kind.parameter {
            case .cells, .percent, .count, .seconds:
                properties.append(
                    .init(
                        name: numberKey, schema: DynamicGenerationSchema(type: Int.self, guides: [.range(0...600)]),
                        isOptional: true))
            case .unitType:
                guard !unitTypes.isEmpty else { return nil }
                properties.append(.init(name: unitKey, schema: DynamicGenerationSchema(referenceTo: "Unit")))
            case .terrain:
                properties.append(
                    .init(
                        name: terrainKey,
                        schema: DynamicGenerationSchema(
                            name: "Terrain", anyOf: Terrain.allCases.map(\.rawValue))))
            case .none:
                break
            }
            properties.append(.init(name: actionKey, schema: DynamicGenerationSchema(referenceTo: "Action")))
            return DynamicGenerationSchema(name: "Order_\(condition.rawValue)", properties: properties)
        }
        let order = DynamicGenerationSchema(name: "Order", anyOf: variants)
        let root = DynamicGenerationSchema(
            name: "Reading",
            properties: [
                .init(
                    name: ordersKey,
                    schema: DynamicGenerationSchema(arrayOf: order, minimumElements: 0, maximumElements: maximumOrders)),
                .init(
                    name: problemKey,
                    schema: DynamicGenerationSchema(name: "Problem", anyOf: ProblemMirror.allCases.map(\.rawValue))),
            ])
        return try GenerationSchema(root: root, dependencies: unitTypes.isEmpty ? [action] : [action, unit])
    }

    /// Every action the level allows, with one targeted focus fire per unit type.
    static func actionNames(constraints: RuleConstraints, unitTypes: [UnitTypeID]) -> [String] {
        ActionMirror.allCases.filter { constraints.availableActions.contains($0.kind) }.flatMap { action in
            action == .focusFire
                ? [action.rawValue] + unitTypes.map { action.rawValue + targetSeparator + $0.rawValue }
                : [action.rawValue]
        }
    }
}

// MARK: - Reading the answer

/// The model's answer, read back into drafts with the same rules `TemplateCompiler` follows: the
/// order written is the priority, the default goes last, two different defaults are a conflict.
struct OrderReading {
    private let content: GeneratedContent

    init(_ content: GeneratedContent) {
        self.content = content
    }

    func drafts() throws(RuleCompileError) -> [RuleDraft] {
        let orders: [GeneratedContent]
        let problem: ProblemMirror
        do {
            orders = try content.value([GeneratedContent].self, forProperty: OrderSchema.ordersKey)
            problem =
                ProblemMirror(rawValue: try content.value(String.self, forProperty: OrderSchema.problemKey)) ?? .none
        } catch {
            throw .modelUnavailable
        }
        let drafts = try orders.map(Self.draft(from:))
        switch problem {
        case .none:
            break
        case .notAnOrder:
            throw .noOrderRecognized
        case .unknownCondition:
            throw .unrecognizedCondition
        case .oppositeComparison:
            let kind = drafts.lazy.map(\.conditionKind).first {
                [.healthBelow, .moraleBelow, .enemyWithin].contains($0)
            }
            throw .unsupportedComparison(kind ?? .healthBelow)
        case .twoActionsInOneClause:
            throw .multipleActions
        }
        return try Self.ordered(drafts)
    }

    private static func draft(from order: GeneratedContent) throws(RuleCompileError) -> RuleDraft {
        let condition: ConditionMirror
        let actionName: String
        var number: Int?
        var unit: String?
        var terrain: String?
        do {
            guard
                let mirror = ConditionMirror(
                    rawValue: try order.value(String.self, forProperty: OrderSchema.conditionKey))
            else { throw RuleCompileError.modelUnavailable }
            condition = mirror
            actionName = try order.value(String.self, forProperty: OrderSchema.actionKey)
            switch mirror.kind.parameter {
            case .cells, .percent, .count, .seconds:
                number = try order.value(Int?.self, forProperty: OrderSchema.numberKey)
            case .unitType:
                unit = try order.value(String.self, forProperty: OrderSchema.unitKey)
            case .terrain:
                terrain = try order.value(String.self, forProperty: OrderSchema.terrainKey)
            case .none:
                break
            }
        } catch {
            throw .modelUnavailable
        }
        let kind = condition.kind
        if actionName == ActionMirror.none {
            throw .missingAction(kind)
        }
        let parts = actionName.split(separator: OrderSchema.targetSeparator, maxSplits: 1).map(String.init)
        guard let action = parts.first.flatMap(ActionMirror.init(rawValue:)) else {
            throw .modelUnavailable
        }
        var draft = RuleDraft(conditionKind: kind, actionKind: action.kind)
        draft.conditionNumericValue = number
        draft.conditionUnitType = unit.map(UnitTypeID.init(rawValue:))
        draft.conditionTerrain = terrain.flatMap(Terrain.init(rawValue:))
        if action == .focusFire, parts.count == 2 {
            draft.actionUnitType = UnitTypeID(rawValue: parts[1])
        }
        return draft
    }

    private static func ordered(_ drafts: [RuleDraft]) throws(RuleCompileError) -> [RuleDraft] {
        let defaults = drafts.filter { $0.conditionKind == .always }
        if Set(defaults.map(\.action)).count > 1 {
            throw .conflictingDefaultOrders
        }
        let orders = drafts.filter { $0.conditionKind != .always }
        guard !orders.isEmpty || !defaults.isEmpty else { throw .noOrderRecognized }
        return orders + defaults.prefix(1)
    }
}
