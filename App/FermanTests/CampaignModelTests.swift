import FermanContent
import FermanCore
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

    // MARK: - Faz 1.5 G12: progress

    @Test
    func withNoProgressOnlyTheFirstFrontIsOpen() throws {
        let fronts = CampaignFront.fronts(from: try ContentCatalog.bundled())

        #expect(fronts.first?.state == .open)
        #expect(fronts.dropFirst().allSatisfy { $0.state == .locked })
    }

    @Test
    func winningAFrontClearsItAndOpensTheNext() throws {
        let won: Set<Int> = [1, 2]
        let fronts = CampaignFront.fronts(
            from: try ContentCatalog.bundled(), bestOutcome: { won.contains($0) ? .playerWin : nil })

        #expect(fronts.prefix(3).map(\.state) == [.cleared, .cleared, .open])
        #expect(fronts.dropFirst(3).allSatisfy { $0.state == .locked })
        let model = CampaignModel(fronts: fronts)
        #expect(model.currentFront?.id == 3)
        #expect(model.clearedCount == 2)
    }

    /// A loss is an attempt, not a clear: the next front stays shut.
    @Test
    func aLostFrontDoesNotOpenTheNext() throws {
        let fronts = CampaignFront.fronts(
            from: try ContentCatalog.bundled(), bestOutcome: { $0 == 1 ? .enemyWin : nil })

        #expect(fronts.prefix(2).map(\.state) == [.open, .locked])
    }

    @Test
    func unlockingAllOpensEveryUnclearedFront() throws {
        let fronts = CampaignFront.fronts(
            from: try ContentCatalog.bundled(), bestOutcome: { $0 == 1 ? .playerWin : nil }, unlockAll: true)

        #expect(fronts.first?.state == .cleared)
        #expect(fronts.dropFirst().allSatisfy { $0.state == .open })
    }

    @Test
    func aFrontCarriesItsEnemyAndWhatItNewlyAllows() throws {
        let fronts = CampaignFront.fronts(from: try ContentCatalog.bundled())

        // Level 1: three cavalry; nothing to announce on the very first front.
        #expect(fronts[0].enemyComposition == [UnitCount(type: "suvari", count: 3)])
        #expect(fronts[0].newOrders.isEmpty)
        // Level 2 introduces the single condition it's about (F1.12).
        #expect(fronts[1].newOrders.contains(RulePickerSheet.conditionKindLabel(.enemyWithin)))
        #expect(fronts.allSatisfy { !$0.briefing.isEmpty })
    }

    @Test
    func placeholdersHaveExactlyOneOpenFront() {
        let openFronts = CampaignFront.placeholders.filter { $0.state == .open }

        #expect(openFronts.count == 1)
    }
}
