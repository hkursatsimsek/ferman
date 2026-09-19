import FermanAI
import FermanCore
import SwiftUI

/// The selector-based add/edit flow (design brief §4.4): pick a condition kind, fill in whichever
/// parameter it needs, pick an action kind, fill in its parameter. This is the only way to write an
/// order in Faz 1 — no natural language input exists yet (CLAUDE.md: LLM code isn't in this phase).
struct RulePickerSheet: View {
    enum Mode: Equatable {
        case add
        case editRule
        case editDefaultAction
    }

    let mode: Mode
    let constraints: RuleConstraints
    /// The *enemy's* unit types — every unit-type parameter here (`targetInRange`, `nearestEnemyType`,
    /// `focusFire`) names an enemy unit (`RuleEditorModel.enemyUnitTypes`).
    let availableUnitTypes: [UnitTypeID]
    /// The unit's own ability — `useAbility` reads as it ("YÜKLEN", "KALKAN DUVARI") in the preview.
    let ability: Ability?
    var onConfirmRule: (RuleDraft) -> Void = { _ in }
    var onConfirmDefaultAction: (Action) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var conditionKind: ConditionKind
    @State private var numericValue: Int
    @State private var conditionUnitType: UnitTypeID
    @State private var conditionTerrain: Terrain
    @State private var actionKind: ActionKind
    @State private var actionUnitType: UnitTypeID?

