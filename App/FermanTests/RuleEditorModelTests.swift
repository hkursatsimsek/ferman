import FermanAI
import FermanCore
import SwiftUI
import Testing

@testable import Ferman

@MainActor
struct RuleEditorModelTests {
    private static let archer: UnitTypeID = "okcu"
    private static let shield: UnitTypeID = "kalkan"

    private static func makeModel(
        initialPrograms: [RuleProgram] = [],
        constraints: RuleConstraints = .unrestricted
    ) -> RuleEditorModel {
        RuleEditorModel(
            unitTypes: [archer, shield], catalog: Fixture.catalog, constraints: constraints,
            initialPrograms: initialPrograms)
    }

    @Test
    func startsWithAFixedAdvanceDefaultWhenNoProgramIsGiven() {
        let model = Self.makeModel()

        #expect(model.orders.isEmpty)
        #expect(model.defaultRule.rule == Rule(condition: .always, action: .advance))
        #expect(model.usedBudget == 0)
    }

    @Test
    func decomposesAnExistingProgramIntoOrdersAndAFixedDefault() {
        let program = RuleProgram(
            unitType: Self.archer,
            rules: [
                Rule(condition: .enemyWithin(cells: 3), action: .retreat),
                Rule(condition: .always, action: .hold),
            ])
        let model = Self.makeModel(initialPrograms: [program])

        #expect(model.orders.map(\.rule) == [Rule(condition: .enemyWithin(cells: 3), action: .retreat)])
        #expect(model.defaultRule.rule == Rule(condition: .always, action: .hold))
    }

    @Test
    func addRuleAppendsAndCountsAgainstTheArmyWideBudget() async {
        let model = Self.makeModel()

        await model.addRule(RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 3, actionKind: .retreat))

        #expect(model.orders.map(\.rule) == [Rule(condition: .enemyWithin(cells: 3), action: .retreat)])
        #expect(model.usedBudget == 1)
    }

    @Test
    func addingAnIncompleteDraftSurfacesACompileErrorAndAddsNothing() async {
        let model = Self.makeModel()

        await model.addRule(RuleDraft(conditionKind: .enemyWithin, actionKind: .hold))

        #expect(model.orders.isEmpty)
        #expect(model.lastCompileError == .missingConditionParameter(.enemyWithin))
    }

    @Test
    func removeRuleTakesItOutAndFreesBudget() async {
        let model = Self.makeModel()
        await model.addRule(RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 3, actionKind: .retreat))
        let id = model.orders[0].id

        model.removeRule(id)

        #expect(model.orders.isEmpty)
        #expect(model.usedBudget == 0)
    }

    @Test
    func updateRuleRecompilesInPlaceWithoutChangingItsPosition() async {
        let model = Self.makeModel()
        await model.addRule(RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 3, actionKind: .retreat))
        await model.addRule(RuleDraft(conditionKind: .healthBelow, conditionNumericValue: 30, actionKind: .hold))
        let secondID = model.orders[1].id

        await model.updateRule(
            secondID, to: RuleDraft(conditionKind: .healthBelow, conditionNumericValue: 50, actionKind: .takeCover))

        #expect(model.orders[1].rule == Rule(condition: .healthBelow(percent: 50), action: .takeCover))
        #expect(model.orders[1].id == secondID)
    }

    @Test
    func updateDefaultActionKeepsTheConditionAlways() {
        let model = Self.makeModel()

        model.updateDefaultAction(.hold)

        #expect(model.defaultRule.rule == Rule(condition: .always, action: .hold))
    }

    @Test
    func moveUpAndMoveDownSwapAdjacentOrders() async {
        let model = Self.makeModel()
        await model.addRule(RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 3, actionKind: .retreat))
        await model.addRule(RuleDraft(conditionKind: .healthBelow, conditionNumericValue: 30, actionKind: .hold))
        let firstID = model.orders[0].id
        let secondID = model.orders[1].id

        model.moveDown(firstID)

        #expect(model.orders.map(\.id) == [secondID, firstID])

        model.moveUp(firstID)

        #expect(model.orders.map(\.id) == [firstID, secondID])
    }

    @Test
    func reorderMovesSourcesToJustBeforeTheirAnchor() async {
        let model = Self.makeModel()
        await model.addRule(RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 3, actionKind: .retreat))
        await model.addRule(RuleDraft(conditionKind: .healthBelow, conditionNumericValue: 30, actionKind: .hold))
        await model.addRule(RuleDraft(conditionKind: .isFlanked, actionKind: .takeCover))
        let ids = model.orders.map(\.id)

        model.reorder(sources: [ids[0]], before: ids[2])

        #expect(model.orders.map(\.id) == [ids[1], ids[0], ids[2]])
    }

    @Test
    func reorderWithNoAnchorAppendsToTheEnd() async {
        let model = Self.makeModel()
        await model.addRule(RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 3, actionKind: .retreat))
        await model.addRule(RuleDraft(conditionKind: .healthBelow, conditionNumericValue: 30, actionKind: .hold))
        let ids = model.orders.map(\.id)

        model.reorder(sources: [ids[0]], before: nil)

        #expect(model.orders.map(\.id) == [ids[1], ids[0]])
    }

    @Test
    func numericParameterRoundTripsThroughTheDial() async {
        let model = Self.makeModel()
        await model.addRule(RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 3, actionKind: .retreat))
        let id = model.orders[0].id

        let parameter = model.numericParameter(for: id)
        #expect(parameter?.value == 3)
        #expect(parameter?.range == 1...10)

        model.setNumericParameter(6, for: id)

        #expect(model.orders[0].rule.condition == .enemyWithin(cells: 6))
    }

    @Test
    func aRuleUsingALockedConditionIsFlaggedInvalid() async {
        let constraints = RuleConstraints(
            maxRules: 6, availableConditions: [.always], availableActions: ActionKind.allCases)
        let model = Self.makeModel(
            initialPrograms: [
                RuleProgram(
                    unitType: Self.archer,
                    rules: [
                        Rule(condition: .enemyWithin(cells: 3), action: .retreat),
                        Rule(condition: .always, action: .hold),
                    ])
            ], constraints: constraints)

        #expect(model.state(for: model.orders[0]) == .disabled)
    }

    @Test
    func applyPresetSkipsRulesTheLevelDoesNotAllowAndStopsAtBudget() async {
        let constraints = RuleConstraints(
            maxRules: 1, availableConditions: [.healthBelow, .always], availableActions: ActionKind.allCases)
        let model = Self.makeModel(constraints: constraints)

        await model.applyPreset(.cautious)

        // .cautious is [enemyWithin (locked out), healthBelow (allowed, spends the only budget slot)].
        #expect(model.orders.map(\.rule) == [Rule(condition: .healthBelow(percent: 30), action: .takeCover)])
    }
}

private enum Fixture {
    static let catalog: [UnitType] = [
        UnitType(
            id: "okcu", cost: 30, maxHP: 70, speedMilliCellsPerSecond: 1_000, rangeMilliCells: 6_000, damage: 10,
            attackIntervalTicks: 36, armor: 0, moraleMax: 90, counters: [], ability: .volley),
        UnitType(
            id: "kalkan", cost: 30, maxHP: 160, speedMilliCellsPerSecond: 900, rangeMilliCells: 1_000, damage: 8,
            attackIntervalTicks: 30, armor: 4, moraleMax: 120, counters: [], ability: .shieldWall),
    ]
}
