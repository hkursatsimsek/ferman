import FermanCore
import Foundation
import Testing

@testable import FermanAI

/// The on-device model against the same phrases as `TemplateCompiler` (F2.3: > 88% exact on each
/// set). Slow — every phrase is a real model call — so it runs only when asked for
/// (`FERMAN_MODEL_ACCURACY=1`) and only where Apple Intelligence is on. Its numbers are recorded in
/// `Reports/`, not asserted as a floor: the model can change under an OS update (D17).
@Suite(.enabled(if: ModelAccuracyRun.isRequested))
struct FoundationModelsAccuracyTests {
    private static let context = CompileContext(
        unitType: "okcu", constraints: .unrestricted, availableUnitTypes: ["okcu", "mizrakci", "kalkan", "suvari"],
        remainingRuleBudget: 12)

    private static func run(_ compiler: any RuleCompiler<String>, name: String, phrases: String, reportKey: String)
        async throws -> AccuracyReport
    {
        let report = await AccuracyReport.run(
            compiler: compiler, name: name, phrases: try PhraseFile.load(phrases), context: context)
        let markdown = report.markdown()
        if let path = ProcessInfo.processInfo.environment[reportKey] {
            try markdown.write(toFile: path, atomically: true, encoding: .utf8)
        }
        print(markdown)
        return report
    }

    @Test func modelOnPhrases() async throws {
        let compiler = FoundationModelsCompiler(locale: Locale(identifier: "tr_TR"))
        _ = try await Self.run(
            compiler, name: "FoundationModelsCompiler", phrases: "phrases", reportKey: "FERMAN_MODEL_REPORT")
    }

    @Test func chainOnPhrases() async throws {
        let chain = DraftingCompiler(
            CompilerChain(model: FoundationModelsCompiler(locale: Locale(identifier: "tr_TR"))))
        _ = try await Self.run(chain, name: "CompilerChain", phrases: "phrases", reportKey: "FERMAN_CHAIN_REPORT")
    }

    @Test func chainOnHeldOutPhrases() async throws {
        let chain = DraftingCompiler(
            CompilerChain(model: FoundationModelsCompiler(locale: Locale(identifier: "tr_TR"))))
        _ = try await Self.run(
            chain, name: "CompilerChain (held-out phrases)", phrases: "heldout-phrases",
            reportKey: "FERMAN_CHAIN_HELDOUT_REPORT")
    }

    @Test func modelOnHeldOutPhrases() async throws {
        let compiler = FoundationModelsCompiler(locale: Locale(identifier: "tr_TR"))
        _ = try await Self.run(
            compiler, name: "FoundationModelsCompiler (held-out phrases)", phrases: "heldout-phrases",
            reportKey: "FERMAN_MODEL_HELDOUT_REPORT")
    }
}

/// Scores a drafter the way the editor would use it: a draft with a blank is the same refusal
/// `RuleCompiler` gives (`.missingConditionParameter`).
struct DraftingCompiler: RuleCompiler<String> {
    let drafter: any RuleDrafter

    init(_ drafter: any RuleDrafter) {
        self.drafter = drafter
    }

    func compile(_ input: String, context: CompileContext) async throws(RuleCompileError) -> [Rule] {
        var rules: [Rule] = []
        for draft in try await drafter.drafts(from: input, context: context) {
            rules.append(try draft.rule())
        }
        return rules
    }
}

enum ModelAccuracyRun {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["FERMAN_MODEL_ACCURACY"] != nil
            && FoundationModelsCompiler.isAvailable(for: Locale(identifier: "tr_TR"))
    }
}