    init(
        mode: Mode,
        constraints: RuleConstraints,
        availableUnitTypes: [UnitTypeID],
        ability: Ability? = nil,
        initialRule: Rule? = nil,
        onConfirmRule: @escaping (RuleDraft) -> Void = { _ in },
        onConfirmDefaultAction: @escaping (Action) -> Void = { _ in }
    ) {
        self.mode = mode
        self.constraints = constraints
        self.availableUnitTypes = availableUnitTypes
        self.ability = ability
        self.onConfirmRule = onConfirmRule
        self.onConfirmDefaultAction = onConfirmDefaultAction

        let condition = initialRule?.condition
        let firstAvailableCondition = constraints.availableConditions.first { $0 != .always } ?? .always
        let conditionKind = condition?.kind ?? firstAvailableCondition
        _conditionKind = State(initialValue: conditionKind)
        _numericValue = State(
            initialValue: Self.numericValue(in: condition) ?? Self.defaultNumericValue(for: conditionKind))
        _conditionUnitType = State(initialValue: Self.unitTypeValue(in: condition) ?? availableUnitTypes.first ?? "")
        _conditionTerrain = State(initialValue: Self.terrainValue(in: condition) ?? .open)

        let action = initialRule?.action
        _actionKind = State(initialValue: action?.kind ?? constraints.availableActions.first ?? .advance)
        if case .focusFire(let target) = action {
            _actionUnitType = State(initialValue: target)
        } else {
            _actionUnitType = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FermanSpacing.lg) {
                    // The order being written, as the slip it will become — "bunu ben de yazabilirim"
                    // (brief §9) starts with seeing your words, not a form.
                    OrderCard(
                        priority: 1, condition: OrderPhraseFormatter.condition(buildCondition()),
                        action: OrderPhraseFormatter.action(buildAction(), ability: ability), state: .editing)
                        .accessibilityLabel(String(localized: "Yazılan emir"))

                    if mode != .editDefaultAction {
                        section(String(localized: "Ne zaman?")) {
                            choiceGrid(constraints.availableConditions.filter { $0 != .always }) { kind in
                                ChoiceCard(
                                    symbol: Self.conditionSymbol(kind), label: Self.conditionKindLabel(kind),
                                    isSelected: conditionKind == kind
                                ) { conditionKind = kind }
                            }
                            conditionParameterControl
                        }
                    }

                    section(String(localized: "Ne yapsın?")) {
                        choiceGrid(constraints.availableActions) { kind in
                            ChoiceCard(
                                symbol: Self.actionSymbol(kind), label: Self.actionKindLabel(kind),
                                isSelected: actionKind == kind
                            ) { actionKind = kind }
                        }
                        if actionKind == .focusFire {
                            unitTypeChips(
                                selection: actionUnitType, includesAny: true,
                                select: { actionUnitType = $0 })
                        }
                    }
                }
                .padding(FermanSpacing.md)
            }
            .background(Color.ink)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) { confirm() }
                }
            }
            .onChange(of: conditionKind) { _, kind in
                // A new kind has its own range: carry the number over only if it still fits.
                if let range = Self.numericRange(of: kind), !range.contains(numericValue) {
                    numericValue = Self.defaultNumericValue(for: kind)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FermanSpacing.sm) {
            Text(title)
                .font(FermanFont.sectionTitle())
                .tracking(FermanFont.Tracking.sectionTitle)
                .foregroundStyle(Color.paper)
            content()
        }
    }

    private func choiceGrid<Kind: Hashable, Cell: View>(
        _ kinds: [Kind], @ViewBuilder cell: @escaping (Kind) -> Cell
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: FermanSpacing.sm), GridItem(.flexible(), spacing: FermanSpacing.sm)],
            spacing: FermanSpacing.sm
        ) {
            ForEach(kinds, id: \.self) { cell($0) }
        }
    }

    @ViewBuilder
    private var conditionParameterControl: some View {
        switch conditionKind.parameter {
        case .none:
            EmptyView()
        case .cells(let range), .percent(let range), .count(let range), .seconds(let range):
            ParameterDial(
                label: Self.parameterLabel(for: conditionKind), unit: Self.parameterUnit(for: conditionKind),
                value: $numericValue, range: range)
        case .unitType:
            unitTypeChips(selection: conditionUnitType, includesAny: false, select: { conditionUnitType = $0 ?? "" })
        case .terrain:
            HStack(spacing: FermanSpacing.sm) {
                ForEach(Terrain.allCases.filter { $0 != .water }, id: \.self) { terrain in
                    Button(Self.terrainLabel(terrain)) { conditionTerrain = terrain }
                        .buttonStyle(ChipStyle(isSelected: conditionTerrain == terrain))
                }
            }
        }
    }

    /// The enemy's unit types as iron figures — conditions and `focusFire` both name an enemy unit.
    private func unitTypeChips(
        selection: UnitTypeID?, includesAny: Bool, select: @escaping (UnitTypeID?) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FermanSpacing.sm) {
                if includesAny {
                    Button(String(localized: "En yakın / en zayıf")) { select(nil) }
                        .buttonStyle(ChipStyle(isSelected: selection == nil))
                }
                ForEach(availableUnitTypes, id: \.self) { unitType in
                    Button {
                        select(unitType)
                    } label: {
                        HStack(spacing: FermanSpacing.xxs) {
                            UnitToken(type: unitType, team: .enemy, size: .chip)
                            Text(Self.unitTypeLabel(unitType))
                        }
                    }
                    .buttonStyle(ChipStyle(isSelected: selection == unitType))
                    .accessibilityLabel(Self.unitTypeLabel(unitType))
                }
            }
        }
    }

    private func buildCondition() -> Condition {
        switch conditionKind {
        case .enemyWithin: .enemyWithin(cells: numericValue)
        case .healthBelow: .healthBelow(percent: numericValue)
        case .allyCountBelow: .allyCountBelow(count: numericValue)
        case .isFlanked: .isFlanked
        case .targetInRange: .targetInRange(conditionUnitType)
        case .timeAfter: .timeAfter(seconds: numericValue)
        case .nearestEnemyType: .nearestEnemyType(conditionUnitType)
        case .moraleBelow: .moraleBelow(percent: numericValue)
        case .terrainIs: .terrainIs(conditionTerrain)
        case .commanderDead: .commanderDead
        case .enemyDensityAbove: .enemyDensityAbove(count: numericValue)
        case .always: .always
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .add: String(localized: "Yeni Emir")
        case .editRule: String(localized: "Emri Düzenle")
        case .editDefaultAction: String(localized: "Varsayılan Emri Düzenle")
        }
    }

    private var confirmTitle: String {
        mode == .add ? String(localized: "Ekle") : String(localized: "Kaydet")
    }

    private func confirm() {
        switch mode {
        case .editDefaultAction:
            onConfirmDefaultAction(buildAction())
        case .add, .editRule:
            onConfirmRule(buildDraft())
        }
        dismiss()
    }

    private func buildDraft() -> RuleDraft {
        var draft = RuleDraft(conditionKind: conditionKind, actionKind: actionKind)
        switch conditionKind.parameter {
        case .none:
            break
        case .cells, .percent, .count, .seconds:
            draft.conditionNumericValue = numericValue
        case .unitType:
            draft.conditionUnitType = conditionUnitType
        case .terrain:
            draft.conditionTerrain = conditionTerrain
        }
        if actionKind == .focusFire {
            draft.actionUnitType = actionUnitType
        }
        return draft
    }

    private func buildAction() -> Action {
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

    // MARK: - Pre-fill extraction

    private static func numericValue(in condition: Condition?) -> Int? {
        switch condition {
        case .enemyWithin(let v), .timeAfter(let v), .healthBelow(let v), .moraleBelow(let v),
            .allyCountBelow(let v), .enemyDensityAbove(let v):
            v
        default:
            nil
        }
    }

    private static func unitTypeValue(in condition: Condition?) -> UnitTypeID? {
        switch condition {
        case .targetInRange(let unitType), .nearestEnemyType(let unitType): unitType
        default: nil
        }
    }

    private static func terrainValue(in condition: Condition?) -> Terrain? {
        if case .terrainIs(let terrain) = condition { return terrain }
        return nil
    }

    private static func numericRange(of kind: ConditionKind) -> ClosedRange<Int>? {
        switch kind.parameter {
        case .cells(let range), .percent(let range), .count(let range), .seconds(let range): range
        default: nil
        }
    }

    private static func defaultNumericValue(for kind: ConditionKind) -> Int {
        switch kind.parameter {
        case .cells(let range), .percent(let range), .count(let range), .seconds(let range): range.lowerBound
        default: 0
        }
    }

    // MARK: - Labels

    private static func conditionKindLabel(_ kind: ConditionKind) -> String {
        switch kind {
        case .enemyWithin: String(localized: "Düşman yakınlığı")
        case .healthBelow: String(localized: "Canım azaldığında")
        case .allyCountBelow: String(localized: "Dostlarım azaldığında")
        case .isFlanked: String(localized: "Kuşatıldığımda")
        case .targetInRange: String(localized: "Menzilimde belirli bir birim")
        case .timeAfter: String(localized: "Belirli bir andan sonra")
        case .nearestEnemyType: String(localized: "En yakın düşman türü")
        case .moraleBelow: String(localized: "Moralim azaldığında")
        case .terrainIs: String(localized: "Bulunduğum arazi")
        case .commanderDead: String(localized: "Komutanım öldüğünde")
        case .enemyDensityAbove: String(localized: "Düşman yoğunluğu")
        case .always: String(localized: "Başka durumda")
        }
    }

    private static func actionKindLabel(_ kind: ActionKind) -> String {
        switch kind {
        case .advance: String(localized: "İlerle")
        case .retreat: String(localized: "Geri çekil")
        case .hold: String(localized: "Yerinde kal")
        case .focusFire: String(localized: "Yüklen")
        case .flankLeft: String(localized: "Soldan kuşat")
        case .flankRight: String(localized: "Sağdan kuşat")
        case .regroup: String(localized: "Toplan")
        case .useAbility: String(localized: "Yeteneğini kullan")
        case .takeCover: String(localized: "Siper al")
        case .guardCommander: String(localized: "Komutanı koru")
        case .scatter: String(localized: "Dağıl")
        }
    }

    static func parameterLabel(for kind: ConditionKind) -> String {
        switch kind.parameter {
        case .cells: String(localized: "Mesafe")
        case .percent: String(localized: "Eşik")
        case .count: String(localized: "Sayı")
        case .seconds: String(localized: "Süre")
        case .unitType: String(localized: "Birim türü")
        case .terrain: String(localized: "Arazi")
        case .none: ""
        }
    }

    static func parameterUnit(for kind: ConditionKind) -> String {
        switch kind.parameter {
        case .cells: String(localized: "kare")
        case .percent: "%"
        case .count: String(localized: "adet")
        case .seconds: String(localized: "sn")
        default: ""
        }
    }

    // MARK: - Pictograms

    private static func conditionSymbol(_ kind: ConditionKind) -> String {
        switch kind {
        case .enemyWithin: "scope"
        case .healthBelow: "heart"
        case .allyCountBelow: "person.2"
        case .isFlanked: "arrow.left.and.right"
        case .targetInRange: "target"
        case .timeAfter: "hourglass"
        case .nearestEnemyType: "eye"
        case .moraleBelow: "flag"
        case .terrainIs: "mountain.2"
        case .commanderDead: "crown"
        case .enemyDensityAbove: "circle.grid.3x3"
        case .always: "arrow.uturn.down"
        }
    }

    private static func actionSymbol(_ kind: ActionKind) -> String {
        switch kind {
        case .advance: "arrow.up"
        case .retreat: "arrow.down"
        case .hold: "hand.raised"
        case .focusFire: "scope"
        case .flankLeft: "arrow.turn.up.left"
        case .flankRight: "arrow.turn.up.right"
        case .regroup: "arrow.triangle.merge"
        case .useAbility: "burst"
        case .takeCover: "shield"
        case .guardCommander: "crown"
        case .scatter: "arrow.up.and.down.and.arrow.left.and.right"
        }
    }

    private static func unitTypeLabel(_ unitType: UnitTypeID) -> String {
        OrderPhraseFormatter.unitTypeName(unitType)
    }

    private static func terrainLabel(_ terrain: Terrain) -> String {
        switch terrain {
        case .open: String(localized: "Açık")
        case .forest: String(localized: "Orman")
        case .hill: String(localized: "Tepe")
        case .water: String(localized: "Su")
        case .rubble: String(localized: "Moloz")
        }
    }
}

