import Testing

@testable import FermanCore

/// "Folded under" orders (Faz 1.5, G9): an order below one whose condition holds whenever its own does can
/// never be picked — `RuleEvaluator.firstMatch` takes the first true rule. Thresholds tested at N−1, N, N+1.
@Suite("Rule reachability")
struct RuleReachabilityTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let lower: Condition
        let upper: Condition
        let implied: Bool
        var testDescription: String { "\(lower) ⇒ \(upper): \(implied)" }
    }

    static let cases: [Case] = [
        // Distance: within 3 always means within 5; within 5 doesn't mean within 3.
        Case(lower: .enemyWithin(cells: 2), upper: .enemyWithin(cells: 3), implied: true),
        Case(lower: .enemyWithin(cells: 3), upper: .enemyWithin(cells: 3), implied: true),
        Case(lower: .enemyWithin(cells: 4), upper: .enemyWithin(cells: 3), implied: false),
        // Below a threshold: below 20% is also below 30%.
        Case(lower: .healthBelow(percent: 29), upper: .healthBelow(percent: 30), implied: true),
        Case(lower: .healthBelow(percent: 30), upper: .healthBelow(percent: 30), implied: true),
        Case(lower: .healthBelow(percent: 31), upper: .healthBelow(percent: 30), implied: false),
        Case(lower: .moraleBelow(percent: 40), upper: .moraleBelow(percent: 50), implied: true),
        Case(lower: .moraleBelow(percent: 51), upper: .moraleBelow(percent: 50), implied: false),
        Case(lower: .allyCountBelow(count: 1), upper: .allyCountBelow(count: 2), implied: true),
        Case(lower: .allyCountBelow(count: 3), upper: .allyCountBelow(count: 2), implied: false),
        // After / above a threshold: after 20s is also after 10s.
        Case(lower: .timeAfter(seconds: 11), upper: .timeAfter(seconds: 10), implied: true),
        Case(lower: .timeAfter(seconds: 10), upper: .timeAfter(seconds: 10), implied: true),
        Case(lower: .timeAfter(seconds: 9), upper: .timeAfter(seconds: 10), implied: false),
        Case(lower: .enemyDensityAbove(count: 4), upper: .enemyDensityAbove(count: 3), implied: true),
        Case(lower: .enemyDensityAbove(count: 2), upper: .enemyDensityAbove(count: 3), implied: false),
        // Exact conditions only imply themselves.
        Case(lower: .targetInRange("okcu"), upper: .targetInRange("okcu"), implied: true),
        Case(lower: .targetInRange("okcu"), upper: .targetInRange("suvari"), implied: false),
        Case(lower: .nearestEnemyType("kalkan"), upper: .nearestEnemyType("kalkan"), implied: true),
        Case(lower: .terrainIs(.forest), upper: .terrainIs(.hill), implied: false),
        Case(lower: .isFlanked, upper: .isFlanked, implied: true),
        Case(lower: .commanderDead, upper: .commanderDead, implied: true),
        // Different kinds never imply each other, except that everything implies `.always`.
        Case(lower: .enemyWithin(cells: 1), upper: .healthBelow(percent: 99), implied: false),
        Case(lower: .isFlanked, upper: .always, implied: true),
        Case(lower: .always, upper: .isFlanked, implied: false),
    ]

    @Test(arguments: cases)
    func implication(_ testCase: Case) {
        #expect(RuleReachability.condition(testCase.lower, implies: testCase.upper) == testCase.implied)
    }

    @Test func aLowerOrderCoveredByAnEarlierOneIsFoldedUnderIt() {
        let program = RuleProgram(
            unitType: "okcu",
            rules: [
                Rule(condition: .enemyWithin(cells: 5), action: .retreat),
                Rule(condition: .healthBelow(percent: 30), action: .takeCover),
                Rule(condition: .enemyWithin(cells: 3), action: .hold),
                Rule(condition: .always, action: .advance),
            ])

        #expect(RuleReachability.foldingRules(in: program) == [nil, nil, 0, nil])
    }

    /// The earliest cover is the one to name — it's the one the player has to move or change.
    @Test func theEarliestCoveringOrderIsNamed() {
        let program = RuleProgram(
            unitType: "okcu",
            rules: [
                Rule(condition: .enemyWithin(cells: 6), action: .retreat),
                Rule(condition: .enemyWithin(cells: 4), action: .hold),
                Rule(condition: .enemyWithin(cells: 2), action: .takeCover),
                Rule(condition: .always, action: .advance),
            ])

        #expect(RuleReachability.foldingRules(in: program) == [nil, 0, 0, nil])
    }

    /// The default order is reached whenever nothing above matches; `RuleValidator` already rejects an
    /// `.always` anywhere else, so it is never reported as folded.
    @Test func theDefaultOrderIsNeverFolded() {
        let program = RuleProgram(
            unitType: "okcu",
            rules: [Rule(condition: .isFlanked, action: .retreat), Rule(condition: .always, action: .advance)])

        #expect(RuleReachability.foldingRules(in: program) == [nil, nil])
    }
}
