import FermanCore

/// Finds what a battle's own numbers say happened (design brief §4.6 — a diagnosis
/// screen, not a victory screen). Pure function of a `BattleResult`; no rendering,
/// no localized text (D11).
public enum DebriefAnalyzer {
    /// Deaths, morale breaks and rule switches within this many ticks (0.5s at 30 ticks/s)
    /// of each other count as "at once".
    static let simultaneityWindowTicks: Int32 = 15
    /// A cluster below this share of the group it happened in isn't worth flagging.
    static let clusterFractionThreshold = Fixed(numerator: 1, denominator: 2)
    static let moraleCascadeFractionThreshold = Fixed(numerator: 1, denominator: 3)
    /// A rule below this share of its program's activations isn't "dominant".
    static let dominantRuleFractionThreshold = Fixed(numerator: 1, denominator: 2)

    public static func analyze(result: BattleResult) -> [DebriefInsight] {
        let unitIndex = UnitIndex(events: result.events)

        let ruleUsage = ruleUsageInsights(result: result)
        let deathClusters = deathClusterFindings(result: result, unitIndex: unitIndex)
        let moraleCascades = moraleCascadeFindings(result: result, unitIndex: unitIndex)
        let concurrentActivations = concurrentActivationInsights(result: result, unitIndex: unitIndex)

        var insights = ruleUsage
        insights += deathClusters.map(\.insight)
        insights += moraleCascades.map(\.insight)
        insights += concurrentActivations
        if let keyMoment = keyMomentInsight(deathClusters + moraleCascades) {
            insights.append(keyMoment)
        }
        return insights
    }

    // MARK: - Rule usage

    private static func ruleUsageInsights(result: BattleResult) -> [DebriefInsight] {
        var insights: [DebriefInsight] = []
        for entry in result.ruleFireCounts {
            let total = entry.counts.reduce(0, +)
            for (ruleIndex, count) in entry.counts.enumerated() {
                if count == 0 {
                    insights.append(.unusedRule(team: entry.team, unitType: entry.unitType, ruleIndex: ruleIndex))
                } else if total > 0, Fixed(numerator: count, denominator: total) >= dominantRuleFractionThreshold {
                    insights.append(
                        .dominantRule(
                            team: entry.team, unitType: entry.unitType, ruleIndex: ruleIndex,
                            fireCount: count, totalFireCount: total))
                }
            }
        }
        return insights
    }

    // MARK: - Clustering

    private struct Finding {
        let tick: Int32
        let team: Team
        let unitIDs: [UnitID]
        let insight: DebriefInsight
    }

    private struct TickUnit {
        let tick: Int32
        let unit: UnitID
    }

    private static func clusters(from events: [TickUnit], window: Int32) -> [(tick: Int32, unitIDs: [UnitID])] {
        let sorted = events.sorted { $0.tick == $1.tick ? $0.unit < $1.unit : $0.tick < $1.tick }
        var result: [(tick: Int32, unitIDs: [UnitID])] = []
        var windowStart: Int32?
        var unitIDs: [UnitID] = []

        for event in sorted {
            if let start = windowStart, event.tick - start <= window {
                unitIDs.append(event.unit)
            } else {
                if let start = windowStart {
                    result.append((start, unitIDs))
                }
                windowStart = event.tick
                unitIDs = [event.unit]
            }
        }
        if let start = windowStart {
            result.append((start, unitIDs))
        }
        return result
    }

