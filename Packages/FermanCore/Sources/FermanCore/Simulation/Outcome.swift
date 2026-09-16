/// Whether the battle is over, and why (§5.2.8). Both functions are pure: `BattleSimulator` calls the first after
/// every death and the second only once, when `maxTicks` is reached without an answer from the first.
enum Outcome {
    /// A team is done the moment it has no living units (`elimination`) or every living unit is broken (`rout`).
    /// `nil` means the battle continues.
    static func afterDeaths(units: [UnitState]) -> (outcome: BattleOutcome, reason: EndReason)? {
        let playerReason = Self.reason(of: .player, units: units)
        let enemyReason = Self.reason(of: .enemy, units: units)
        switch (playerReason, enemyReason) {
        case (nil, nil):
            return nil
        case (.some(let reason), nil):
            return (.enemyWin, reason)
        case (nil, .some(let reason)):
            return (.playerWin, reason)
        case (.some(let playerReason), .some(let enemyReason)):
            // Both teams gave out on the exact same tick: elimination is the more specific story when either side
            // has one, since a routed team could also happen to be down to zero units this same tick.
            return (.draw, playerReason == .elimination || enemyReason == .elimination ? .elimination : .rout)
        }
    }

    /// `maxTicks` elapsed with both teams still fielding at least one unbroken unit; the objective decides (§5.1).
    static func atTimeLimit(units: [UnitState], catalog: [UnitType], objective: BattleObjective)
        -> (outcome: BattleOutcome, reason: EndReason)
    {
        switch objective {
        case .holdLine:
            let playerAlive = units.contains { $0.team == .player && $0.isAlive }
            return (playerAlive ? .playerWin : .enemyWin, .timeLimit)
        case .eliminate:
            let playerValue = Self.remainingValue(of: .player, units: units, catalog: catalog)
            let enemyValue = Self.remainingValue(of: .enemy, units: units, catalog: catalog)
            if playerValue == enemyValue {
                return (.draw, .timeLimit)
            }
            return (playerValue > enemyValue ? .playerWin : .enemyWin, .timeLimit)
        }
    }

    private static func reason(of team: Team, units: [UnitState]) -> EndReason? {
        let living = units.filter { $0.team == team && $0.isAlive }
        if living.isEmpty {
            return .elimination
        }
        return living.allSatisfy { $0.morale.isBroken } ? .rout : nil
    }

    /// Σ `cost × hp / maxHP`, integer division per unit before summing so the total never depends on order.
    private static func remainingValue(of team: Team, units: [UnitState], catalog: [UnitType]) -> Int {
        units.filter { $0.team == team && $0.isAlive }.reduce(into: 0) { total, unit in
            guard let type = catalog.first(where: { $0.id == unit.type }) else { return }
            total += type.cost * unit.hp / type.maxHP
        }
    }
}
