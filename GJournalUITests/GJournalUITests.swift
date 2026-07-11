import XCTest

/// Smoke-level UI tests. Deterministic app state is provided by `UITestSupport`
/// (DEBUG-only), driven through launch arguments:
/// - `UI_TESTING_STATE_ONBOARDING` — fresh install
/// - `UI_TESTING_STATE_LOCKED`     — registered user, PIN 123456, lock screen
/// - `UI_TESTING_STATE_DASHBOARD`  — session pre-authenticated, dashboard
/// - `UI_TESTING_SEED_ENTRIES`     — 40 seeded entries so insight gates unlock
final class GJournalUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(state: String? = nil, seeded: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        if let state { app.launchArguments.append("UI_TESTING_STATE_\(state)") }
        if seeded { app.launchArguments.append("UI_TESTING_SEED_ENTRIES") }
        app.launch()
        return app
    }

    // MARK: - Launch

    func testAppLaunchesWithoutCrash() {
        let app = launchApp()
        XCTAssertEqual(app.state, .runningForeground, "App should be in the foreground after launch")
    }

    // MARK: - Onboarding

    func testOnboardingPagesThroughToGetStarted() {
        let app = launchApp(state: "ONBOARDING")
        let next = app.buttons["Next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "Onboarding should show on a fresh install")
        next.tap()   // page 2
        next.tap()   // page 3
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 3),
                      "Final onboarding page should offer Get started")
    }

    // MARK: - Lock screen

    func testLockScreenRejectsWrongPINAndAcceptsCorrectPIN() {
        let app = launchApp(state: "LOCKED", seeded: true)
        XCTAssertTrue(app.buttons["PINDigit1"].waitForExistence(timeout: 5),
                      "PIN keypad should appear on the lock screen")

        // Wrong PIN → inline error, still locked.
        enterPIN("111112", in: app)
        XCTAssertTrue(app.staticTexts["Incorrect PIN — try again"].waitForExistence(timeout: 3),
                      "Wrong PIN should show an inline error")

        // Correct PIN → dashboard.
        enterPIN("123456", in: app)
        XCTAssertTrue(app.staticTexts["Recent Entries"].waitForExistence(timeout: 8),
                      "Dashboard should appear after entering the correct PIN")
    }

    private func enterPIN(_ pin: String, in app: XCUIApplication) {
        for digit in pin {
            app.buttons["PINDigit\(digit)"].tap()
        }
    }

    // MARK: - Paywall

    func testPaywallRendersWhenLockedInsightTapped() {
        let app = launchApp(state: "DASHBOARD", seeded: true)
        // Seeded data unlocks the insight gates; without a purchase the cards read "Unlock".
        let insightCard = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Unlock'")).firstMatch
        XCTAssertTrue(insightCard.waitForExistence(timeout: 8),
                      "A locked insight card should exist on the seeded dashboard")

        // The insights grid sits below the fold — scroll until the card is tappable.
        var attempts = 0
        while !insightCard.isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        insightCard.tap()

        XCTAssertTrue(app.staticTexts["GJournal Insights"].waitForExistence(timeout: 4),
                      "Paywall sheet should appear after tapping a locked insight")
    }

    // MARK: - Launch performance

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
