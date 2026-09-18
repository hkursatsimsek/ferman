import FermanCore
import Testing

@testable import FermanReplay

private let archer: UnitTypeID = "okcu"
private let soldier: UnitTypeID = "mizrakci"

private let unit1 = UnitID(rawValue: 1)
private let unit2 = UnitID(rawValue: 2)
private let unit3 = UnitID(rawValue: 3)

private func makeResult() -> BattleResult {
    let events: [BattleEvent] = [
        BattleEvent(tick: 0, kind: .spawn(unit1, archer, .player, FixedVector2(x: Fixed(1), y: Fixed(1)))),
        BattleEvent(tick: 0, kind: .spawn(unit2, archer, .player, FixedVector2(x: Fixed(2), y: Fixed(1)))),
        BattleEvent(tick: 0, kind: .spawn(unit3, soldier, .enemy, FixedVector2(x: Fixed(10), y: Fixed(1)))),
        BattleEvent(tick: 6, kind: .ruleActivated(unit1, ruleIndex: 0)),
        BattleEvent(tick: 9, kind: .ruleActivated(unit2, ruleIndex: 0)),
        BattleEvent(tick: 12, kind: .move(unit1, FixedVector2(x: Fixed(3), y: Fixed(1)))),
        BattleEvent(tick: 18, kind: .ruleActivated(unit2, ruleIndex: 1)),
        BattleEvent(tick: 24, kind: .ruleActivated(unit1, ruleIndex: 1)),
        BattleEvent(tick: 40, kind: .moraleBroken(unit3)),
        BattleEvent(tick: 55, kind: .attack(unit1, target: unit3, damage: 5)),
        BattleEvent(tick: 55, kind: .death(unit3)),
        BattleEvent(tick: 55, kind: .battleEnded(.playerWin, .elimination)),
    ]
    return BattleResult(
        outcome: .playerWin,
        endReason: .elimination,
        tickCount: 60,
        events: events,
        ruleFireCounts: [
            RuleFireCounts(team: .player, unitType: archer, counts: [2, 2]),
            RuleFireCounts(team: .enemy, unitType: soldier, counts: [0]),
        ],
        survivorsPlayer: 2,
        survivorsEnemy: 0,
        checksum: 0
    )
}

struct ReplayTimelineTests {

    @Test func seekMatchesFoldFromStart() async throws {
        let result = makeResult()
        let keyed = ReplayTimeline(result: result, keyframeInterval: 30)
        let unkeyed = ReplayTimeline(result: result, keyframeInterval: .max)

        for tick in stride(from: Int32(0), through: Int32(70), by: 7) {
            #expect(keyed.frame(at: tick) == unkeyed.frame(at: tick), "mismatch at tick \(tick)")
        }
    }

    @Test func frameClampsNegativeTickToZero() async throws {
        let timeline = ReplayTimeline(result: makeResult())
        #expect(timeline.frame(at: -1) == timeline.frame(at: 0))
    }

    @Test func frameReflectsSpawnsAndDeaths() async throws {
        let timeline = ReplayTimeline(result: makeResult())

        let atSpawn = timeline.frame(at: 0)
        #expect(atSpawn.livingUnits == [unit1, unit2, unit3])
        #expect(atSpawn.teams[unit1] == .player)
        #expect(atSpawn.unitTypes[unit3] == soldier)

        let afterDeath = timeline.frame(at: 55)
        #expect(afterDeath.livingUnits == [unit1, unit2])
        #expect(afterDeath.brokenMorale.contains(unit3) == false)
    }

    @Test func frameTracksActiveRuleAndPosition() async throws {
        let timeline = ReplayTimeline(result: makeResult())
        let frame = timeline.frame(at: 30)
        #expect(frame.activeRuleIndex[unit1] == 1)
        #expect(frame.activeRuleIndex[unit2] == 1)
        #expect(frame.positions[unit1] == FixedVector2(x: Fixed(3), y: Fixed(1)))
    }

