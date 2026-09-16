/// A tick-based cooldown shared by attack intervals and ability recharge: it only ever counts down or gets reset by
/// its caller, so both uses stay simple state machines with no notion of wall-clock time (CLAUDE.md rule 2).
struct Cooldown: Sendable, Hashable {
    var ticksRemaining: Int

    var isReady: Bool { ticksRemaining <= 0 }
    static let ready = Cooldown(ticksRemaining: 0)

    func afterTick() -> Cooldown {
        Cooldown(ticksRemaining: Swift.max(0, ticksRemaining - 1))
    }

    func reset(to ticks: Int) -> Cooldown {
        Cooldown(ticksRemaining: ticks)
    }
}

/// The attacking side's active abilities, as they bear on this one attack. Defaults to "nothing active" so simple
/// 1v1 damage tests don't have to mention abilities at all.
struct AttackerAbilityState: Sendable, Hashable {
    var spearWallActive = false
    /// `charge`'s first-hit bonus applies to this specific attack (already spent by the caller via
    /// `AbilityState.consumingChargeBonus`).
    var chargeBonusApplies = false
}

/// The defending side's active abilities, as they bear on this one attack.
struct DefenderAbilityState: Sendable, Hashable {
    var spearWallActive = false
    var shieldWallActive = false
}

/// The damage formula (FERMAN-PLAN §5.2.5) and the flanking check that feeds `Morale` (§5.2.6).
enum Combat {
    /// `max(1, damage × modifiers − armor)`. Every attack in this game resolves at the attacker's stated range, so
    /// the cover reduction applies uniformly rather than to a separate "ranged" unit category that doesn't exist in
    /// `UnitType`.
    static func damage(
        attacker: UnitType, defender: UnitType, defenderTerrain: Terrain,
        attackerAbility: AttackerAbilityState = AttackerAbilityState(),
        defenderAbility: DefenderAbilityState = DefenderAbilityState(),
        tuning: SimulationTuning
    ) -> Int {
        let attackerCountersDefender = attacker.counters.contains(defender.id)
        var effective = attacker.damage * (attackerCountersDefender ? tuning.counterDamagePercent : 100) / 100

        if attackerCountersDefender, attackerAbility.spearWallActive {
            effective = effective * (100 + tuning.spearWallDamageDealtBonusPercent) / 100
        }
        if attackerAbility.chargeBonusApplies {
            effective = effective * (100 + tuning.chargeFirstHitDamageBonusPercent) / 100
        }
        if defenderTerrain.providesCover {
            effective = effective * (100 - tuning.coverRangedDamageReductionPercent) / 100
        }
        if defenderAbility.shieldWallActive {
            effective = effective * (100 - tuning.shieldWallDamageReductionPercent) / 100
        }
        if defenderAbility.spearWallActive, defender.counters.contains(attacker.id) {
            effective = effective * (100 - tuning.spearWallDamageTakenReductionPercent) / 100
        }

        return Swift.max(1, effective - defender.armor)
    }

    /// A hit lands from behind when the attacker sits opposite the way the defender is facing (§5.2.6).
    /// `attackDirection` points from the defender toward the attacker.
    static func isFlankingHit(defenderFacing: FixedVector2, attackDirection: FixedVector2) -> Bool {
        defenderFacing.dot(attackDirection) < .zero
    }
}
