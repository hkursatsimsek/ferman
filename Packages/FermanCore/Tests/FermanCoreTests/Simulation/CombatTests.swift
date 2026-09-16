import Testing

@testable import FermanCore

@Suite("Cooldown")
struct CooldownTests {
    @Test func startsReadyOnlyWhenExplicitlyReady() {
        #expect(Cooldown.ready.isReady)
        #expect(!Cooldown(ticksRemaining: 1).isReady)
    }

    @Test func tickingDownFloorsAtZero() {
        var cooldown = Cooldown(ticksRemaining: 1)
        cooldown = cooldown.afterTick()
        #expect(cooldown.isReady)
        cooldown = cooldown.afterTick()
        #expect(cooldown.isReady)
        #expect(cooldown.ticksRemaining == 0)
    }

    @Test func resetReplacesTheRemainingTicks() {
        let cooldown = Cooldown.ready.reset(to: 30)
        #expect(cooldown.ticksRemaining == 30)
        #expect(!cooldown.isReady)
    }
}

@Suite("Combat")
struct CombatTests {
    // SimulationTuning.standard: counterDamagePercent 150, coverRangedDamageReductionPercent 30,
    // spearWallDamageTakenReductionPercent/DealtBonusPercent 50, shieldWallDamageReductionPercent 70,
    // chargeFirstHitDamageBonusPercent 100.

    @Test func aCounteredTargetTakesTheCounterBonus() {
        // Spearman (damage 12) counters cavalry: 12 * 1.5 = 18, minus cavalry's armor (1).
        let damage = Combat.damage(
            attacker: Fixtures.unitType(Fixtures.spearman), defender: Fixtures.unitType(Fixtures.cavalry),
            defenderTerrain: .open,
            tuning: .standard)
        #expect(damage == 17)
    }

    @Test func anUncounteredTargetTakesPlainDamage() {
        // Cavalry does not counter spearman: 14, minus spearman's armor (2).
        let damage = Combat.damage(
            attacker: Fixtures.unitType(Fixtures.cavalry), defender: Fixtures.unitType(Fixtures.spearman),
            defenderTerrain: .open,
            tuning: .standard)
        #expect(damage == 12)
    }

    @Test func coverReducesDamageBeforeArmorAndRoundsDown() {
        // Archer counters spearman: 10 * 1.5 = 15; cover cuts 30% (15 * 0.7 = 10.5 → 10); minus armor (2).
        let onOpen = Combat.damage(
            attacker: Fixtures.unitType(Fixtures.archer), defender: Fixtures.unitType(Fixtures.spearman),
            defenderTerrain: .open,
            tuning: .standard)
        let onForest = Combat.damage(
            attacker: Fixtures.unitType(Fixtures.archer), defender: Fixtures.unitType(Fixtures.spearman),
            defenderTerrain: .forest,
            tuning: .standard)
        #expect(onOpen == 13)
        #expect(onForest == 8)
    }

    @Test func armorNeverDropsDamageBelowOne() {
        // Archer (damage 10) is not countered by shield's armor(4); shieldWall cuts a further 70%: 10 * 0.3 = 3,
        // which armor alone would push negative without the floor.
        let damage = Combat.damage(
            attacker: Fixtures.unitType(Fixtures.archer), defender: Fixtures.unitType(Fixtures.shield),
            defenderTerrain: .open,
            defenderAbility: DefenderAbilityState(shieldWallActive: true), tuning: .standard)
        #expect(damage == 1)
    }

    @Test func spearWallAmplifiesBothSidesOfTheCounterRelationship() {
        // Attacker side: spearman vs cavalry, spearWall active: 12 * 1.5 * 1.5 = 27, minus armor (1).
        let attackerBonus = Combat.damage(
            attacker: Fixtures.unitType(Fixtures.spearman), defender: Fixtures.unitType(Fixtures.cavalry),
            defenderTerrain: .open,
            attackerAbility: AttackerAbilityState(spearWallActive: true), tuning: .standard)
        #expect(attackerBonus == 26)

        // Defender side: cavalry attacks spearman (not a counter for the attacker), spearman's spearWall halves it
        // because spearman counters cavalry: 14 * 0.5 = 7, minus armor (2).
        let defenderReduction = Combat.damage(
            attacker: Fixtures.unitType(Fixtures.cavalry), defender: Fixtures.unitType(Fixtures.spearman),
            defenderTerrain: .open,
            defenderAbility: DefenderAbilityState(spearWallActive: true), tuning: .standard)
        #expect(defenderReduction == 5)
    }

    @Test func spearWallDoesNothingOutsideTheCounterRelationship() {
        // Shield doesn't counter or get countered by spearman; spearWall on either side has no effect here.
        let damage = Combat.damage(
            attacker: Fixtures.unitType(Fixtures.spearman), defender: Fixtures.unitType(Fixtures.shield),
            defenderTerrain: .open,
            attackerAbility: AttackerAbilityState(spearWallActive: true),
            defenderAbility: DefenderAbilityState(spearWallActive: true), tuning: .standard)
        let plain = Combat.damage(
            attacker: Fixtures.unitType(Fixtures.spearman), defender: Fixtures.unitType(Fixtures.shield),
            defenderTerrain: .open,
            tuning: .standard)
        #expect(damage == plain)
    }

    @Test func chargeBonusStacksWithTheCounterMultiplier() {
        // Cavalry counters archer: 14 * 1.5 = 21; charge doubles it: 42; minus armor (0).
        let damage = Combat.damage(
            attacker: Fixtures.unitType(Fixtures.cavalry), defender: Fixtures.unitType(Fixtures.archer),
            defenderTerrain: .open,
            attackerAbility: AttackerAbilityState(chargeBonusApplies: true), tuning: .standard)
        #expect(damage == 42)
    }

    @Test func aHitFromBehindTheDefenderIsFlanking() {
        let facingEast = FixedVector2(x: .one, y: .zero)
        let attackerIsBehindToTheWest = FixedVector2(x: -.one, y: .zero)
        #expect(Combat.isFlankingHit(defenderFacing: facingEast, attackDirection: attackerIsBehindToTheWest))
    }

    @Test func aHitFromTheFrontIsNotFlanking() {
        let facingEast = FixedVector2(x: .one, y: .zero)
        let attackerIsAheadToTheEast = FixedVector2(x: .one, y: .zero)
        #expect(!Combat.isFlankingHit(defenderFacing: facingEast, attackDirection: attackerIsAheadToTheEast))
    }
}
