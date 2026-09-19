import FermanCore
import Observation

/// Where `NavigationStack(path:)` can go (D12). Only pushed screens live here — each screen's own
/// contextual sheets (the level info sheet, the rule picker) stay local `@State` next to the view
/// that presents them, matching F1.7's `RuleEditorView`.
enum Route: Hashable {
    case campaign
    case settings
    case armySetup(CampaignFront)
    /// The player's placements from `ArmySetup` (no programs yet — those are `RuleEditor`'s job).
    case ruleEditor(CampaignFront, TeamSetup)
    /// `front` is where the battle was fought from — `nil` when there is no campaign front behind it.
    case battle(BattleConfig, front: CampaignFront?)
    case debrief(BattleConfig, BattleResult, front: CampaignFront?)
}

@Observable
@MainActor
final class AppRouter {
    var path: [Route] = []
    /// Set by the debrief's "O anı izle" just before popping back to the battle, which picks it up on
    /// reappearing and replays from a little before that tick.
    var replayRequest: Int32?

    func push(_ route: Route) {
        path.append(route)
    }

    /// "Emirleri Düzelt" (`DebriefView`) uses this to drop back to the `ruleEditor` entry already on
    /// the stack (past `battle` and `debrief`) instead of pushing a fresh one.
    func pop(_ count: Int = 1) {
        path.removeLast(min(count, path.count))
    }
}
