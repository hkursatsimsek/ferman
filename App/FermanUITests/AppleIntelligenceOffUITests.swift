import XCTest

/// F2.6: the whole game with Apple Intelligence off. The model behind the template answers nothing
/// (`-uiTestAppleIntelligenceOff`), and a front is still played from the home screen to the debrief —
/// placing the army, writing an order in words, sealing it, fighting, reading the result.
final class AppleIntelligenceOffUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAWholeFrontIsPlayableWithoutTheModel() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSandbox", "-uiTestAppleIntelligenceOff"]
        app.launch()

        app.buttons["home.seferberlik"].tap()
        XCTAssertTrue(app.buttons["campaign.front.3"].waitForExistence(timeout: 3))
        app.buttons["campaign.front.3"].tap()
        XCTAssertTrue(app.buttons["Hazırlan"].waitForExistence(timeout: 3))
        app.buttons["Hazırlan"].tap()

        // Choose-then-tap (G10): the archer stays in hand for one cell after another.
        let archer = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Okçu,'"))
            .firstMatch
        XCTAssertTrue(archer.waitForExistence(timeout: 3))
        archer.tap()
        for _ in 0..<3 {
            let emptyCell = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Boş hücre'"))
                .firstMatch
            XCTAssertTrue(emptyCell.waitForExistence(timeout: 2))
            emptyCell.tap()
        }
        let writeOrders = app.buttons["Emirleri Yaz"]
        XCTAssertTrue(writeOrders.waitForExistence(timeout: 2))
        writeOrders.tap()

        // Text the template can't read: with no model to ask, the template's own answer, at once.
        let field = app.textFields["writeOrderField"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("selam komutan\n")
        XCTAssertTrue(app.staticTexts["writeOrderError"].waitForExistence(timeout: 3))

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        field.typeText("düşman 3 kareden yakınsa geri çekil\n")
        let seal = app.buttons["Mühürle"]
        XCTAssertTrue(seal.waitForExistence(timeout: 3))
        seal.tap()

        let startBattle = app.buttons["Savaşı Başlat"]
        XCTAssertTrue(startBattle.waitForExistence(timeout: 3))
        XCTAssertTrue(startBattle.isEnabled)
        startBattle.tap()

        let result = app.buttons["Sonuç"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        let held = app.staticTexts["Hat tutuldu."]
        let broken = app.staticTexts["Cephe yarıldı."]
        XCTAssertTrue(held.waitForExistence(timeout: 10) || broken.exists)
    }
}
