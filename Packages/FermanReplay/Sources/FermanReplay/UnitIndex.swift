import FermanCore

/// Identifies one unit type's order list for one team — the grain `RuleFireCounts` is kept at.
struct ProgramKey: Hashable {
    let team: Team
    let unitType: UnitTypeID
}

extension ProgramKey: Comparable {
    static func < (lhs: ProgramKey, rhs: ProgramKey) -> Bool {
        (lhs.team.rawValue, lhs.unitType) < (rhs.team.rawValue, rhs.unitType)
    }
}

/// (team, unit type) for every unit that ever spawned, read once from the event stream.
/// `ReplayTimeline` and `DebriefAnalyzer` both need this and neither owns the other.
struct UnitIndex: Sendable {
    private let info: [UnitID: (team: Team, unitType: UnitTypeID)]

    init(events: [BattleEvent]) {
        var info: [UnitID: (team: Team, unitType: UnitTypeID)] = [:]
        for event in events {
            if case .spawn(let unit, let unitType, let team, _) = event.kind {
                info[unit] = (team, unitType)
            }
        }
        self.info = info
    }

    func team(of unit: UnitID) -> Team? {
        info[unit]?.team
    }

    func unitType(of unit: UnitID) -> UnitTypeID? {
        info[unit]?.unitType
    }

    /// Every unit spawned for a (team, unit type), in spawn order.
    func units(team: Team, unitType: UnitTypeID) -> [UnitID] {
        info.filter { $0.value.team == team && $0.value.unitType == unitType }
            .map(\.key)
            .sorted()
    }

    /// Every unit spawned for a team, across all unit types.
    func units(team: Team) -> [UnitID] {
        info.filter { $0.value.team == team }
            .map(\.key)
            .sorted()
    }
}
