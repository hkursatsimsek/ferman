import FermanCore
import Foundation
import FoundationModels
import Testing

@testable import FermanAI

/// `FoundationModelsCompiler` without the real model (D17): a scripted `LanguageModel` answers with
/// fixed JSON, so the schema, the reading of the answer and the error mapping are tested on any Mac.
/// How well the real model reads orders is `CompilerAccuracy`'s job.
struct FoundationModelsCompilerTests {
    private static let units: [UnitTypeID] = ["okcu", "mizrakci", "kalkan", "suvari"]
    private static let context = CompileContext(
        unitType: "okcu", constraints: .unrestricted, availableUnitTypes: units, remainingRuleBudget: 6)

    private static func compiler(replying reply: String) -> FoundationModelsCompiler {
        FoundationModelsCompiler { instructions in
            LanguageModelSession(model: ScriptedModel(reply: reply), instructions: instructions)
        }
    }

    private static func read(_ json: String) throws -> [RuleDraft] {
        try OrderReading(GeneratedContent(json: json)).drafts()
    }

    // MARK: Mirrors

    @Test func everyConditionKindHasExactlyOneMirror() {
        #expect(ConditionMirror.allCases.count == ConditionKind.allCases.count)
        for kind in ConditionKind.allCases {
            #expect(ConditionMirror(kind).kind == kind)
        }
    }

    @Test func everyActionKindHasExactlyOneMirror() {
        #expect(ActionMirror.allCases.count == ActionKind.allCases.count)
        for kind in ActionKind.allCases {
            #expect(ActionMirror(kind).kind == kind)
        }
        #expect(ActionMirror(rawValue: ActionMirror.none) == nil)
    }

    // MARK: Schema

