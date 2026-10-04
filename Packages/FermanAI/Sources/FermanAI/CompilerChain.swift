import FermanCore

/// The text path the editor uses (D17, D30): `TemplateCompiler` first, the language model only for
/// what the template didn't understand at all.
///
/// The template answers instantly and, where it reads a sentence, reads it exactly; measured on the
/// 150 labeled phrases the on-device model alone was right about two times in three and accepted a
/// wrong order about once in five (`Tests/CompilerAccuracy/Reports/`). So the model never overrides
/// the template: it is asked only when the template found no order (`noOrderRecognized`) or a
/// condition it doesn't know (`unrecognizedCondition`), or a condition beside words that are no
/// action it knows (`unrecognizedAction` — usually a verb missing from its lexicon). A refusal that
/// means "understood, but not something the game can do" — a condition with nothing after it,
/// "above" instead of "below", two actions in one clause, two defaults — stands as it is. If the model is unavailable or slower than `timeout`, the
/// template's own answer is what the player sees.
public struct CompilerChain: RuleDrafter {
    private let template = TemplateCompiler()
    private let model: (any RuleDrafter)?
    private let timeout: Duration

    public init(model: (any RuleDrafter)?, timeout: Duration = .seconds(2)) {
        self.model = model
        self.timeout = timeout
    }

    public func prewarm() async {
        await model?.prewarm()
    }

    public func drafts(from text: String, context: CompileContext) async throws(RuleCompileError) -> [RuleDraft] {
        let templateError: RuleCompileError
        do {
            return try await template.drafts(from: text, context: context)
        } catch {
            templateError = error
        }
        guard let model, Self.modelMayHelp(with: templateError) else {
            throw templateError
        }
        switch await answer(from: model, text: text, context: context) {
        case .success(let drafts):
            return drafts
        case .failure(.modelUnavailable), .failure(.noOrderRecognized), .failure(.missingAction), nil:
            throw templateError
        case .failure(let modelError):
            throw modelError
        }
    }

    static func modelMayHelp(with error: RuleCompileError) -> Bool {
        switch error {
        case .noOrderRecognized, .unrecognizedCondition, .unrecognizedAction:
            true
        case .missingConditionParameter, .missingAction, .unsupportedComparison, .conflictingDefaultOrders,
            .multipleActions, .modelUnavailable:
            false
        }
    }

    /// The model's answer, or `nil` once `timeout` passes first.
    private func answer(from model: any RuleDrafter, text: String, context: CompileContext) async
        -> Result<[RuleDraft], RuleCompileError>?
    {
        let timeout = timeout
        return await withTaskGroup(of: Result<[RuleDraft], RuleCompileError>?.self) { group in
            group.addTask {
                do throws(RuleCompileError) {
                    return .success(try await model.drafts(from: text, context: context))
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
