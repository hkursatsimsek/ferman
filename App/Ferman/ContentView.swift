//
//  ContentView.swift
//  Ferman
//
//  Created by Hamza Kürşat Şimşek on 15.09.2026.
//

import FermanContent
import FermanCore
import SwiftUI
import os

struct ContentView: View {
    private static let logger = Logger(subsystem: "com.hksimsek.FERMAN", category: "Content")

    @State private var router = AppRouter()
    @Namespace private var frontTransition
    private let catalog: ContentCatalog?
    /// Persisted progress (D14): which fronts are won, every battle fought. `nil` only if the store
    /// can't open — then every front is left open rather than locking the player out.
    @State private var progress: ProgressStore?
    /// `-uiTestSandbox`: an in-memory store and every front open, so UI tests start from the same
    /// place every run instead of whatever the last run left on the simulator's disk.
    private let isSandbox = ProcessInfo.processInfo.arguments.contains("-uiTestSandbox")

    init() {
        do {
            catalog = try ContentCatalog.bundled()
        } catch {
            Self.logger.critical("Failed to load bundled content: \(error, privacy: .public)")
            catalog = nil
        }
        do {
            _progress = State(initialValue: try ProgressStore(inMemory: isSandbox))
        } catch {
            Self.logger.error("Progress store unavailable: \(error, privacy: .public)")
            _progress = State(initialValue: nil)
        }
    }

    private func fronts(_ catalog: ContentCatalog) -> [CampaignFront] {
        CampaignFront.fronts(
            from: catalog, bestOutcome: { progress?.progress(forLevel: $0)?.bestOutcome },
            unlockAll: isSandbox || progress == nil)
    }

