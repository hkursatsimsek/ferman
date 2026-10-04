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

    // MARK: Written orders (F2.4)

    @MainActor
    private func write(_ text: String, in app: XCUIApplication) {
        let field = app.textFields["writeOrderField"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        field.typeText(text + "\n")
    }

    @MainActor
    func testAWrittenOrderIsSealedIntoTheStack() throws {
        let app = launchApp()
        write("düşman 3 kareden yakınsa geri çekil", in: app)

        XCTAssertTrue(app.staticTexts["düşman 3 kareden yakınsa"].waitForExistence(timeout: 3))
        // Waiting to be sealed: the field and "Emir ekle" give way to the review bar.
        XCTAssertFalse(app.buttons["Emir ekle"].exists)
        let seal = app.buttons["Mühürle"]
        XCTAssertTrue(seal.exists)
        seal.tap()

        XCTAssertTrue(app.buttons["Emir ekle"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Mühürle"].exists)
        XCTAssertTrue(app.staticTexts["düşman 3 kareden yakınsa"].exists)
        XCTAssertTrue(app.staticTexts["GERİ ÇEKİL"].exists)
    }

    @MainActor
    func testABlankMustBeFilledBeforeSealing() throws {
        let app = launchApp()
        write("düşman yaklaşırsa geri çekil", in: app)

        XCTAssertTrue(app.staticTexts["Boşlukları doldur, sonra mühürle."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Mühürle"].exists)

        app.staticTexts["GERİ ÇEKİL"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["parameterDial"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["düşman 1 kareden yakınsa"].exists)

        let seal = app.buttons["Mühürle"]
        XCTAssertTrue(seal.waitForExistence(timeout: 2))
        seal.tap()
        XCTAssertTrue(app.buttons["Emir ekle"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["düşman 1 kareden yakınsa"].exists)
    }

    @MainActor
    func testDiscardingAWrittenOrderLeavesTheStackAsItWas() throws {
        let app = launchApp()
        write("kuşatıldıysam dağıl", in: app)

        XCTAssertTrue(app.staticTexts["kuşatıldıysam"].waitForExistence(timeout: 3))
        app.buttons["Vazgeç"].tap()

        XCTAssertTrue(app.buttons["Emir ekle"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["kuşatıldıysam"].exists)
        XCTAssertTrue(app.staticTexts["Henüz emir yok."].exists)
    }

    @MainActor
    func testTextThatIsNotAnOrderSaysWhy() throws {
        let app = launchApp()
        write("merhaba komutan", in: app)

        XCTAssertTrue(app.staticTexts["writeOrderError"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Mühürle"].exists)
    }

    // MARK: Spoken orders (F2.5)

    /// A scripted microphone (`-uiTestSpokenOrder`) — the real one needs a device.
    @MainActor
    func testASpokenOrderLandsAsSlipsToSeal() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSpokenOrder", "düşman 3 kareden yakınsa geri çekil"]
        app.launch()

        let microphone = app.buttons["Emri söyle"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 3))
        microphone.tap()

        let transcript = app.staticTexts["spokenTranscript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 2))
        let stop = app.buttons["Söylemeyi bitir"]
        XCTAssertTrue(stop.exists)
        stop.tap()

        XCTAssertTrue(app.staticTexts["düşman 3 kareden yakınsa"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Mühürle"].exists)
    }

    @MainActor
    func testWithoutAMicrophoneThereIsNoMicrophoneButton() throws {
        let app = launchApp()
        XCTAssertTrue(app.textFields["writeOrderField"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Emri söyle"].exists)
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
