/// One unit's ability cooldown and, while a stance (`spearWall`, `shieldWall`, `charge`) holds, how much longer it
/// lasts. `volley` has no stance: it fires once and goes straight to cooldown (§5.5).
struct AbilityState: Sendable, Hashable {
    var cooldown: Cooldown
    var activeTicksRemaining: Int
    /// Whether `charge`'s first-hit bonus has already been spent during the current activation.
    var chargeBonusSpent: Bool

    var isActive: Bool { activeTicksRemaining > 0 }
    static let initial = AbilityState(cooldown: .ready, activeTicksRemaining: 0, chargeBonusSpent: false)
}

enum Abilities {
    /// Starts a fresh activation if the cooldown allows it; otherwise returns `state` unchanged, so the caller falls
    /// back to `hold` per `useAbility`'s definition (§5.4).
    static func activate(_ state: AbilityState, ability: Ability, tuning: SimulationTuning) -> AbilityState {
        guard state.cooldown.isReady else {
            return state
        }
        let activeTicksRemaining = ability == .volley ? 0 : tuning.abilityDurationTicks
        return AbilityState(
            cooldown: Cooldown(ticksRemaining: tuning.abilityCooldownTicks), activeTicksRemaining: activeTicksRemaining,
            chargeBonusSpent: false)
    }

    static func afterTick(_ state: AbilityState) -> AbilityState {
        AbilityState(
            cooldown: state.cooldown.afterTick(), activeTicksRemaining: Swift.max(0, state.activeTicksRemaining - 1),
            chargeBonusSpent: state.chargeBonusSpent)
    }

    /// Whether `charge`'s bonus applies to an attack landing right now, and the state after spending it: it fires
    /// at most once per activation.
    static func consumingChargeBonus(_ state: AbilityState) -> (bonusApplies: Bool, state: AbilityState) {
        guard state.isActive, !state.chargeBonusSpent else {
            return (false, state)
        }
        return (
            true,
            AbilityState(
                cooldown: state.cooldown, activeTicksRemaining: state.activeTicksRemaining, chargeBonusSpent: true)
        )
    }
}
