import FermanCore
import Testing

@testable import FermanReplay

private let archerType: UnitTypeID = "okcu"
private let shieldType: UnitTypeID = "kalkan"
private let archer = UnitID(rawValue: 0)
private let shield = UnitID(rawValue: 1)

private func point(_ x: Int, _ y: Int) -> FixedVector2 {
    FixedVector2(x: Fixed(x), y: Fixed(y))
}

private func makeResult() -> BattleResult {
    let events: [BattleEvent] = [
        BattleEvent(tick: 0, kind: .spawn(archer, archerType, .player, point(1, 1))),
        BattleEvent(tick: 0, kind: .spawn(shield, shieldType, .enemy, point(9, 1))),
        BattleEvent(tick: 3, kind: .ruleActivated(archer, ruleIndex: 1)),
        BattleEvent(tick: 3, kind: .move(shield, point(8, 1))),
        BattleEvent(tick: 6, kind: .move(shield, point(7, 1))),
        BattleEvent(tick: 9, kind: .abilityUsed(shield, .shieldWall)),
        BattleEvent(tick: 12, kind: .attack(archer, target: shield, damage: 10)),
        BattleEvent(tick: 24, kind: .attack(archer, target: shield, damage: 12)),
        BattleEvent(tick: 30, kind: .moraleBroken(shield)),
        BattleEvent(tick: 30, kind: .move(shield, point(8, 1))),
        BattleEvent(tick: 36, kind: .attack(archer, target: shield, damage: 9)),
        BattleEvent(tick: 40, kind: .moraleRecovered(shield)),
        BattleEvent(tick: 48, kind: .attack(archer, target: shield, damage: 11)),
        BattleEvent(tick: 50, kind: .moraleBroken(shield)),
        BattleEvent(tick: 55, kind: .death(shield)),
        BattleEvent(tick: 55, kind: .battleEnded(.playerWin, .elimination)),
    ]
    return BattleResult(
        outcome: .playerWin, endReason: .elimination, tickCount: 55, events: events,
        ruleFireCounts: [], survivorsPlayer: 1, survivorsEnemy: 0, checksum: 0)
}

struct UnitTrackTests {
    let tracks = UnitTracks(result: makeResult())

    @Test func everySpawnedUnitHasATrackInSpawnOrder() throws {
        #expect(tracks.tracks.map(\.unit) == [archer, shield])
        let track = try #require(tracks[shield])
        #expect(track.unitType == shieldType)
        #expect(track.team == .enemy)
    }

    @Test func thePathStartsAtTheSpawnAndHoldsBetweenSamples() throws {
        let track = try #require(tracks[shield])
        #expect(track.path.map(\.tick) == [0, 3, 6, 30])
        #expect(track.position(at: 0) == point(9, 1))
        #expect(track.position(at: 5) == point(8, 1))
        #expect(track.position(at: 29) == point(7, 1))
        #expect(track.position(at: 100) == point(8, 1))
        // A unit that never moved stays at its spawn point.
        #expect(try #require(tracks[archer]).position(at: 40) == point(1, 1))
    }

    @Test func strikesAreKeptOnBothSides() throws {
        let archerTrack = try #require(tracks[archer])
        let shieldTrack = try #require(tracks[shield])
        #expect(archerTrack.strikesMade.map(\.tick) == [12, 24, 36, 48])
        #expect(shieldTrack.strikesTaken.map(\.other) == [archer, archer, archer, archer])
        #expect(archerTrack.lastStrikeMade(atOrBefore: 30)?.tick == 24)
        #expect(archerTrack.lastStrikeMade(atOrBefore: 11) == nil)
        #expect(shieldTrack.lastStrikeTaken(atOrBefore: 36)?.damage == 9)
    }

    @Test func strikesInAWindowIncludeBothEnds() throws {
        let archerTrack = try #require(tracks[archer])
        #expect(archerTrack.strikesMade(in: 12...36).map(\.tick) == [12, 24, 36])
        #expect(archerTrack.strikesMade(in: 13...35).map(\.tick) == [24])
        #expect(archerTrack.strikesMade(in: 49...60).isEmpty)
    }

    @Test func damageTakenAccumulates() throws {
        let shieldTrack = try #require(tracks[shield])
        #expect(shieldTrack.damageTaken(upTo: 11) == 0)
        #expect(shieldTrack.damageTaken(upTo: 12) == 10)
        #expect(shieldTrack.damageTaken(upTo: 47) == 31)
        #expect(shieldTrack.damageTaken(upTo: 60) == 42)
    }

    @Test func moraleBreaksCloseOnRecoveryOrDeath() throws {
        let shieldTrack = try #require(tracks[shield])
        #expect(
            shieldTrack.moraleBreaks == [
                UnitTrack.MoraleBreak(start: 30, end: 40), UnitTrack.MoraleBreak(start: 50, end: 55),
            ])
        #expect(shieldTrack.isMoraleBroken(at: 29) == false)
        #expect(shieldTrack.isMoraleBroken(at: 30))
        #expect(shieldTrack.isMoraleBroken(at: 40) == false)
        #expect(shieldTrack.isMoraleBroken(at: 52))
    }

    @Test func deathEndsTheUnitsLife() throws {
        let shieldTrack = try #require(tracks[shield])
        #expect(shieldTrack.deathTick == 55)
        #expect(shieldTrack.isAlive(at: 54))
        #expect(shieldTrack.isAlive(at: 55) == false)
        #expect(try #require(tracks[archer]).isAlive(at: 1_000))
    }

    @Test func abilitiesAndOrdersAreIndexed() throws {
        #expect(try #require(tracks[shield]).lastAbilityStart(atOrBefore: 20)?.ability == .shieldWall)
        #expect(try #require(tracks[shield]).lastAbilityStart(atOrBefore: 8) == nil)
        #expect(try #require(tracks[archer]).lastRuleActivation(atOrBefore: 10)?.ruleIndex == 1)
    }
}
