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

    /// The sheet used to open at `.medium` with "Hazırlan" scrolled below its bottom edge. `isHittable`
    /// doesn't scroll, so this fails wherever the button isn't on screen as the sheet opens.
    @MainActor
    func testTheLevelSheetShowsHazirlanWithoutScrolling() throws {
        // 3: briefing, enemy, both budgets and a new-order dispatch; 8: the largest enemy.
        for frontID in [3, 8] {
            let app = launchApp()
            app.buttons["home.seferberlik"].tap()
            let front = app.buttons["campaign.front.\(frontID)"]
            XCTAssertTrue(front.waitForExistence(timeout: 3))
            front.tap()

            let prepare = app.buttons["Hazırlan"]
            XCTAssertTrue(prepare.waitForExistence(timeout: 3))
            // Let the sheet settle at the height it measured for itself.
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(prepare.isHittable, "front \(frontID)")
            XCTAssertLessThanOrEqual(prepare.frame.maxY, app.windows.firstMatch.frame.maxY, "front \(frontID)")

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "level-sheet-\(frontID)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
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
