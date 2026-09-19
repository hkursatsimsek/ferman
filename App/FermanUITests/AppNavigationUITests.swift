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
        // In-memory progress, every front open: the same starting point every run (G12).
        app.launchArguments += ["-uiTestSandbox"]
        app.launch()
        return app
    }

    @MainActor
    func testTappingSeferberlikOpensTheCampaignLine() throws {
        let app = launchApp()

        app.buttons["home.seferberlik"].tap()

        XCTAssertTrue(app.buttons["campaign.front.3"].waitForExistence(timeout: 2))
    }

    /// Under `-uiTestSandbox` every front is open; the real lock/unlock sequence from progress is
    /// covered at the model level (`CampaignModelTests`, G12).
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
