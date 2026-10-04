import FermanCore
import Foundation

@testable import FermanAI

/// One labeled phrase: what the player typed and what they meant. A phrase either means rules, or
/// is text that cannot become an order and should be refused with a specific reason.
struct LabeledPhrase: Decodable, Sendable {
    let id: String
    let locale: String
    let text: String
    let rules: [Rule]?
    let error: String?

    var category: String {
        guard let rules else {
            return "refusal"
        }
        if rules.count > 1 {
            return "several orders"
        }
        return rules.first?.condition == .always ? "bare action" : "one order"
    }
}

struct PhraseFile: Decodable {
    let version: Int
    let phrases: [LabeledPhrase]

    static func load(_ resource: String = "phrases") throws -> [LabeledPhrase] {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(PhraseFile.self, from: Data(contentsOf: url)).phrases
    }
}

enum Outcome: Equatable {
    case rules([Rule])
    case refused(String)

    init(compiling text: String, with compiler: any RuleCompiler<String>, context: CompileContext) async {
        do {
            self = .rules(try await compiler.compile(text, context: context))
        } catch {
            self = .refused(Self.label(of: error))
        }
    }

    var isRules: Bool {
        if case .rules = self {
            return true
        }
        return false
    }

    /// The same shape `phrases.json` uses for expected refusals.
    static func label(of error: RuleCompileError) -> String {
        switch error {
        case .missingConditionParameter(let kind): "missingConditionParameter:\(kind.rawValue)"
        case .missingAction(let kind): "missingAction:\(kind.rawValue)"
        case .unrecognizedAction(let kind): "unrecognizedAction:\(kind.rawValue)"
        case .unsupportedComparison(let kind): "unsupportedComparison:\(kind.rawValue)"
        case .noOrderRecognized: "noOrderRecognized"
        case .unrecognizedCondition: "unrecognizedCondition"
        case .conflictingDefaultOrders: "conflictingDefaultOrders"
        case .multipleActions: "multipleActions"
        case .modelUnavailable: "modelUnavailable"
        }
    }

    private static func label(of error: any Error) -> String {
        (error as? RuleCompileError).map(label(of:)) ?? "otherError"
    }
}

/// Scores one phrase. Exact match means the whole answer is right; the fields below say where a
/// wrong one went wrong, since "the model gets the number wrong" and "the model picks the wrong
/// action" need different fixes.
struct PhraseScore {
    let phrase: LabeledPhrase
    let outcome: Outcome
    let isExact: Bool
    /// Per field: how many of the expected rule slots were right, out of how many there were.
    var fields: [Field: (right: Int, total: Int)] = [:]

    enum Field: String, CaseIterable {
        case ruleCount = "number of orders"
        case conditionKind = "condition kind"
        case conditionParameter = "condition number / unit / terrain"
        case actionKind = "action kind"
        case actionParameter = "action target unit"
        case refusal = "refusal reason"
    }

    init(phrase: LabeledPhrase, outcome: Outcome) {
        self.phrase = phrase
        self.outcome = outcome

        if let expectedRules = phrase.rules {
            let actual: [Rule]
            if case .rules(let compiled) = outcome {
                actual = compiled
            } else {
                actual = []
            }
            isExact = actual == expectedRules
            record(.ruleCount, actual.count == expectedRules.count)
            for (slot, expected) in expectedRules.enumerated() {
                let rule = slot < actual.count ? actual[slot] : nil
                record(.conditionKind, rule?.condition.kind == expected.condition.kind)
                if let expectedParameter = Self.parameter(of: expected.condition) {
                    record(.conditionParameter, rule.map { Self.parameter(of: $0.condition) } == expectedParameter)
                }
                record(.actionKind, rule?.action.kind == expected.action.kind)
                if case .focusFire(let target) = expected.action, target != nil {
                    record(.actionParameter, rule?.action == expected.action)
                }
            }
        } else {
            isExact = outcome == .refused(phrase.error ?? "")
            record(.refusal, isExact)
        }
    }

    private mutating func record(_ field: Field, _ isRight: Bool) {
        let current = fields[field] ?? (0, 0)
        fields[field] = (current.right + (isRight ? 1 : 0), current.total + 1)
    }

    private static func parameter(of condition: Condition) -> String? {
        switch condition {
        case .enemyWithin(let value), .healthBelow(let value), .allyCountBelow(let value), .timeAfter(let value),
            .moraleBelow(let value), .enemyDensityAbove(let value):
            String(value)
        case .targetInRange(let unitType), .nearestEnemyType(let unitType):
            unitType.rawValue
        case .terrainIs(let terrain):
            terrain.rawValue
        case .isFlanked, .commanderDead, .always:
            nil
        }
    }
}

struct AccuracyReport {
    let compilerName: String
    let scores: [PhraseScore]
    /// Wall-clock time per phrase, in the order compiled.
    var durations: [Duration] = []

