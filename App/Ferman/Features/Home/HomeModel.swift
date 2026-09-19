import FermanCore
import FermanReplay
import Foundation
import Observation

struct HomeMenuRow: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    /// Where the row leads; `nil` for what isn't built yet (Arena, F4.x; Emir Kütüphanesi, F4.8).
    let route: Route?
}

/// The last battle laid out on the home screen's table, frozen on its final frame (brief §4.1).
struct BattleTableau {
    let config: BattleConfig
    let timeline: ReplayTimeline
    let clock: ReplayClock
    let caption: String
}

/// AnaMenü (design brief §4.1): the sand table with the last battle still on it, the wordmark, and a
/// short menu. Rows that lead nowhere yet say so plainly rather than showing invented numbers.
@Observable
@MainActor
final class HomeModel {
    let campaignSubtitle: String
    let secondaryRows: [HomeMenuRow]
    private(set) var tableau: BattleTableau?

    private let lastBattle: (levelID: Int, config: BattleConfig)?
    private let runner: BattleRunner

    init(
        nextFront: CampaignFront?, lastBattle: (levelID: Int, config: BattleConfig)? = nil,
        runner: BattleRunner = BattleRunner()
    ) {
        if let nextFront {
            campaignSubtitle = String(localized: "\(nextFront.id). cephe")
        } else {
            campaignSubtitle = String(localized: "Tüm cepheler geçildi")
        }
        let later = String(localized: "Sonra açılacak")
        secondaryRows = [
            HomeMenuRow(id: "arena", title: String(localized: "Arena"), subtitle: later, route: nil),
            HomeMenuRow(id: "library", title: String(localized: "Emir Kütüphanesi"), subtitle: later, route: nil),
            HomeMenuRow(id: "settings", title: String(localized: "Ayarlar"), subtitle: "", route: .settings),
        ]
        self.lastBattle = lastBattle
        self.runner = runner
    }

    /// Re-runs the last battle off the main actor (the simulation is deterministic, so it lands exactly
    /// as it ended) and freezes its final frame for the table.
    func loadTableau() async {
        guard tableau == nil, let lastBattle else { return }
        let result = await runner.run(lastBattle.config)
        let clock = ReplayClock(tickCount: Int32(result.tickCount) + BattleModel.settleTicks)
        clock.seek(to: clock.tickCount)
        clock.isPlaying = false
        tableau = BattleTableau(
            config: lastBattle.config, timeline: ReplayTimeline(result: result), clock: clock,
            caption: String(localized: "son savaş · \(lastBattle.levelID). cephe"))
    }
}
