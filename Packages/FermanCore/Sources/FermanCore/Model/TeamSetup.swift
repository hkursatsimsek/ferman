public struct UnitPlacement: Sendable, Hashable, Codable {
    public let type: UnitTypeID
    /// A cell index inside the team's placement zone.
    public let cell: Int
    /// At most one placement per team may be the commander (§5.4).
    public let isCommander: Bool

    public init(type: UnitTypeID, cell: Int, isCommander: Bool = false) {
        self.type = type
        self.cell = cell
        self.isCommander = isCommander
    }
}

/// One side of a battle: where its units stand and the orders each unit type follows.
public struct TeamSetup: Sendable, Hashable, Codable {
    /// Units receive their `UnitID` in this order, player team first.
    public let placements: [UnitPlacement]
    /// One program per unit type, ordered by `unitType`.
    public let programs: [RuleProgram]

    public init(placements: [UnitPlacement], programs: [RuleProgram]) {
        self.placements = placements
        self.programs = programs
    }

    public func program(for unitType: UnitTypeID) -> RuleProgram? {
        programs.first { $0.unitType == unitType }
    }
}
