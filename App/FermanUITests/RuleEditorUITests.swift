import XCTest

/// Exercises the selector-based order editor end to end (F1.7 done-definition: "ekle / sırala /
/// düzenle"). Reaches `RuleEditorView` through the `-uiTestRuleEditor` launch argument since no
/// real navigation exists yet (F1.9). The order form (G9) shows every condition and action as a
/// button labeled with its plain word, so choosing one is a single tap on that label.
final class RuleEditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestRuleEditor"]
        app.launch()
        return app
    }

    @MainActor
    func testAddingAnOrderShowsItInTheStack() throws {
        let app = launchApp()
        app.buttons["Emir ekle"].tap()
        app.buttons["Ekle"].tap()

        XCTAssertTrue(app.staticTexts["düşman 1 kareden yakınsa"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["İLERLE"].exists)
    }

    @MainActor
    func testTappingANumericConditionOpensTheInPlaceDial() throws {
        let app = launchApp()
        app.buttons["Emir ekle"].tap()
        app.buttons["Ekle"].tap()
        XCTAssertTrue(app.staticTexts["düşman 1 kareden yakınsa"].waitForExistence(timeout: 2))

        app.staticTexts["düşman 1 kareden yakınsa"].tap()
        // The dial is one adjustable element to VoiceOver; turning it is a sideways drag.
        let dial = app.descendants(matching: .any)["parameterDial"]
        XCTAssertTrue(dial.waitForExistence(timeout: 2))
        dial.swipeLeft()

        let turned = app.staticTexts.matching(
            NSPredicate(
                format: "label BEGINSWITH 'düşman ' AND label ENDSWITH ' kareden yakınsa' AND label != 'düşman 1 kareden yakınsa'"
            )
        ).firstMatch
        XCTAssertTrue(turned.waitForExistence(timeout: 2))
    }

    @MainActor
    func testEditingTheDefaultOrderThroughItsSheet() throws {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["İLERLE"].waitForExistence(timeout: 2))

        app.staticTexts["başka durumda"].tap()
        app.buttons["Yerinde kal"].tap()
        app.buttons["Kaydet"].tap()

        XCTAssertTrue(app.staticTexts["YERİNDE KAL"].waitForExistence(timeout: 2))
    }

    // "Sırala" (reorder) is exercised at the model level instead of here
    // (RuleEditorModelTests.reorderMovesSourcesToJustBeforeTheirAnchor,
    // .moveUpAndMoveDownSwapAdjacentOrders): a live `press(forDuration:thenDragTo:)` onto a
    // `reorderContainer`/`reorderable()` row reliably crashed the app in this environment with a
    // `preconditionFailure` inside AppKit/UIKit's `DragContainerStorage.payload(for:)`, reachable
    // from `_UILongPressClickInteractionDriver`'s drag-lift handling — a framework-internal
    // assertion, not a call into our code. Given how new this API is (WWDC26), this may be a
    // simulator/synthetic-gesture-specific issue rather than something a real finger drag hits;
    // it needs checking by hand on-device before this ships.
}
