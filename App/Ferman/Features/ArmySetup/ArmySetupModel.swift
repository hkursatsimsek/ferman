import CoreGraphics
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
/// §4.3). The whole upright table is shown (D26) — the enemy's figures stand at the top, unless a
/// level hides them (Sis, F3.2).
@Observable
@MainActor
final class ArmySetupModel {
    let map: BattleMap
    let catalog: [UnitType]
    let totalBudget: Int
    let constraintBadge: ArmyConstraintBadge?
    /// Where the enemy stands — shown, not editable.
    let enemyPlacements: [UnitPlacement]

    /// The player zone's bounding rectangle — the part of the table the brief's §4.3 is about; the
    /// view marks it out and scrolls to it.
    let gridColumns: ClosedRange<Int>
    let gridRows: ClosedRange<Int>

    /// The baked sand table (`TerrainBaker`) — the same picture the battle draws, so the ground a unit
    /// is placed on is the ground it fights on.
    let tableImage: CGImage?

    private(set) var placements: [ArmyPlacement]
    var selectedPlacementID: ArmyPlacement.ID?
    /// The tray unit picked up for tap-to-place — a second way to place besides dragging, and the one
    /// that works without fine drag control (Apple HIG: offer a non-drag alternative).
    private(set) var chosenTrayUnit: UnitTypeID?

    /// Counts figures set down on the table — placed or moved — for the view's haptic.
    private(set) var setDownCount = 0

    /// A figure set down (or moved) clinks on the table (ART-DIRECTION §7, "Figür bırakma: Metal").
    private let audio: any AudioPlaying

    init(
        map: BattleMap,
        catalog: [UnitType],
        totalBudget: Int,
        constraintBadge: ArmyConstraintBadge? = nil,
        enemyPlacements: [UnitPlacement] = [],
        initialPlacements: [UnitPlacement] = [],
        audio: any AudioPlaying = SilentAudioPlaying()
    ) {
        self.audio = audio
        self.map = map
        self.catalog = catalog
        self.totalBudget = totalBudget
        self.constraintBadge = constraintBadge
        self.enemyPlacements = enemyPlacements
        self.placements = initialPlacements.map {
            ArmyPlacement(unitType: $0.type, cell: $0.cell, isCommander: $0.isCommander)
        }

        let coordinates = map.zone(for: .player).map(map.coordinates(ofCell:))
        let columns = coordinates.map(\.column)
        let rows = coordinates.map(\.row)
        self.gridColumns = (columns.min() ?? 0)...(columns.max() ?? 0)
        self.gridRows = (rows.min() ?? 0)...(rows.max() ?? 0)
        self.tableImage = TerrainBaker.bake(
            map: map, projection: .table(for: map), pixelsPerPoint: TerrainBaker.battlePixelsPerPoint)
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

    /// Whether one more unit of this type still fits the budget. Placing is refused past it (the
    /// F1.8 version only turned the meter red, which let an over-budget army reach battle).
    func canAfford(_ unitTypeID: UnitTypeID) -> Bool {
        guard let cost = unitType(unitTypeID)?.cost else { return false }
        return usedBudget + cost <= totalBudget
    }

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

    /// Returns whether the unit was placed, so the view can answer a refused drop (occupied cell,
    /// outside the zone, or over budget) with feedback instead of silently dropping it.
    @discardableResult
    func place(_ unitType: UnitTypeID, at cell: Int) -> Bool {
        guard canPlace(at: cell), canAfford(unitType) else { return false }
        placements.append(ArmyPlacement(unitType: unitType, cell: cell))
        setDown()
        return true
    }

    /// Picks a tray unit up for tap-to-place, or puts it back if it was already in hand.
    func chooseTrayUnit(_ unitType: UnitTypeID) {
        chosenTrayUnit = chosenTrayUnit == unitType ? nil : unitType
    }

    /// A tap on a zone cell: places the chosen tray unit on an empty cell, or selects the unit already
    /// standing there. Returns whether a unit was placed.
    @discardableResult
    func tapCell(_ cell: Int) -> Bool {
        if let placed = placement(at: cell) {
            toggleSelection(placed.id)
            return false
        }
        guard let chosenTrayUnit else { return false }
        return place(chosenTrayUnit, at: cell)
    }

    /// Moves a placed unit to another free cell of the zone. Returns whether it moved.
    @discardableResult
    func move(_ id: ArmyPlacement.ID, to cell: Int) -> Bool {
        guard canPlace(at: cell), let index = placements.firstIndex(where: { $0.id == id }) else { return false }
        placements[index].cell = cell
        setDown()
        return true
    }

    private func setDown() {
        setDownCount += 1
        audio.play(.place)
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
