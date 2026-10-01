import FermanContent
import FermanCore
import FermanReplay
import Testing

@testable import Ferman

/// G16's stress battle has to actually load the table: 150 figures, every type on both sides, and a fight
/// long enough to measure frame rate over, not a rout in the opening seconds.
struct StressBattleTests {
    @Test
    func fieldsSeventyFiveOfEveryTypeASide() throws {
        let config = try #require(StressBattle.config(catalog: try ContentCatalog.bundled()))

        #expect(config.player.placements.count == StressBattle.unitsPerSide)
        #expect(config.enemy.placements.count == StressBattle.unitsPerSide)
        let types = Set(config.unitCatalog.map(\.id))
        #expect(Set(config.player.placements.map(\.type)) == types)
        #expect(Set(config.enemy.placements.map(\.type)) == types)
        #expect(Set(config.player.placements.map(\.cell)).count == StressBattle.unitsPerSide)
    }

    /// Only the first 20 seconds are simulated — the whole battle takes long enough in a debug build to
    /// starve the timing-sensitive tests running beside it. Reaching the tick cap means neither side had
    /// been wiped out by then.
    @Test
    func keepsTheTableFullForAMeasurableFight() throws {
        let full = try #require(StressBattle.config(catalog: try ContentCatalog.bundled()))
        let twentySeconds = 20 * BattleConfig.ticksPerSecond
        let config = BattleConfig(
            map: full.map, unitCatalog: full.unitCatalog, player: full.player, enemy: full.enemy,
            objective: full.objective, constraints: full.constraints, seed: full.seed, maxTicks: twentySeconds)
        let result = BattleSimulator.run(config)
        let tracks = UnitTracks(result: result)
        let tenSeconds = Int32(10 * BattleConfig.ticksPerSecond)

        #expect(tracks.tracks.count == 2 * StressBattle.unitsPerSide)
        #expect(result.tickCount == twentySeconds)
        #expect(tracks.tracks.filter { $0.isAlive(at: tenSeconds) }.count > StressBattle.unitsPerSide)
    }
}