    /// The most recent battle on record, to lay out on the home screen's table.
    private func lastBattle(_ catalog: ContentCatalog) -> BattleRecordSnapshot? {
        catalog.levels.flatMap { progress?.battleRecords(forLevel: $0.id) ?? [] }.max { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        // FermanUITests still reaches RuleEditorView directly through this launch argument, with a
        // fixed two-unit fixture instead of a real army — a fast, deterministic UI-test entry point
        // that doesn't need to walk Home -> Campaign -> ArmySetup first.
        if ProcessInfo.processInfo.arguments.contains("-uiTestRuleEditor") {
            RuleEditorView(model: Self.ruleEditorFixture())
        } else if ProcessInfo.processInfo.arguments.contains("-uiTestRuleEditorSample") {
            RuleEditorView(model: Self.ruleEditorFixture(programs: Self.sampleOrders))
        } else if ProcessInfo.processInfo.arguments.contains("-uiTestRulePicker") {
            RulePickerSheet(
                mode: .add, constraints: .unrestricted, availableUnitTypes: ["mizrakci", "okcu", "suvari", "kalkan"],
                ability: .volley)
        } else if let catalog, UserDefaults.standard.bool(forKey: "uiTestCampaign") {
            // `-uiTestCampaign YES`: the campaign line straight away, with the store's real progress.
            NavigationStack(path: $router.path) {
                destination(for: .campaign, catalog: catalog)
                    .navigationDestination(for: Route.self) { route in
                        destination(for: route, catalog: catalog)
                    }
            }
            .environment(router)
            .environment(\.frontTransition, frontTransition)
        } else if let catalog, let screen = DirectLaunch.current, let front = directLaunchFront(screen, catalog) {
            NavigationStack(path: $router.path) {
                directLaunchView(screen, front: front, catalog: catalog)
                    .navigationDestination(for: Route.self) { route in
                        destination(for: route, catalog: catalog)
                    }
            }
            .environment(router)
            .environment(\.frontTransition, frontTransition)
        } else if let catalog {
            NavigationStack(path: $router.path) {
                HomeView(
                    model: HomeModel(
                        nextFront: CampaignModel(fronts: fronts(catalog)).currentFront,
                        lastBattle: lastBattle(catalog).map { ($0.levelID, $0.config) }))
                    .navigationDestination(for: Route.self) { route in
                        destination(for: route, catalog: catalog)
                    }
            }
            .environment(router)
            .environment(\.frontTransition, frontTransition)
        } else {
            contentLoadFailed
        }
    }

    @ViewBuilder
    private func destination(for route: Route, catalog: ContentCatalog) -> some View {
        switch route {
        case .campaign:
            CampaignView(model: CampaignModel(fronts: fronts(catalog)), loadFronts: { fronts(catalog) })
        case .settings:
            SettingsView(model: SettingsModel(audio: AudioService.shared))
        case .armySetup(let front):
            if let map = catalog.map(front.map) {
                ArmySetupView(
                    front: front,
                    model: ArmySetupModel(
                        map: map, catalog: catalog.units, totalBudget: front.playerBudget,
                        constraintBadge: front.constraintBadge,
                        enemyPlacements: catalog.level(front.id)?.enemy.placements ?? [],
                        audio: AudioService.shared))
                // The front's table opens out of its pin on the campaign line.
                .navigationTransition(.zoom(sourceID: front.id, in: frontTransition))
            } else {
                contentLoadFailed
            }
        case .ruleEditor(let front, let playerSetup):
            if let level = catalog.level(front.id), let map = catalog.map(level.map) {
                let placedTypes = Set(playerSetup.placements.map(\.type))
                let unitTypes = catalog.units.map(\.id).filter { placedTypes.contains($0) }
                let enemyTypes = Set(level.enemy.placements.map(\.type))
                if unitTypes.isEmpty {
                    contentLoadFailed
                } else {
                    RuleEditorView(
                        model: RuleEditorModel(
                            unitTypes: unitTypes, catalog: catalog.units, constraints: level.constraints,
                            enemyUnitTypes: catalog.units.map(\.id).filter { enemyTypes.contains($0) },
                            audio: AudioService.shared),
                        battleSetup: RuleEditorView.BattleSetup(
                            front: front, level: level, map: map, catalog: catalog, placements: playerSetup.placements))
                }
            } else {
                contentLoadFailed
            }
        case .battle(let config, let front):
            BattleView(
                config: config, orders: orderStackItems(for: config), phrases: orderPhrases(for: config),
                tutorialFront: front?.id
            ) { result in
                if let front {
                    do {
                        try progress?.recordBattle(levelID: front.id, config: config, result: result)
                    } catch {
                        Self.logger.error("Couldn't record battle: \(error, privacy: .public)")
                    }
                }
                router.push(.debrief(config, result, front: front))
            }
        case .debrief(let config, let result, let front):
            let next = front.flatMap { current in
                fronts(catalog).first { $0.id == current.id + 1 && $0.state != .locked }
            }
            DebriefView(
                model: DebriefModel(config: config, result: result),
                onFixOrders: { router.pop(2) },
                onReview: { tick in
                    router.replayRequest = tick
                    router.pop(1)
                },
                onNextFront: next.map { next in { router.path = [.campaign, .armySetup(next)] } }
            )
        }
    }

    /// The intro choreography's stamped stack (F1.5): every unit type's program, each under its own
    /// heading — stamping only the first type's (as F1.5 did) sealed half the army's orders out of
    /// sight. Building `OrderStack.Item` (MainActor-isolated, like every other type in this app
    /// target) has to happen here rather than in `OrderPhraseFormatter`, which stays `nonisolated`
    /// on purpose.
    private func orderStackItems(for config: BattleConfig) -> [OrderStack.Item] {
        let phrases = orderPhrases(for: config)
        return config.player.programs.flatMap { phrases[$0.unitType] ?? [] }
    }

    /// Each of the player's programs as order cards, by unit type (the trigger strip, the tapped unit's
    /// bubble, and — flattened — the intro's stamped stack).
    private func orderPhrases(for config: BattleConfig) -> [UnitTypeID: [OrderStack.Item]] {
        var phrases: [UnitTypeID: [OrderStack.Item]] = [:]
        for program in config.player.programs {
            let ability = config.unitCatalog.first { $0.id == program.unitType }?.ability
            let heading = OrderPhraseFormatter.unitTypeName(program.unitType)
            phrases[program.unitType] = program.rules.enumerated().map { index, rule in
                OrderStack.Item(
                    priority: index + 1,
                    condition: OrderPhraseFormatter.condition(rule.condition),
                    action: OrderPhraseFormatter.action(rule.action, ability: ability),
                    state: index == program.rules.count - 1 ? .isDefault : .normal,
                    groupTitle: heading)
            }
        }
        return phrases
    }

    // MARK: - Direct launch (UI tests, screenshots)

    /// `-uiTestBattle <level>` / `-uiTestArmySetup <level>` / `-uiTestDebrief <level>` open that
    /// level's battle (its reference solution against its enemy), army setup, or debrief directly — a
    /// screen a test or a screenshot can reach without walking Home → Campaign by touch, which this
    /// machine's simulator can't automate.
    private enum DirectLaunch {
        case battle(level: Int)
        case armySetup(level: Int)
        case debrief(level: Int)

        static var current: DirectLaunch? {
            let defaults = UserDefaults.standard
            if defaults.integer(forKey: "uiTestBattle") > 0 {
                return .battle(level: defaults.integer(forKey: "uiTestBattle"))
            }
            if defaults.integer(forKey: "uiTestDebrief") > 0 {
                return .debrief(level: defaults.integer(forKey: "uiTestDebrief"))
            }
            if defaults.integer(forKey: "uiTestArmySetup") > 0 {
                return .armySetup(level: defaults.integer(forKey: "uiTestArmySetup"))
            }
            return nil
        }

        var level: Int {
            switch self {
            case .battle(let level), .armySetup(let level), .debrief(let level): level
            }
        }
    }

    private func directLaunchFront(_ screen: DirectLaunch, _ catalog: ContentCatalog) -> CampaignFront? {
        CampaignFront.fronts(from: catalog, unlockAll: true).first { $0.id == screen.level }
    }

    /// The level's reference solution against its enemy, as a `BattleConfig` — shared by the `.battle`
    /// and `.debrief` direct-launch entries below.
    private func referenceConfig(front: CampaignFront, catalog: ContentCatalog) -> BattleConfig? {
        guard let level = catalog.level(front.id), let map = catalog.map(level.map) else { return nil }
        return BattleConfig(
            map: map, unitCatalog: catalog.units, player: level.referenceSolution, enemy: level.enemy,
            objective: level.objective, constraints: level.constraints, seed: level.seed, maxTicks: level.maxTicks)
    }

    @ViewBuilder
    private func directLaunchView(_ screen: DirectLaunch, front: CampaignFront, catalog: ContentCatalog) -> some View {
        switch screen {
        case .battle:
            if let config = referenceConfig(front: front, catalog: catalog) {
                destination(for: .battle(config, front: front), catalog: catalog)
            } else {
                contentLoadFailed
            }
        case .debrief:
            // `-uiTestDebrief <level>`: the reference battle's debrief, simulated off the main actor first.
            if let config = referenceConfig(front: front, catalog: catalog) {
                DirectDebrief(config: config) { result in
                    destination(for: .debrief(config, result, front: front), catalog: catalog)
                }
            } else {
                contentLoadFailed
            }
        case .armySetup:
            // `-uiTestArmySetupPlaced YES`: the zone already holds the level's reference army and a tray
            // unit is in hand, so a screenshot shows placed figures and the unit brief.
            if UserDefaults.standard.bool(forKey: "uiTestArmySetupPlaced"), let level = catalog.level(front.id),
                let map = catalog.map(front.map)
            {
                let model = ArmySetupModel(
                    map: map, catalog: catalog.units, totalBudget: front.playerBudget,
                    constraintBadge: front.constraintBadge, enemyPlacements: level.enemy.placements,
                    initialPlacements: level.referenceSolution.placements)
                let _ = model.chooseTrayUnit(catalog.units.first?.id ?? "")
                ArmySetupView(front: front, model: model)
            } else {
                destination(for: .armySetup(front), catalog: catalog)
            }
        }
    }

    private var contentLoadFailed: some View {
        Text(String(localized: "İçerik yüklenemedi."))
            .font(FermanFont.body())
            .foregroundStyle(Color.paper)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ink)
    }

