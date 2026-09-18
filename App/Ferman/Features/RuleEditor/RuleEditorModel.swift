import FermanAI
import FermanCore
import Observation
import SwiftUI

/// UI identity for a `Rule` (D7) — the core carries no id, priority is just array position.
struct EditableRule: Identifiable, Sendable, Hashable {
    let id: UUID
    var rule: Rule

    init(id: UUID = UUID(), rule: Rule) {
        self.id = id
        self.rule = rule
    }
}

/// A small built-in bundle of orders a player can drop into an empty stack (design brief §4.4's
/// empty-state CTA). Not the same thing as the Emir Kütüphanesi (F4.8) — that saves a player's own
/// sets; this is a fixed, shipped starting point.
enum RulePreset: CaseIterable {
    case cautious
    case balanced
    case aggressive

    var displayName: String {
        switch self {
        case .cautious: String(localized: "Temkinli")
        case .balanced: String(localized: "Dengeli")
        case .aggressive: String(localized: "Saldırgan")
        }
    }

    var drafts: [RuleDraft] {
        switch self {
        case .cautious:
            [
                RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 3, actionKind: .retreat),
                RuleDraft(conditionKind: .healthBelow, conditionNumericValue: 30, actionKind: .takeCover),
            ]
        case .balanced:
            [
                RuleDraft(conditionKind: .healthBelow, conditionNumericValue: 40, actionKind: .retreat),
                RuleDraft(conditionKind: .allyCountBelow, conditionNumericValue: 2, actionKind: .regroup),
            ]
        case .aggressive:
            [
                RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 5, actionKind: .focusFire),
                RuleDraft(conditionKind: .healthBelow, conditionNumericValue: 20, actionKind: .takeCover),
            ]
        }
    }
}

/// Every unit type's order stack, the fixed default order under it, and the army-wide budget they
/// share (D4). The whole game must stay playable through this — a `ManualCompiler` and a selector
/// sheet, no language model (CLAUDE.md rule 3).
@Observable
@MainActor
final class RuleEditorModel {
    let unitTypes: [UnitTypeID]
    let catalog: [UnitType]
    let constraints: RuleConstraints

    private(set) var ordersByUnitType: [UnitTypeID: [EditableRule]]
    private(set) var defaultRuleByUnitType: [UnitTypeID: EditableRule]
    private(set) var validationErrors: [RuleValidationError] = []
    var selectedUnitType: UnitTypeID
    var lastCompileError: RuleCompileError?

    private let compiler: any RuleCompiler<RuleDraft>
    private let audio: any AudioPlaying

    init(
        unitTypes: [UnitTypeID],
        catalog: [UnitType],
        constraints: RuleConstraints,
        initialPrograms: [RuleProgram] = [],
        compiler: any RuleCompiler<RuleDraft> = ManualCompiler(),
        audio: any AudioPlaying = SilentAudioPlaying()
    ) {
        precondition(!unitTypes.isEmpty, "RuleEditorModel needs at least one unit type")
        self.unitTypes = unitTypes
        self.catalog = catalog
        self.constraints = constraints
        self.compiler = compiler
        self.audio = audio
        self.selectedUnitType = unitTypes[0]

        var orders: [UnitTypeID: [EditableRule]] = [:]
        var defaults: [UnitTypeID: EditableRule] = [:]
        for unitType in unitTypes {
            var rules = initialPrograms.first { $0.unitType == unitType }?.rules ?? []
            let defaultRule = rules.popLast() ?? Rule(condition: .always, action: .advance)
            orders[unitType] = rules.map { EditableRule(rule: $0) }
            defaults[unitType] = EditableRule(rule: defaultRule)
        }
        self.ordersByUnitType = orders
        self.defaultRuleByUnitType = defaults
        refreshValidation()
    }

    // MARK: - Derived state

    /// One program per unit type, the fixed default order last in each (D7).
    var programs: [RuleProgram] {
        unitTypes.map { unitType in
            let orders = ordersByUnitType[unitType, default: []].map(\.rule)
            let defaultRule = defaultRuleByUnitType[unitType]?.rule ?? Rule(condition: .always, action: .advance)
            return RuleProgram(unitType: unitType, rules: orders + [defaultRule])
        }
    }

    /// Non-default orders across every unit type — what counts against `constraints.maxRules` (D4).
    var usedBudget: Int {
        ordersByUnitType.values.map(\.count).reduce(0, +)
    }

    var orders: [EditableRule] {
        ordersByUnitType[selectedUnitType, default: []]
    }

    var defaultRule: EditableRule {
        defaultRuleByUnitType[selectedUnitType] ?? EditableRule(rule: Rule(condition: .always, action: .advance))
    }

    func ability(for unitType: UnitTypeID) -> Ability? {
        catalog.first { $0.id == unitType }?.ability
    }

    func state(for editableRule: EditableRule) -> OrderCardState {
        let index = orders.firstIndex(of: editableRule) ?? 0
        let isInvalid = validationErrors.contains {
            switch $0 {
            case .conditionNotAvailable(let unitType, let ruleIndex, _),
                .actionNotAvailable(let unitType, let ruleIndex, _),
                .conditionParameterOutOfRange(let unitType, let ruleIndex, _, _, _):
                unitType == selectedUnitType && ruleIndex == index
            default:
                false
            }
        }
        return isInvalid ? .disabled : .normal
    }

    // MARK: - Intents

    func selectUnitType(_ unitType: UnitTypeID) {
        guard unitTypes.contains(unitType) else { return }
        selectedUnitType = unitType
    }

    func addRule(_ draft: RuleDraft) async {
        guard let rule = await compile(draft) else { return }
        ordersByUnitType[selectedUnitType, default: []].append(EditableRule(rule: rule))
        refreshValidation()
    }

