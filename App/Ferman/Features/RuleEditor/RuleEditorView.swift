import FermanContent
import FermanCore
import SwiftUI

/// EmirEditörü — the game's heart (design brief §4.4). Unit type tabs, a reorderable order stack
/// with a fixed default at the bottom, and a selector sheet to add or edit an order. No natural
/// language input here yet — that's Faz 2 (CLAUDE.md rule 3).
struct RuleEditorView: View {
    /// Non-nil only on the real navigation path (`Route.ruleEditor`) — `nil` for the standalone
    /// `-uiTestRuleEditor` fixture (`ContentView`), which has no front/army to build a `BattleConfig`
    /// from and so shows no "Savaşı Başlat" button.
    let battleSetup: BattleSetup?
    @State var model: RuleEditorModel
    @State private var sheet: SheetKind?
    @State private var dialTarget: EditableRule.ID?
    @State private var showingPresets = false
    /// Optional, not required: `-uiTestRuleEditor`'s standalone fixture never wraps this view in
    /// `.environment(AppRouter())`, and a required `@Environment(AppRouter.self)` crashes as soon as
    /// SwiftUI resolves this view's dependencies — before `body` even runs, regardless of whether the
    /// "Savaşı Başlat" branch that actually reads it is taken.
    @Environment(AppRouter.self) private var router: AppRouter?

    init(model: RuleEditorModel, battleSetup: BattleSetup? = nil) {
        _model = State(initialValue: model)
        self.battleSetup = battleSetup
    }

    /// Everything `RuleEditorModel` itself doesn't know (front, level content, placements) but
    /// "Savaşı Başlat" needs to assemble a `BattleConfig` — a View-level concern (`LevelSheet.onConfirm`,
    /// `DebriefView.onFixOrders`), not the model's.
    struct BattleSetup {
        let front: CampaignFront
        let level: LevelDefinition
        /// Resolved by whoever builds this (`ContentView`, same as `Route.armySetup`'s own
        /// `catalog.map(front.map)` lookup) so this view never needs to force-unwrap a lookup that
        /// content validation already guaranteed succeeds.
        let map: BattleMap
        let catalog: ContentCatalog
        let placements: [UnitPlacement]
    }

    private enum SheetKind: Identifiable, Equatable {
        case add
        case editRule(EditableRule.ID)
        case editDefaultAction

