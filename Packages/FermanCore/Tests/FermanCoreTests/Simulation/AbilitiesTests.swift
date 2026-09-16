import Testing

@testable import FermanCore

@Suite("Abilities")
struct AbilitiesTests {
    @Test func activatingAStanceStartsItsDurationAndCooldown() {
        let activated = Abilities.activate(.initial, ability: .spearWall, tuning: .standard)
        #expect(activated.isActive)
        #expect(activated.activeTicksRemaining == SimulationTuning.standard.abilityDurationTicks)
        #expect(activated.cooldown.ticksRemaining == SimulationTuning.standard.abilityCooldownTicks)
        #expect(!activated.chargeBonusSpent)
    }

    @Test func volleyHasNoStanceButStillGoesOnCooldown() {
        let activated = Abilities.activate(.initial, ability: .volley, tuning: .standard)
        #expect(!activated.isActive)
        #expect(activated.activeTicksRemaining == 0)
        #expect(activated.cooldown.ticksRemaining == SimulationTuning.standard.abilityCooldownTicks)
    }

    @Test func activatingOnCooldownIsANoOp() {
        let onCooldown = AbilityState(
            cooldown: Cooldown(ticksRemaining: 10), activeTicksRemaining: 0, chargeBonusSpent: false)
        let result = Abilities.activate(onCooldown, ability: .charge, tuning: .standard)
        #expect(result == onCooldown)
    }

    @Test func eachTickCountsDownCooldownAndActiveDurationIndependently() {
        let state = AbilityState(cooldown: Cooldown(ticksRemaining: 5), activeTicksRemaining: 1, chargeBonusSpent: true)
        let next = Abilities.afterTick(state)
        #expect(next.cooldown.ticksRemaining == 4)
        #expect(next.activeTicksRemaining == 0)
        #expect(!next.isActive)
        #expect(next.chargeBonusSpent)

        let atZero = Abilities.afterTick(next)
        #expect(atZero.cooldown.ticksRemaining == 3)
        #expect(atZero.activeTicksRemaining == 0)
    }

    @Test func chargeBonusFiresOnceThenIsSpent() {
        let activated = Abilities.activate(.initial, ability: .charge, tuning: .standard)

        let first = Abilities.consumingChargeBonus(activated)
        #expect(first.bonusApplies)
        #expect(first.state.chargeBonusSpent)

        let second = Abilities.consumingChargeBonus(first.state)
        #expect(!second.bonusApplies)
        #expect(second.state == first.state)
    }

    @Test func chargeBonusNeverAppliesWhenNotActive() {
        let result = Abilities.consumingChargeBonus(.initial)
        #expect(!result.bonusApplies)
        #expect(result.state == .initial)
    }
}