    /// A filled stack for screenshots: the archer's second order is folded under its first.
    private static let sampleOrders = [
        RuleProgram(
            unitType: "okcu",
            rules: [
                Rule(condition: .enemyWithin(cells: 4), action: .retreat),
                Rule(condition: .healthBelow(percent: 35), action: .takeCover),
                Rule(condition: .enemyWithin(cells: 2), action: .hold),
                Rule(condition: .always, action: .advance),
            ])
    ]

    private static func ruleEditorFixture(programs: [RuleProgram] = []) -> RuleEditorModel {
        let archer: UnitTypeID = "okcu"
        let shield: UnitTypeID = "kalkan"
        let catalog: [UnitType] = [
            UnitType(
                id: archer, cost: 30, maxHP: 70, speedMilliCellsPerSecond: 1_000, rangeMilliCells: 6_000,
                damage: 10, attackIntervalTicks: 36, armor: 0, moraleMax: 90, counters: [], ability: .volley),
            UnitType(
                id: shield, cost: 30, maxHP: 160, speedMilliCellsPerSecond: 900, rangeMilliCells: 1_000,
                damage: 8, attackIntervalTicks: 30, armor: 4, moraleMax: 120, counters: [], ability: .shieldWall),
        ]
        return RuleEditorModel(
            unitTypes: [archer, shield], catalog: catalog, constraints: .unrestricted, initialPrograms: programs,
            audio: AudioService.shared)
    }
}

#Preview {
    ContentView()
}

/// Runs a battle once, then shows what's built from its result — `-uiTestDebrief`'s way in.
private struct DirectDebrief<Content: View>: View {
    let config: BattleConfig
    @ViewBuilder let content: (BattleResult) -> Content
    @State private var result: BattleResult?

    var body: some View {
        Group {
            if let result {
                content(result)
            } else {
                Color.ink.ignoresSafeArea()
            }
        }
        .task { result = await BattleRunner().run(config) }
    }
}
