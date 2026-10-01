import FermanCore
import Testing

@testable import FermanAI

struct TemplateCompilerTests {
    private static let context = CompileContext(
        unitType: "okcu", constraints: .unrestricted, availableUnitTypes: ["okcu", "mizrakci", "kalkan", "suvari"],
        remainingRuleBudget: 6)

    private static func compile(_ text: String) async throws -> [Rule] {
        try await TemplateCompiler().compile(text, context: context)
    }

    private static func rule(_ condition: Condition, _ action: Action) -> Rule {
        Rule(condition: condition, action: action)
    }

    // MARK: One order, every condition

    @Test(
        arguments: [
            ("düşman 3 kareden yakınsa geri çekil", rule(.enemyWithin(cells: 3), .retreat)),
            ("Düşman üç kareye yaklaşırsa GERİ ÇEKİL", rule(.enemyWithin(cells: 3), .retreat)),
            ("dusman 3 kareden yakinsa geri cekil", rule(.enemyWithin(cells: 3), .retreat)),
            ("canım %40'ın altındaysa siper al", rule(.healthBelow(percent: 40), .takeCover)),
            ("canım yüzde kırk beşin altına düşerse geri çekil", rule(.healthBelow(percent: 45), .retreat)),
            ("canım yarıya düşerse toplan", rule(.healthBelow(percent: 50), .regroup)),
            ("yanımda 3'ten az dost varsa toplan", rule(.allyCountBelow(count: 3), .regroup)),
            ("kuşatıldıysam dağıl", rule(.isFlanked, .scatter)),
            ("menzilimde süvari varsa yüklen", rule(.targetInRange("suvari"), .focusFire(nil))),
            ("10. saniyeden sonra ilerle", rule(.timeAfter(seconds: 10), .advance)),
            ("on saniye sonra soldan kuşat", rule(.timeAfter(seconds: 10), .flankLeft)),
            ("en yakın düşman okçuysa sağdan kuşat", rule(.nearestEnemyType("okcu"), .flankRight)),
            ("moralim %30'un altındaysa komutanı koru", rule(.moraleBelow(percent: 30), .guardCommander)),
            ("ormandaysam yerinde kal", rule(.terrainIs(.forest), .hold)),
            ("tepedeysem bekle", rule(.terrainIs(.hill), .hold)),
            ("komutan düştüyse dağıl", rule(.commanderDead, .scatter)),
            ("yakınımda 4'ten fazla düşman varsa geri çekil", rule(.enemyDensityAbove(count: 4), .retreat)),
            ("düşman 2 kareden yakınsa mızrak duvarı", rule(.enemyWithin(cells: 2), .useAbility)),
            ("düşman 5 kareden yakınsa okçulara yüklen", rule(.enemyWithin(cells: 5), .focusFire("okcu"))),
            ("süvariler 2 kareden yakınsa yeteneğini kullan", rule(.enemyWithin(cells: 2), .useAbility)),
            ("atlılar menzile girerse ateş et", rule(.targetInRange("suvari"), .focusFire(nil))),
            ("moral 40'ın altındaysa komutanın yanına git", rule(.moraleBelow(percent: 40), .guardCommander)),
            ("canın 30'un altına inerse kaç", rule(.healthBelow(percent: 30), .retreat)),
            ("süvarilere saldır", rule(.always, .focusFire("suvari"))),
        ] as [(String, Rule)])
    func compilesTurkish(text: String, expected: Rule) async throws {
        #expect(try await Self.compile(text) == [expected])
    }

    @Test(
        arguments: [
            ("retreat if an enemy is within 3 cells", rule(.enemyWithin(cells: 3), .retreat)),
            ("If an enemy is within three cells, fall back", rule(.enemyWithin(cells: 3), .retreat)),
            ("take cover when health drops below 40%", rule(.healthBelow(percent: 40), .takeCover)),
            ("regroup if fewer than 3 allies nearby", rule(.allyCountBelow(count: 3), .regroup)),
            ("scatter if flanked", rule(.isFlanked, .scatter)),
            ("focus fire on the archers if cavalry is in range", rule(.targetInRange("suvari"), .focusFire("okcu"))),
            ("after 20 seconds advance", rule(.timeAfter(seconds: 20), .advance)),
            ("if the nearest enemy is cavalry, hold", rule(.nearestEnemyType("suvari"), .hold)),
            (
                "guard the commander when morale is below fifty percent",
                rule(.moraleBelow(percent: 50), .guardCommander)
            ),
            ("hold if in the forest", rule(.terrainIs(.forest), .hold)),
            ("if the commander is dead, retreat", rule(.commanderDead, .retreat)),
            ("retreat if more than 4 enemies are nearby", rule(.enemyDensityAbove(count: 4), .retreat)),
            ("use ability if an enemy is within 2 cells", rule(.enemyWithin(cells: 2), .useAbility)),
            ("attack the cavalry", rule(.always, .focusFire("suvari"))),
        ] as [(String, Rule)])
    func compilesEnglish(text: String, expected: Rule) async throws {
        #expect(try await Self.compile(text) == [expected])
    }

    // MARK: Several orders

