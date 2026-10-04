import FermanCore
import Testing

@testable import FermanAI

struct RuleDraftTests {
    private static let context = CompileContext(
        unitType: "okcu", constraints: .unrestricted, availableUnitTypes: ["okcu", "kalkan"], remainingRuleBudget: 6)

    private static func drafts(_ text: String) async throws -> [RuleDraft] {
        try await TemplateCompiler().drafts(from: text, context: context)
    }

    @Test(
        arguments: [
            Rule(condition: .enemyWithin(cells: 3), action: .retreat),
            Rule(condition: .healthBelow(percent: 40), action: .takeCover),
            Rule(condition: .targetInRange("suvari"), action: .focusFire("suvari")),
            Rule(condition: .nearestEnemyType("okcu"), action: .focusFire(nil)),
            Rule(condition: .terrainIs(.forest), action: .hold),
            Rule(condition: .isFlanked, action: .scatter),
            Rule(condition: .commanderDead, action: .guardCommander),
            Rule(condition: .timeAfter(seconds: 10), action: .flankLeft),
            Rule(condition: .always, action: .advance),
        ])
    func roundTripsEveryRuleShape(rule: Rule) throws {
        let draft = RuleDraft(rule)
        #expect(!draft.isMissingConditionParameter)
        #expect(try draft.rule() == rule)
    }

    @Test func aMissingNumberStaysBlankInsteadOfRefusingTheSentence() async throws {
        let drafts = try await Self.drafts("düşman yaklaşırsa geri çekil, canım %30'un altındaysa siper al")
        #expect(drafts.count == 2)
        #expect(drafts[0].conditionKind == .enemyWithin)
        #expect(drafts[0].conditionNumericValue == nil)
        #expect(drafts[0].isMissingConditionParameter)
        #expect(drafts[0].actionKind == .retreat)
        #expect(try drafts[1].rule() == Rule(condition: .healthBelow(percent: 30), action: .takeCover))
        #expect(throws: RuleCompileError.missingConditionParameter(.enemyWithin)) { try drafts[0].rule() }
    }

    @Test func aMissingUnitTypeStaysBlank() async throws {
        let drafts = try await Self.drafts("menzilimde düşman varsa yüklen")
        #expect(drafts == [RuleDraft(conditionKind: .targetInRange, actionKind: .focusFire)])
        #expect(drafts[0].isMissingConditionParameter)
    }

    @Test func draftsKeepTheDefaultOrderLast() async throws {
        let drafts = try await Self.drafts("başka durumda yerinde kal, düşman 2 kareden yakınsa geri çekil")
        #expect(drafts.map(\.conditionKind) == [.enemyWithin, .always])
        #expect(drafts.last?.actionKind == .hold)
    }

    @Test func everythingElseThatCannotBeReadIsStillAnError() async {
        await #expect(throws: RuleCompileError.unsupportedComparison(.healthBelow)) {
            try await Self.drafts("canım %40'ın üstündeyse ilerle")
        }
        await #expect(throws: RuleCompileError.missingAction(.enemyWithin)) {
            try await Self.drafts("düşman yaklaşırsa")
        }
        await #expect(throws: RuleCompileError.noOrderRecognized) {
            try await Self.drafts("merhaba komutan")
        }
    }
}
