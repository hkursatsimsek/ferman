import Testing

@testable import FermanCore

@Suite("RuleValidator")
struct RuleValidatorTests {
    private static let archer: UnitTypeID = "okcu"
    private static let spearman: UnitTypeID = "mizrakci"

    @Test func aWellFormedProgramWithinBudgetHasNoErrors() {
        let programs = [
            RuleProgram(
                unitType: Self.archer,
                rules: [
                    Rule(condition: .enemyWithin(cells: 3), action: .retreat),
                    Rule(condition: .always, action: .hold),
                ]
            )
        ]
        #expect(RuleValidator.validate(programs: programs, constraints: .unrestricted).isEmpty)
    }

    @Test func aConditionOutsideTheLevelsAvailableSetIsRejected() {
        let programs = [RuleProgram(unitType: Self.archer, rules: [Rule(condition: .isFlanked, action: .hold)])]
        let constraints = RuleConstraints(
            maxRules: 12, availableConditions: [.enemyWithin], availableActions: ActionKind.allCases)
        #expect(
            RuleValidator.validate(programs: programs, constraints: constraints) == [
                .conditionNotAvailable(unitType: Self.archer, ruleIndex: 0, kind: .isFlanked)
            ])
    }

    @Test func anActionOutsideTheLevelsAvailableSetIsRejected() {
        let programs = [RuleProgram(unitType: Self.archer, rules: [Rule(condition: .always, action: .scatter)])]
        let constraints = RuleConstraints(
            maxRules: 12, availableConditions: ConditionKind.allCases, availableActions: [.hold])
        #expect(
            RuleValidator.validate(programs: programs, constraints: constraints) == [
                .actionNotAvailable(unitType: Self.archer, ruleIndex: 0, kind: .scatter)
            ])
    }

    @Test(
        arguments: [
            (Condition.enemyWithin(cells: 0), false), (.enemyWithin(cells: 1), true), (.enemyWithin(cells: 10), true),
            (.enemyWithin(cells: 11), false),
            (.healthBelow(percent: 9), false), (.healthBelow(percent: 10), true), (.healthBelow(percent: 90), true),
            (.healthBelow(percent: 91), false),
            (.moraleBelow(percent: 9), false), (.moraleBelow(percent: 90), true), (.moraleBelow(percent: 91), false),
            (.allyCountBelow(count: 0), false), (.allyCountBelow(count: 1), true), (.allyCountBelow(count: 10), true),
            (.allyCountBelow(count: 11), false),
            (.enemyDensityAbove(count: 1), false), (.enemyDensityAbove(count: 2), true),
            (.enemyDensityAbove(count: 8), true), (.enemyDensityAbove(count: 9), false),
            (.timeAfter(seconds: 0), false), (.timeAfter(seconds: 1), true), (.timeAfter(seconds: 60), true),
            (.timeAfter(seconds: 61), false),
        ] as [(Condition, Bool)]
    )
    func conditionParametersAreValidatedAgainstTheirRange(condition: Condition, isValid: Bool) {
        let programs = [RuleProgram(unitType: Self.archer, rules: [Rule(condition: condition, action: .hold)])]
        let errors = RuleValidator.validate(programs: programs, constraints: .unrestricted)
        let hasRangeError = errors.contains {
            if case .conditionParameterOutOfRange = $0 { true } else { false }
        }
        #expect(hasRangeError == !isValid, "\(condition) valid=\(isValid) errors=\(errors)")
    }

    @Test func unparameterizedConditionsNeverProduceARangeError() {
        let programs = [
            RuleProgram(
                unitType: Self.archer,
                rules: [
                    Rule(condition: .isFlanked, action: .hold),
                    Rule(condition: .commanderDead, action: .hold),
                    Rule(condition: .terrainIs(.forest), action: .hold),
                    Rule(condition: .targetInRange(Self.spearman), action: .hold),
                    Rule(condition: .nearestEnemyType(Self.spearman), action: .hold),
                    Rule(condition: .always, action: .hold),
                ]
            )
        ]
        #expect(RuleValidator.validate(programs: programs, constraints: .unrestricted).isEmpty)
    }

    @Test func anAlwaysRuleThatIsNotLastIsRejected() {
        let programs = [
            RuleProgram(
                unitType: Self.archer,
                rules: [Rule(condition: .always, action: .hold), Rule(condition: .isFlanked, action: .retreat)]
            )
        ]
        #expect(
            RuleValidator.validate(programs: programs, constraints: .unrestricted) == [
                .alwaysRuleIsNotLast(unitType: Self.archer, ruleIndex: 0)
            ])
    }

    @Test func alwaysRulesDoNotConsumeTheBudget() {
        let program = RuleProgram(
            unitType: Self.archer,
            rules: Array(repeating: Rule(condition: .always, action: .hold), count: 50)
        )
        let constraints = RuleConstraints(maxRules: 0, availableConditions: [.always], availableActions: [.hold])
        // Every rule but the last violates "not last"; none should trip the budget check.
        let errors = RuleValidator.validate(programs: [program], constraints: constraints)
        #expect(!errors.contains { if case .ruleBudgetExceeded = $0 { true } else { false } })
    }

    @Test func theBudgetIsSharedAcrossEveryProgramInTheArmy() {
        let rule = Rule(condition: .isFlanked, action: .hold)
        let programs = [
            RuleProgram(unitType: Self.archer, rules: [rule, rule]),
            RuleProgram(unitType: Self.spearman, rules: [rule]),
        ]
        let constraints = RuleConstraints(
            maxRules: 3, availableConditions: [.isFlanked], availableActions: [.hold])
        #expect(RuleValidator.validate(programs: programs, constraints: constraints).isEmpty)

        let tighter = RuleConstraints(maxRules: 2, availableConditions: [.isFlanked], availableActions: [.hold])
        #expect(
            RuleValidator.validate(programs: programs, constraints: tighter) == [
                .ruleBudgetExceeded(used: 3, budget: 2)
            ]
        )
    }

    @Test func everyViolationOnARuleIsReportedTogether() {
        let programs = [
            RuleProgram(
                unitType: Self.archer, rules: [Rule(condition: .healthBelow(percent: 5), action: .scatter)])
        ]
        let constraints = RuleConstraints(maxRules: 12, availableConditions: [], availableActions: [])
        let errors = RuleValidator.validate(programs: programs, constraints: constraints)
        #expect(errors.count == 3)
        #expect(errors.contains(.conditionNotAvailable(unitType: Self.archer, ruleIndex: 0, kind: .healthBelow)))
        #expect(errors.contains(.actionNotAvailable(unitType: Self.archer, ruleIndex: 0, kind: .scatter)))
        #expect(
            errors.contains(
                .conditionParameterOutOfRange(
                    unitType: Self.archer, ruleIndex: 0, kind: .healthBelow, value: 5, validRange: 10...90)))
    }
}