#Preview("RulePickerSheet — ekle", traits: .sizeThatFitsLayout) {
    RulePickerSheet(mode: .add, constraints: .unrestricted, availableUnitTypes: ["okcu", "mizrakci"])
        .preferredColorScheme(.dark)
}

/// One choice on the order form: a pictogram and a plain word. Chosen, it turns to paper — the slip
/// being written — rather than lighting up like a switch.
private struct ChoiceCard: View {
    let symbol: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FermanSpacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text(label)
                    .font(FermanFont.caption())
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(isSelected ? Color.paperInk : Color.paper)
            .padding(.horizontal, FermanSpacing.sm)
            .padding(.vertical, FermanSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isSelected ? Color.paper : Color.slateRaised,
                in: RoundedRectangle(cornerRadius: FermanRadius.orderCard))
            .overlay(
                RoundedRectangle(cornerRadius: FermanRadius.orderCard)
                    .strokeBorder(isSelected ? Color.brass : Color.paper.opacity(0.12), lineWidth: isSelected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct ChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FermanFont.caption())
            .foregroundStyle(isSelected ? Color.paperInk : Color.paper)
            .padding(.horizontal, FermanSpacing.sm)
            .padding(.vertical, FermanSpacing.xs)
            .frame(minHeight: 44)
            .background(
                isSelected ? Color.paper : Color.slateRaised,
                in: RoundedRectangle(cornerRadius: FermanRadius.button))
            .overlay(
                RoundedRectangle(cornerRadius: FermanRadius.button)
                    .strokeBorder(isSelected ? Color.brass : Color.paper.opacity(0.12), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
