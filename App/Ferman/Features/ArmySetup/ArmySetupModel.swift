import FermanCore
import Foundation
import Observation

/// UI identity for a placement (D7-style rationale: `UnitPlacement` carries no id, position in an
/// array is not stable identity for SwiftUI).
struct ArmyPlacement: Identifiable, Sendable, Hashable {
    let id: UUID
    var unitType: UnitTypeID
    var cell: Int
    var isCommander: Bool

    init(id: UUID = UUID(), unitType: UnitTypeID, cell: Int, isCommander: Bool = false) {
        self.id = id
        self.unitType = unitType
        self.cell = cell
        self.isCommander = isCommander
    }
}

/// A level's constraint badge, shown but not enforced (F1.8 — "Sis gösterimi" is display only; the
/// gameplay effect a card like Sis describes, hiding the enemy's composition, is a Faz 3 mechanic,
/// F3.2). No `ConstraintCard` type exists in `FermanCore` yet, so this is a plain label pair rather
/// than something read off real level content.
struct ArmyConstraintBadge: Sendable, Hashable {
    let title: String
    let detail: String
}

/// Placing units in the player's zone and picking a commander before writing orders (design brief
/// §4.3). Only the player's zone is shown, never the enemy's.
@Observable
@MainActor
final class ArmySetupModel {
    let map: BattleMap
    let catalog: [UnitType]
    let totalBudget: Int
    let constraintBadge: ArmyConstraintBadge?

    /// The player zone's bounding rectangle — the "sol üçte biri" of the sand table the brief
    /// describes, not the whole map.
    let gridColumns: ClosedRange<Int>
    let gridRows: ClosedRange<Int>

    private(set) var placements: [ArmyPlacement]
    var selectedPlacementID: ArmyPlacement.ID?

    init(
        map: BattleMap,
        catalog: [UnitType],
        totalBudget: Int,
        constraintBadge: ArmyConstraintBadge? = nil,
        initialPlacements: [UnitPlacement] = []
    ) {
        self.map = map
        self.catalog = catalog
        self.totalBudget = totalBudget
        self.constraintBadge = constraintBadge
        self.placements = initialPlacements.map {
            ArmyPlacement(unitType: $0.type, cell: $0.cell, isCommander: $0.isCommander)
        }

        let coordinates = map.zone(for: .player).map(map.coordinates(ofCell:))
        let columns = coordinates.map(\.column)
        let rows = coordinates.map(\.row)
        self.gridColumns = (columns.min() ?? 0)...(columns.max() ?? 0)
        self.gridRows = (rows.min() ?? 0)...(rows.max() ?? 0)
    }

    // MARK: - Derived state

    func unitType(_ id: UnitTypeID) -> UnitType? {
        catalog.first { $0.id == id }
    }

    /// Every placed unit's `cost` — the budget the design brief's "Bütçe 248 / 310" shows. Not the
    /// army-wide rule budget (D4), which is a different number the rule editor tracks.
    var usedBudget: Int {
        placements.compactMap { unitType($0.unitType)?.cost }.reduce(0, +)
    }

    var isOverBudget: Bool { usedBudget > totalBudget }

    func isPlayerZone(_ cell: Int) -> Bool {
        map.zone(for: .player).contains(cell)
    }

    func placement(at cell: Int) -> ArmyPlacement? {
        placements.first { $0.cell == cell }
    }

    func canPlace(at cell: Int) -> Bool {
        isPlayerZone(cell) && placement(at: cell) == nil
    }

    var commander: ArmyPlacement? {
        placements.first { $0.isCommander }
    }

    var teamSetup: TeamSetup {
        TeamSetup(
            placements: placements.map { UnitPlacement(type: $0.unitType, cell: $0.cell, isCommander: $0.isCommander) },
            programs: [])
    }

    // MARK: - Intents

    func place(_ unitType: UnitTypeID, at cell: Int) {
        guard canPlace(at: cell) else { return }
        placements.append(ArmyPlacement(unitType: unitType, cell: cell))
    }

    func remove(_ id: ArmyPlacement.ID) {
        placements.removeAll { $0.id == id }
        if selectedPlacementID == id { selectedPlacementID = nil }
    }

    func toggleSelection(_ id: ArmyPlacement.ID) {
        selectedPlacementID = selectedPlacementID == id ? nil : id
    }

    /// At most one commander per army — `UnitPlacement.isCommander` documents that but doesn't
    /// enforce it (`FermanCore` just reads the first one it finds); this is where it's enforced.
    func setCommander(_ id: ArmyPlacement.ID) {
        guard placements.contains(where: { $0.id == id }) else { return }
        for index in placements.indices {
            placements[index].isCommander = placements[index].id == id
        }
    }

    func clearCommander(_ id: ArmyPlacement.ID) {
        guard let index = placements.firstIndex(where: { $0.id == id }) else { return }
        placements[index].isCommander = false
    }
}
