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

    /// Real fronts, one per `ContentCatalog.levels` entry. Every front is `.open`: `ProgressStore`
    /// (F1.11) isn't wired to any screen yet, so there is no real "cleared" signal to gate a lock/
    /// unlock sequence on — that join is separate, later work, not this step's.
    static func fronts(from catalog: ContentCatalog) -> [CampaignFront] {
        let costByUnitType = Dictionary(uniqueKeysWithValues: catalog.units.map { ($0.id, $0.cost) })
        return catalog.levels.map { level in
            let enemyBudget = level.enemy.placements.reduce(0) { $0 + (costByUnitType[$1.type] ?? 0) }
            return CampaignFront(
                id: level.id,
                title: titles[level.id] ?? String(localized: "\(level.id). Cephe"),
                map: level.map,
                enemyBudget: enemyBudget,
                playerBudget: level.playerBudget,
                ruleBudget: level.constraints.maxRules,
                constraintBadge: nil,
                state: .open)
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
    let fronts: [CampaignFront]

    init(fronts: [CampaignFront] = CampaignFront.placeholders) {
        self.fronts = fronts
    }

    func canOpen(_ front: CampaignFront) -> Bool {
        front.state != .locked
    }
}
