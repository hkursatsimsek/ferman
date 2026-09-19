import XCTest

/// G13: the first fronts leave pencil notes on the table (TipKit), and a closed note stays closed.
/// `-uiTestTips` starts from a fresh TipKit datastore, so the notes behave as they will for a new player.
final class TutorialNotesUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSandbox", "-uiTestTips"] + arguments
        app.launch()
        return app
    }

    @MainActor
    func testTheFirstFrontsDeploymentHasANoteThatCanBeClosed() throws {
        let app = launch(["-uiTestArmySetup", "1"])
        let note = app.staticTexts["Birliklerini diz."]
        XCTAssertTrue(note.waitForExistence(timeout: 5))

        app.buttons["Notu kapat"].firstMatch.tap()

        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: note)
        wait(for: [gone], timeout: 3)
    }

    /// The note is paper and pencil-grey ink on the table: it must pass the same audit as the screen.
    @MainActor
    func testTheNoteIsAccessible() throws {
        let app = launch(["-uiTestArmySetup", "1"])
        XCTAssertTrue(app.staticTexts["Birliklerini diz."].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit()
    }

    /// Without `-uiTestTips` the sandbox keeps every note away, so the other screen tests see the
    /// layout they expect.
    @MainActor
    func testTheSandboxShowsNoNotes() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSandbox", "-uiTestArmySetup", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Bütçe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Birliklerini diz."].exists)
    }
}