    @Test func fireCountsAccumulateAndMatchFinalTotals() async throws {
        let result = makeResult()
        let timeline = ReplayTimeline(result: result)

        let partial = timeline.fireCounts(upTo: 6)
        let playerArcher = partial.first { $0.team == .player && $0.unitType == archer }
        #expect(playerArcher?.counts == [1, 0])

        let final = timeline.fireCounts(upTo: Int32(result.tickCount))
        #expect(Set(final) == Set(result.ruleFireCounts))
    }

    @Test func fireCountsMatchAFullScanAtEveryTick() async throws {
        let result = makeResult()
        let timeline = ReplayTimeline(result: result)

        for tick in Int32(-1)...Int32(result.tickCount + 5) {
            #expect(timeline.fireCounts(upTo: tick) == fullScanFireCounts(result, upTo: tick), "tick \(tick)")
        }
    }

    /// `frame(at:)` runs twice per rendered frame (F1.4); it must fold only the events between its
    /// keyframe and the requested tick, never the whole stream from the start.
    @Test func frameFoldsOnlyTheEventsAfterItsKeyframe() async throws {
        let result = longResult(ticks: 3_000)
        let timeline = ReplayTimeline(result: result, keyframeInterval: 30)

        for tick in stride(from: Int32(0), through: Int32(3_000), by: 97) {
            let keyframeTick = tick / 30 * 30
            let window = result.events.indices.filter {
                result.events[$0].tick > keyframeTick && result.events[$0].tick <= tick
            }
            #expect(Array(timeline.foldedEventRange(forFrameAt: tick)) == window, "tick \(tick)")
        }
    }

    @Test func aLongBattleStillSeeksToTheSameFrameAsFoldingFromTheStart() async throws {
        let result = longResult(ticks: 900)
        let keyed = ReplayTimeline(result: result, keyframeInterval: 30)
        let unkeyed = ReplayTimeline(result: result, keyframeInterval: .max)

        for tick in stride(from: Int32(0), through: Int32(900), by: 13) {
            #expect(keyed.frame(at: tick) == unkeyed.frame(at: tick), "mismatch at tick \(tick)")
        }
    }
}

/// One unit walking one step per tick and switching orders every 7 ticks — a stream long enough that
/// a full scan and a keyframe-bounded fold differ by orders of magnitude.
private func longResult(ticks: Int32) -> BattleResult {
    var events: [BattleEvent] = [
        BattleEvent(tick: 0, kind: .spawn(unit1, archer, .player, FixedVector2(x: Fixed(0), y: Fixed(1))))
    ]
    for tick in 1...ticks {
        events.append(BattleEvent(tick: tick, kind: .move(unit1, FixedVector2(x: Fixed(Int(tick % 20)), y: Fixed(1)))))
        if tick % 7 == 0 {
            events.append(BattleEvent(tick: tick, kind: .ruleActivated(unit1, ruleIndex: Int(tick / 7 % 2))))
        }
    }
    return BattleResult(
        outcome: .draw, endReason: .timeLimit, tickCount: Int(ticks), events: events,
        ruleFireCounts: [RuleFireCounts(team: .player, unitType: archer, counts: [0, 0])],
        survivorsPlayer: 1, survivorsEnemy: 0, checksum: 0)
}

/// The definition `fireCounts(upTo:)` has to keep matching: every `ruleActivated` event up to `tick`.
private func fullScanFireCounts(_ result: BattleResult, upTo tick: Int32) -> [RuleFireCounts] {
    var unitTypes: [UnitID: (Team, UnitTypeID)] = [:]
    for event in result.events {
        if case .spawn(let unit, let type, let team, _) = event.kind { unitTypes[unit] = (team, type) }
    }
    return result.ruleFireCounts.map { entry in
        var counts = Array(repeating: 0, count: entry.counts.count)
        for event in result.events where event.tick <= tick {
            guard case .ruleActivated(let unit, let ruleIndex) = event.kind, let owner = unitTypes[unit],
                owner.0 == entry.team, owner.1 == entry.unitType, ruleIndex < counts.count
            else { continue }
            counts[ruleIndex] += 1
        }
        return RuleFireCounts(team: entry.team, unitType: entry.unitType, counts: counts)
    }
}
