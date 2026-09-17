import FermanContent
import Testing

@testable import Ferman

@MainActor
struct CampaignModelTests {
    private static let fronts: [CampaignFront] = [
        CampaignFront(
            id: 1, title: "A", map: "ova", enemyBudget: 100, playerBudget: 100, ruleBudget: 3, constraintBadge: nil,
            state: .cleared),
        CampaignFront(
            id: 2, title: "B", map: "ova", enemyBudget: 200, playerBudget: 200, ruleBudget: 4, constraintBadge: nil,
            state: .open),
        CampaignFront(
            id: 3, title: "C", map: "ova", enemyBudget: 300, playerBudget: 300, ruleBudget: 5, constraintBadge: nil,
            state: .locked),
    ]

    @Test
    func exposesTheFrontsItWasGiven() {
        let model = CampaignModel(fronts: Self.fronts)

        #expect(model.fronts == Self.fronts)
    }

    @Test
    func clearedAndOpenFrontsCanBeOpened() {
        let model = CampaignModel(fronts: Self.fronts)

        #expect(model.canOpen(Self.fronts[0]) == true)
        #expect(model.canOpen(Self.fronts[1]) == true)
    }

    @Test
    func lockedFrontsCannotBeOpened() {
        let model = CampaignModel(fronts: Self.fronts)

        #expect(model.canOpen(Self.fronts[2]) == false)
    }

    @Test
    func placeholdersHaveExactlyOneOpenFront() {
        let openFronts = CampaignFront.placeholders.filter { $0.state == .open }

        #expect(openFronts.count == 1)
    }
}
