/// A problem found in a compiled army's rule programs, keyed by where it happened so the UI can point at the exact
/// order. Every kind a `RuleCompiler` produces passes through `validate` before the player ever sees it (CLAUDE.md
/// rule 3): the model can misuse a locked-out kind or an out-of-range parameter just as easily as a person can.
public enum RuleValidationError: Error, Equatable, Sendable {
    case conditionNotAvailable(unitType: UnitTypeID, ruleIndex: Int, kind: ConditionKind)
    case actionNotAvailable(unitType: UnitTypeID, ruleIndex: Int, kind: ActionKind)
    case conditionParameterOutOfRange(
        unitType: UnitTypeID, ruleIndex: Int, kind: ConditionKind, value: Int, validRange: ClosedRange<Int>)
    /// The default order (D4) must sit last in its program; anything after it can never be reached.
    case alwaysRuleIsNotLast(unitType: UnitTypeID, ruleIndex: Int)
    /// The army-wide total of non-`always` rules exceeds `RuleConstraints.maxRules` (D4).
    case ruleBudgetExceeded(used: Int, budget: Int)
}

/// Checks a level's worth of rule programs against what that level allows: locked conditions and actions,
/// out-of-range parameters, default-order placement, and the shared army-wide rule budget (D4, D8).
public enum RuleValidator {
    public static func validate(programs: [RuleProgram], constraints: RuleConstraints) -> [RuleValidationError] {
        var errors: [RuleValidationError] = []
        var budgetUsed = 0

        for program in programs {
            let lastRuleIndex = program.rules.count - 1
            for (ruleIndex, rule) in program.rules.enumerated() {
                let conditionKind = rule.condition.kind
                if conditionKind != .always {
                    budgetUsed += 1
                }
                if !constraints.availableConditions.contains(conditionKind) {
                    errors.append(
                        .conditionNotAvailable(unitType: program.unitType, ruleIndex: ruleIndex, kind: conditionKind))
                }
                if !constraints.availableActions.contains(rule.action.kind) {
                    errors.append(
                        .actionNotAvailable(unitType: program.unitType, ruleIndex: ruleIndex, kind: rule.action.kind))
                }
                if let violation = Self.rangeViolation(of: rule.condition) {
                    errors.append(
                        .conditionParameterOutOfRange(
                            unitType: program.unitType, ruleIndex: ruleIndex, kind: conditionKind,
                            value: violation.value, validRange: violation.range))
                }
                if conditionKind == .always, ruleIndex != lastRuleIndex {
                    errors.append(.alwaysRuleIsNotLast(unitType: program.unitType, ruleIndex: ruleIndex))
                }
            }
        }

        if budgetUsed > constraints.maxRules {
            errors.append(.ruleBudgetExceeded(used: budgetUsed, budget: constraints.maxRules))
        }
        return errors
    }

    private static func rangeViolation(of condition: Condition) -> (value: Int, range: ClosedRange<Int>)? {
        let value: Int
        switch condition {
        case .enemyWithin(let cells): value = cells
        case .healthBelow(let percent), .moraleBelow(let percent): value = percent
        case .allyCountBelow(let count), .enemyDensityAbove(let count): value = count
        case .timeAfter(let seconds): value = seconds
        case .isFlanked, .targetInRange, .nearestEnemyType, .terrainIs, .commanderDead, .always:
            return nil
        }
        guard let range = Self.numericRange(of: condition.kind.parameter) else {
            return nil
        }
        return range.contains(value) ? nil : (value, range)
    }

    private static func numericRange(of parameter: ConditionParameter) -> ClosedRange<Int>? {
        switch parameter {
        case .cells(let range), .percent(let range), .count(let range), .seconds(let range):
            range
        case .none, .unitType, .terrain:
            nil
        }
    }
}
