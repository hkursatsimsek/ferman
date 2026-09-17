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
    let availableUnitTypes: [UnitTypeID]
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
        initialRule: Rule? = nil,
        onConfirmRule: @escaping (RuleDraft) -> Void = { _ in },
        onConfirmDefaultAction: @escaping (Action) -> Void = { _ in }
    ) {
        self.mode = mode
        self.constraints = constraints
        self.availableUnitTypes = availableUnitTypes
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
            Form {
                if mode != .editDefaultAction {
                    Section("Koşul") {
                        Picker("Koşul", selection: $conditionKind) {
                            ForEach(constraints.availableConditions.filter { $0 != .always }, id: \.self) { kind in
                                Text(Self.conditionKindLabel(kind)).tag(kind)
                            }
                        }
                        conditionParameterControl
                    }
                }

                Section("Eylem") {
                    Picker("Eylem", selection: $actionKind) {
                        ForEach(constraints.availableActions, id: \.self) { kind in
                            Text(Self.actionKindLabel(kind)).tag(kind)
                        }
                    }
                    if actionKind == .focusFire {
                        Picker("Hedef", selection: $actionUnitType) {
                            Text("En yakın / en zayıf").tag(UnitTypeID?.none)
                            ForEach(availableUnitTypes, id: \.self) { unitType in
                                Text(Self.unitTypeLabel(unitType)).tag(UnitTypeID?.some(unitType))
                            }
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) { confirm() }
                }
            }
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
            Picker(Self.parameterLabel(for: conditionKind), selection: $conditionUnitType) {
                ForEach(availableUnitTypes, id: \.self) { unitType in
                    Text(Self.unitTypeLabel(unitType)).tag(unitType)
                }
            }
        case .terrain:
            Picker(Self.parameterLabel(for: conditionKind), selection: $conditionTerrain) {
                ForEach(Terrain.allCases.filter { $0 != .water }, id: \.self) { terrain in
                    Text(Self.terrainLabel(terrain)).tag(terrain)
                }
            }
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

    private static func parameterLabel(for kind: ConditionKind) -> String {
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

    private static func parameterUnit(for kind: ConditionKind) -> String {
        switch kind.parameter {
        case .cells: String(localized: "kare")
        case .percent: "%"
        case .count: String(localized: "adet")
        case .seconds: String(localized: "sn")
        default: ""
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
