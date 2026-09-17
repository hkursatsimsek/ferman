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

    @MainActor
    func testLockedFrontsCannotBeOpened() throws {
        let app = launchApp()
        app.buttons["home.seferberlik"].tap()
        let lockedFront = app.buttons["campaign.front.4"]
        XCTAssertTrue(lockedFront.waitForExistence(timeout: 2))

        XCTAssertFalse(lockedFront.isEnabled)
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
        XCTAssertTrue(app.staticTexts["0 / 310"].exists)
    }
}
