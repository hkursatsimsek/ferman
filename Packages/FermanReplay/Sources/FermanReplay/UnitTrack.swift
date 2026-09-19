import FermanCore

/// One unit's whole battle, indexed by tick (D27): where it went, what it hit, what hit it, when it
/// broke, when it fell. The renderer derives every pose from this as a pure function of replay time, so
/// seeking, 1×/2×/4× and an offline clip (D15) all draw the same frame.
///
/// Ticks only — no floating point here. Interpolating between ticks is the renderer's job.
public struct UnitTrack: Sendable, Hashable {
    public struct PathSample: Sendable, Hashable {
        public let tick: Int32
        public let position: FixedVector2
    }

    public struct Strike: Sendable, Hashable {
        public let tick: Int32
        /// The other side of the blow: the target for a strike made, the attacker for a strike taken.
        public let other: UnitID
        public let damage: Int
    }

    public struct AbilityStart: Sendable, Hashable {
        public let tick: Int32
        public let ability: Ability
    }

    public struct RuleActivation: Sendable, Hashable {
        public let tick: Int32
        public let ruleIndex: Int
    }

    /// Ticks `start..<end` during which morale was broken; `end` is `nil` if it never recovered.
    public struct MoraleBreak: Sendable, Hashable {
        public let start: Int32
        public let end: Int32?
    }

    public let unit: UnitID
    public let unitType: UnitTypeID
    public let team: Team
    /// Spawn position first, then every recorded move, in tick order. A unit that stands still records
    /// no moves (`BattleSimulator` samples only moving units), so a gap means it didn't move.
    public let path: [PathSample]
    public let strikesMade: [Strike]
    public let strikesTaken: [Strike]
    public let abilityStarts: [AbilityStart]
    public let ruleActivations: [RuleActivation]
    public let moraleBreaks: [MoraleBreak]
    public let deathTick: Int32?

    /// Where the unit stood at `tick`: its last sample at or before it (or its spawn point).
    public func sampleIndex(atOrBefore tick: Int32) -> Int {
        max(0, Self.lastIndex(in: path, atOrBefore: tick, tickOf: \.tick))
    }

    public func position(at tick: Int32) -> FixedVector2 {
        path[sampleIndex(atOrBefore: tick)].position
    }

    public func isAlive(at tick: Int32) -> Bool {
        deathTick.map { tick < $0 } ?? true
    }

    public func isMoraleBroken(at tick: Int32) -> Bool {
        moraleBreaks.contains { tick >= $0.start && $0.end.map { tick < $0 } ?? true }
    }

    /// The latest strike this unit made at or before `tick`.
    public func lastStrikeMade(atOrBefore tick: Int32) -> Strike? {
        let index = Self.lastIndex(in: strikesMade, atOrBefore: tick, tickOf: \.tick)
        return index >= 0 ? strikesMade[index] : nil
    }

    /// The latest blow this unit took at or before `tick`.
    public func lastStrikeTaken(atOrBefore tick: Int32) -> Strike? {
        let index = Self.lastIndex(in: strikesTaken, atOrBefore: tick, tickOf: \.tick)
        return index >= 0 ? strikesTaken[index] : nil
    }

    public func lastAbilityStart(atOrBefore tick: Int32) -> AbilityStart? {
        let index = Self.lastIndex(in: abilityStarts, atOrBefore: tick, tickOf: \.tick)
        return index >= 0 ? abilityStarts[index] : nil
    }

    public func lastRuleActivation(atOrBefore tick: Int32) -> RuleActivation? {
        let index = Self.lastIndex(in: ruleActivations, atOrBefore: tick, tickOf: \.tick)
        return index >= 0 ? ruleActivations[index] : nil
    }

    /// Every strike this unit makes in `ticks` — e.g. the arrows already in the air at some moment.
    public func strikesMade(in ticks: ClosedRange<Int32>) -> ArraySlice<Strike> {
        let start = Self.lastIndex(in: strikesMade, atOrBefore: ticks.lowerBound - 1, tickOf: \.tick) + 1
        let end = Self.lastIndex(in: strikesMade, atOrBefore: ticks.upperBound, tickOf: \.tick) + 1
        return strikesMade[start..<max(start, end)]
    }

    /// Damage taken up to and including `tick`.
    public func damageTaken(upTo tick: Int32) -> Int {
        let index = Self.lastIndex(in: strikesTaken, atOrBefore: tick, tickOf: \.tick)
        return index >= 0 ? damagePrefix[index] : 0
    }

    private let damagePrefix: [Int]

