import FermanCore

/// Everything `BattleScene` needs to draw one instant: where units are, which
/// are alive, and which order each is currently under (CLAUDE.md rule 4 —
/// the scene draws frames, it doesn't know battle rules).
public struct ReplayFrame: Sendable, Hashable {
    public let tick: Int32
    public let livingUnits: Set<UnitID>
    public let positions: [UnitID: FixedVector2]
    public let teams: [UnitID: Team]
    public let unitTypes: [UnitID: UnitTypeID]
    /// The rule index each unit last activated, as of this tick (D9).
    public let activeRuleIndex: [UnitID: Int]
    public let brokenMorale: Set<UnitID>

    static let empty = ReplayFrame(
        tick: -1,
        livingUnits: [],
        positions: [:],
        teams: [:],
        unitTypes: [:],
        activeRuleIndex: [:],
        brokenMorale: []
    )

    func applying(_ event: BattleEvent) -> ReplayFrame {
        var livingUnits = livingUnits
        var positions = positions
        var teams = teams
        var unitTypes = unitTypes
        var activeRuleIndex = activeRuleIndex
        var brokenMorale = brokenMorale

        switch event.kind {
        case .spawn(let unit, let unitType, let team, let position):
            livingUnits.insert(unit)
            positions[unit] = position
            teams[unit] = team
            unitTypes[unit] = unitType
        case .move(let unit, let position):
            positions[unit] = position
        case .ruleActivated(let unit, let ruleIndex):
            activeRuleIndex[unit] = ruleIndex
        case .death(let unit):
            livingUnits.remove(unit)
            brokenMorale.remove(unit)
        case .moraleBroken(let unit):
            brokenMorale.insert(unit)
        case .moraleRecovered(let unit):
            brokenMorale.remove(unit)
        case .attack, .abilityUsed, .battleEnded:
            break
        }

        return ReplayFrame(
            tick: event.tick,
            livingUnits: livingUnits,
            positions: positions,
            teams: teams,
            unitTypes: unitTypes,
            activeRuleIndex: activeRuleIndex,
            brokenMorale: brokenMorale
        )
    }

    /// Same state, relabeled at a tick with no event of its own (the common case for `frame(at:)`).
    func withTick(_ tick: Int32) -> ReplayFrame {
        ReplayFrame(
            tick: tick,
            livingUnits: livingUnits,
            positions: positions,
            teams: teams,
            unitTypes: unitTypes,
            activeRuleIndex: activeRuleIndex,
            brokenMorale: brokenMorale
        )
    }
}
