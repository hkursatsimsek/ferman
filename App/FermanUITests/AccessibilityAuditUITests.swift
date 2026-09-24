import XCTest

/// `performAccessibilityAudit()` (iOS 17+) on the app's core screens (F1.13's done-definition).
final class AccessibilityAuditUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Collects every issue instead of throwing on the first one, so a failure names all of them
    /// with `detailedDescription` — the summary XCTest prints for a bare `try audit()` throw doesn't.
    /// `knownIssueLabels` skips issues already investigated and confirmed not real (see
    /// `testRuleEditorScreenHasNoAccessibilityIssues`) instead of silently swallowing every future one.
    @MainActor
    private func auditAndReport(
        _ app: XCUIApplication, knownIssueLabels: Set<String> = [], file: StaticString = #filePath, line: UInt = #line
    ) throws {
        var issues: [String] = []
        try app.performAccessibilityAudit { issue in
            guard let label = issue.element?.label, !knownIssueLabels.contains(label) else { return true }
            issues.append(
                "\(issue.detailedDescription) | label=\(label) "
                    + "id=\(issue.element?.identifier ?? "?") frame=\(issue.element?.frame ?? .zero)")
            return true
        }
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n---\n"), file: file, line: line)
    }

    /// Same tool limitation as `testRuleEditorScreenHasNoAccessibilityIssues` (icon-plus-text rows
    /// whose combined accessibility frame the `.contrast` check samples somewhere that isn't the
    /// text): `HomeView.menuRow` and `CampaignView.frontRow` already replace default combining with
    /// an explicit `.accessibilityElement(children: .ignore)` + one manual label each, and the audit
    /// still reports the pre-existing per-`Text` labels ("Arena", "3 maç bekliyor", "N. Cephe", the
    /// front title) as separate issues — confirmed unchanged across a clean rebuild, so it isn't
    /// build staleness. `ArmySetupView`'s tray items use the identical pattern and do pass, so this
    /// isn't universal; it wasn't chased further than that.
    ///
    /// G12 correction: the home rows' reports were partly real. Their locked rows were `.plain`-styled
    /// disabled buttons, which SwiftUI fades to ~2.5:1 contrast (pixel-sampled) — `FermanButton.Row`
    /// now draws them as given, and the home screen passes with no exceptions. The campaign's caption
    /// labels ("N. Cephe") on their dark slips pixel-sample at 7.0–7.2:1 (G12, after the same fix), so
    /// those reports remain the tool limitation described above.
    private static let homeKnownIssueLabels: Set<String> = []
    private static let campaignKnownIssueLabels: Set<String> = [
        "1. Cephe", "2. Cephe", "4. Cephe", "5. Cephe", "8. Cephe", "Son Hat", "Demir Kapı",
    ]

    @MainActor
    func testHomeScreenHasNoAccessibilityIssues() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSandbox"]
        app.launch()
        XCTAssertTrue(app.buttons["home.seferberlik"].waitForExistence(timeout: 2))
        try auditAndReport(app, knownIssueLabels: Self.homeKnownIssueLabels)
    }

    @MainActor
    func testCampaignScreenHasNoAccessibilityIssues() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSandbox"]
        app.launch()
        app.buttons["home.seferberlik"].tap()
        XCTAssertTrue(app.buttons["campaign.front.3"].waitForExistence(timeout: 2))
        // The line opens scrolled to the current front, which can leave a pin half under the opaque
        // navigation bar — the audit then samples the bar's pixels for that pin's contrast. Audit the
        // line at rest at its top instead, where nothing sits under the bar (G12).
        app.swipeDown()
        app.swipeDown()
        // Let the scroll view's bounce settle — auditing mid-bounce samples moving text.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "scroll settles")], timeout: 1.5)
        try auditAndReport(app, knownIssueLabels: Self.campaignKnownIssueLabels)
    }

    @MainActor
    func testArmySetupScreenHasNoAccessibilityIssues() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSandbox"]
        app.launch()
        app.buttons["home.seferberlik"].tap()
        XCTAssertTrue(app.buttons["campaign.front.3"].waitForExistence(timeout: 2))
        app.buttons["campaign.front.3"].tap()
        XCTAssertTrue(app.buttons["Hazırlan"].waitForExistence(timeout: 2))
        app.buttons["Hazırlan"].tap()
        XCTAssertTrue(app.staticTexts["Bütçe"].waitForExistence(timeout: 2))
        try auditAndReport(app)
    }

    /// Same tool limitation as `testRuleEditorScreenHasNoAccessibilityIssues`: `SpeedControl`'s
    /// unselected segments (`BattleTopBar`) reported `.contrast` here — "2×" on one run, "4×" on
    /// another (same style, same code path). Pixel-sampled a real screenshot (`-uiTestBattle 2`, live
    /// on a booted simulator) at an unselected segment's glass background: text ~(213,217,216) on
    /// glass ~(57,64,70), ~8.7:1 — comfortably above 4.5:1. Also `.dynamicType` ("user will not be able
    /// to change the font size") on the trigger strip's priority badges (`BattleTriggerStrip`,
    /// `FermanFont.counter`, same scaling font as `debriefKnownIssueLabels`'s "33 sn") — reported as
    /// "2" on one run, "1" on another (level 2 only has two rules, so only these two badges exist to
    /// flag): set the simulator to `content_size accessibility-extra-extra-extra-large` and
    /// screenshotted the paused battle screen — both badges grow right along with the rest of the
    /// strip. None chased further than that (G15).
    private static let battleKnownIssueLabels: Set<String> = ["2×", "4×", "1", "2"]
    /// Same tool limitation, two different audit categories on the same merged-subtree pattern
    /// (`DebriefTapeView`'s `.accessibilityElement(children: .ignore)`, `DebriefView`'s footer):
    /// (1) `.contrast` on "Sonraki Cephe" (`FermanButton.Primary`'s brass gradient) — pixel-sampled a
    /// real screenshot (`-uiTestDebrief 2`) across the whole gradient, text to background, at both its
    /// lightest and darkest ends: ink ~(15,5,0) on brass ~(195,157,92) down to ~(171,139,64), 6.1–8.0:1
    /// throughout, comfortably above 4.5:1 everywhere on the button. (2) `.dynamicType` ("user will not
    /// be able to change the font size") on "33 sn" (the tape's total-duration label, `FermanFont.counter`,
    /// which does scale — F1.13 already relies on that) — set the simulator to
    /// `content_size accessibility-extra-extra-extra-large` and screenshotted the same screen: "33 sn"
    /// grows right along with "emir"/"kayıp" beside it. Neither chased further than that (G15).
    private static let debriefKnownIssueLabels: Set<String> = ["Sonraki Cephe", "33 sn"]

    /// The battle (G15): the top bar, the trigger strip, and the table's figures as VoiceOver hears
    /// them. Paused first, so the audit doesn't sample a table that's moving under it.
    @MainActor
    func testBattleScreenHasNoAccessibilityIssues() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSandbox", "-uiTestBattle", "2"]
        app.launch()
        let pause = app.buttons["Duraklat"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        XCTAssertTrue(app.buttons["Oynat"].waitForExistence(timeout: 2))
        try auditAndReport(app, knownIssueLabels: Self.battleKnownIssueLabels)
    }

    @MainActor
    func testDebriefScreenHasNoAccessibilityIssues() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSandbox", "-uiTestDebrief", "2"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Hat tutuldu."].waitForExistence(timeout: 10))
        try auditAndReport(app, knownIssueLabels: Self.debriefKnownIssueLabels)
    }

    @MainActor
    func testRuleEditorScreenHasNoAccessibilityIssues() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestRuleEditor"]
        app.launch()
        XCTAssertTrue(app.staticTexts["İLERLE"].waitForExistence(timeout: 2))
        // "Okçu"/"Kalkanlı" (the unit type tabs, `RuleEditorView.unitTypeTabs`) report `.contrast`
        // failures here regardless of grouping (`.combine`, `.ignore` + a manual label — tried
        // both). Pixel-sampled a screenshot at the reported frame directly: the text itself renders
        // near-white (~(216,217,219)) on near-black (~(14,21,27)), ~11:1 — the frame the tool reports
        // spans the tab's `UnitToken` icon above the text too, and whatever it samples inside that
        // combined frame isn't the text pixels. Treating as a tool limitation, not a real contrast
        // bug, until it can be reproduced against a plain `Text`-only element.
        try auditAndReport(app, knownIssueLabels: ["Okçu", "Kalkanlı"])
    }
}
