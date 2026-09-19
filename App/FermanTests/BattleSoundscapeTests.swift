import FermanContent
import FermanCore
import FermanReplay
import Testing

@testable import Ferman

/// ART-DIRECTION §7 on real battles: level 1 (spearmen meeting cavalry head on) and level 2 (archers
/// retreating from shield-bearers and shooting).
struct BattleSoundscapeTests {
    struct Battle {
        let config: BattleConfig
        let result: BattleResult
        let motion: FigureMotion
        let soundscape: BattleSoundscape

        init(level number: Int) throws {
            let catalog = try ContentCatalog.bundled()
            let level = try #require(catalog.level(number))
            let map = try #require(catalog.map(level.map))
            config = BattleConfig(
                map: map, unitCatalog: catalog.units, player: level.referenceSolution, enemy: level.enemy,
                objective: level.objective, constraints: level.constraints, seed: level.seed, maxTicks: level.maxTicks)
            result = BattleSimulator.run(config)
            let projection = BoardProjection.table(for: map)
            motion = FigureMotion(result: result, config: config, projection: projection)
            soundscape = BattleSoundscape(result: result, config: config, motion: motion, projection: projection)
        }

        var teams: [UnitID: Team] {
            var teams: [UnitID: Team] = [:]
            for event in result.events {
                if case .spawn(let unit, _, let team, _) = event.kind { teams[unit] = team }
            }
            return teams
        }

        /// Everything heard over the whole battle, window by window, with no per-window limit.
        func everything() -> [BattleSoundscape.Cue] {
            var cues: [BattleSoundscape.Cue] = []
            var tick = -1.0
            while tick < Double(result.tickCount) + 1 {
                cues += soundscape.cues(after: tick, through: tick + 1, limit: .max)
                tick += 1
            }
            return cues
        }
    }

    /// One paper "tık" per order the player's units took up — and none for the enemy's.
    @Test(arguments: [1, 2])
    func onlyThePlayersOrdersAreHeard(level: Int) throws {
        let battle = try Battle(level: level)
        let teams = battle.teams
        let playerActivations = battle.result.events.filter {
            if case .ruleActivated(let unit, _) = $0.kind { return teams[unit] == .player }
            return false
        }
        let orders = battle.everything().filter { $0.effect == .order }
        #expect(!playerActivations.isEmpty)
        #expect(orders.count == playerActivations.count)
        #expect(orders.allSatisfy { $0.isPlayerOrder })
    }

    /// Level 2's archers retreat and hold: each order comes with its action's own sound, on its tick.
    @Test
    func anOrderIsHeardWithItsActionsSound() throws {
        let battle = try Battle(level: 2)
        let teams = battle.teams
        var types: [UnitID: UnitTypeID] = [:]
        for event in battle.result.events {
            if case .spawn(let unit, let type, _, _) = event.kind { types[unit] = type }
        }
        var heardActions: Set<SoundEffect> = []
        for event in battle.result.events {
            guard case .ruleActivated(let unit, let ruleIndex) = event.kind, teams[unit] == .player,
                let type = types[unit], let rule = battle.config.player.program(for: type)?.rules[ruleIndex],
                let expected = SoundEffect.action(rule.action.kind)
            else { continue }
            let cues = battle.soundscape.cues(after: Double(event.tick) - 1, through: Double(event.tick), limit: .max)
            #expect(cues.contains { $0.effect == expected }, "tick \(event.tick)")
            heardActions.insert(expected)
        }
        #expect(heardActions.contains(.retreat))
    }

    /// An arrow is released a flight early and lands on the attack tick; the ranged blow itself isn't a
    /// melee clash.
    @Test
    func arrowsAreHeardLeavingAndLanding() throws {
        let battle = try Battle(level: 2)
        let flight = try #require(battle.motion.flights.first)
        let atLaunch = battle.soundscape.cues(after: flight.launchTick - 0.5, through: flight.launchTick, limit: .max)
        let atLanding = battle.soundscape.cues(after: flight.landTick - 1, through: flight.landTick, limit: .max)
        #expect(atLaunch.contains { $0.effect == .release })
        #expect(atLanding.contains { $0.effect == .land })
        #expect(flight.launchTick < flight.landTick)
        // Level 2's only attackers are the archers — no blade ever rings.
        let archersOnly = battle.result.events.allSatisfy {
            guard case .attack(let attacker, _, _) = $0.kind else { return true }
            return battle.motion.figures[attacker]?.isRanged == true
        }
        if archersOnly {
            #expect(!battle.everything().contains { $0.effect == .hit })
        }
    }

    @Test
    func meleeBlowsAndFallsAreHeard() throws {
        let battle = try Battle(level: 1)
        let cues = battle.everything()
        let deaths = battle.result.events.filter { if case .death = $0.kind { return true } else { return false } }
        #expect(cues.contains { $0.effect == .hit })
        #expect(cues.filter { $0.effect == .fall }.count == deaths.count)
    }

    /// Seeking — backwards, or further than a frame's worth — is silent: it skips sounds, never replays
    /// a burst of them.
    @Test
    func seekingIsSilent() throws {
        let battle = try Battle(level: 1)
        #expect(battle.soundscape.cues(after: 0, through: Double(battle.result.tickCount)).isEmpty)
        #expect(battle.soundscape.cues(after: 40, through: 20).isEmpty)
    }

    /// A crowded window — several units taking up an order in the same tick — plays each sound at most
    /// twice. Looks for such a tick in the biggest battles rather than assuming where it falls.
    @Test
    func aCrowdedWindowIsCapped() throws {
        var checked = false
        for level in [8, 7, 6, 5] {
            let battle = try Battle(level: level)
            var crowdedTick: Double?
            var tick = 0.0
            while crowdedTick == nil, tick < Double(battle.result.tickCount) {
                let all = battle.soundscape.cues(after: tick - 1, through: tick, limit: .max)
                if all.filter({ $0.effect == .order }).count > BattleSoundscape.perEffectLimit { crowdedTick = tick }
                tick += 1
            }
            guard let crowdedTick else { continue }
            let capped = battle.soundscape.cues(after: crowdedTick - 1, through: crowdedTick)
            for effect in Set(capped.map(\.effect)) {
                #expect(capped.filter { $0.effect == effect }.count <= BattleSoundscape.perEffectLimit)
            }
            #expect(capped.contains { $0.effect == .order })
            checked = true
            break
        }
        #expect(checked, "no battle had a crowded tick to check")
    }

    @Test
    func soundsStayInsideTheStereoField() throws {
        let battle = try Battle(level: 2)
        #expect(battle.everything().allSatisfy { (-1...1).contains($0.pan) && (0...1).contains($0.volume) })
    }
}