        var id: String {
            switch self {
            case .add: "add"
            case .editRule(let id): "edit-\(id)"
            case .editDefaultAction: "default"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            unitTypeTabs

            BudgetMeter(
                label: String(localized: "Kural hakkın"), used: model.usedBudget, total: model.constraints.maxRules
            )
            .padding(.horizontal, FermanSpacing.md)
            .padding(.top, FermanSpacing.sm)

            ScrollView {
                VStack(spacing: FermanSpacing.md - 2) {
                    if model.orders.isEmpty {
                        emptyState
                    } else {
                        reorderableStack
                    }
                    defaultCard
                }
                .padding(FermanSpacing.md)
            }

            if model.canAddRule {
                Button {
                    sheet = .add
                } label: {
                    Label(String(localized: "Emir ekle"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FermanButton.Outline())
                .padding(.horizontal, FermanSpacing.md)
                .padding(.top, FermanSpacing.md)
            } else if model.canWriteOrders {
                Text(String(localized: "Kural hakkın doldu. Yeni emir için birini sil."))
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, FermanSpacing.md)
                    .padding(.top, FermanSpacing.md)
            }

            if let battleSetup {
                VStack(spacing: FermanSpacing.xs) {
                    if let blocker = model.battleBlocker {
                        Text(Self.sentence(for: blocker))
                            .font(FermanFont.caption())
                            .foregroundStyle(Color.paper)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    Button(String(localized: "Savaşı Başlat")) {
                        router?.push(.battle(battleConfig(battleSetup)))
                    }
                    .buttonStyle(FermanButton.Primary())
                    .disabled(model.battleBlocker != nil)
                }
                .padding(FermanSpacing.md)
            }
        }
        .background(Color.ink)
        .sheet(item: $sheet) { kind in
            sheetView(for: kind)
        }
        .confirmationDialog(
            String(localized: "Hazır emir setleri"), isPresented: $showingPresets, titleVisibility: .visible
        ) {
            ForEach(RulePreset.allCases, id: \.self) { preset in
                Button(preset.displayName) {
                    Task { await model.applyPreset(preset) }
                }
            }
        }
        .alert(
            String(localized: "Emir tamamlanmadı"),
            isPresented: Binding(
                get: { model.lastCompileError != nil },
                set: { isPresented in if !isPresented { model.lastCompileError = nil } }),
            actions: {
                Button(String(localized: "Tamam")) { model.lastCompileError = nil }
            },
            message: {
                Text(String(localized: "Bu emrin bir parametresi eksik kaldı. Tekrar dene."))
            }
        )
    }

    /// Says what to fix, not that something is wrong (brief §7 — a calm officer, no "hata oluştu").
    private static func sentence(for blocker: RuleEditorModel.BattleBlocker) -> String {
        switch blocker {
        case .budgetExceeded(let used, let budget):
            String(localized: "Kural hakkın \(budget), \(used) emir yazdın. Birini sil.")
        case .invalidOrder(let unitType, let priority):
            String(
                localized: "\(OrderPhraseFormatter.unitTypeName(unitType)) · \(priority). emir bu cephede geçerli değil.")
        }
    }

    private func battleConfig(_ setup: BattleSetup) -> BattleConfig {
        BattleConfig(
            map: setup.map,
            unitCatalog: setup.catalog.units,
            player: TeamSetup(placements: setup.placements, programs: model.programs),
            enemy: setup.level.enemy,
            objective: setup.level.objective,
            constraints: setup.level.constraints,
            seed: setup.level.seed,
            maxTicks: setup.level.maxTicks)
    }

    // MARK: - Tabs

    private var unitTypeTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FermanSpacing.lg) {
                ForEach(model.unitTypes, id: \.self) { unitType in
                    let isSelected = unitType == model.selectedUnitType
                    Button {
                        model.selectUnitType(unitType)
                    } label: {
                        VStack(spacing: FermanSpacing.xxs) {
                            UnitToken(team: .brass, size: .tray, isSelected: isSelected)
                            Text(OrderPhraseFormatter.unitTypeName(unitType))
                                .font(isSelected ? FermanFont.tabSelected() : FermanFont.tab())
                                .foregroundStyle(isSelected ? Color.paper : Color.paper.opacity(0.75))
                        }
                    }
                    .buttonStyle(.plain)
                    // See `HomeView.menuRow`: a tab combining `UnitToken`'s icon with `Text` under
                    // the default grouping gave the contrast audit a frame reaching into the icon
                    // instead of just the text (F1.13). `.accessibilityElement` first, traits/label
                    // after — the reverse order lets them get discarded when the element regroups.
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityLabel(OrderPhraseFormatter.unitTypeName(unitType))
                }
            }
            .padding(.horizontal, FermanSpacing.md)
            .padding(.top, FermanSpacing.md)
        }
    }

    // MARK: - Order stack

    /// **Unverified end to end.** `moveUp`/`moveDown` (VoiceOver's accessibility actions below) and
    /// `RuleEditorModel.reorder(sources:before:)` are tested directly. A live drag through this
    /// `reorderContainer`/`reorderable()` pair reliably crashed the app under XCUITest's synthetic
    /// `press(forDuration:thenDragTo:)` in this environment (a `preconditionFailure` inside AppKit/
    /// UIKit's own `DragContainerStorage`, not our code) — needs a hands-on check on a real device
    /// before shipping, since this API is brand new (WWDC26) and the failure may be simulator- or
    /// synthetic-gesture-specific.
    private var reorderableStack: some View {
        VStack(spacing: FermanSpacing.md - 2) {
            ForEach(model.orders) { item in
                orderCardView(for: item)
                    .accessibilityAction(named: Text("Yukarı taşı")) { model.moveUp(item.id) }
                    .accessibilityAction(named: Text("Aşağı taşı")) { model.moveDown(item.id) }
            }
            .reorderable()
        }
        .reorderContainer(for: EditableRule.self) { difference in
            model.move(difference)
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: model.orders)
    }

