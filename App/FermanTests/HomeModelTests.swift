import FermanContent
import Testing

@testable import Ferman

@MainActor
struct HomeModelTests {
    private static let openFront = CampaignFront(
        id: 3, title: "Taş Geçit", map: "ova", enemyBudget: 420, playerBudget: 310, ruleBudget: 6,
        constraintBadge: nil, state: .open)

    @Test
    func campaignSubtitleNamesTheNextOpenFront() {
        let model = HomeModel(nextFront: Self.openFront)

        #expect(model.campaignSubtitle == "3. cephe")
    }

    @Test
    func campaignSubtitleFallsBackWhenNoFrontIsOpen() {
        let model = HomeModel(nextFront: nil)

        #expect(model.campaignSubtitle == "Tüm cepheler geçildi")
    }

    @Test
    func secondaryRowsAreArenaLibraryAndSettingsInOrder() {
        let model = HomeModel(nextFront: Self.openFront)

        #expect(model.secondaryRows.map(\.id) == ["arena", "library", "settings"])
        #expect(model.secondaryRows[0].subtitle == "3 maç bekliyor")
    }
}
