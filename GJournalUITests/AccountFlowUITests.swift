import XCTest

/// Drives the account-management surface added for production readiness:
/// renaming, the security rows, and the danger zone. None of this existed
/// before — the name was static text and there was no account deletion.
final class AccountFlowUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchDashboard() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UI_TESTING", "UI_TESTING_STATE_DASHBOARD", "UI_TESTING_SEED_ENTRIES"]
        app.launch()
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["gearshape.fill"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8), "Settings button should be on the dashboard")
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5),
                      "Settings should open")
    }

    /// `List` only instantiates visible cells, so a row below the fold reports
    /// `exists == false`. Scroll until it materialises rather than assuming a
    /// particular settings length.
    @discardableResult
    private func scrollToRow(_ app: XCUIApplication, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = app.staticTexts[label]
        for _ in 0..<8 {
            if element.exists && element.isHittable { return element }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists, "\(label) should be reachable in Settings", file: file, line: line)
        return element
    }

    func testSettingsExposesTheProductionAccountRows() {
        let app = launchDashboard()
        openSettings(app)

        // Rows that did not exist before this work.
        XCTAssertTrue(app.staticTexts["Change PIN"].exists, "Change PIN should be reachable")
        XCTAssertFalse(app.staticTexts["Log Out"].exists, "Log Out should be gone — it never survived relaunch")

        scrollToRow(app, "Lock Now")            // replaced the old Log Out
        scrollToRow(app, "Delete Account & All Data")
        scrollToRow(app, "Restore Purchases")   // must work outside the paywall
        scrollToRow(app, "Privacy Policy")      // App Review requires this reachable
    }

    /// The headline gap: the display name was read-only with no way to change it.
    func testRenameUpdatesTheDashboardGreeting() {
        let app = launchDashboard()

        // Seeded account is named "UITest".
        XCTAssertTrue(app.staticTexts["UITest"].waitForExistence(timeout: 8),
                      "Dashboard should greet the seeded user")

        openSettings(app)

        let nameRow = app.buttons.containing(.staticText, identifier: "Name").firstMatch
        XCTAssertTrue(nameRow.waitForExistence(timeout: 5), "Profile name row should be tappable")
        nameRow.tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Name editor should present a text field")
        field.tap()
        // Clear whatever is prefilled, then type a new name.
        if let existing = field.value as? String, !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText("Renamed")

        app.buttons["Save"].tap()

        // Back on Settings, then dismiss to the dashboard.
        XCTAssertTrue(app.staticTexts["Renamed"].waitForExistence(timeout: 5),
                      "Settings should show the new name")
        app.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["Renamed"].waitForExistence(timeout: 5),
                      "Dashboard greeting should reflect the new name")
    }

    /// Before this existed, forgetting the PIN meant losing the journal with no
    /// path back. On the simulator biometrics are unenrolled, so this exercises
    /// the destructive branch and its typed confirmation.
    func testForgotPINOffersRecoveryFromTheLockScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["UI_TESTING", "UI_TESTING_STATE_LOCKED", "UI_TESTING_SEED_ENTRIES"]
        app.launch()

        XCTAssertTrue(app.buttons["PINDigit1"].waitForExistence(timeout: 6),
                      "PIN keypad should appear")

        let forgot = app.buttons["Forgot PIN?"]
        XCTAssertTrue(forgot.waitForExistence(timeout: 3),
                      "The lock screen must offer a recovery path")
        forgot.tap()

        XCTAssertTrue(app.staticTexts["No way to verify you"].waitForExistence(timeout: 5),
                      "Without biometrics the only honest option is starting over")

        app.buttons["Erase & Start Over"].tap()

        XCTAssertTrue(app.staticTexts["Erase everything?"].waitForExistence(timeout: 5),
                      "The destructive branch must confirm before erasing")

        // The erase button stays disabled until DELETE is typed exactly.
        let eraseButton = app.buttons["Erase Everything"]
        XCTAssertTrue(eraseButton.waitForExistence(timeout: 3))
        XCTAssertFalse(eraseButton.isEnabled,
                       "Erase must be blocked until the confirmation is typed")
    }

    /// Lock Now must actually relock, not just dismiss the sheet.
    func testLockNowReturnsToTheLockScreen() {
        let app = launchDashboard()
        openSettings(app)

        scrollToRow(app, "Lock Now").tap()

        XCTAssertTrue(app.buttons["PINDigit1"].waitForExistence(timeout: 6),
                      "Lock Now should return the app to the PIN screen")
    }
}