    private static func deathClusterFindings(result: BattleResult, unitIndex: UnitIndex) -> [Finding] {
        var byProgram: [ProgramKey: [TickUnit]] = [:]
        for event in result.events {
            guard case .death(let unit) = event.kind,
                let team = unitIndex.team(of: unit),
                let unitType = unitIndex.unitType(of: unit)
            else { continue }
            byProgram[ProgramKey(team: team, unitType: unitType), default: []].append(
                TickUnit(tick: event.tick, unit: unit))
        }

        var findings: [Finding] = []
        for key in byProgram.keys.sorted() {
            let totalOfType = unitIndex.units(team: key.team, unitType: key.unitType).count
            guard totalOfType > 0, let events = byProgram[key] else { continue }
            for cluster in clusters(from: events, window: simultaneityWindowTicks) {
                let fraction = Fixed(numerator: cluster.unitIDs.count, denominator: totalOfType)
                guard cluster.unitIDs.count >= 2, fraction >= clusterFractionThreshold else { continue }
                let unitIDs = cluster.unitIDs.sorted()
                findings.append(
                    Finding(
                        tick: cluster.tick, team: key.team, unitIDs: unitIDs,
                        insight: .deathCluster(
                            team: key.team, unitType: key.unitType, tick: cluster.tick, unitIDs: unitIDs,
                            fractionOfType: fraction)))
            }
        }
        return findings
    }

    private static func moraleCascadeFindings(result: BattleResult, unitIndex: UnitIndex) -> [Finding] {
        var byTeam: [Team: [TickUnit]] = [:]
        var teamSize: [Team: Int] = [:]
        for event in result.events {
            guard case .moraleBroken(let unit) = event.kind, let team = unitIndex.team(of: unit) else { continue }
            byTeam[team, default: []].append(TickUnit(tick: event.tick, unit: unit))
        }
        for team in Team.allCases {
            teamSize[team] = unitIndex.units(team: team).count
        }

        var findings: [Finding] = []
        for team in Team.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            let total = teamSize[team] ?? 0
            guard total > 0, let events = byTeam[team] else { continue }
            for cluster in clusters(from: events, window: simultaneityWindowTicks) {
                let fraction = Fixed(numerator: cluster.unitIDs.count, denominator: total)
                guard cluster.unitIDs.count >= 2, fraction >= moraleCascadeFractionThreshold else { continue }
                let unitIDs = cluster.unitIDs.sorted()
                findings.append(
                    Finding(
                        tick: cluster.tick, team: team, unitIDs: unitIDs,
                        insight: .moraleCascade(
                            team: team, tick: cluster.tick, unitIDs: unitIDs, fractionOfTeam: fraction)
                    ))
            }
        }
        return findings
    }

    private static func concurrentActivationInsights(result: BattleResult, unitIndex: UnitIndex) -> [DebriefInsight] {
        struct RuleKey: Hashable, Comparable {
            let program: ProgramKey
            let ruleIndex: Int
            static func < (lhs: RuleKey, rhs: RuleKey) -> Bool {
                lhs.program == rhs.program ? lhs.ruleIndex < rhs.ruleIndex : lhs.program < rhs.program
            }
        }

        var byRule: [RuleKey: [TickUnit]] = [:]
        for event in result.events {
            guard case .ruleActivated(let unit, let ruleIndex) = event.kind,
                let team = unitIndex.team(of: unit),
                let unitType = unitIndex.unitType(of: unit)
            else { continue }
            let key = RuleKey(program: ProgramKey(team: team, unitType: unitType), ruleIndex: ruleIndex)
            byRule[key, default: []].append(TickUnit(tick: event.tick, unit: unit))
        }

        var insights: [DebriefInsight] = []
        for key in byRule.keys.sorted() {
            guard let events = byRule[key] else { continue }
            for cluster in clusters(from: events, window: simultaneityWindowTicks) {
                let distinctUnits = Set(cluster.unitIDs)
                guard distinctUnits.count >= 2 else { continue }
                insights.append(
                    .concurrentActivation(
                        team: key.program.team, unitType: key.program.unitType, ruleIndex: key.ruleIndex,
                        tick: cluster.tick, unitIDs: cluster.unitIDs.sorted()))
            }
        }
        return insights
    }

    private static func keyMomentInsight(_ findings: [Finding]) -> DebriefInsight? {
        guard
            let largest = findings.max(by: { lhs, rhs in
                lhs.unitIDs.count == rhs.unitIDs.count ? lhs.tick > rhs.tick : lhs.unitIDs.count < rhs.unitIDs.count
            })
        else { return nil }
        return .keyMoment(tick: largest.tick, team: largest.team, unitIDs: largest.unitIDs)
    }
}