    @Test func keepsWrittenOrderAndPutsTheDefaultLast() async throws {
        let text = "ilerle. canım %40'ın altındaysa siper al, düşman 3 kareden yakınsa geri çekil"

        #expect(
            try await Self.compile(text) == [
                Self.rule(.healthBelow(percent: 40), .takeCover),
                Self.rule(.enemyWithin(cells: 3), .retreat),
                Self.rule(.always, .advance),
            ])
    }

    @Test func readsAnExplicitDefaultOrder() async throws {
        let text = "düşman 3 kareden yakınsa geri çekil; başka durumda yerinde kal"

        #expect(
            try await Self.compile(text) == [
                Self.rule(.enemyWithin(cells: 3), .retreat), Self.rule(.always, .hold),
            ])
    }

    @Test func elseStartsTheDefaultOrder() async throws {
        #expect(
            try await Self.compile("if an enemy is within 3 cells then retreat else advance") == [
                Self.rule(.enemyWithin(cells: 3), .retreat), Self.rule(.always, .advance),
            ])
        #expect(
            try await Self.compile("düşman 3 kareden yakınsa geri çekil yoksa ilerle") == [
                Self.rule(.enemyWithin(cells: 3), .retreat), Self.rule(.always, .advance),
            ])
    }

    @Test func pairsAConditionWithTheActionAcrossAComma() async throws {
        #expect(
            try await Self.compile("retreat, if an enemy is within 3 cells") == [
                Self.rule(.enemyWithin(cells: 3), .retreat)
            ])
        #expect(
            try await Self.compile("düşman 3 kareden yakınsa, geri çekil") == [
                Self.rule(.enemyWithin(cells: 3), .retreat)
            ])
    }

    @Test func aBareActionIsTheDefaultOrder() async throws {
        #expect(try await Self.compile("İlerle!") == [Self.rule(.always, .advance)])
    }

    @Test func repeatingTheSameDefaultIsFine() async throws {
        #expect(try await Self.compile("ilerle. aksi halde ilerle") == [Self.rule(.always, .advance)])
    }

    // MARK: Faithful translation

    @Test func keepsOutOfRangeNumbersForTheValidatorToFlag() async throws {
        let rules = try await Self.compile("düşman 15 kareden yakınsa geri çekil")

        #expect(rules == [Self.rule(.enemyWithin(cells: 15), .retreat)])
        #expect(
            RuleValidator.validate(
                programs: [RuleProgram(unitType: "okcu", rules: rules)], constraints: .unrestricted)
                == [
                    .conditionParameterOutOfRange(
                        unitType: "okcu", ruleIndex: 0, kind: .enemyWithin, value: 15, validRange: 1...10)
                ])
    }

    @Test func doesNotDropKindsTheLevelLocks() async throws {
        let locked = CompileContext(
            unitType: "okcu",
            constraints: RuleConstraints(maxRules: 1, availableConditions: [.always], availableActions: [.advance]),
            availableUnitTypes: ["okcu"], remainingRuleBudget: 1)

        let rules = try await TemplateCompiler().compile("kuşatıldıysam dağıl", context: locked)

        #expect(rules == [Self.rule(.isFlanked, .scatter)])
    }

    @Test func conditionUnitIsNotMistakenForTheFocusTarget() async throws {
        #expect(
            try await Self.compile("en yakın düşman okçuysa yüklen") == [
                Self.rule(.nearestEnemyType("okcu"), .focusFire(nil))
            ])
    }

    @Test func aConditionalVerbIsNotAnAction() async throws {
        await #expect(throws: RuleCompileError.unrecognizedCondition) {
            try await Self.compile("düşman ilerlerse geri çekil")
        }
    }

    @Test func turkishArticleDoesNotStealTheNumber() async throws {
        #expect(
            try await Self.compile("bir düşman 4 kareden yakınsa geri çekil") == [
                Self.rule(.enemyWithin(cells: 4), .retreat)
            ])
    }

    @Test func minutesBecomeSeconds() async throws {
        #expect(try await Self.compile("1 dakika sonra ilerle") == [Self.rule(.timeAfter(seconds: 60), .advance)])
    }

    @Test func abilityNameIsNotReadAsAUnit() async throws {
        #expect(try await Self.compile("kalkan duvarı") == [Self.rule(.always, .useAbility)])
    }

    // MARK: Errors

    @Test(
        arguments: [
            ("düşman yaklaşırsa geri çekil", RuleCompileError.missingConditionParameter(.enemyWithin)),
            ("canım azalırsa siper al", .missingConditionParameter(.healthBelow)),
            ("menzilimde düşman varsa yüklen", .missingConditionParameter(.targetInRange)),
            ("düşman 3 kareden yakınsa", .missingAction(.enemyWithin)),
            ("düşman görünce geri çekil", .unrecognizedCondition),
            ("canım %40'ın üstündeyse ilerle", .unsupportedComparison(.healthBelow)),
            ("düşman 3 kareden uzaksa ilerle", .unsupportedComparison(.enemyWithin)),
            ("ilerle, başka durumda geri çekil", .conflictingDefaultOrders),
            ("ilk 10 saniye bekle sonra ilerle", .multipleActions),
            ("düşman çoksa geri çekil", .missingConditionParameter(.enemyDensityAbove)),
            ("merhaba komutan", .noOrderRecognized),
            ("", .noOrderRecognized),
        ] as [(String, RuleCompileError)])
    func reportsWhyTextIsNotAnOrder(text: String, expected: RuleCompileError) async throws {
        await #expect(throws: expected) {
            try await Self.compile(text)
        }
    }
}
