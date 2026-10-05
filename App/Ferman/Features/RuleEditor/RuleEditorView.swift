import FermanAI
import FermanContent
import FermanCore
import SwiftUI
import TipKit

/// EmirEditörü — the game's heart (design brief §4.4). Unit type tabs, a reorderable order stack
/// with a fixed default at the bottom, a selector sheet to add or edit an order, and a small field
/// to write one in words (F2.4). Written orders land as unsealed slips the player checks, fills in
/// and seals — nothing written reaches a battle unseen (CLAUDE.md rule 3).
struct RuleEditorView: View {
    /// Non-nil only on the real navigation path (`Route.ruleEditor`) — `nil` for the standalone
    /// `-uiTestRuleEditor` fixture (`ContentView`), which has no front/army to build a `BattleConfig`
    /// from and so shows no "Savaşı Başlat" button.
    let battleSetup: BattleSetup?
    @State var model: RuleEditorModel
    @State private var sheet: SheetKind?
    @State private var dialTarget: EditableRule.ID?
    @State private var showingPresets = false
    @State private var slipDialTarget: WrittenSlip.ID?
    @State private var offeringSpeechDownload = false
    @FocusState private var isWriteFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        case editSlip(WrittenSlip.ID)

        var id: String {
            switch self {
            case .add: "add"
            case .editRule(let id): "edit-\(id)"
            case .editDefaultAction: "default"
            case .editSlip(let id): "slip-\(id)"
            }
        }
    }

    /// The first three fronts' pencil note (G13): watch the default order, write a first order, mind
    /// the order they're read in.
    @ViewBuilder
    private var tutorialNote: some View {
        switch battleSetup?.front.id {
        case 1: TipView(DefaultOrderNote()).tipViewStyle(PencilNoteStyle())
        case 2: TipView(FirstOrderNote()).tipViewStyle(PencilNoteStyle())
        case 3: TipView(PriorityNote()).tipViewStyle(PencilNoteStyle())
        default: EmptyView()
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

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: FermanSpacing.md - 2) {
                        tutorialNote
                        if model.orders.isEmpty {
                            if model.written == nil { emptyState }
                        } else {
                            reorderableStack
                        }
                        if let written = model.written, written.unitType == model.selectedUnitType {
                            writtenSection(written)
                                .id(Self.writtenAnchor)
                                .transition(.opacity)
                        }
                        defaultCard
                        if model.orders.count >= 2, dialTarget == nil, model.written == nil {
                            Text(String(localized: "Pusulayı yukarı taşımak önceliğini artırır."))
                                .font(FermanFont.caption())
                                .foregroundStyle(Color.paper.opacity(0.65))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, FermanSpacing.xs)
                        }
                    }
                    .padding(FermanSpacing.md)
                    .animation(.easeOut(duration: 0.2), value: dialTarget)
                    .animation(.easeOut(duration: 0.2), value: slipDialTarget)
                }
                .onChange(of: model.written?.text) { _, text in
                    guard text != nil else { return }
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(Self.writtenAnchor, anchor: .bottom) }
                }
            }

            if let written = model.written {
                reviewBar(written)
            } else {
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
                if model.canWriteOrders {
                    writeField
                }
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
                        router?.push(.battle(battleConfig(battleSetup), front: battleSetup.front))
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
        .sensoryFeedback(SoundEffect.stamp.feel?.feedback ?? .impact, trigger: model.justSealed) { _, sealed in
            !sealed.isEmpty
        }
        .task {
            await model.checkListening()
            await model.prewarmWriting()
        }
        .task(id: model.justSealed) {
            guard !model.justSealed.isEmpty else { return }
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.4)) { model.clearJustSealed() }
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
        case .unsealedOrders:
            String(localized: "Yazdığın emri mühürle ya da vazgeç.")
        case .unwrittenText:
            String(localized: "Alttaki emir henüz pusulaya geçmedi. “Yaz”a dokun ya da sil.")
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
                            UnitToken(type: unitType, size: .tray, isSelected: isSelected)
                            Text(OrderPhraseFormatter.unitTypeName(unitType))
                                .font(isSelected ? FermanFont.tabSelected() : FermanFont.tab())
                                .foregroundStyle(isSelected ? Color.paper : Color.paper.opacity(0.75))
                        }
                    }
                    .buttonStyle(.plain)
                    // A written order is sealed or set aside on its own tab first.
                    .disabled(model.written != nil && !isSelected)
                    .opacity(model.written != nil && !isSelected ? 0.4 : 1)
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
                VStack(spacing: FermanSpacing.xs) {
                    orderCardView(for: item)
                        .accessibilityAction(named: Text("Yukarı taşı")) { model.moveUp(item.id) }
                        .accessibilityAction(named: Text("Aşağı taşı")) { model.moveDown(item.id) }
                        .accessibilityAction(named: Text("Sil")) { model.removeRule(item.id) }
                    if dialTarget == item.id, let parameter = model.numericParameter(for: item.id) {
                        dialPanel(for: item, parameter: parameter)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                // While one order's dial is open the others step back (design mock), so it's clear
                // which slip is being written on.
                .opacity(dialTarget == nil || dialTarget == item.id ? 1 : 0.5)
            }
            .reorderable()
        }
        .reorderContainer(for: EditableRule.self) { difference in
            model.move(difference)
        }
        .sensoryFeedback(SoundEffect.paper.feel?.feedback ?? .selection, trigger: model.orders)
        .onAppear {
            // The second front's note asks for exactly this: once there's an order, it has been read.
            if battleSetup?.front.id == 2 {
                FirstOrderNote().invalidate(reason: .actionPerformed)
            }
        }
    }

    @ViewBuilder
    private func orderCardView(for item: EditableRule) -> some View {
        let priority = (model.orders.firstIndex(of: item) ?? 0) + 1
        let isEditingDial = dialTarget == item.id

        OrderCard(
            priority: priority,
            condition: OrderPhraseFormatter.condition(item.rule.condition),
            action: OrderPhraseFormatter.action(item.rule.action, ability: model.ability(for: model.selectedUnitType)),
            state: isEditingDial ? .editing : model.state(for: item),
            isSealed: model.justSealed.contains(item.id),
            foldedUnder: model.foldedUnder[item.id],
            highlightsParameter: model.numericParameter(for: item.id) != nil
        )
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

    /// The dial opens right under its slip (design mock), with the two other things one reaches for
    /// while there: rewriting the whole order, or striking it.
    private func dialPanel(for item: EditableRule, parameter: (value: Int, range: ClosedRange<Int>)) -> some View {
        VStack(spacing: FermanSpacing.xs) {
            ParameterDial(
                label: RulePickerSheet.parameterLabel(for: item.rule.condition.kind),
                unit: RulePickerSheet.parameterUnit(for: item.rule.condition.kind),
                value: Binding(
                    get: { parameter.value },
                    set: { model.setNumericParameter($0, for: item.id) }
                ),
                range: parameter.range
            )
            HStack {
                Button(String(localized: "Emri düzenle")) {
                    dialTarget = nil
                    sheet = .editRule(item.id)
                }
                .buttonStyle(FermanButton.Ghost())
                Spacer()
                Button(String(localized: "Sil"), role: .destructive) {
                    dialTarget = nil
                    model.removeRule(item.id)
                }
                .buttonStyle(FermanButton.Ghost())
            }
        }
    }

    private var defaultCard: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.xxs) {
            OrderCard(
                priority: model.orders.count + writtenOrderCount + 1,
                condition: OrderPhraseFormatter.condition(.always),
                action: OrderPhraseFormatter.action(
                    model.defaultRule.rule.action, ability: model.ability(for: model.selectedUnitType)),
                state: .isDefault
            )
            .onTapGesture {
                sheet = .editDefaultAction
            }
            Text(String(localized: "Varsayılan emir her zaman yığının sonundadır."))
                .font(FermanFont.caption())
                .foregroundStyle(Color.paper.opacity(0.65))
        }
        .opacity(dialTarget == nil ? 1 : 0.5)
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

    // MARK: - Written orders (F2.4)

    private static let writtenAnchor = "written"

    /// Written slips waiting on this tab that will join the stack (the default one replaces it instead).
    private var writtenOrderCount: Int {
        guard let written = model.written, written.unitType == model.selectedUnitType else { return 0 }
        return written.slips.count { !$0.isDefault }
    }

    /// The field stays small and plain (brief §4.4): the slips are the interface, this is a shortcut.
    /// The microphone beside it appears only where speech can be taken (D16).
    private var writeField: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.xs) {
            HStack(spacing: FermanSpacing.sm) {
                microphoneButton
                if case .installing(let progress) = model.listening {
                    ProgressView(value: progress) {
                        Text(String(localized: "Ses paketi iniyor…"))
                            .font(FermanFont.caption())
                            .foregroundStyle(Color.paper)
                    }
                    .tint(Color.brass)
                } else if case .listening(let transcript) = model.listening {
                    Text(transcript.isEmpty ? String(localized: "Dinliyorum…") : transcript)
                        .font(FermanFont.body())
                        .foregroundStyle(Color.paper.opacity(transcript.isEmpty ? 0.7 : 1))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("spokenTranscript")
                } else {
                    // The prompt stays this short even beside the microphone, whose own label says
                    // "Emri söyle": "Emri söyle ya da yaz" clipped at large Dynamic Type sizes there.
                    TextField(
                        String(localized: "Emri yaz"), text: $model.writeText,
                        prompt: Text(String(localized: "Emri yaz")).foregroundStyle(Color.paper.opacity(0.7))
                    )
                    .font(FermanFont.body())
                    .foregroundStyle(Color.paper)
                    .tint(Color.brass)
                    .submitLabel(.done)
                    .focused($isWriteFieldFocused)
                    .onSubmit(submitWriting)
                    .accessibilityIdentifier("writeOrderField")
                    if model.isWriting {
                        ProgressView()
                            .tint(Color.paper)
                    } else if !model.writeText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button(String(localized: "Yaz"), action: submitWriting)
                            .buttonStyle(FermanButton.Chip())
                    }
                }
            }
            .padding(.horizontal, FermanSpacing.md)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: FermanRadius.orderCard)
                    .strokeBorder(Color.paper.opacity(0.35), lineWidth: 1))
            if let error = model.writeError {
                Text(Self.sentence(for: error))
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("writeOrderError")
            } else if let error = model.listeningError {
                Text(Self.sentence(for: error))
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, FermanSpacing.md)
        .padding(.top, FermanSpacing.sm)
        .onChange(of: model.writeText) {
            model.writeError = nil
        }
        .confirmationDialog(
            String(localized: "Sesle emir"), isPresented: $offeringSpeechDownload, titleVisibility: .visible
        ) {
            Button(String(localized: "Ses paketini indir")) {
                Task { await model.installSpeechAssets() }
            }
        } message: {
            Text(String(localized: "Söylediğin emri yazıya dökmek için ses paketi bir kez indirilir. Sonra internetsiz çalışır; sesin cihazdan çıkmaz."))
        }
    }

    @ViewBuilder
    private var microphoneButton: some View {
        switch model.listening {
        case .unavailable, .installing:
            EmptyView()
        case .needsAssets:
            Button {
                offeringSpeechDownload = true
            } label: {
                Image(systemName: "mic")
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(Color.paper)
            .accessibilityLabel(String(localized: "Emri söyle"))
        case .idle:
            Button {
                isWriteFieldFocused = false
                Task { await model.startListening() }
            } label: {
                Image(systemName: "mic")
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(Color.paper)
            .accessibilityLabel(String(localized: "Emri söyle"))
        case .listening:
            Button {
                Task {
                    let transcript = await model.stopListening()
                    guard !transcript.isEmpty else { return }
                    model.writeText = transcript
                    submitWriting()
                }
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(Color.brass)
            .symbolEffect(.pulse, isActive: !reduceMotion)
            .accessibilityLabel(String(localized: "Söylemeyi bitir"))
        }
    }

    private func submitWriting() {
        let text = model.writeText
        Task {
            await model.write(text)
            if model.written != nil {
                isWriteFieldFocused = false
            }
        }
    }

    private func writtenSection(_ written: WrittenOrders) -> some View {
        VStack(alignment: .leading, spacing: FermanSpacing.sm) {
            Text("“\(written.text)”")
                .font(FermanFont.caption())
                .italic()
                .foregroundStyle(Color.paper.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(written.slips.enumerated()), id: \.element.id) { index, slip in
                writtenSlipView(slip, index: index, priority: writtenPriority(of: slip, in: written))
            }
        }
    }

    private func writtenPriority(of slip: WrittenSlip, in written: WrittenOrders) -> Int {
        // The default slip takes the default order's place, under every written order.
        let ahead = slip.isDefault ? writtenOrderCount : written.slips.prefix { $0.id != slip.id }.count { !$0.isDefault }
        return model.orders.count + ahead + 1
    }

    @ViewBuilder
    private func writtenSlipView(_ slip: WrittenSlip, index: Int, priority: Int) -> some View {
        let issue = model.slipIssues[slip.id]
        VStack(alignment: .leading, spacing: FermanSpacing.xs) {
            WrittenSlipCard(
                priority: priority,
                condition: OrderPhraseFormatter.condition(of: slip.draft),
                action: OrderPhraseFormatter.action(slip.draft.action, ability: model.ability(for: model.selectedUnitType)),
                inkDelay: Double(index) * 0.8
            )
            .onTapGesture { tapSlip(slip) }
            .contextMenu {
                Button(String(localized: "Düzenle")) { sheet = .editSlip(slip.id) }
                Button(role: .destructive) {
                    model.removeSlip(slip.id)
                } label: {
                    Text(String(localized: "Sil"))
                }
            }
            .accessibilityValue(issue.map(Self.sentence(for:)) ?? "")
            .accessibilityHint(String(localized: "Düzeltmek için dokun."))
            .accessibilityAction(named: Text("Sil")) { model.removeSlip(slip.id) }
            if slipDialTarget == slip.id, let parameter = model.slipNumericParameter(for: slip.id) {
                slipDialPanel(for: slip, parameter: parameter)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if slip.isDefault {
                Text(String(localized: "Varsayılan emrin yerine geçer."))
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper.opacity(0.65))
            }
            if let issue {
                Text(Self.sentence(for: issue))
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.paper)
                    .padding(.leading, FermanSpacing.sm)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.brass).frame(width: 2)
                    }
                    .accessibilityHidden(true)
            }
        }
        .opacity(slipDialTarget == nil || slipDialTarget == slip.id ? 1 : 0.5)
    }

    /// A numeric slot opens the dial right under the slip — a blank one starts where a new order
    /// would, and is filled the moment the dial opens, so what the player sees is what gets sealed.
    private func tapSlip(_ slip: WrittenSlip) {
        if let parameter = model.slipNumericParameter(for: slip.id) {
            if slip.draft.conditionNumericValue == nil {
                model.setSlipNumber(parameter.value, for: slip.id)
            }
            slipDialTarget = slipDialTarget == slip.id ? nil : slip.id
        } else {
            sheet = .editSlip(slip.id)
        }
    }

    private func slipDialPanel(for slip: WrittenSlip, parameter: (value: Int, range: ClosedRange<Int>)) -> some View {
        VStack(spacing: FermanSpacing.xs) {
            ParameterDial(
                label: RulePickerSheet.parameterLabel(for: slip.draft.conditionKind),
                unit: RulePickerSheet.parameterUnit(for: slip.draft.conditionKind),
                value: Binding(
                    get: { parameter.value },
                    set: { model.setSlipNumber($0, for: slip.id) }
                ),
                range: parameter.range
            )
            HStack {
                Button(String(localized: "Emri düzenle")) {
                    slipDialTarget = nil
                    sheet = .editSlip(slip.id)
                }
                .buttonStyle(FermanButton.Ghost())
                Spacer()
                Button(String(localized: "Tamam")) {
                    slipDialTarget = nil
                }
                .buttonStyle(FermanButton.Ghost())
            }
        }
    }

    /// Replaces the field while slips are on the table: they're sealed or set aside, never left
    /// half-read (F2.4's "zorunlu onay").
    private func reviewBar(_ written: WrittenOrders) -> some View {
        VStack(spacing: FermanSpacing.sm) {
            Text(model.sealBlocker.map(Self.sentence(for:)) ?? String(localized: "Doğruysa mühürle. Yanlışsa pusulaya dokunup düzelt."))
                .font(FermanFont.caption())
                .foregroundStyle(Color.paper)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: FermanSpacing.md) {
                Button(String(localized: "Vazgeç")) {
                    slipDialTarget = nil
                    withAnimation(.easeOut(duration: 0.2)) { model.discardWritten() }
                }
                .buttonStyle(FermanButton.Ghost())
                if model.sealBlocker == nil {
                    Button(String(localized: "Mühürle")) {
                        slipDialTarget = nil
                        withAnimation(.spring(duration: 0.3, bounce: 0.35)) { model.sealWritten() }
                    }
                    .buttonStyle(FermanButton.Primary())
                }
            }
        }
        .padding(.horizontal, FermanSpacing.md)
        .padding(.top, FermanSpacing.md)
    }

    /// Says what to do next, not what went wrong (brief §7). Never a word from the ban list (CLAUDE.md
    /// rule 7): the player "writes" orders, nothing is "read by the machine".
    private static func sentence(for error: RuleCompileError) -> String {
        switch error {
        case .noOrderRecognized:
            String(localized: "Bunu bir emre çeviremedim. Örneğin: “düşman 3 kareden yakınsa geri çekil”.")
        case .missingAction:
            String(localized: "Ne zaman olacağı belli, ne yapacakları değil. Sonuna bir eylem ekle: “… geri çekil”.")
        case .unrecognizedAction:
            String(localized: "Ne yapacaklarını anlayamadım. Eylemi başka bir sözle yaz: “… geri çekil”.")
        case .unrecognizedCondition:
            String(localized: "Bu durumu tanımıyorum. “Emir ekle” ile seçerek yazabilirsin.")
        case .unsupportedComparison(let kind):
            switch kind {
            case .enemyWithin:
                String(localized: "Mesafe yalnızca “yakınsa” diye sorulur: “düşman 3 kareden yakınsa”.")
            default:
                String(localized: "Bu yalnızca “altındaysa” diye sorulur: “canım %40'ın altındaysa”.")
            }
        case .conflictingDefaultOrders:
            String(localized: "İki ayrı varsayılan emir yazdın. Birini seç.")
        case .multipleActions:
            String(localized: "Bir cümlede iki eylem var. Emirleri virgülle ayır.")
        case .missingConditionParameter:
            String(localized: "Bu emrin bir parametresi eksik kaldı. Tekrar dene.")
        case .modelUnavailable:
            // `CompilerChain` answers these itself; only reachable if a lone model is wired in.
            String(localized: "Bu emri şimdi okuyamadım. “Emir ekle” ile seçerek yazabilirsin.")
        }
    }

    private static func sentence(for error: ListeningError) -> String {
        switch error {
        case .microphoneDenied:
            String(localized: "Mikrofon izni kapalı. Ayarlar'dan açabilir ya da emri yazabilirsin.")
        case .noMicrophone:
            String(localized: "Mikrofon bulunamadı. Emri yazabilirsin.")
        case .assetsMissing:
            String(localized: "Ses paketi henüz inmedi. Mikrofona dokunup indirebilirsin.")
        case .failed:
            String(localized: "Sesini şimdi duyamadım. Tekrar söyle ya da yaz.")
        }
    }

    private static func sentence(for issue: RuleEditorModel.SlipIssue) -> String {
        switch issue {
        case .blank:
            String(localized: "Bir boşluk var. Pusulaya dokunup doldur.")
        case .conditionLocked:
            String(localized: "Bu cephede bu koşul yok. Dokunup değiştir ya da sil.")
        case .actionLocked:
            String(localized: "Bu cephede bu eylem yok. Dokunup değiştir ya da sil.")
        case .outOfRange(let range):
            String(localized: "Bu sayı \(range.lowerBound) ile \(range.upperBound) arasında olmalı. Dokunup düzelt.")
        }
    }

    private static func sentence(for blocker: RuleEditorModel.SealBlocker) -> String {
        switch blocker {
        case .blank:
            String(localized: "Boşlukları doldur, sonra mühürle.")
        case .notAllowedHere:
            String(localized: "İşaretli pusulaları düzelt ya da sil.")
        case .budget(let needed, let remaining):
            if remaining == 0 {
                String(localized: "Kural hakkın dolu. Yığından bir emri sil ya da vazgeç.")
            } else {
                String(localized: "Kural hakkında \(remaining) yer var, \(needed) emir yazdın. Birini sil.")
            }
        }
    }

    // MARK: - Sheet

    @ViewBuilder
    private func sheetView(for kind: SheetKind) -> some View {
        switch kind {
        case .add:
            RulePickerSheet(
                mode: .add, constraints: model.constraints, availableUnitTypes: model.enemyUnitTypes,
                ability: model.ability(for: model.selectedUnitType),
                onConfirmRule: { draft in Task { await model.addRule(draft) } })
        case .editRule(let id):
            if let item = model.orders.first(where: { $0.id == id }) {
                RulePickerSheet(
                    mode: .editRule, constraints: model.constraints, availableUnitTypes: model.enemyUnitTypes,
                    ability: model.ability(for: model.selectedUnitType),
                    initialRule: item.rule,
                    onConfirmRule: { draft in Task { await model.updateRule(id, to: draft) } })
            }
        case .editDefaultAction:
            RulePickerSheet(
                mode: .editDefaultAction, constraints: model.constraints, availableUnitTypes: model.enemyUnitTypes,
                ability: model.ability(for: model.selectedUnitType),
                initialRule: model.defaultRule.rule,
                onConfirmDefaultAction: { action in model.updateDefaultAction(action) })
        case .editSlip(let id):
            if let slip = model.written?.slips.first(where: { $0.id == id }) {
                if slip.isDefault {
                    RulePickerSheet(
                        mode: .editDefaultAction, constraints: model.constraints,
                        availableUnitTypes: model.enemyUnitTypes, ability: model.ability(for: model.selectedUnitType),
                        initialDraft: slip.draft,
                        onConfirmDefaultAction: { action in
                            model.updateSlip(id, to: RuleDraft(Rule(condition: .always, action: action)))
                        })
                } else {
                    RulePickerSheet(
                        mode: .editRule, constraints: model.constraints, availableUnitTypes: model.enemyUnitTypes,
                        ability: model.ability(for: model.selectedUnitType),
                        initialDraft: slip.draft,
                        onConfirmRule: { draft in model.updateSlip(id, to: draft) })
                }
            }
        }
    }
}

/// A written slip, inked a moment after it lands (ART-DIRECTION §8): the condition, then the action.
/// Reduce Motion skips the pen and shows the words at once.
private struct WrittenSlipCard: View {
    let priority: Int
    let condition: String
    let action: String
    let inkDelay: Double
    @State private var isInked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OrderCard(
            priority: priority, condition: condition, action: action, state: .written,
            isInked: isInked || reduceMotion
        )
        .task {
            guard !isInked else { return }
            try? await Task.sleep(for: .seconds(inkDelay))
            isInked = true
        }
    }
}
