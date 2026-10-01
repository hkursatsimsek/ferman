import FermanCore

/// Turns a typed or spoken order — "düşman 3 kareden yakınsa geri çekil, başka durumda ilerle",
/// "retreat if an enemy is within 3 cells" — into rules with a fixed Turkish and English keyword
/// lexicon, no language model (F2.1). It is the fallback when Foundation Models is unavailable
/// or too slow (D17), and the baseline the model has to beat.
///
/// It translates faithfully rather than helpfully: a locked condition or an out-of-range number
/// comes out as written and `RuleValidator` flags it, the same as for a hand-picked order. Rules
/// keep the order they were written in, which is their priority (D7); a default order
/// ("başka durumda ilerle", or an action with no condition) goes last.
public struct TemplateCompiler: RuleCompiler<String> {
    public init() {}

    public func compile(_ input: String, context: CompileContext) async throws(RuleCompileError) -> [Rule] {
        try Self.rules(from: input)
    }

    static func rules(from text: String) throws(RuleCompileError) -> [Rule] {
        var assembler = OrderAssembler()
        for tokens in TemplateTokenizer.fragments(of: text) {
            var fragment = TemplateFragment(tokens)
            let action = try fragment.takeAction()
            let condition = try fragment.takeCondition()
            if condition == nil, fragment.hasConditionalWord {
                throw .unrecognizedCondition
            }
            try assembler.add(condition: condition, action: action)
        }
        return try assembler.finish()
    }
}

/// Pairs conditions with actions across fragments. "düşman yakınsa, geri çekil" (Turkish order)
/// and "retreat, if an enemy is close" (English order) both split at the comma; a condition-only
/// fragment takes the action-only fragment right before or after it.
private struct OrderAssembler {
    private var rules: [Rule] = []
    private var defaultAction: Action?
    private var pendingCondition: Condition?
    private var pendingAction: Action?

    mutating func add(condition: Condition?, action: Action?) throws(RuleCompileError) {
        switch (condition, action) {
        case (nil, nil):
            return
        case (let condition?, let action?):
            try flushPendingAction()
            try flushPendingCondition()
            try append(condition, action)
        case (let condition?, nil):
            if let action = pendingAction {
                pendingAction = nil
                try append(condition, action)
            } else {
                try flushPendingCondition()
                pendingCondition = condition
            }
        case (nil, let action?):
            if let condition = pendingCondition {
                pendingCondition = nil
                try append(condition, action)
            } else {
                try flushPendingAction()
                pendingAction = action
            }
        }
    }

    mutating func finish() throws(RuleCompileError) -> [Rule] {
        try flushPendingAction()
        try flushPendingCondition()
        guard !rules.isEmpty || defaultAction != nil else {
            throw .noOrderRecognized
        }
        guard let defaultAction else {
            return rules
        }
        return rules + [Rule(condition: .always, action: defaultAction)]
    }

    private mutating func append(_ condition: Condition, _ action: Action) throws(RuleCompileError) {
        if condition == .always {
            try setDefault(action)
        } else {
            rules.append(Rule(condition: condition, action: action))
        }
    }

    private mutating func setDefault(_ action: Action) throws(RuleCompileError) {
        if let defaultAction, defaultAction != action {
            throw .conflictingDefaultOrders
        }
        defaultAction = action
    }

    private mutating func flushPendingAction() throws(RuleCompileError) {
        if let action = pendingAction {
            pendingAction = nil
            try setDefault(action)
        }
    }

    private mutating func flushPendingCondition() throws(RuleCompileError) {
        if let condition = pendingCondition {
            throw .missingAction(condition.kind)
        }
    }
}
