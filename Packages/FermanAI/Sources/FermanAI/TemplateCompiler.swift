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
///
/// As a `RuleDrafter` it leaves a number or unit type the words didn't give as a blank for the
/// player to fill in; as a `RuleCompiler` that same blank is `.missingConditionParameter`.
public struct TemplateCompiler: RuleCompiler<String>, RuleDrafter {
    public init() {}

    public func compile(_ input: String, context: CompileContext) async throws(RuleCompileError) -> [Rule] {
        try Self.rules(from: input)
    }

    public func drafts(from text: String, context: CompileContext) async throws(RuleCompileError) -> [RuleDraft] {
        try Self.drafts(from: text)
    }

    static func rules(from text: String) throws(RuleCompileError) -> [Rule] {
        var rules: [Rule] = []
        for draft in try drafts(from: text) {
            rules.append(try draft.rule())
        }
        return rules
    }

    static func drafts(from text: String) throws(RuleCompileError) -> [RuleDraft] {
        var assembler = OrderAssembler()
        for tokens in TemplateTokenizer.fragments(of: text) {
            var fragment = TemplateFragment(tokens)
            let action = try fragment.takeAction()
            let condition = try fragment.takeCondition()
            if condition == nil, fragment.hasConditionalWord {
                throw .unrecognizedCondition
            }
            try assembler.add(condition: condition, action: action, hasUnreadWords: fragment.hasUnreadWords)
        }
        return try assembler.finish()
    }
}

/// Pairs conditions with actions across fragments. "düşman yakınsa, geri çekil" (Turkish order)
/// and "retreat, if an enemy is close" (English order) both split at the comma; a condition-only
/// fragment takes the action-only fragment right before or after it.
private struct OrderAssembler {
    private var drafts: [RuleDraft] = []
    private var defaultAction: Action?
    private var pendingCondition: ConditionDraft?
    /// Whether the pending condition's fragment had words left that no match used.
    private var pendingConditionHadUnreadWords = false
    private var pendingAction: Action?

    mutating func add(condition: ConditionDraft?, action: Action?, hasUnreadWords: Bool) throws(RuleCompileError) {
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
                pendingConditionHadUnreadWords = hasUnreadWords
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

    mutating func finish() throws(RuleCompileError) -> [RuleDraft] {
        try flushPendingAction()
        try flushPendingCondition()
        guard !drafts.isEmpty || defaultAction != nil else {
            throw .noOrderRecognized
        }
        guard let defaultAction else {
            return drafts
        }
        return drafts + [ConditionDraft(kind: .always).draft(with: defaultAction)]
    }

    private mutating func append(_ condition: ConditionDraft, _ action: Action) throws(RuleCompileError) {
        if condition.kind == .always {
            try setDefault(action)
        } else {
            drafts.append(condition.draft(with: action))
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
            throw pendingConditionHadUnreadWords ? .unrecognizedAction(condition.kind) : .missingAction(condition.kind)
        }
    }
}
