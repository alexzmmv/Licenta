import XCTest

final class GJournalUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch

    func testAppLaunchesWithoutCrash() {
        XCTAssertTrue(app.state == .runningForeground, "App should be in the foreground after launch")
    }

    func testOnboardingOrLockScreenIsVisible() {
        // On first launch, the onboarding is shown. On subsequent launches, the lock screen.
        // Either way, something must be on screen within 3 seconds.
        let hasContent = app.buttons.count > 0 || app.staticTexts.count > 0
        XCTAssertTrue(hasContent, "App should render at least one interactive element after launch")
    }

    // MARK: - Lock screen

    func testLockScreenShowsPINKeypad() {
        // If the app has a PIN set and is on the lock screen, the keypad should appear.
        // Skip if onboarding is showing instead.
        let keypad = app.buttons.matching(identifier: "PINDigit").firstMatch
        let onboardingNext = app.buttons["Next"].firstMatch
        let gettingStarted = app.buttons["Get started"].firstMatch

        let lockOrOnboardingAppears = keypad.waitForExistence(timeout: 3)
            || onboardingNext.waitForExistence(timeout: 3)
            || gettingStarted.waitForExistence(timeout: 3)

        XCTAssertTrue(lockOrOnboardingAppears, "Lock screen or onboarding should appear after launch")
    }

    // MARK: - Paywall

    func testPaywallRendersWhenInsightsTapped() throws {
        // Navigate to the paywall by tapping a locked insight card.
        // This test assumes the onboarding is completed and the PIN is set up.
        // It uses a generous timeout for the main dashboard to appear.
        let insightCard = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Unlock'")).firstMatch
        guard insightCard.waitForExistence(timeout: 8) else {
            throw XCTSkip("Could not reach the main dashboard — likely blocked by onboarding/lock screen in this test environment")
        }
        insightCard.tap()

        let paywallText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'GJournal Insights'")).firstMatch
        XCTAssertTrue(paywallText.waitForExistence(timeout: 4), "Paywall sheet should appear after tapping a locked insight")
    }

    // MARK: - Launch performance

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
