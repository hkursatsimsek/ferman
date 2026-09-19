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
    private let catalog: ContentCatalog?

    init() {
        do {
            catalog = try ContentCatalog.bundled()
        } catch {
            Self.logger.critical("Failed to load bundled content: \(error, privacy: .public)")
            catalog = nil
        }
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
        } else if let catalog, let screen = DirectLaunch.current, let front = directLaunchFront(screen, catalog) {
            NavigationStack(path: $router.path) {
                directLaunchView(screen, front: front, catalog: catalog)
                    .navigationDestination(for: Route.self) { route in
                        destination(for: route, catalog: catalog)
                    }
            }
            .environment(router)
        } else if let catalog {
            NavigationStack(path: $router.path) {
                HomeView(model: HomeModel(nextFront: CampaignFront.fronts(from: catalog).first))
                    .navigationDestination(for: Route.self) { route in
                        destination(for: route, catalog: catalog)
                    }
            }
            .environment(router)
        } else {
            contentLoadFailed
        }
    }

    @ViewBuilder
    private func destination(for route: Route, catalog: ContentCatalog) -> some View {
        switch route {
        case .campaign:
            CampaignView(model: CampaignModel(fronts: CampaignFront.fronts(from: catalog)))
        case .armySetup(let front):
            if let map = catalog.map(front.map) {
                ArmySetupView(
                    front: front,
                    model: ArmySetupModel(
                        map: map, catalog: catalog.units, totalBudget: front.playerBudget,
                        constraintBadge: front.constraintBadge,
                        enemyPlacements: catalog.level(front.id)?.enemy.placements ?? []))
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
            BattleView(config: config, orders: orderStackItems(for: config), phrases: orderPhrases(for: config)) {
                result in
                router.push(.debrief(config, result, front: front))
            }
        case .debrief(let config, let result, let front):
            let next = front.flatMap { current in
                CampaignFront.fronts(from: catalog).first { $0.id == current.id + 1 }
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

    /// `-uiTestBattle <level>` / `-uiTestArmySetup <level>` open that level's battle (its reference
    /// solution against its enemy) or army setup directly — a screen a test or a screenshot can reach
    /// without walking Home → Campaign by touch, which this machine's simulator can't automate.
    private enum DirectLaunch {
        case battle(level: Int)
        case armySetup(level: Int)

        static var current: DirectLaunch? {
            let defaults = UserDefaults.standard
            if defaults.integer(forKey: "uiTestBattle") > 0 {
                return .battle(level: defaults.integer(forKey: "uiTestBattle"))
            }
            if defaults.integer(forKey: "uiTestArmySetup") > 0 {
                return .armySetup(level: defaults.integer(forKey: "uiTestArmySetup"))
            }
            return nil
        }

        var level: Int {
            switch self {
            case .battle(let level), .armySetup(let level): level
            }
        }
    }

    private func directLaunchFront(_ screen: DirectLaunch, _ catalog: ContentCatalog) -> CampaignFront? {
        CampaignFront.fronts(from: catalog).first { $0.id == screen.level }
    }

    @ViewBuilder
    private func directLaunchView(_ screen: DirectLaunch, front: CampaignFront, catalog: ContentCatalog) -> some View {
        switch screen {
        case .battle:
            if let level = catalog.level(front.id), let map = catalog.map(level.map) {
                let config = BattleConfig(
                    map: map, unitCatalog: catalog.units, player: level.referenceSolution, enemy: level.enemy,
                    objective: level.objective, constraints: level.constraints, seed: level.seed,
                    maxTicks: level.maxTicks)
                destination(for: .battle(config, front: front), catalog: catalog)
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
