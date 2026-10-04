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

/// One slip of a written order (F2.4): what the words said, possibly with its number or unit type
/// still blank. A slip whose condition is `.always` replaces the unit type's default order.
struct WrittenSlip: Identifiable, Sendable, Hashable {
    let id: UUID
    var draft: RuleDraft

    init(id: UUID = UUID(), draft: RuleDraft) {
        self.id = id
        self.draft = draft
    }

    var isDefault: Bool { draft.conditionKind == .always }
}

/// What the player typed (or, from F2.5, said), read into slips but not yet sealed into the stack.
/// Nothing here is part of `programs` or reaches a battle until the player has seen it and sealed
/// it (CLAUDE.md rule 3).
struct WrittenOrders: Sendable, Equatable {
    let unitType: UnitTypeID
    let text: String
    var slips: [WrittenSlip]
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
    /// Why "Savaşı Başlat" is off — the first validation error, in terms a player can act on. The
    /// view turns it into a sentence (String Catalog), this model only decides which one it is.
    enum BattleBlocker: Equatable {
        /// A written order is on the table, neither sealed nor discarded.
        case unsealedOrders
        case budgetExceeded(used: Int, budget: Int)
        /// `priority` is 1-based, the number printed on the card.
        case invalidOrder(unitType: UnitTypeID, priority: Int)
    }

    let unitTypes: [UnitTypeID]
    let catalog: [UnitType]
    let constraints: RuleConstraints
    /// What the unit-type pickers (`targetInRange`, `nearestEnemyType`, `focusFire`) offer: these
    /// conditions and actions are about the *enemy's* units, so listing the player's own army (as F1.7
    /// did) let a player target a type the enemy didn't even field.
    let enemyUnitTypes: [UnitTypeID]

    private(set) var ordersByUnitType: [UnitTypeID: [EditableRule]]
    private(set) var defaultRuleByUnitType: [UnitTypeID: EditableRule]
    private(set) var validationErrors: [RuleValidationError] = []
    var selectedUnitType: UnitTypeID
    var lastCompileError: RuleCompileError?

    /// Why a written order can't be sealed yet, slip by slip.
    enum SlipIssue: Equatable {
        /// The words left out the condition's number or unit type.
        case blank
        case conditionLocked
        case actionLocked
        case outOfRange(ClosedRange<Int>)
    }

    enum SealBlocker: Equatable {
        case blank
        case notAllowedHere
        /// More new orders than the army-wide budget (D4) has room for.
        case budget(needed: Int, remaining: Int)
    }

    private(set) var written: WrittenOrders?
    /// Why the last text couldn't be read at all. Cleared as soon as the player edits the text.
    var writeError: RuleCompileError?
    private(set) var isWriting = false
    /// Orders sealed a moment ago — the view presses the seal on these, then lets it fade.
    private(set) var justSealed: Set<EditableRule.ID> = []

    private let compiler: any RuleCompiler<RuleDraft>
    private let textCompiler: any RuleDrafter
    private let audio: any AudioPlaying

