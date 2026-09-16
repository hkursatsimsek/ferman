import FermanCore
import Testing

@testable import FermanReplay

private let archer: UnitTypeID = "okcu"
private let soldier: UnitTypeID = "mizrakci"

private func unit(_ raw: UInt32) -> UnitID { UnitID(rawValue: raw) }
private let origin = FixedVector2.zero

struct DebriefAnalyzerTests {

    @Test func flagsUnusedAndDominantRules() async throws {
        let result = BattleResult(
            outcome: .playerWin,
            endReason: .elimination,
            tickCount: 10,
            events: [],
            ruleFireCounts: [
                RuleFireCounts(team: .player, unitType: archer, counts: [8, 0, 1])
            ],
            survivorsPlayer: 1,
            survivorsEnemy: 0,
            checksum: 0
        )

        let insights = DebriefAnalyzer.analyze(result: result)

        #expect(insights.contains(.unusedRule(team: .player, unitType: archer, ruleIndex: 1)))
        #expect(
            insights.contains(
                .dominantRule(team: .player, unitType: archer, ruleIndex: 0, fireCount: 8, totalFireCount: 9)))
        #expect(!insights.contains(.unusedRule(team: .player, unitType: archer, ruleIndex: 0)))
    }

    @Test func flagsDeathClusterAboveThreshold() async throws {
        let units = (1...4).map { unit(UInt32($0)) }
        var events: [BattleEvent] = units.map {
            BattleEvent(tick: 0, kind: .spawn($0, archer, .player, origin))
        }
        // 3 of 4 archers die within the simultaneity window.
        events.append(BattleEvent(tick: 100, kind: .death(units[0])))
        events.append(BattleEvent(tick: 103, kind: .death(units[1])))
        events.append(BattleEvent(tick: 108, kind: .death(units[2])))

        let result = BattleResult(
            outcome: .enemyWin,
            endReason: .elimination,
            tickCount: 200,
            events: events,
            ruleFireCounts: [RuleFireCounts(team: .player, unitType: archer, counts: [3])],
            survivorsPlayer: 1,
            survivorsEnemy: 5,
            checksum: 0
        )

        let insights = DebriefAnalyzer.analyze(result: result)

        guard
            case .deathCluster(let team, let unitType, let tick, let unitIDs, let fraction) = insights.first(
                where: {
                    if case .deathCluster = $0 { return true }
                    return false
                })
        else {
            Issue.record("expected a deathCluster insight")
            return
        }
        #expect(team == .player)
        #expect(unitType == archer)
        #expect(tick == 100)
        #expect(Set(unitIDs) == Set(units[0...2]))
        #expect(fraction == Fixed(numerator: 3, denominator: 4))
    }

    @Test func ignoresDeathsBelowThreshold() async throws {
        let units = (1...4).map { unit(UInt32($0)) }
        var events: [BattleEvent] = units.map {
            BattleEvent(tick: 0, kind: .spawn($0, archer, .player, origin))
        }
        // Only 1 of 4 dies — no cluster.
        events.append(BattleEvent(tick: 100, kind: .death(units[0])))

        let result = BattleResult(
            outcome: .playerWin,
            endReason: .elimination,
            tickCount: 200,
            events: events,
            ruleFireCounts: [RuleFireCounts(team: .player, unitType: archer, counts: [1])],
            survivorsPlayer: 3,
            survivorsEnemy: 0,
            checksum: 0
        )

        let insights = DebriefAnalyzer.analyze(result: result)
        #expect(
            !insights.contains {
                if case .deathCluster = $0 { return true }
                return false
            })
    }

    @Test func flagsConcurrentActivation() async throws {
        let a = unit(1)
        let b = unit(2)
        let events: [BattleEvent] = [
            BattleEvent(tick: 0, kind: .spawn(a, archer, .player, origin)),
            BattleEvent(tick: 0, kind: .spawn(b, archer, .player, origin)),
            BattleEvent(tick: 200, kind: .ruleActivated(a, ruleIndex: 0)),
            BattleEvent(tick: 203, kind: .ruleActivated(b, ruleIndex: 0)),
        ]
        let result = BattleResult(
            outcome: .playerWin,
            endReason: .timeLimit,
            tickCount: 300,
            events: events,
            ruleFireCounts: [RuleFireCounts(team: .player, unitType: archer, counts: [2])],
            survivorsPlayer: 2,
            survivorsEnemy: 0,
            checksum: 0
        )

        let insights = DebriefAnalyzer.analyze(result: result)
        #expect(
            insights.contains(
                .concurrentActivation(team: .player, unitType: archer, ruleIndex: 0, tick: 200, unitIDs: [a, b])))
    }

    @Test func flagsMoraleCascade() async throws {
        let units = (1...6).map { unit(UInt32($0)) }
        var events: [BattleEvent] = units.map {
            BattleEvent(tick: 0, kind: .spawn($0, archer, .enemy, origin))
        }
        // Half the team breaks morale together — a line failing, not a straggler.
        events.append(BattleEvent(tick: 50, kind: .moraleBroken(units[0])))
        events.append(BattleEvent(tick: 52, kind: .moraleBroken(units[1])))
        events.append(BattleEvent(tick: 58, kind: .moraleBroken(units[2])))

        let result = BattleResult(
            outcome: .playerWin,
            endReason: .rout,
            tickCount: 300,
            events: events,
            ruleFireCounts: [RuleFireCounts(team: .enemy, unitType: archer, counts: [0])],
            survivorsPlayer: 0,
            survivorsEnemy: 6,
            checksum: 0
        )

        let insights = DebriefAnalyzer.analyze(result: result)
        #expect(
            insights.contains(
                .moraleCascade(
                    team: .enemy, tick: 50, unitIDs: Array(units[0...2]).sorted(),
                    fractionOfTeam: Fixed(numerator: 1, denominator: 2))))
    }

    @Test func keyMomentPicksLargestClusterBreakingTiesByEarlierTick() async throws {
        let deathUnits = (1...4).map { unit(UInt32($0)) }
        let moraleUnits = (5...8).map { unit(UInt32($0)) }
        var events: [BattleEvent] = deathUnits.map {
            BattleEvent(tick: 0, kind: .spawn($0, archer, .player, origin))
        }
        // A distinct unit type so the death cluster's fraction isn't diluted by moraleUnits.
        events += moraleUnits.map {
            BattleEvent(tick: 0, kind: .spawn($0, soldier, .player, origin))
        }
        // Two equally-sized clusters (3 units each); the earlier one should win.
        events.append(BattleEvent(tick: 100, kind: .death(deathUnits[0])))
        events.append(BattleEvent(tick: 101, kind: .death(deathUnits[1])))
        events.append(BattleEvent(tick: 102, kind: .death(deathUnits[2])))
        events.append(BattleEvent(tick: 200, kind: .moraleBroken(moraleUnits[0])))
        events.append(BattleEvent(tick: 201, kind: .moraleBroken(moraleUnits[1])))
        events.append(BattleEvent(tick: 202, kind: .moraleBroken(moraleUnits[2])))

        let result = BattleResult(
            outcome: .enemyWin,
            endReason: .elimination,
            tickCount: 300,
            events: events,
            ruleFireCounts: [RuleFireCounts(team: .player, unitType: archer, counts: [0])],
            survivorsPlayer: 2,
            survivorsEnemy: 0,
            checksum: 0
        )

        let insights = DebriefAnalyzer.analyze(result: result)
        #expect(insights.contains(.keyMoment(tick: 100, team: .player, unitIDs: Array(deathUnits[0...2]).sorted())))
    }
}
