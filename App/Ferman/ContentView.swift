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
        // FermanUITests still reaches RuleEditorView directly through this launch argument — it
        // isn't a stop on the real navigation graph below (RuleEditor needs an army's unit types,
        // which only exist once ArmySetup has placements; that hop isn't wired yet).
        if ProcessInfo.processInfo.arguments.contains("-uiTestRuleEditor") {
            RuleEditorView(model: Self.ruleEditorFixture())
        } else if let catalog {
            NavigationStack(path: $router.path) {
                HomeView(model: HomeModel(nextFront: CampaignFront.placeholders.first { $0.state == .open }))
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
            CampaignView(model: CampaignModel())
        case .armySetup(let front):
            if let map = catalog.map(front.map) {
                ArmySetupView(
                    model: ArmySetupModel(
                        map: map, catalog: catalog.units, totalBudget: front.playerBudget,
                        constraintBadge: front.constraintBadge))
            } else {
                contentLoadFailed
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
