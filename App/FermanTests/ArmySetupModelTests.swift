import FermanCore
import Testing

@testable import Ferman

@MainActor
struct ArmySetupModelTests {
    private static let archer: UnitTypeID = "okcu"
    private static let shield: UnitTypeID = "kalkan"

    private static let catalog: [UnitType] = [
        UnitType(
            id: archer, cost: 30, maxHP: 70, speedMilliCellsPerSecond: 1_000, rangeMilliCells: 6_000, damage: 10,
            attackIntervalTicks: 36, armor: 0, moraleMax: 90, counters: [], ability: .volley),
        UnitType(
            id: shield, cost: 40, maxHP: 160, speedMilliCellsPerSecond: 900, rangeMilliCells: 1_000, damage: 8,
            attackIntervalTicks: 30, armor: 4, moraleMax: 120, counters: [], ability: .shieldWall),
    ]

    private static func map() throws -> BattleMap {
        // 4 wide x 3 tall; player zone is the left column, enemy zone the right column.
        try BattleMap(terrainRows: ["....", "....", "...."], zoneRows: ["P..E", "P..E", "P..E"])
    }

    private static func makeModel(
        totalBudget: Int = 100, constraintBadge: ArmyConstraintBadge? = nil, initialPlacements: [UnitPlacement] = []
    ) throws -> ArmySetupModel {
        ArmySetupModel(
            map: try map(), catalog: catalog, totalBudget: totalBudget, constraintBadge: constraintBadge,
            initialPlacements: initialPlacements)
    }

    @Test
    func computesTheGridBoundsFromThePlayerZoneOnly() throws {
        let model = try Self.makeModel()

        // Player zone is column 0, rows 0...2 — the enemy's column 3 must not leak in.
        #expect(model.gridColumns == 0...0)
        #expect(model.gridRows == 0...2)
    }

    @Test
    func decomposesInitialPlacements() throws {
        let placement = UnitPlacement(type: Self.archer, cell: 4, isCommander: true)
        let model = try Self.makeModel(initialPlacements: [placement])

        #expect(model.placements.map(\.unitType) == [Self.archer])
        #expect(model.placements[0].cell == 4)
        #expect(model.placements[0].isCommander == true)
    }

    @Test
    func placingInsideAnEmptyPlayerZoneCellSucceeds() throws {
        let model = try Self.makeModel()

        model.place(Self.archer, at: 4)

        #expect(model.placement(at: 4)?.unitType == Self.archer)
        #expect(model.usedBudget == 30)
    }

    @Test
    func placingOutsideThePlayerZoneFails() throws {
        let model = try Self.makeModel()

        model.place(Self.archer, at: 3)  // enemy zone

        #expect(model.placements.isEmpty)
    }

    @Test
    func placingOnAnOccupiedCellFails() throws {
        let model = try Self.makeModel()
        model.place(Self.archer, at: 4)

        model.place(Self.shield, at: 4)

        #expect(model.placements.count == 1)
        #expect(model.placement(at: 4)?.unitType == Self.archer)
    }

    @Test
    func usedBudgetSumsPlacedUnitCosts() throws {
        let model = try Self.makeModel()
        model.place(Self.archer, at: 0)
        model.place(Self.shield, at: 4)

        #expect(model.usedBudget == 70)
        #expect(model.isOverBudget == false)
    }

    @Test
    func exceedingTheBudgetIsFlaggedButNotBlocked() throws {
        let model = try Self.makeModel(totalBudget: 50)
        model.place(Self.archer, at: 0)
        model.place(Self.shield, at: 4)

        #expect(model.usedBudget == 70)
        #expect(model.isOverBudget == true)
    }

    @Test
    func onlyOneUnitCanBeCommanderAtATime() throws {
        let model = try Self.makeModel()
        model.place(Self.archer, at: 0)
        model.place(Self.shield, at: 4)
        let firstID = model.placements[0].id
        let secondID = model.placements[1].id

        model.setCommander(firstID)
        #expect(model.commander?.id == firstID)

        model.setCommander(secondID)
        #expect(model.commander?.id == secondID)
        #expect(model.placements.first { $0.id == firstID }?.isCommander == false)
    }

    @Test
    func clearingTheCommanderLeavesNoneSelected() throws {
        let model = try Self.makeModel()
        model.place(Self.archer, at: 0)
        let id = model.placements[0].id
        model.setCommander(id)

        model.clearCommander(id)

        #expect(model.commander == nil)
    }

    @Test
    func removingAPlacementClearsItsSelection() throws {
        let model = try Self.makeModel()
        model.place(Self.archer, at: 0)
        let id = model.placements[0].id
        model.toggleSelection(id)

        model.remove(id)

        #expect(model.placements.isEmpty)
        #expect(model.selectedPlacementID == nil)
    }

    @Test
    func teamSetupRoundTripsPlacementsWithNoPrograms() throws {
        let model = try Self.makeModel()
        model.place(Self.archer, at: 0)
        let id = model.placements[0].id
        model.setCommander(id)

        let setup = model.teamSetup

        #expect(setup.placements == [UnitPlacement(type: Self.archer, cell: 0, isCommander: true)])
        #expect(setup.programs.isEmpty)
    }
}
