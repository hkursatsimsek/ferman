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

    /// `-uiTestBattle <level>`: the level's reference solution against its enemy, straight to the sand
    /// table — no touch automation available on this machine to walk Home → Campaign → ArmySetup first
    /// (the same constraint every other direct-launch entry point works around). Waits for "Sonuç"
    /// (`BattleTopBar`'s always-present result button) rather than anything about the outcome, since the
    /// intro choreography's length isn't fixed.
    @MainActor
    func testBattleScreenHasNoAccessibilityIssues() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSandbox", "-uiTestBattle", "1"]
        app.launch()
        XCTAssertTrue(app.buttons["Sonuç"].waitForExistence(timeout: 8))
        try auditAndReport(app)
    }

    /// `-uiTestDebrief <level>`: the same reference battle, already simulated, opened straight on the
    /// debrief. "Emirlerin" (`DebriefView.ordersSection`'s header) is shown regardless of the outcome.
    @MainActor
    func testDebriefScreenHasNoAccessibilityIssues() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSandbox", "-uiTestDebrief", "1"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Emirlerin"].waitForExistence(timeout: 3))
        try auditAndReport(app)
    }
}
