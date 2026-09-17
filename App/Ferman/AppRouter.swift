import Observation

/// Where `NavigationStack(path:)` can go (D12). Only pushed screens live here — each screen's own
/// contextual sheets (the level info sheet, the rule picker) stay local `@State` next to the view
/// that presents them, matching F1.7's `RuleEditorView`.
enum Route: Hashable {
    case campaign
    case armySetup(CampaignFront)
}

@Observable
@MainActor
final class AppRouter {
    var path: [Route] = []

    func push(_ route: Route) {
        path.append(route)
    }
}
