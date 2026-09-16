import FermanCore

/// A structured finding from `DebriefAnalyzer`. Turning this into a Turkish sentence
/// is the app's job (String Catalog, D11) — this type carries only facts.
public enum DebriefInsight: Sendable, Hashable {
    /// A large share of one (team, unit type) died within the same short window.
    case deathCluster(team: Team, unitType: UnitTypeID, tick: Int32, unitIDs: [UnitID], fractionOfType: Fixed)
    /// A large share of one team's units broke morale within the same short window — the line failed together.
    case moraleCascade(team: Team, tick: Int32, unitIDs: [UnitID], fractionOfTeam: Fixed)
    /// An order that never fired once in the whole battle.
    case unusedRule(team: Team, unitType: UnitTypeID, ruleIndex: Int)
    /// An order that accounted for most of its program's activations.
    case dominantRule(team: Team, unitType: UnitTypeID, ruleIndex: Int, fireCount: Int, totalFireCount: Int)
    /// Multiple units of the same (team, unit type) switched to the same order within the same short window.
    case concurrentActivation(team: Team, unitType: UnitTypeID, ruleIndex: Int, tick: Int32, unitIDs: [UnitID])
    /// The single tick with the battle's largest combined death/morale cluster.
    case keyMoment(tick: Int32, team: Team, unitIDs: [UnitID])
}