    init(
        unitTypes: [UnitTypeID],
        catalog: [UnitType],
        constraints: RuleConstraints,
        enemyUnitTypes: [UnitTypeID]? = nil,
        initialPrograms: [RuleProgram] = [],
        compiler: any RuleCompiler<RuleDraft> = ManualCompiler(),
        textCompiler: any RuleDrafter = TemplateCompiler(),
        audio: any AudioPlaying = SilentAudioPlaying()
    ) {
        precondition(!unitTypes.isEmpty, "RuleEditorModel needs at least one unit type")
        self.unitTypes = unitTypes
        self.catalog = catalog
        self.constraints = constraints
        // No list means nothing is known about the enemy (the standalone UI-test fixture today, a
        // Sis front later — F3.2): every type in the catalog is a possible target.
        self.enemyUnitTypes = enemyUnitTypes ?? catalog.map(\.id)
        self.compiler = compiler
        self.textCompiler = textCompiler
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

    /// Whether this level lets the player write any order at all. Level 1 doesn't (`maxRules == 0`,
    /// only `.always` available — F1.12): the lesson there is that the default order is enough, and an
    /// "Emir ekle" button would only produce an order the validator then rejects.
    var canWriteOrders: Bool {
        constraints.maxRules > 0 && constraints.availableConditions.contains { $0 != .always }
    }

    var canAddRule: Bool {
        canWriteOrders && usedBudget < constraints.maxRules
    }

    var battleBlocker: BattleBlocker? {
        if written != nil {
            return .unsealedOrders
        }
        if let budget = validationErrors.lazy.compactMap(Self.budgetBlocker).first {
            return budget
        }
        return validationErrors.lazy.compactMap(Self.orderBlocker).first
    }

    private static func budgetBlocker(_ error: RuleValidationError) -> BattleBlocker? {
        if case .ruleBudgetExceeded(let used, let budget) = error { return .budgetExceeded(used: used, budget: budget) }
        return nil
    }

    private static func orderBlocker(_ error: RuleValidationError) -> BattleBlocker? {
        guard let location = Self.location(of: error) else { return nil }
        return .invalidOrder(unitType: location.unitType, priority: location.ruleIndex + 1)
    }

    private static func location(of error: RuleValidationError) -> (unitType: UnitTypeID, ruleIndex: Int)? {
        switch error {
        case .conditionNotAvailable(let unitType, let ruleIndex, _),
            .actionNotAvailable(let unitType, let ruleIndex, _),
            .conditionParameterOutOfRange(let unitType, let ruleIndex, _, _, _),
            .alwaysRuleIsNotLast(let unitType, let ruleIndex):
            (unitType, ruleIndex)
        case .ruleBudgetExceeded:
            nil
        }
    }

    var defaultRule: EditableRule {
        defaultRuleByUnitType[selectedUnitType] ?? EditableRule(rule: Rule(condition: .always, action: .advance))
    }

    /// For each of the selected type's orders, the priority (1-based) of an earlier order that always
    /// decides first — the order is folded under it and will never run (`RuleReachability`).
    var foldedUnder: [EditableRule.ID: Int] {
        let program = RuleProgram(unitType: selectedUnitType, rules: orders.map(\.rule) + [defaultRule.rule])
        var result: [EditableRule.ID: Int] = [:]
        for (index, folding) in RuleReachability.foldingRules(in: program).enumerated() where index < orders.count {
            if let folding { result[orders[index].id] = folding + 1 }
        }
        return result
    }

    func ability(for unitType: UnitTypeID) -> Ability? {
        catalog.first { $0.id == unitType }?.ability
    }

    func state(for editableRule: EditableRule) -> OrderCardState {
        let index = orders.firstIndex(of: editableRule) ?? 0
        let isInvalid = validationErrors.contains { error in
            guard let location = Self.location(of: error) else { return false }
            return location.unitType == selectedUnitType && location.ruleIndex == index
        }
        return isInvalid ? .disabled : .normal
    }

    // MARK: - Intents

    func selectUnitType(_ unitType: UnitTypeID) {
        // A written order belongs to the tab it was written on; it's sealed or set aside first.
        guard unitTypes.contains(unitType), written == nil else { return }
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

    // MARK: - Written orders (F2.4)

    var slipIssues: [WrittenSlip.ID: SlipIssue] {
        guard let written else { return [:] }
        var issues: [WrittenSlip.ID: SlipIssue] = [:]
        var located: [(id: WrittenSlip.ID, rule: Rule)] = []
        for slip in written.slips {
            if let rule = try? slip.draft.rule() {
                located.append((slip.id, rule))
            } else {
                issues[slip.id] = .blank
            }
        }
        // The same validator every order passes (D18), on the written orders alone: a slip is
        // flagged exactly when it would be once sealed. The default slip has to be last.
        located = located.filter { $0.rule.condition != .always } + located.filter { $0.rule.condition == .always }
        let program = RuleProgram(unitType: written.unitType, rules: located.map(\.rule))
        for error in RuleValidator.validate(programs: [program], constraints: constraints) {
            switch error {
            case .conditionNotAvailable(_, let index, _):
                issues[located[index].id] = issues[located[index].id] ?? .conditionLocked
            case .actionNotAvailable(_, let index, _):
                issues[located[index].id] = issues[located[index].id] ?? .actionLocked
            case .conditionParameterOutOfRange(_, let index, _, _, let range):
                issues[located[index].id] = issues[located[index].id] ?? .outOfRange(range)
            case .alwaysRuleIsNotLast, .ruleBudgetExceeded:
                break
            }
        }
        return issues
    }

    var sealBlocker: SealBlocker? {
        guard let written else { return nil }
        let issues = slipIssues.values
        if issues.contains(.blank) {
            return .blank
        }
        if !issues.isEmpty {
            return .notAllowedHere
        }
        let needed = written.slips.count { !$0.isDefault }
        let remaining = max(0, constraints.maxRules - usedBudget)
        if needed > remaining {
            return .budget(needed: needed, remaining: remaining)
        }
        return nil
    }

    /// Reads typed (or spoken) text into slips for the selected unit type. Nothing joins the
    /// stack until `sealWritten()`.
    func write(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, written == nil, !isWriting else { return }
        let unitType = selectedUnitType
        isWriting = true
        defer { isWriting = false }
        do {
            let drafts = try await textCompiler.drafts(from: trimmed, context: compileContext)
            written = WrittenOrders(unitType: unitType, text: trimmed, slips: drafts.map { WrittenSlip(draft: $0) })
            writeError = nil
            audio.play(.paper)
        } catch {
            writeError = error
        }
    }

    /// Warms the text path's language model when the editor opens (D17), so the first written order
    /// doesn't wait for it to load.
    func prewarmWriting() async {
        guard canWriteOrders else { return }
        await textCompiler.prewarm()
    }

    func sealWritten() {
        guard let written, sealBlocker == nil else { return }
        var sealed: Set<EditableRule.ID> = []
        for slip in written.slips {
            guard let rule = try? slip.draft.rule() else { continue }
            if slip.isDefault {
                let id = defaultRuleByUnitType[written.unitType]?.id ?? UUID()
                defaultRuleByUnitType[written.unitType] = EditableRule(id: id, rule: rule)
                sealed.insert(id)
            } else {
                let order = EditableRule(rule: rule)
                ordersByUnitType[written.unitType, default: []].append(order)
                sealed.insert(order.id)
            }
        }
        self.written = nil
        justSealed = sealed
        audio.play(.stamp)
        refreshValidation()
    }

    func discardWritten() {
        written = nil
        writeError = nil
    }

    func clearJustSealed() {
        justSealed = []
    }

    func removeSlip(_ id: WrittenSlip.ID) {
        written?.slips.removeAll { $0.id == id }
        if written?.slips.isEmpty == true {
            written = nil
        }
    }

    func updateSlip(_ id: WrittenSlip.ID, to draft: RuleDraft) {
        guard let index = written?.slips.firstIndex(where: { $0.id == id }) else { return }
        written?.slips[index].draft = draft
    }

    /// The number the dial edits on a written slip, blank or not — and where a blank one starts.
    func slipNumericParameter(for id: WrittenSlip.ID) -> (value: Int, range: ClosedRange<Int>)? {
        guard let draft = written?.slips.first(where: { $0.id == id })?.draft else { return nil }
        switch draft.conditionKind.parameter {
        case .cells(let range), .percent(let range), .count(let range), .seconds(let range):
            return (draft.conditionNumericValue ?? RulePickerSheet.defaultNumericValue(for: draft.conditionKind), range)
        case .none, .unitType, .terrain:
            return nil
        }
    }

    func setSlipNumber(_ value: Int, for id: WrittenSlip.ID) {
        guard let index = written?.slips.firstIndex(where: { $0.id == id }) else { return }
        written?.slips[index].draft.conditionNumericValue = value
    }

    // MARK: - Compiling and validation

    private var compileContext: CompileContext {
        CompileContext(
            unitType: selectedUnitType, constraints: constraints, availableUnitTypes: unitTypes,
            remainingRuleBudget: max(0, constraints.maxRules - usedBudget))
    }

    private func compile(_ draft: RuleDraft) async -> Rule? {
        do {
            let rules = try await compiler.compile(draft, context: compileContext)
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
