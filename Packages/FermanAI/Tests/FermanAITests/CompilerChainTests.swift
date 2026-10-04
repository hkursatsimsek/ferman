import FermanCore
import Testing

@testable import FermanAI

/// `CompilerChain` (D30): the template answers first; the model is asked only when the template
/// didn't understand the text, and never outlives its timeout.
struct CompilerChainTests {
    private static let context = CompileContext(
        unitType: "okcu", constraints: .unrestricted, availableUnitTypes: ["okcu", "mizrakci", "kalkan", "suvari"],
        remainingRuleBudget: 6)

    /// Answers with a fixed result and counts how often it was asked.
    private actor StubModel: RuleDrafter {
        let answer: Result<[RuleDraft], RuleCompileError>
        let delay: Duration
        private(set) var calls = 0
        private(set) var prewarms = 0

        init(_ answer: Result<[RuleDraft], RuleCompileError>, delay: Duration = .zero) {
            self.answer = answer
            self.delay = delay
        }

        func drafts(from text: String, context: CompileContext) async throws(RuleCompileError) -> [RuleDraft] {
            calls += 1
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            return try answer.get()
        }

        func prewarm() async {
            prewarms += 1
        }
    }

    private static let modelDraft = RuleDraft(conditionKind: .always, actionKind: .guardCommander)

    @Test func whatTheTemplateReadsNeverReachesTheModel() async throws {
        let model = StubModel(.success([Self.modelDraft]))
        let chain = CompilerChain(model: model)

        let drafts = try await chain.drafts(from: "düşman 3 kareden yakınsa geri çekil", context: Self.context)

        #expect(drafts == [RuleDraft(conditionKind: .enemyWithin, conditionNumericValue: 3, actionKind: .retreat)])
        #expect(await model.calls == 0)
    }

    @Test func aBlankFromTheTemplateStaysABlank() async throws {
        let model = StubModel(.success([Self.modelDraft]))
        let drafts = try await CompilerChain(model: model).drafts(
            from: "düşman yaklaşırsa geri çekil", context: Self.context)

        #expect(drafts.first?.isMissingConditionParameter == true)
        #expect(await model.calls == 0)
    }

    @Test(arguments: ["selam komutan", "düşman görünce saldır", "protect the general if morale is under 30%"])
    func textTheTemplateDidNotUnderstandGoesToTheModel(text: String) async throws {
        let model = StubModel(.success([Self.modelDraft]))

        let drafts = try await CompilerChain(model: model).drafts(from: text, context: Self.context)

        #expect(drafts == [Self.modelDraft])
        #expect(await model.calls == 1)
    }

    @Test(
        arguments: [
            ("düşman 3 kareden yakınsa", RuleCompileError.missingAction(.enemyWithin)),
            ("canım %40'ın üstündeyse ilerle", .unsupportedComparison(.healthBelow)),
            ("ilk 10 saniye bekle sonra ilerle", .multipleActions),
            ("ilerle, başka durumda geri çekil", .conflictingDefaultOrders),
        ] as [(String, RuleCompileError)])
    func refusalsTheTemplateUnderstoodStand(text: String, expected: RuleCompileError) async {
        let model = StubModel(.success([Self.modelDraft]))

        await #expect(throws: expected) {
            try await CompilerChain(model: model).drafts(from: text, context: Self.context)
        }
        #expect(await model.calls == 0)
    }

    @Test(
        arguments: [
            RuleCompileError.modelUnavailable, .noOrderRecognized, .missingAction(.enemyWithin),
        ])
    func aModelThatCannotAnswerLeavesTheTemplatesAnswer(modelError: RuleCompileError) async {
        let model = StubModel(.failure(modelError))

        await #expect(throws: RuleCompileError.noOrderRecognized) {
            try await CompilerChain(model: model).drafts(from: "selam komutan", context: Self.context)
        }
    }

    @Test func aSpecificRefusalFromTheModelIsPassedOn() async {
        let model = StubModel(.failure(.unsupportedComparison(.moraleBelow)))

        await #expect(throws: RuleCompileError.unsupportedComparison(.moraleBelow)) {
            try await CompilerChain(model: model).drafts(from: "selam komutan", context: Self.context)
        }
    }

    @Test func aSlowModelIsCutOffAtTheTimeout() async {
        let model = StubModel(.success([Self.modelDraft]), delay: .seconds(5))
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: RuleCompileError.noOrderRecognized) {
            try await CompilerChain(model: model, timeout: .milliseconds(100)).drafts(
                from: "selam komutan", context: Self.context)
        }
        #expect(clock.now - start < .seconds(2))
    }

    @Test func withNoModelTheChainIsTheTemplate() async {
        await #expect(throws: RuleCompileError.noOrderRecognized) {
            try await CompilerChain(model: nil).drafts(from: "selam komutan", context: Self.context)
        }
    }

    @Test func prewarmReachesTheModel() async {
        let model = StubModel(.success([]))
        await CompilerChain(model: model).prewarm()
        #expect(await model.prewarms == 1)
    }
}
