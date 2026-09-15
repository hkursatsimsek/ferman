public enum Ability: String, Sendable, Codable, CaseIterable {
    /// Mızrakçı: holds position and turns cavalry charges against the charger.
    case spearWall
    /// Okçu: a single area volley around the target cell.
    case volley
    /// Süvari: a short burst of speed with bonus damage on the first hit.
    case charge
    /// Kalkanlı: holds position and absorbs most ranged damage.
    case shieldWall
}

/// Static statistics of a unit type, in integer units only (D19).
public struct UnitType: Sendable, Hashable, Codable {
    public let id: UnitTypeID
    public let cost: Int
    public let maxHP: Int
    public let speedMilliCellsPerSecond: Int
    public let rangeMilliCells: Int
    public let damage: Int
    public let attackIntervalTicks: Int
    public let armor: Int
    public let moraleMax: Int
    /// Unit types this one deals counter damage to (`SimulationTuning.counterDamagePercent`).
    public let counters: [UnitTypeID]
    public let ability: Ability

    public init(
        id: UnitTypeID,
        cost: Int,
        maxHP: Int,
        speedMilliCellsPerSecond: Int,
        rangeMilliCells: Int,
        damage: Int,
        attackIntervalTicks: Int,
        armor: Int,
        moraleMax: Int,
        counters: [UnitTypeID],
        ability: Ability
    ) {
        self.id = id
        self.cost = cost
        self.maxHP = maxHP
        self.speedMilliCellsPerSecond = speedMilliCellsPerSecond
        self.rangeMilliCells = rangeMilliCells
        self.damage = damage
        self.attackIntervalTicks = attackIntervalTicks
        self.armor = armor
        self.moraleMax = moraleMax
        self.counters = counters
        self.ability = ability
    }
}
