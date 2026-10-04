import FermanCore

/// Compiles a selector-picked `RuleDraft` into a `Rule`. The whole game must be playable through
/// this alone, with no language model involved (CLAUDE.md rule 3, D18).
public struct ManualCompiler: RuleCompiler<RuleDraft> {
    public init() {}

    public func compile(_ input: RuleDraft, context: CompileContext) async throws(RuleCompileError) -> [Rule] {
        [try input.rule()]
    }
}
