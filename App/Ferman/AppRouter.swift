import FermanCore
import Observation

/// Where `NavigationStack(path:)` can go (D12). Only pushed screens live here — each screen's own
/// contextual sheets (the level info sheet, the rule picker) stay local `@State` next to the view
/// that presents them, matching F1.7's `RuleEditorView`.
enum Route: Hashable {
    case campaign
    case armySetup(CampaignFront)
    /// The player's placements from `ArmySetup` (no programs yet — those are `RuleEditor`'s job).
    case ruleEditor(CampaignFront, TeamSetup)
    case battle(BattleConfig)
    case debrief(BattleConfig, BattleResult)
}

@Observable
@MainActor
final class AppRouter {
    var path: [Route] = []

    func push(_ route: Route) {
        path.append(route)
    }

    /// "Emirleri Düzelt" (`DebriefView`) uses this to drop back to the `ruleEditor` entry already on
    /// the stack (past `battle` and `debrief`) instead of pushing a fresh one.
    func pop(_ count: Int = 1) {
        path.removeLast(min(count, path.count))
    }
}
