import FermanCore
import Testing

@testable import FermanAI

struct ManualCompilerTests {
    private static let archer: UnitTypeID = "okcu"
    private static let context = CompileContext(
        unitType: "mizrakci", constraints: .unrestricted, availableUnitTypes: [archer, "mizrakci"],
        remainingRuleBudget: 6)

    @Test(
        arguments: [
            (ConditionKind.enemyWithin, Condition.enemyWithin(cells: 3)),
            (ConditionKind.healthBelow, Condition.healthBelow(percent: 35)),
            (ConditionKind.allyCountBelow, Condition.allyCountBelow(count: 2)),
            (ConditionKind.timeAfter, Condition.timeAfter(seconds: 20)),
            (ConditionKind.moraleBelow, Condition.moraleBelow(percent: 40)),
            (ConditionKind.enemyDensityAbove, Condition.enemyDensityAbove(count: 4)),
        ] as [(ConditionKind, Condition)])
    func compilesNumericConditions(kind: ConditionKind, expected: Condition) async throws {
        var draft = RuleDraft(conditionKind: kind, actionKind: .hold)
        draft.conditionNumericValue = Self.numericValue(of: expected)

        let rules = try await ManualCompiler().compile(draft, context: Self.context)

        #expect(rules == [Rule(condition: expected, action: .hold)])
    }

    @Test(
        arguments: [
            ConditionKind.enemyWithin, .healthBelow, .allyCountBelow, .timeAfter, .moraleBelow,
            .enemyDensityAbove,
        ])
    func missingNumericValueThrows(kind: ConditionKind) async throws {
        let draft = RuleDraft(conditionKind: kind, actionKind: .hold)

        await #expect(throws: RuleCompileError.missingConditionParameter(kind)) {
            try await ManualCompiler().compile(draft, context: Self.context)
        }
    }

    @Test
    func compilesUnitTypeConditions() async throws {
        let targetInRange = RuleDraft(conditionKind: .targetInRange, conditionUnitType: Self.archer, actionKind: .hold)
        let nearestEnemyType = RuleDraft(
            conditionKind: .nearestEnemyType, conditionUnitType: Self.archer, actionKind: .hold)

        #expect(
            try await ManualCompiler().compile(targetInRange, context: Self.context)
                == [Rule(condition: .targetInRange(Self.archer), action: .hold)])
        #expect(
            try await ManualCompiler().compile(nearestEnemyType, context: Self.context)
                == [Rule(condition: .nearestEnemyType(Self.archer), action: .hold)])
    }

    @Test
    func missingUnitTypeThrows() async throws {
        let draft = RuleDraft(conditionKind: .targetInRange, actionKind: .hold)

        await #expect(throws: RuleCompileError.missingConditionParameter(.targetInRange)) {
            try await ManualCompiler().compile(draft, context: Self.context)
        }
    }

    @Test
    func compilesTerrainCondition() async throws {
        let draft = RuleDraft(conditionKind: .terrainIs, conditionTerrain: .forest, actionKind: .hold)

        let rules = try await ManualCompiler().compile(draft, context: Self.context)

        #expect(rules == [Rule(condition: .terrainIs(.forest), action: .hold)])
    }

    @Test
    func missingTerrainThrows() async throws {
        let draft = RuleDraft(conditionKind: .terrainIs, actionKind: .hold)

        await #expect(throws: RuleCompileError.missingConditionParameter(.terrainIs)) {
            try await ManualCompiler().compile(draft, context: Self.context)
        }
    }

    @Test(arguments: [ConditionKind.isFlanked, .commanderDead, .always])
    func parameterlessConditionsNeedNoValue(kind: ConditionKind) async throws {
        let draft = RuleDraft(conditionKind: kind, actionKind: .advance)

        let rules = try await ManualCompiler().compile(draft, context: Self.context)

        #expect(rules.count == 1)
        #expect(rules[0].condition.kind == kind)
    }

    @Test
    func focusFireWithoutATargetCompilesToNil() async throws {
        let draft = RuleDraft(conditionKind: .always, actionKind: .focusFire)

        let rules = try await ManualCompiler().compile(draft, context: Self.context)

        #expect(rules == [Rule(condition: .always, action: .focusFire(nil))])
    }

    @Test
    func focusFireWithATargetCompilesToThatUnitType() async throws {
        let draft = RuleDraft(conditionKind: .always, actionKind: .focusFire, actionUnitType: Self.archer)

        let rules = try await ManualCompiler().compile(draft, context: Self.context)

        #expect(rules == [Rule(condition: .always, action: .focusFire(Self.archer))])
    }

    private static func numericValue(of condition: Condition) -> Int? {
        switch condition {
        case .enemyWithin(let cells): cells
        case .healthBelow(let percent), .moraleBelow(let percent): percent
        case .allyCountBelow(let count), .enemyDensityAbove(let count): count
        case .timeAfter(let seconds): seconds
        default: nil
        }
    }
}
