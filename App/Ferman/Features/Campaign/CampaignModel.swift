import FermanContent
import FermanCore
import Foundation
import Observation

/// A front-line pin on the campaign line (design brief §4.2). `FermanContent` carries no level data
/// yet (that joins in F1.12) and there is no `ProgressStore` (F1.11) to say which fronts a player has
/// actually cleared — this is a small fixed list, enough to exercise real navigation and the level
/// sheet's layout, not tuned content. Numbers mirror the brief's own mockup (420 vs. 310 puan) for the
/// one front that is `.open`.
struct CampaignFront: Identifiable, Sendable, Hashable {
    let id: Int
    let title: String
    let map: MapID
    let enemyBudget: Int
    let playerBudget: Int
    let ruleBudget: Int
    let constraintBadge: ArmyConstraintBadge?
    let state: FrontFlagState
    /// What the enemy fields, by unit type — shown on the level sheet as iron figures (hidden under Sis).
    var enemyComposition: [UnitCount] = []
    /// One line from the officer about what this front asks of the player.
    var briefing: String = ""
    /// Order forms this front makes available that the one before it didn't — the "sealed dispatch".
    var newOrders: [String] = []
}

struct UnitCount: Sendable, Hashable {
    let type: UnitTypeID
    let count: Int
}

extension CampaignFront {
    /// Titles for the 8 real levels `FermanContent` ships (F1.12) — `LevelDefinition` carries no
    /// display name of its own (same reasoning as `UnitType.id`, D19), and nothing here reads a
    /// `level.<id>` String Catalog key yet, so these are plain literals rather than a lookup.
    private static let titles: [Int: String] = [
        1: String(localized: "İlk Tepe"),
        2: String(localized: "Kum Sırtı"),
        3: String(localized: "Taş Geçit"),
        4: String(localized: "Kuru Vadi"),
        5: String(localized: "Demir Kapı"),
        6: String(localized: "Kızıl Yamaç"),
        7: String(localized: "Son Hat"),
        8: String(localized: "Kara Boğaz"),
    ]

    /// One line per front from the officer (brief §7: calm, no cheering): what to watch for, never
    /// the answer.
    private static let briefings: [Int: String] = [
        1: String(localized: "Bu cephede emir yazılmaz. Askerlerinin kendi başına ne yaptığını izle."),
        2: String(localized: "Kalkanlılar yavaştır. Okçuların onları yakına sokmamalı."),
        3: String(localized: "Yaralanan okçu ne yapsın? Emirlerin sırası önemli."),
        4: String(localized: "Bir kol yerinde dursun, öbürü vursun."),
        5: String(localized: "İlk karma ordu. Mızrakçı süvariyi karşılar."),
        6: String(localized: "Düşman büyüdü. Her tipe kendi emrini yaz."),
        7: String(localized: "Kanatlar ağırlaştı. Kimin kimi karşılayacağını baştan düşün."),
        8: String(localized: "Son hat. Düşman her şeyiyle geliyor."),
    ]

    /// Real fronts, one per `ContentCatalog.levels` entry, in order. A front is cleared once the player
    /// has won it (`bestOutcome`, from `ProgressStore`), open if it's the first or follows a cleared
    /// one, and locked otherwise — unless `unlockAll` (no progress store, or a UI-test sandbox).
    static func fronts(
        from catalog: ContentCatalog, bestOutcome: (Int) -> BattleOutcome? = { _ in nil }, unlockAll: Bool = false
    ) -> [CampaignFront] {
        let costByUnitType = Dictionary(uniqueKeysWithValues: catalog.units.map { ($0.id, $0.cost) })
        var previousCleared = true
        var previousConditions: Set<ConditionKind> = [.always]
        var previousActions: Set<ActionKind> = []
        return catalog.levels.sorted { $0.id < $1.id }.map { level in
            let enemyBudget = level.enemy.placements.reduce(0) { $0 + (costByUnitType[$1.type] ?? 0) }
            let cleared = bestOutcome(level.id) == .playerWin
            let state: FrontFlagState = cleared ? .cleared : (unlockAll || previousCleared ? .open : .locked)
            let counts = Dictionary(grouping: level.enemy.placements, by: \.type).mapValues(\.count)
            let composition = catalog.units.compactMap { unit in
                counts[unit.id].map { UnitCount(type: unit.id, count: $0) }
            }
            let newConditions = level.constraints.availableConditions.filter { !previousConditions.contains($0) }
            let newActions = level.constraints.availableActions.filter { !previousActions.contains($0) }
            // The first front's single order is the default everyone starts with — nothing "new" to announce.
            let newOrders =
                level.id == catalog.levels.map(\.id).min()
                ? []
                : newConditions.map(RulePickerSheet.conditionKindLabel) + newActions.map(RulePickerSheet.actionKindLabel)
            defer {
                previousCleared = cleared
                previousConditions.formUnion(level.constraints.availableConditions)
                previousActions.formUnion(level.constraints.availableActions)
            }
            return CampaignFront(
                id: level.id,
                title: titles[level.id] ?? String(localized: "\(level.id). Cephe"),
                map: level.map,
                enemyBudget: enemyBudget,
                playerBudget: level.playerBudget,
                ruleBudget: level.constraints.maxRules,
                constraintBadge: nil,
                state: state,
                enemyComposition: composition,
                briefing: briefings[level.id] ?? "",
                newOrders: newOrders)
        }
    }

    static let placeholders: [CampaignFront] = [
        CampaignFront(
            id: 1, title: String(localized: "İlk Tepe"), map: "ova", enemyBudget: 120, playerBudget: 150,
            ruleBudget: 3, constraintBadge: nil, state: .cleared),
        CampaignFront(
            id: 2, title: String(localized: "Kum Sırtı"), map: "ova", enemyBudget: 260, playerBudget: 260,
            ruleBudget: 4, constraintBadge: nil, state: .cleared),
        CampaignFront(
            id: 3, title: String(localized: "Taş Geçit"), map: "ova", enemyBudget: 420, playerBudget: 310,
            ruleBudget: 6,
            constraintBadge: ArmyConstraintBadge(
                title: String(localized: "Sis"), detail: String(localized: "düşman kompozisyonu gizli")),
            state: .open),
        CampaignFront(
            id: 4, title: String(localized: "Demir Kapı"), map: "ova", enemyBudget: 480, playerBudget: 320,
            ruleBudget: 6, constraintBadge: nil, state: .locked),
        CampaignFront(
            id: 5, title: String(localized: "Son Hat"), map: "ova", enemyBudget: 560, playerBudget: 340,
            ruleBudget: 8, constraintBadge: nil, state: .locked),
    ]
}

/// Cephe (design brief §4.2) — the campaign line the player scrolls through and picks a front from.
@Observable
@MainActor
final class CampaignModel {
    private(set) var fronts: [CampaignFront]

    init(fronts: [CampaignFront] = CampaignFront.placeholders) {
        self.fronts = fronts
    }

    /// Re-read after a battle: coming back to the line, a won front shows cleared and the next opens.
    func update(fronts: [CampaignFront]) {
        self.fronts = fronts
    }

    func canOpen(_ front: CampaignFront) -> Bool {
        front.state != .locked
    }

    /// The front to play next: the first one open and not yet cleared.
    var currentFront: CampaignFront? {
        fronts.first { $0.state == .open }
    }

    var clearedCount: Int {
        fronts.filter { $0.state == .cleared }.count
    }
}