    @ViewBuilder
    private func orderCardView(for item: EditableRule) -> some View {
        let priority = (model.orders.firstIndex(of: item) ?? 0) + 1
        let isEditingDial = dialTarget == item.id

        OrderCard(
            priority: priority,
            condition: OrderPhraseFormatter.condition(item.rule.condition),
            action: OrderPhraseFormatter.action(item.rule.action, ability: model.ability(for: model.selectedUnitType)),
            state: isEditingDial ? .editing : model.state(for: item)
        )
        .overlay(alignment: .top) {
            if isEditingDial, let parameter = model.numericParameter(for: item.id) {
                ParameterDial(
                    label: String(localized: "Değer"), unit: "",
                    value: Binding(
                        get: { parameter.value },
                        set: { model.setNumericParameter($0, for: item.id) }
                    ),
                    range: parameter.range
                )
                .offset(y: -70)
                .zIndex(1)
            }
        }
        .onTapGesture {
            if model.numericParameter(for: item.id) != nil {
                dialTarget = dialTarget == item.id ? nil : item.id
            } else {
                sheet = .editRule(item.id)
            }
        }
        .contextMenu {
            Button(String(localized: "Düzenle")) { sheet = .editRule(item.id) }
            Button(role: .destructive) {
                model.removeRule(item.id)
            } label: {
                Text(String(localized: "Sil"))
            }
        }
    }

    private var defaultCard: some View {
        OrderCard(
            priority: model.orders.count + 1,
            condition: OrderPhraseFormatter.condition(.always),
            action: OrderPhraseFormatter.action(
                model.defaultRule.rule.action, ability: model.ability(for: model.selectedUnitType)),
            state: .isDefault
        )
        .onTapGesture {
            sheet = .editDefaultAction
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: FermanSpacing.md) {
            if model.canWriteOrders {
                Text("Henüz emir yok.")
                    .font(FermanFont.sectionTitle())
                    .tracking(FermanFont.Tracking.sectionTitle)
                    .foregroundStyle(Color.paper)
                Text("Askerlerin emir almazsa düşmana doğru yürür ve öldürülene kadar dövüşür.")
                    .font(FermanFont.body())
                    .foregroundStyle(Color.paper.opacity(0.65))
                    .multilineTextAlignment(.center)
                Button(String(localized: "Hazır emir setlerini gör")) {
                    showingPresets = true
                }
                .buttonStyle(FermanButton.Chip())
            } else {
                // Level 1 (F1.12): nothing to write, the default order is the whole lesson.
                Text("Bu cephede emir yazılmaz.")
                    .font(FermanFont.sectionTitle())
                    .tracking(FermanFont.Tracking.sectionTitle)
                    .foregroundStyle(Color.paper)
                Text("Askerlerin varsayılan emri uygular: düşmana doğru yürür ve öldürülene kadar dövüşür. İzle.")
                    .font(FermanFont.body())
                    .foregroundStyle(Color.paper.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, FermanSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sheet

    @ViewBuilder
    private func sheetView(for kind: SheetKind) -> some View {
        switch kind {
        case .add:
            RulePickerSheet(
                mode: .add, constraints: model.constraints, availableUnitTypes: model.enemyUnitTypes,
                onConfirmRule: { draft in Task { await model.addRule(draft) } })
        case .editRule(let id):
            if let item = model.orders.first(where: { $0.id == id }) {
                RulePickerSheet(
                    mode: .editRule, constraints: model.constraints, availableUnitTypes: model.enemyUnitTypes,
                    initialRule: item.rule,
                    onConfirmRule: { draft in Task { await model.updateRule(id, to: draft) } })
            }
        case .editDefaultAction:
            RulePickerSheet(
                mode: .editDefaultAction, constraints: model.constraints, availableUnitTypes: model.enemyUnitTypes,
                initialRule: model.defaultRule.rule,
                onConfirmDefaultAction: { action in model.updateDefaultAction(action) })
        }
    }
}
