//
//  ContentView.swift
//  Ferman
//
//  Created by Hamza Kürşat Şimşek on 15.09.2026.
//

import FermanCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        // No AppRouter/navigation exists yet (F1.9); FermanUITests reaches RuleEditorView through
        // this launch argument until real navigation supersedes it.
        if ProcessInfo.processInfo.arguments.contains("-uiTestRuleEditor") {
            RuleEditorView(model: Self.ruleEditorFixture())
        } else {
            TokenReferenceView()
        }
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
        return RuleEditorModel(unitTypes: [archer, shield], catalog: catalog, constraints: .unrestricted)
    }
}

#Preview {
    ContentView()
}
