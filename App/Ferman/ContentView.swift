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
                        constraintBadge: front.constraintBadge))
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
        case .battle(let config):
            BattleView(config: config, orders: orderStackItems(for: config)) { result in
                router.push(.debrief(config, result))
            }
        case .debrief(let config, let result):
            DebriefView(model: DebriefModel(config: config, result: result)) {
                router.pop(2)
            }
        }
    }

    /// The intro choreography's stamped stack (F1.5): every unit type's program, each under its own
    /// heading — stamping only the first type's (as F1.5 did) sealed half the army's orders out of
    /// sight. Building `OrderStack.Item` (MainActor-isolated, like every other type in this app
    /// target) has to happen here rather than in `OrderPhraseFormatter`, which stays `nonisolated`
    /// on purpose.
    private func orderStackItems(for config: BattleConfig) -> [OrderStack.Item] {
        config.player.programs.flatMap { program in
            let ability = config.unitCatalog.first { $0.id == program.unitType }?.ability
            let heading = OrderPhraseFormatter.unitTypeName(program.unitType)
            return program.rules.enumerated().map { index, rule in
                OrderStack.Item(
                    priority: index + 1,
                    condition: OrderPhraseFormatter.condition(rule.condition),
                    action: OrderPhraseFormatter.action(rule.action, ability: ability),
                    state: index == program.rules.count - 1 ? .isDefault : .normal,
                    groupTitle: heading)
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

    private static func ruleEditorFixture() -> RuleEditorModel {
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
            unitTypes: [archer, shield], catalog: catalog, constraints: .unrestricted, audio: AudioService.shared)
    }
}

#Preview {
    ContentView()
}
