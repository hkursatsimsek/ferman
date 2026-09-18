import XCTest

/// Exercises the real navigation graph (F1.9 done-definition): `HomeView` → `CampaignView` → the
/// level sheet → `ArmySetupView`, driven by `AppRouter`'s `[Route]` stack. No launch argument here —
/// this is the app's actual default entry point, unlike `RuleEditorUITests` (F1.7), which still
/// reaches `RuleEditorView` through `-uiTestRuleEditor` since that hop isn't wired yet.
final class AppNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    @MainActor
    func testTappingSeferberlikOpensTheCampaignLine() throws {
        let app = launchApp()

        app.buttons["home.seferberlik"].tap()

        XCTAssertTrue(app.buttons["campaign.front.3"].waitForExistence(timeout: 2))
    }

    /// `CampaignFront.fronts(from:)` (F1.14) makes every real level `.open` — there is no persisted
    /// "cleared" signal yet to gate a lock/unlock sequence on (`ProgressStore`, F1.11, still isn't
    /// wired to any screen). The `.locked` mechanism itself is still real and still covered directly
    /// at the model level, with a fixture that has one (`CampaignModelTests.lockedFrontsCannotBeOpened`);
    /// this end-to-end check now confirms the opposite: nothing in the shipped content is locked out.
    @MainActor
    func testNoRealFrontIsLocked() throws {
        let app = launchApp()
        app.buttons["home.seferberlik"].tap()
        XCTAssertTrue(app.buttons["campaign.front.1"].waitForExistence(timeout: 2))

        for id in 1...8 {
            XCTAssertTrue(app.buttons["campaign.front.\(id)"].isEnabled)
        }
    }

    @MainActor
    func testHazirlanPushesIntoArmySetupWithTheFrontsBudget() throws {
        let app = launchApp()
        app.buttons["home.seferberlik"].tap()
        XCTAssertTrue(app.buttons["campaign.front.3"].waitForExistence(timeout: 2))

        app.buttons["campaign.front.3"].tap()
        XCTAssertTrue(app.buttons["Hazırlan"].waitForExistence(timeout: 2))
        app.buttons["Hazırlan"].tap()

        XCTAssertTrue(app.staticTexts["Bütçe"].waitForExistence(timeout: 2))
        // Level 3's playerBudget (Packages/FermanContent/Sources/FermanContent/Resources/levels.json).
        XCTAssertTrue(app.staticTexts["0 / 90"].exists)
    }
}
