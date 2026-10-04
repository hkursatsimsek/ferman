import FermanAI
import FermanCore
import Testing

@testable import Ferman

/// F2.4: a typed order becomes unsealed slips the player checks, fills in and seals. Nothing written
/// reaches `programs` (and so a battle) before it is sealed (CLAUDE.md rule 3).
@MainActor
struct WrittenOrdersTests {
    private static let archer: UnitTypeID = "okcu"
    private static let shield: UnitTypeID = "kalkan"

    private static func makeModel(
        constraints: RuleConstraints = .unrestricted,
        initialPrograms: [RuleProgram] = [],
        audio: any AudioPlaying = SilentAudioPlaying()
    ) -> RuleEditorModel {
        RuleEditorModel(
            unitTypes: [archer, shield], catalog: Fixture.catalog, constraints: constraints,
            initialPrograms: initialPrograms, audio: audio)
    }

    private static func constraints(
        maxRules: Int = 6,
        conditions: [ConditionKind] = ConditionKind.allCases,
        actions: [ActionKind] = ActionKind.allCases
    ) -> RuleConstraints {
        RuleConstraints(maxRules: maxRules, availableConditions: conditions, availableActions: actions)
    }

    @Test
    func writingLaysSlipsOnTheTableWithoutTouchingTheProgram() async {
        let model = Self.makeModel()
        let programsBefore = model.programs

        await model.write("düşman 3 kareden yakınsa geri çekil, canım %30'un altındaysa siper al")

        #expect(model.written?.unitType == Self.archer)
        #expect(model.written?.slips.map(\.draft) == [
            RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 3, actionKind: .retreat),
            RuleDraft(conditionKind: .healthBelow, conditionNumericValue: 30, actionKind: .takeCover),
        ])
        #expect(model.programs == programsBefore)
        #expect(model.usedBudget == 0)
        #expect(model.battleBlocker == .unsealedOrders)
        #expect(model.sealBlocker == nil)
    }

    @Test
    func sealingAppendsTheOrdersInWrittenOrderAndStampsThem() async {
        let audio = RecordingAudio()
        let model = Self.makeModel(audio: audio)
        await model.addRule(RuleDraft(conditionKind: .isFlanked, actionKind: .scatter))

        await model.write("düşman 3 kareden yakınsa geri çekil, canım %30'un altındaysa siper al")
        model.sealWritten()

        #expect(model.orders.map(\.rule) == [
            Rule(condition: .isFlanked, action: .scatter),
            Rule(condition: .enemyWithin(cells: 3), action: .retreat),
            Rule(condition: .healthBelow(percent: 30), action: .takeCover),
        ])
        #expect(model.written == nil)
        #expect(model.battleBlocker == nil)
        #expect(model.justSealed == Set(model.orders.dropFirst().map(\.id)))
        #expect(audio.played == [.paper, .stamp])
    }

    @Test
    func aWrittenDefaultOrderReplacesTheDefaultWhenSealed() async {
        let model = Self.makeModel()

        await model.write("düşman 2 kareden yakınsa geri çekil, başka durumda yerinde kal")
        #expect(model.written?.slips.map(\.isDefault) == [false, true])
        model.sealWritten()

        #expect(model.orders.map(\.rule) == [Rule(condition: .enemyWithin(cells: 2), action: .retreat)])
        #expect(model.defaultRule.rule == Rule(condition: .always, action: .hold))
        #expect(model.usedBudget == 1)
    }

    @Test
    func aMissingNumberIsABlankThatBlocksSealingUntilFilled() async throws {
        let model = Self.makeModel()

        await model.write("düşman yaklaşırsa geri çekil")
        let slip = try #require(model.written?.slips.first)
        #expect(model.slipIssues[slip.id] == .blank)
        #expect(model.sealBlocker == .blank)
        // The dial starts a blank where a new order would.
        #expect(model.slipNumericParameter(for: slip.id)?.value == 1)
        #expect(model.slipNumericParameter(for: slip.id)?.range == 1...10)

        model.sealWritten()
        #expect(model.orders.isEmpty)

        model.setSlipNumber(4, for: slip.id)
        #expect(model.sealBlocker == nil)
        model.sealWritten()
        #expect(model.orders.map(\.rule) == [Rule(condition: .enemyWithin(cells: 4), action: .retreat)])
    }

    @Test
    func aMissingUnitTypeIsFilledThroughTheSheet() async throws {
        let model = Self.makeModel()

        await model.write("menzilimde düşman varsa yüklen")
        let slip = try #require(model.written?.slips.first)
        #expect(model.slipNumericParameter(for: slip.id) == nil)
        #expect(model.sealBlocker == .blank)

        model.updateSlip(
            slip.id, to: RuleDraft(conditionKind: .targetInRange, conditionUnitType: "kalkan", actionKind: .focusFire))
        model.sealWritten()
        #expect(model.orders.map(\.rule) == [Rule(condition: .targetInRange("kalkan"), action: .focusFire(nil))])
    }

    @Test
    func aKindThisFrontLocksIsFlaggedOnItsSlip() async throws {
        let model = Self.makeModel(
            constraints: Self.constraints(
                conditions: [.enemyWithin, .always], actions: [.advance, .retreat, .hold]))

        await model.write("düşman 3 kareden yakınsa geri çekil, canım %30'un altındaysa siper al, düşman 2 kareden yakınsa dağıl")
        let slips = try #require(model.written?.slips)
        #expect(model.slipIssues[slips[0].id] == nil)
        #expect(model.slipIssues[slips[1].id] == .conditionLocked)
        #expect(model.slipIssues[slips[2].id] == .actionLocked)
        #expect(model.sealBlocker == .notAllowedHere)

        model.removeSlip(slips[1].id)
        model.removeSlip(slips[2].id)
        #expect(model.sealBlocker == nil)
    }

    @Test
    func anOutOfRangeNumberIsFlaggedWithItsRange() async throws {
        let model = Self.makeModel()

        await model.write("düşman 15 kareden yakınsa geri çekil")
        let slip = try #require(model.written?.slips.first)
        #expect(model.slipIssues[slip.id] == .outOfRange(1...10))
    }

    @Test
    func moreNewOrdersThanTheBudgetHasRoomForCannotBeSealed() async {
        let model = Self.makeModel(constraints: Self.constraints(maxRules: 2))
        await model.addRule(RuleDraft(conditionKind: .isFlanked, actionKind: .scatter))

        await model.write("düşman 3 kareden yakınsa geri çekil, canım %30'un altındaysa siper al, ilerle")
        #expect(model.sealBlocker == .budget(needed: 2, remaining: 1))

        // Freeing room in the stack while the slips wait is enough.
        model.removeRule(model.orders[0].id)
        #expect(model.sealBlocker == nil)
    }

    @Test
    func discardingLeavesEverythingAsItWas() async {
        let model = Self.makeModel()
        let programsBefore = model.programs

        await model.write("ilerle, düşman 3 kareden yakınsa geri çekil")
        model.discardWritten()

        #expect(model.written == nil)
        #expect(model.programs == programsBefore)
        #expect(model.battleBlocker == nil)
    }

    @Test
    func removingTheLastSlipClearsTheTable() async throws {
        let model = Self.makeModel()

        await model.write("geri çekil")
        let slip = try #require(model.written?.slips.first)
        model.removeSlip(slip.id)

        #expect(model.written == nil)
    }

    @Test
    func textThatIsNotAnOrderSaysWhyAndLaysNothingDown() async {
        let model = Self.makeModel()

        await model.write("canım %40'ın üstündeyse ilerle")

        #expect(model.written == nil)
        #expect(model.writeError == .unsupportedComparison(.healthBelow))
        #expect(model.battleBlocker == nil)
    }

    @Test
    func theWrittenOrdersStayOnTheirTabUntilSealedOrDiscarded() async {
        let model = Self.makeModel()

        await model.write("geri çekil")
        model.selectUnitType(Self.shield)
        #expect(model.selectedUnitType == Self.archer)

        model.discardWritten()
        model.selectUnitType(Self.shield)
        #expect(model.selectedUnitType == Self.shield)
    }

    @Test
    func blankSlipsReadWithAGapInTheirCondition() {
        let blank = RuleDraft(conditionKind: .enemyWithin, actionKind: .retreat)
        let filled = RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 3, actionKind: .retreat)

        #expect(OrderPhraseFormatter.condition(of: blank) == "düşman \(OrderCard.blank) kareden yakınsa")
        #expect(OrderPhraseFormatter.condition(of: filled) == "düşman 3 kareden yakınsa")
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