    @Test func lockedKindsAreLeftOutOfTheSchema() throws {
        let constraints = RuleConstraints(
            maxRules: 2, availableConditions: [.enemyWithin, .always], availableActions: [.retreat, .focusFire])

        #expect(OrderSchema.conditionChoices(constraints: constraints) == [.enemyCloserThan, .otherwise])
        #expect(
            OrderSchema.actionNames(constraints: constraints, unitTypes: ["okcu", "kalkan"])
                == ["retreat", "focusFire", "focusFire okcu", "focusFire kalkan"])
        _ = try OrderSchema.make(constraints: constraints, unitTypes: ["okcu", "kalkan"])
    }

    @Test func theDefaultOrderIsAlwaysOffered() {
        let constraints = RuleConstraints(maxRules: 0, availableConditions: [], availableActions: [.advance])
        #expect(OrderSchema.conditionChoices(constraints: constraints) == [.otherwise])
    }

    @Test func everyFrontsSchemaBuilds() throws {
        _ = try OrderSchema.make(constraints: .unrestricted, unitTypes: Self.units)
        _ = try OrderSchema.make(constraints: .unrestricted, unitTypes: [])
    }

    @Test func instructionsOpenWithTheLocaleSentence() {
        let instructions = FoundationModelsCompiler.instructions(locale: Locale(identifier: "tr_TR"))
        #expect(instructions.hasPrefix("The person's locale is tr_TR.\n"))
    }

    // MARK: Reading the answer

    @Test func readsOrdersInTheirWrittenOrderWithTheDefaultLast() throws {
        let drafts = try Self.read(
            """
            {"orders":[{"when":"otherwise","action":"advance"},{"when":"enemyCloserThan","number":3,"action":"retreat"},\
            {"when":"targetInRange","unit":"suvari","action":"focusFire suvari"},\
            {"when":"standingOn","terrain":"forest","action":"hold"}],"problem":"none"}
            """)

        #expect(
            try drafts.map { try $0.rule() } == [
                Rule(condition: .enemyWithin(cells: 3), action: .retreat),
                Rule(condition: .targetInRange("suvari"), action: .focusFire("suvari")),
                Rule(condition: .terrainIs(.forest), action: .hold),
                Rule(condition: .always, action: .advance),
            ])
    }

    @Test func aMissingNumberIsABlank() throws {
        let drafts = try Self.read(#"{"orders":[{"when":"healthBelow","action":"takeCover"}],"problem":"none"}"#)
        #expect(drafts == [RuleDraft(conditionKind: .healthBelow, actionKind: .takeCover)])
        #expect(drafts[0].isMissingConditionParameter)
    }

    @Test(
        arguments: [
            (#"{"orders":[],"problem":"notAnOrder"}"#, RuleCompileError.noOrderRecognized),
            (#"{"orders":[],"problem":"none"}"#, .noOrderRecognized),
            (#"{"orders":[],"problem":"unknownCondition"}"#, .unrecognizedCondition),
            (#"{"orders":[],"problem":"twoActionsInOneClause"}"#, .multipleActions),
            (
                #"{"orders":[{"when":"moraleBelow","number":60,"action":"advance"}],"problem":"oppositeComparison"}"#,
                .unsupportedComparison(.moraleBelow)
            ),
            (#"{"orders":[{"when":"flanked","action":"none"}],"problem":"none"}"#, .missingAction(.isFlanked)),
            (
                #"{"orders":[{"when":"otherwise","action":"advance"},{"when":"otherwise","action":"retreat"}],"problem":"none"}"#,
                .conflictingDefaultOrders
            ),
            (#"{"orders":[{"when":"somethingElse","action":"advance"}],"problem":"none"}"#, .modelUnavailable),
            (#"{"problem":"none"}"#, .modelUnavailable),
        ] as [(String, RuleCompileError)])
    func refusalsMapToTheTemplatesReasons(json: String, expected: RuleCompileError) {
        #expect(throws: expected) { try Self.read(json) }
    }

    // MARK: Through a session

    @Test func aSessionAnswerBecomesDrafts() async throws {
        let compiler = Self.compiler(
            replying: #"{"orders":[{"when":"afterSeconds","number":20,"action":"flankLeft"}],"problem":"none"}"#)

        let rules = try await compiler.compile("yirmi saniye sonra soldan dolan", context: Self.context)

        #expect(rules == [Rule(condition: .timeAfter(seconds: 20), action: .flankLeft)])
    }

    @Test func aSessionThatFailsMeansTheModelIsUnavailable() async {
        let compiler = FoundationModelsCompiler { instructions in
            LanguageModelSession(model: ScriptedModel(reply: nil), instructions: instructions)
        }

        await #expect(throws: RuleCompileError.modelUnavailable) {
            try await compiler.drafts(from: "bir şey", context: Self.context)
        }
    }

    @Test func emptyTextIsNoOrderWithoutAskingTheModel() async {
        await #expect(throws: RuleCompileError.noOrderRecognized) {
            try await Self.compiler(replying: "{}").drafts(from: "  ", context: Self.context)
        }
    }

    // MARK: The real model's budget

    /// Instructions plus the longest phrase stay under D17's token budget. Needs the system model.
    @Test(.enabled(if: SystemLanguageModel.default.isAvailable))
    func instructionsAndALongOrderFitTheTokenBudget() async throws {
        let model = SystemLanguageModel.default
        let instructions = FoundationModelsCompiler.instructions(locale: Locale(identifier: "tr_TR"))
        let longOrder =
            "yanımda 3'ten az dost varsa toplan, düşman 2 kareden yakınsa saldır, canım %25'in altına düşerse "
            + "siper al, komutan ölürse dağıl, yoksa yerinde kal"
        let tokens =
            try await model.tokenCount(for: Instructions(instructions)) + model.tokenCount(for: Prompt(longOrder))
        #expect(tokens < FoundationModelsCompiler.tokenBudget)
    }
}

/// A model that answers every request with the same text — or fails, when there's none.
private struct ScriptedModel: LanguageModel {
    typealias Executor = ScriptedExecutor
    let reply: String?

    var capabilities: LanguageModelCapabilities { LanguageModelCapabilities([.guidedGeneration]) }
    var executorConfiguration: ScriptedExecutor.Configuration { .init(reply: reply) }
}

private struct ScriptedExecutor: LanguageModelExecutor {
    struct Configuration: Hashable, Sendable {
        let reply: String?
    }

    struct NoReply: Error {}

    typealias Model = ScriptedModel
    private let reply: String?

    init(configuration: Configuration) throws {
        reply = configuration.reply
    }

    func prewarm(model: ScriptedModel, transcript: Transcript) {}

    nonisolated(nonsending) func respond(
        to request: LanguageModelExecutorGenerationRequest, model: ScriptedModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        guard let reply else { throw NoReply() }
        await channel.send(.response(action: .appendText(reply, tokenCount: 1)))
    }
}

/// Prints what the real model answers for a few orders, with the instruction token count — for
/// working on the instructions. `FERMAN_MODEL_PROBE=1 swift test --filter ModelProbe`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FERMAN_MODEL_PROBE"] != nil))
struct ModelProbe {
    @Test func printRawAnswers() async throws {
        let schema = try OrderSchema.make(
            constraints: .unrestricted, unitTypes: ["okcu", "mizrakci", "kalkan", "suvari"])
        let instructions = FoundationModelsCompiler.instructions(locale: Locale(identifier: "tr_TR"))
        print("TOKENS instructions", try await SystemLanguageModel.default.tokenCount(for: Instructions(instructions)))
        for text in ["düşman 4 kareye sokulunca kaç", "if my health drops under 20 percent, duck behind cover"] {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: text, schema: schema, includeSchemaInPrompt: false,
                options: GenerationOptions(samplingMode: .greedy))
            print("RAW", text, "=>", response.content.jsonString)
        }
    }
}
