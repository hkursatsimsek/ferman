import FermanCore
import Foundation
import Testing

@testable import FermanAI

struct TemplateCompilerAccuracyTests {
    private static let context = CompileContext(
        unitType: "okcu", constraints: .unrestricted, availableUnitTypes: ["okcu", "mizrakci", "kalkan", "suvari"],
        remainingRuleBudget: 12)

    @Test func phraseFileIsWellFormed() throws {
        let phrases = try PhraseFile.load()

        #expect(phrases.count == 150)
        #expect(Set(phrases.map(\.id)).count == phrases.count)
        #expect(phrases.allSatisfy { ($0.rules == nil) != ($0.error == nil) })
        #expect(phrases.filter { $0.locale == "tr" }.count >= 70)
        #expect(phrases.filter { $0.locale == "en" }.count >= 70)
        for kind in ConditionKind.allCases {
            #expect(
                phrases.contains { $0.rules?.contains { $0.condition.kind == kind } == true },
                "no phrase covers condition \(kind)")
        }
        for kind in ActionKind.allCases {
            #expect(
                phrases.contains { $0.rules?.contains { $0.action.kind == kind } == true },
                "no phrase covers action \(kind)")
        }
    }

    /// The template compiler's baseline: what the model compiler (F2.3) has to beat. The phrases
    /// were written by the same author as the lexicon, so this over-states what real players
    /// typing freely would get; the floor guards against regressions, not against that bias.
    @Test func templateBaseline() async throws {
        let report = await AccuracyReport.run(
            compiler: TemplateCompiler(), name: "TemplateCompiler", phrases: try PhraseFile.load(),
            context: Self.context)
        let markdown = report.markdown()

        if let path = ProcessInfo.processInfo.environment["FERMAN_ACCURACY_REPORT"] {
            try markdown.write(toFile: path, atomically: true, encoding: .utf8)
        }
        print(markdown)

        #expect(report.exactRate >= Self.regressionFloor)
    }

    /// Phrases written after the lexicon was frozen and never used to tune it: the closest this
    /// harness gets to an unbiased estimate until real players' phrases exist (Faz 6 beta).
    /// Nothing here may be fixed in the lexicon without replacing the phrase with a fresh one.
    @Test func templateHeldOut() async throws {
        let report = await AccuracyReport.run(
            compiler: TemplateCompiler(), name: "TemplateCompiler (held-out phrases)",
            phrases: try PhraseFile.load("heldout-phrases"), context: Self.context)
        let markdown = report.markdown()

        if let path = ProcessInfo.processInfo.environment["FERMAN_ACCURACY_HELDOUT_REPORT"] {
            try markdown.write(toFile: path, atomically: true, encoding: .utf8)
        }
        print(markdown)

        #expect(report.exactRate >= Self.heldOutRegressionFloor)
    }

    /// A little under the recorded held-out baseline (`Reports/template-heldout.md`: 79.3%).
    private static let heldOutRegressionFloor = 0.75

    /// A little under the recorded baseline (`Reports/template-baseline.md`: 99.3%), so a lexicon
    /// change that breaks working phrases fails here. It guards regressions; it is not the claim.
    private static let regressionFloor = 0.97
}