    init(
        unit: UnitID, unitType: UnitTypeID, team: Team, path: [PathSample], strikesMade: [Strike],
        strikesTaken: [Strike], abilityStarts: [AbilityStart], ruleActivations: [RuleActivation],
        moraleBreaks: [MoraleBreak], deathTick: Int32?
    ) {
        self.unit = unit
        self.unitType = unitType
        self.team = team
        self.path = path
        self.strikesMade = strikesMade
        self.strikesTaken = strikesTaken
        self.abilityStarts = abilityStarts
        self.ruleActivations = ruleActivations
        self.moraleBreaks = moraleBreaks
        self.deathTick = deathTick
        var total = 0
        self.damagePrefix = strikesTaken.map { strike in
            total += strike.damage
            return total
        }
    }

    /// The last index whose tick is `<= tick`, or -1. `elements` must be sorted by tick.
    private static func lastIndex<Element>(
        in elements: [Element], atOrBefore tick: Int32, tickOf: (Element) -> Int32
    ) -> Int {
        var low = 0
        var high = elements.count
        while low < high {
            let middle = (low + high) / 2
            if tickOf(elements[middle]) <= tick {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low - 1
    }
}

/// Every unit's `UnitTrack`, built in one pass over a result's events.
public struct UnitTracks: Sendable {
    public let tracks: [UnitTrack]
    private let indexByUnit: [UnitID: Int]

    /// Requires `result.events` sorted by tick, as `BattleSimulator` produces them.
    public init(result: BattleResult) {
        var builders: [UnitID: Builder] = [:]
        var order: [UnitID] = []

        for event in result.events {
            switch event.kind {
            case .spawn(let unit, let unitType, let team, let position):
                builders[unit] = Builder(unit: unit, unitType: unitType, team: team, spawn: position)
                order.append(unit)
            case .move(let unit, let position):
                builders[unit]?.path.append(UnitTrack.PathSample(tick: event.tick, position: position))
            case .attack(let attacker, let target, let damage):
                builders[attacker]?.strikesMade.append(
                    UnitTrack.Strike(tick: event.tick, other: target, damage: damage))
                builders[target]?.strikesTaken.append(
                    UnitTrack.Strike(tick: event.tick, other: attacker, damage: damage))
            case .abilityUsed(let unit, let ability):
                builders[unit]?.abilityStarts.append(UnitTrack.AbilityStart(tick: event.tick, ability: ability))
            case .ruleActivated(let unit, let ruleIndex):
                builders[unit]?.ruleActivations.append(
                    UnitTrack.RuleActivation(tick: event.tick, ruleIndex: ruleIndex))
            case .moraleBroken(let unit):
                builders[unit]?.brokenSince = event.tick
            case .moraleRecovered(let unit):
                builders[unit]?.closeMoraleBreak(at: event.tick)
            case .death(let unit):
                builders[unit]?.deathTick = event.tick
                builders[unit]?.closeMoraleBreak(at: event.tick)
            case .battleEnded:
                break
            }
        }

        tracks = order.compactMap { builders[$0]?.build() }
        indexByUnit = Dictionary(uniqueKeysWithValues: tracks.enumerated().map { ($1.unit, $0) })
    }

    public subscript(unit: UnitID) -> UnitTrack? {
        indexByUnit[unit].map { tracks[$0] }
    }

    private struct Builder {
        let unit: UnitID
        let unitType: UnitTypeID
        let team: Team
        var path: [UnitTrack.PathSample]
        var strikesMade: [UnitTrack.Strike] = []
        var strikesTaken: [UnitTrack.Strike] = []
        var abilityStarts: [UnitTrack.AbilityStart] = []
        var ruleActivations: [UnitTrack.RuleActivation] = []
        var moraleBreaks: [UnitTrack.MoraleBreak] = []
        var brokenSince: Int32?
        var deathTick: Int32?

        init(unit: UnitID, unitType: UnitTypeID, team: Team, spawn: FixedVector2) {
            self.unit = unit
            self.unitType = unitType
            self.team = team
            self.path = [UnitTrack.PathSample(tick: 0, position: spawn)]
        }

        mutating func closeMoraleBreak(at tick: Int32) {
            guard let start = brokenSince else { return }
            moraleBreaks.append(UnitTrack.MoraleBreak(start: start, end: tick))
            brokenSince = nil
        }

        func build() -> UnitTrack {
            var breaks = moraleBreaks
            if let start = brokenSince {
                breaks.append(UnitTrack.MoraleBreak(start: start, end: nil))
            }
            return UnitTrack(
                unit: unit, unitType: unitType, team: team, path: path, strikesMade: strikesMade,
                strikesTaken: strikesTaken, abilityStarts: abilityStarts, ruleActivations: ruleActivations,
                moraleBreaks: breaks, deathTick: deathTick)
        }
    }
}
