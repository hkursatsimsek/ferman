//
//  FermanUITests.swift
//  FermanUITests
//
//  Created by Hamza Kürşat Şimşek on 15.09.2026.
//

import XCTest

final class FermanUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunches() throws {
        let app = XCUIApplication()
        app.launch()
    }
}