    func updateRule(_ id: EditableRule.ID, to draft: RuleDraft) async {
        guard let rule = await compile(draft),
            let index = ordersByUnitType[selectedUnitType]?.firstIndex(where: { $0.id == id })
        else { return }
        ordersByUnitType[selectedUnitType]?[index].rule = rule
        refreshValidation()
    }

    /// The numeric parameter behind a card's condition, if it has one — what the in-place dial
    /// (design brief §4.4 — "sayısal parametreler pusulanın içinde dokunulabilir") edits.
    func numericParameter(for id: EditableRule.ID) -> (value: Int, range: ClosedRange<Int>)? {
        guard let condition = orders.first(where: { $0.id == id })?.rule.condition else { return nil }
        let value: Int
        switch condition {
        case .enemyWithin(let v), .timeAfter(let v), .healthBelow(let v), .moraleBelow(let v),
            .allyCountBelow(let v), .enemyDensityAbove(let v):
            value = v
        default:
            return nil
        }
        switch condition.kind.parameter {
        case .cells(let range), .percent(let range), .count(let range), .seconds(let range):
            return (value, range)
        default:
            return nil
        }
    }

    func setNumericParameter(_ value: Int, for id: EditableRule.ID) {
        guard var rules = ordersByUnitType[selectedUnitType], let index = rules.firstIndex(where: { $0.id == id })
        else { return }
        let updated: Condition
        switch rules[index].rule.condition {
        case .enemyWithin: updated = .enemyWithin(cells: value)
        case .healthBelow: updated = .healthBelow(percent: value)
        case .allyCountBelow: updated = .allyCountBelow(count: value)
        case .timeAfter: updated = .timeAfter(seconds: value)
        case .moraleBelow: updated = .moraleBelow(percent: value)
        case .enemyDensityAbove: updated = .enemyDensityAbove(count: value)
        default: return
        }
        rules[index].rule.condition = updated
        ordersByUnitType[selectedUnitType] = rules
        refreshValidation()
    }

    func updateDefaultAction(_ action: Action) {
        defaultRuleByUnitType[selectedUnitType] = EditableRule(
            id: defaultRule.id, rule: Rule(condition: .always, action: action))
        refreshValidation()
    }

    func removeRule(_ id: EditableRule.ID) {
        ordersByUnitType[selectedUnitType]?.removeAll { $0.id == id }
        refreshValidation()
    }

    /// Applied from `reorderContainer(for:isEnabled:move:)` (ARCHITECTURE §7, D12). `ReorderDifference`
    /// has no public initializer, so the actual reordering lives in `reorder(sources:before:)`, which
    /// a test can call directly instead of manufacturing a difference the framework doesn't let it make.
    func move(_ difference: ReorderDifference<EditableRule.ID, ReorderableSingleCollectionIdentifier>) {
        let anchorID: EditableRule.ID? =
            if case .before(let id) = difference.destination.position { id } else { nil }
        reorder(sources: difference.sources, before: anchorID)
    }

    func reorder(sources: [EditableRule.ID], before anchorID: EditableRule.ID?) {
        var rules = orders
        let movingIDs = Set(sources)
        let moving = sources.compactMap { id in rules.first { $0.id == id } }
        rules.removeAll { movingIDs.contains($0.id) }

        if let anchorID, let index = rules.firstIndex(where: { $0.id == anchorID }) {
            rules.insert(contentsOf: moving, at: index)
        } else {
            rules.append(contentsOf: moving)
        }
        ordersByUnitType[selectedUnitType] = rules
        audio.play(.paper)
        refreshValidation()
    }

    /// VoiceOver's stand-in for the drag gesture (F1.7 — "taşımak için accessibility action").
    func moveUp(_ id: EditableRule.ID) {
        guard var rules = ordersByUnitType[selectedUnitType], let index = rules.firstIndex(where: { $0.id == id }),
            index > 0
        else { return }
        rules.swapAt(index, index - 1)
        ordersByUnitType[selectedUnitType] = rules
        audio.play(.paper)
        refreshValidation()
    }

    func moveDown(_ id: EditableRule.ID) {
        guard var rules = ordersByUnitType[selectedUnitType], let index = rules.firstIndex(where: { $0.id == id }),
            index < rules.count - 1
        else { return }
        rules.swapAt(index, index + 1)
        ordersByUnitType[selectedUnitType] = rules
        audio.play(.paper)
        refreshValidation()
    }

    /// Adds whatever fits: skips a draft whose kind this level locks, and stops once the army-wide
    /// budget (D4) is spent. Silent, partial application is preferable to an all-or-nothing preset
    /// that a low level could never fully accept.
    func applyPreset(_ preset: RulePreset) async {
        for draft in preset.drafts {
            guard usedBudget < constraints.maxRules else { break }
            guard constraints.availableConditions.contains(draft.conditionKind),
                constraints.availableActions.contains(draft.actionKind)
            else { continue }
            await addRule(draft)
        }
    }

    // MARK: - Compiling and validation

    private func compile(_ draft: RuleDraft) async -> Rule? {
        let context = CompileContext(
            unitType: selectedUnitType, constraints: constraints, availableUnitTypes: unitTypes,
            remainingRuleBudget: max(0, constraints.maxRules - usedBudget))
        do {
            let rules = try await compiler.compile(draft, context: context)
            lastCompileError = nil
            return rules.first
        } catch {
            lastCompileError = error
            return nil
        }
    }

    private func refreshValidation() {
        validationErrors = RuleValidator.validate(programs: programs, constraints: constraints)
    }
}