    var exactRate: Double { Self.rate(scores.filter(\.isExact).count, scores.count) }

    static func run(
        compiler: any RuleCompiler<String>, name: String, phrases: [LabeledPhrase], context: CompileContext
    ) async -> AccuracyReport {
        var scores: [PhraseScore] = []
        var durations: [Duration] = []
        let clock = ContinuousClock()
        for phrase in phrases {
            let start = clock.now
            let outcome = await Outcome(compiling: phrase.text, with: compiler, context: context)
            durations.append(clock.now - start)
            scores.append(PhraseScore(phrase: phrase, outcome: outcome))
        }
        return AccuracyReport(compilerName: name, scores: scores, durations: durations)
    }

    /// The `fraction` quantile of the per-phrase times (nearest rank).
    func latency(_ fraction: Double) -> Duration {
        let sorted = durations.sorted()
        guard !sorted.isEmpty else { return .zero }
        let rank = Int((fraction * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return "\(seconds * 1000 + attoseconds / 1_000_000_000_000_000) ms"
    }

    static func rate(_ right: Int, _ total: Int) -> Double {
        total == 0 ? 0 : Double(right) / Double(total)
    }

    private static func percent(_ value: Double) -> String {
        let tenths = Int((value * 1000).rounded())
        return "\(tenths / 10).\(tenths % 10)%"
    }

    func exactRate(where isIncluded: (PhraseScore) -> Bool) -> (right: Int, total: Int) {
        let included = scores.filter(isIncluded)
        return (included.filter(\.isExact).count, included.count)
    }

    func markdown() -> String {
        var lines = ["# Compiler accuracy — \(compilerName)", ""]
        let all = exactRate { _ in true }
        lines.append("**Exact match: \(all.right)/\(all.total) (\(Self.percent(exactRate)))**")
        if !durations.isEmpty {
            lines += [
                "",
                "Time per phrase: p50 \(Self.milliseconds(latency(0.5))) · p95 \(Self.milliseconds(latency(0.95))) · "
                    + "max \(Self.milliseconds(latency(1)))",
            ]
        }
        lines += ["", "| By language | Exact |", "|---|---|"]
        for locale in ["tr", "en"] {
            let part = exactRate { $0.phrase.locale == locale }
            lines.append(
                "| \(locale) | \(part.right)/\(part.total) (\(Self.percent(Self.rate(part.right, part.total)))) |")
        }
        lines += ["", "| By kind of phrase | Exact |", "|---|---|"]
        for category in ["one order", "bare action", "several orders", "refusal"] {
            let part = exactRate { $0.phrase.category == category }
            lines.append(
                "| \(category) | \(part.right)/\(part.total) (\(Self.percent(Self.rate(part.right, part.total)))) |")
        }
        lines += ["", "| By field | Right |", "|---|---|"]
        for field in PhraseScore.Field.allCases {
            let right = scores.reduce(0) { $0 + ($1.fields[field]?.right ?? 0) }
            let total = scores.reduce(0) { $0 + ($1.fields[field]?.total ?? 0) }
            guard total > 0 else {
                continue
            }
            lines.append("| \(field.rawValue) | \(right)/\(total) (\(Self.percent(Self.rate(right, total)))) |")
        }
        let wrongButAccepted = scores.filter { $0.phrase.rules != nil && !$0.isExact && $0.outcome.isRules }
        let refusedValid = scores.filter { $0.phrase.rules != nil && !$0.isExact && !$0.outcome.isRules }
        let acceptedInvalid = scores.filter { $0.phrase.rules == nil && $0.outcome.isRules }
        lines += [
            "", "| Kind of miss | Count |", "|---|---|",
            "| Wrong order accepted (the dangerous one: looks valid, is not what was meant) | \(wrongButAccepted.count) |",
            "| Valid order refused | \(refusedValid.count) |",
            "| Text that is no order accepted as one | \(acceptedInvalid.count) |",
        ]
        let misses = scores.filter { !$0.isExact }
        lines += ["", "## Misses (\(misses.count))", ""]
        for miss in misses {
            lines.append("- `\(miss.phrase.id)` \"\(miss.phrase.text)\"")
            lines.append("  - expected: \(Self.describe(miss.phrase))")
            lines.append("  - got: \(Self.describe(miss.outcome))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func describe(_ phrase: LabeledPhrase) -> String {
        phrase.rules.map { describe(.rules($0)) } ?? "refused \(phrase.error ?? "?")"
    }

    private static func describe(_ outcome: Outcome) -> String {
        switch outcome {
        case .refused(let reason):
            "refused \(reason)"
        case .rules(let rules):
            rules.map { "\($0.condition) → \($0.action)" }.joined(separator: " | ")
        }
    }
}
