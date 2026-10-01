import FermanContent
import FermanCore

/// G16's stress battle: 75 figures a side on level 8's table (`vadi`, the one with terrain), every unit
/// type on both sides, orders that keep abilities, retreats and cover firing — the most the battle screen
/// is asked to draw at once (the plan's "150 birim 60 fps"). `-uiTestStressBattle YES` opens it directly.
nonisolated enum StressBattle {
    static let unitsPerSide = 75
    static let mapID: MapID = "vadi"

    /// Front rank first: shields, then spears, cavalry, archers at the back.
    private static let ranks: [(type: UnitTypeID, count: Int)] = [
        ("kalkan", 14), ("mizrakci", 21), ("suvari", 16), ("okcu", 24),
    ]

    /// Both armies follow the same orders, so neither side collapses early and the table stays full.
    private static let programs: [RuleProgram] = [
        RuleProgram(
            unitType: "kalkan",
            rules: [
                Rule(condition: .enemyWithin(cells: 2), action: .useAbility),
                Rule(condition: .always, action: .advance),
            ]),
        RuleProgram(
            unitType: "mizrakci",
            rules: [
                Rule(condition: .enemyWithin(cells: 2), action: .useAbility),
                Rule(condition: .always, action: .advance),
            ]),
        RuleProgram(
            unitType: "okcu",
            rules: [
                Rule(condition: .healthBelow(percent: 40), action: .takeCover),
                Rule(condition: .enemyWithin(cells: 3), action: .retreat),
                Rule(condition: .always, action: .hold),
            ]),
        RuleProgram(
            unitType: "suvari",
            rules: [
                Rule(condition: .enemyWithin(cells: 4), action: .useAbility),
                Rule(condition: .always, action: .advance),
            ]),
    ].sorted { $0.unitType.rawValue < $1.unitType.rawValue }

    static func config(catalog: ContentCatalog) -> BattleConfig? {
        guard let map = catalog.map(mapID) else { return nil }
        let player = team(.player, on: map)
        let enemy = team(.enemy, on: map)
        guard player.placements.count == unitsPerSide, enemy.placements.count == unitsPerSide else { return nil }
        return BattleConfig(
            map: map, unitCatalog: catalog.units, player: player, enemy: enemy, objective: .eliminate,
            constraints: .unrestricted, seed: 1, maxTicks: 3_600)
    }

    /// Fills the zone from the edge facing the enemy backward, one column at a time.
    private static func team(_ team: Team, on map: BattleMap) -> TeamSetup {
        let midColumn = map.width / 2
        let cells = map.zone(for: team).sorted { lhs, rhs in
            let (lhsColumn, lhsRow) = map.coordinates(ofCell: lhs)
            let (rhsColumn, rhsRow) = map.coordinates(ofCell: rhs)
            let lhsDepth = abs(lhsColumn - midColumn)
            let rhsDepth = abs(rhsColumn - midColumn)
            return lhsDepth != rhsDepth ? lhsDepth < rhsDepth : lhsRow < rhsRow
        }
        let types = ranks.flatMap { Array(repeating: $0.type, count: $0.count) }
        let placements = zip(types, cells).map { UnitPlacement(type: $0, cell: $1) }
        return TeamSetup(placements: placements, programs: programs)
    }
}
