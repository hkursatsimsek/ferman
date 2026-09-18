/// One entry of the event stream the renderer replays (CLAUDE.md rule 4).
public struct BattleEvent: Sendable, Hashable {
    public let tick: Int32
    public let kind: Kind

    public init(tick: Int32, kind: Kind) {
        self.tick = tick
        self.kind = kind
    }

    public enum Kind: Sendable, Hashable {
        case spawn(UnitID, UnitTypeID, Team, FixedVector2)
        /// Sampled at 10 Hz, only for units whose position changed.
        case move(UnitID, FixedVector2)
        /// The unit switched to a different order; this is what `ruleFireCounts` counts (D9).
        case ruleActivated(UnitID, ruleIndex: Int)
        case attack(UnitID, target: UnitID, damage: Int)
        /// An ability started: a `volley` after its hits (same tick), a wall or charge when `useAbility` finds it
        /// off cooldown. Recorded for the replay only (D27); the simulation state is the same without it.
        case abilityUsed(UnitID, Ability)
        case death(UnitID)
        case moraleBroken(UnitID)
        case moraleRecovered(UnitID)
        case battleEnded(BattleOutcome, EndReason)
    }
}

/// Events encode flat, discriminated by `kind`: `{"tick": 42, "kind": "attack", "unit": 3, "target": 9, "damage": 7}`.
extension BattleEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case tick
        case kind
        case unit
        case unitType
        case team
        case position
        case ruleIndex
        case target
        case damage
        case ability
        case outcome
        case reason
    }

    private enum KindName: String, Codable {
        case spawn
        case move
        case ruleActivated
        case attack
        case abilityUsed
        case death
        case moraleBroken
        case moraleRecovered
        case battleEnded
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tick = try container.decode(Int32.self, forKey: .tick)

        func unit() throws -> UnitID {
            try container.decode(UnitID.self, forKey: .unit)
        }

        switch try container.decode(KindName.self, forKey: .kind) {
        case .spawn:
            kind = .spawn(
                try unit(),
                try container.decode(UnitTypeID.self, forKey: .unitType),
                try container.decode(Team.self, forKey: .team),
                try container.decode(FixedVector2.self, forKey: .position)
            )
        case .move:
            kind = .move(try unit(), try container.decode(FixedVector2.self, forKey: .position))
        case .ruleActivated:
            kind = .ruleActivated(try unit(), ruleIndex: try container.decode(Int.self, forKey: .ruleIndex))
        case .attack:
            kind = .attack(
                try unit(),
                target: try container.decode(UnitID.self, forKey: .target),
                damage: try container.decode(Int.self, forKey: .damage)
            )
        case .abilityUsed:
            kind = .abilityUsed(try unit(), try container.decode(Ability.self, forKey: .ability))
        case .death:
            kind = .death(try unit())
        case .moraleBroken:
            kind = .moraleBroken(try unit())
        case .moraleRecovered:
            kind = .moraleRecovered(try unit())
        case .battleEnded:
            kind = .battleEnded(
                try container.decode(BattleOutcome.self, forKey: .outcome),
                try container.decode(EndReason.self, forKey: .reason)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tick, forKey: .tick)
        switch kind {
        case .spawn(let unit, let unitType, let team, let position):
            try container.encode(KindName.spawn, forKey: .kind)
            try container.encode(unit, forKey: .unit)
            try container.encode(unitType, forKey: .unitType)
            try container.encode(team, forKey: .team)
            try container.encode(position, forKey: .position)
        case .move(let unit, let position):
            try container.encode(KindName.move, forKey: .kind)
            try container.encode(unit, forKey: .unit)
            try container.encode(position, forKey: .position)
        case .ruleActivated(let unit, let ruleIndex):
            try container.encode(KindName.ruleActivated, forKey: .kind)
            try container.encode(unit, forKey: .unit)
            try container.encode(ruleIndex, forKey: .ruleIndex)
        case .attack(let unit, let target, let damage):
            try container.encode(KindName.attack, forKey: .kind)
            try container.encode(unit, forKey: .unit)
            try container.encode(target, forKey: .target)
            try container.encode(damage, forKey: .damage)
        case .abilityUsed(let unit, let ability):
            try container.encode(KindName.abilityUsed, forKey: .kind)
            try container.encode(unit, forKey: .unit)
            try container.encode(ability, forKey: .ability)
        case .death(let unit):
            try container.encode(KindName.death, forKey: .kind)
            try container.encode(unit, forKey: .unit)
        case .moraleBroken(let unit):
            try container.encode(KindName.moraleBroken, forKey: .kind)
            try container.encode(unit, forKey: .unit)
        case .moraleRecovered(let unit):
            try container.encode(KindName.moraleRecovered, forKey: .kind)
            try container.encode(unit, forKey: .unit)
        case .battleEnded(let outcome, let reason):
            try container.encode(KindName.battleEnded, forKey: .kind)
            try container.encode(outcome, forKey: .outcome)
            try container.encode(reason, forKey: .reason)
        }
    }
}
