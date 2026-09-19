import CoreGraphics
import FermanContent
import FermanCore
import FermanReplay
import Testing

@testable import Ferman

/// D27: a figure's pose is a pure function of replay time, built from the event stream alone.
/// Exercised on a real battle — level 2, archers kiting shield-bearers — not a hand-made stream.
struct FigureMotionTests {
    let result: BattleResult
    let motion: FigureMotion
    let tracks: UnitTracks

    init() throws {
        let catalog = try ContentCatalog.bundled()
        let level = try #require(catalog.level(2))
        let map = try #require(catalog.map(level.map))
        let config = BattleConfig(
            map: map, unitCatalog: catalog.units, player: level.referenceSolution, enemy: level.enemy,
            objective: level.objective, constraints: level.constraints, seed: level.seed, maxTicks: level.maxTicks)
        result = BattleSimulator.run(config)
        motion = FigureMotion(result: result, config: config, projection: .table(for: map))
        tracks = UnitTracks(result: result)
    }

    /// The simulation applies ranged damage the tick it's dealt; the arrow must arrive exactly then.
    @Test
    func anArrowLandsOnItsTargetOnTheAttackTick() throws {
        let archer = try #require(tracks.tracks.first { $0.unitType == "okcu" && !$0.strikesMade.isEmpty })
        let strike = try #require(archer.strikesMade.first)
        let target = try #require(motion.figures[strike.other])
        let landing = target.groundPoint(atTick: Double(strike.tick))

        let arrows = motion.arrows(atTick: Double(strike.tick))
        #expect(arrows.contains { hypot($0.groundPosition.x - landing.x, $0.groundPosition.y - landing.y) < 0.01 })
        // A moment earlier it is still in the air, on its way.
        #expect(!motion.arrows(atTick: Double(strike.tick) - 3).isEmpty)
    }

    @Test
    func aFallenFigureLiesWhereItFellForTheRestOfTheBattle() throws {
        let dead = try #require(tracks.tracks.first { $0.deathTick != nil })
        let death = Double(try #require(dead.deathTick))

        let before = try #require(motion.pose(of: dead.unit, atTick: death - 1, reduceMotion: false))
        let after = try #require(motion.pose(of: dead.unit, atTick: death + 10, reduceMotion: false))
        // The replay settles past the last tick (`BattleModel.settleTicks`) so a unit killed by the final
        // blow — the battle ends the tick it dies — still finishes falling.
        let settledEnd = Double(Int32(result.tickCount) + BattleModel.settleTicks)
        let end = try #require(motion.pose(of: dead.unit, atTick: settledEnd, reduceMotion: false))
        #expect(before.isFallen == false)
        #expect(after.isFallen && after.pose == .fallen)
        #expect(end.isFallen)
        #expect(end.position == after.position)
        #expect(end.spark == nil && end.seal == nil)
    }

    /// Seeking back and forth, or rebuilding the whole motion, never changes a frame.
    @Test
    func aPoseDependsOnlyOnTheTime() throws {
        let unit = try #require(tracks.tracks.first?.unit)
        let times = [45.5, 12.25, 90, 45.5, 0, 12.25]
        let poses = times.map { motion.pose(of: unit, atTick: $0, reduceMotion: false) }
        #expect(poses[0] == poses[3])
        #expect(poses[1] == poses[5])

        let rebuilt = FigureMotion(
            result: result, config: try Self.config(), projection: .table(for: try Self.config().map))
        #expect(rebuilt.pose(of: unit, atTick: 45.5, reduceMotion: false) == poses[0])
    }

    /// The spark means "your logic is working" (brief §3.2): the enemy's orders never throw one.
    @Test
    func onlyThePlayersFiguresSpark() throws {
        let player = try #require(tracks.tracks.first { $0.team == .player && !$0.ruleActivations.isEmpty })
        let playerTick = Double(try #require(player.ruleActivations.first).tick)
        #expect(motion.pose(of: player.unit, atTick: playerTick + 1, reduceMotion: false)?.spark != nil)
        #expect(motion.pose(of: player.unit, atTick: playerTick + 1, reduceMotion: false)?.seal != nil)

        let enemy = try #require(tracks.tracks.first { $0.team == .enemy && !$0.ruleActivations.isEmpty })
        let enemyTick = Double(try #require(enemy.ruleActivations.first).tick)
        #expect(motion.pose(of: enemy.unit, atTick: enemyTick + 1, reduceMotion: false)?.spark == nil)
        #expect(motion.pose(of: enemy.unit, atTick: enemyTick + 1, reduceMotion: false)?.seal == nil)
    }

    /// Reduce Motion (brief §6): no hops, lunges, knockback or tremble — a figure stays on its ground point.
    @Test
    func reduceMotionKeepsEveryFigureOnItsGroundPoint() throws {
        for track in tracks.tracks {
            let figure = try #require(motion.figures[track.unit])
            for tick in stride(from: 0.0, to: Double(result.tickCount), by: 17.5) {
                let pose = try #require(motion.pose(of: track.unit, atTick: tick, reduceMotion: true))
                #expect(pose.lift == 0)
                #expect(pose.position == figure.groundPoint(atTick: tick))
            }
        }
    }

    private static func config() throws -> BattleConfig {
        let catalog = try ContentCatalog.bundled()
        let level = try #require(catalog.level(2))
        let map = try #require(catalog.map(level.map))
        return BattleConfig(
            map: map, unitCatalog: catalog.units, player: level.referenceSolution, enemy: level.enemy,
            objective: level.objective, constraints: level.constraints, seed: level.seed, maxTicks: level.maxTicks)
    }
}
