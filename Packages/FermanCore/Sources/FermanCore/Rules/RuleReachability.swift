/// Which orders can never run because an earlier one always takes the decision first (Faz 1.5, G9).
///
/// `RuleEvaluator.firstMatch` takes the first rule whose condition holds, so a rule whose condition only
/// ever holds when an earlier rule's also does is folded under that earlier rule: it will fire zero times,
/// whatever happens in battle. Telling the player while they edit — "② yüzünden hiç sıra gelmez" — beats
/// the debrief's "Bu emir hiç çalışmadı." after the fact. Editor-time analysis only; the simulation never
/// calls this.
public enum RuleReachability {
    /// For each rule in `program`, the index of the earliest rule above it that always wins first, or `nil`.
    public static func foldingRules(in program: RuleProgram) -> [Int?] {
        program.rules.indices.map { index in
            let condition = program.rules[index].condition
            guard condition != .always else { return nil }
            return program.rules[..<index].firstIndex { Self.condition(condition, implies: $0.condition) }
        }
    }

    /// Whether `condition` holding guarantees `other` holds — in `RuleEvaluator.matches`' exact terms.
    public static func condition(_ condition: Condition, implies other: Condition) -> Bool {
        switch (condition, other) {
        case (_, .always):
            true
        // "Within" and "below" thresholds: the tighter one implies the looser one.
        case (.enemyWithin(let lower), .enemyWithin(let upper)),
            (.healthBelow(let lower), .healthBelow(let upper)),
            (.moraleBelow(let lower), .moraleBelow(let upper)),
            (.allyCountBelow(let lower), .allyCountBelow(let upper)):
            lower <= upper
        // "After" and "above" thresholds: the later / higher one implies the earlier / lower one.
        case (.timeAfter(let lower), .timeAfter(let upper)),
            (.enemyDensityAbove(let lower), .enemyDensityAbove(let upper)):
            lower >= upper
        default:
            condition == other
        }
    }
}
