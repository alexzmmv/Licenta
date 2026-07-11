#if DEBUG
import Foundation
import SwiftData
import Security

/// Deterministic app-state setup for UI tests.
///
/// Only active when the `UI_TESTING` launch argument is present (set by
/// `GJournalUITests`); compiled out of Release builds entirely.
///
/// Supported states (mutually exclusive, passed as extra launch arguments):
/// - `UI_TESTING_STATE_ONBOARDING` — fresh install, onboarding shows.
/// - `UI_TESTING_STATE_LOCKED`     — registered user with PIN `testPIN`, lock screen shows.
/// - `UI_TESTING_STATE_DASHBOARD`  — registered + session authenticated, dashboard shows
///                                   (see the matching hook in `AuthManager.init`).
/// - `UI_TESTING_SEED_ENTRIES`     — seed journal entries so the insight gates unlock.
enum UITestSupport {

    /// The PIN installed for `UI_TESTING_STATE_LOCKED` / `_DASHBOARD` runs.
    static let testPIN = "123456"

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("UI_TESTING")
    }

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }

    /// Called from `GJournalApp.init()` before any state objects are created,
    /// so `AuthManager` and `@AppStorage` reads observe the prepared state.
    static func configureLaunchState() {
        guard isActive else { return }
        let defaults = UserDefaults.standard

        if arguments.contains("UI_TESTING_STATE_ONBOARDING") {
            defaults.set(false, forKey: "hasCompletedOnboarding")
            defaults.set(false, forKey: "user_registered")
            defaults.set(false, forKey: "user_logged_in")
            defaults.removeObject(forKey: "user_name")
        } else if arguments.contains("UI_TESTING_STATE_LOCKED")
                    || arguments.contains("UI_TESTING_STATE_DASHBOARD") {
            defaults.set(true, forKey: "hasCompletedOnboarding")
            defaults.set(true, forKey: "user_registered")
            defaults.set(true, forKey: "user_logged_in")
            defaults.set("UITest", forKey: "user_name")
            defaults.set(false, forKey: "biometric_enabled")   // PIN path is deterministic on simulators
            defaults.set(false, forKey: "bypassPaywall")

            clearPINLockoutCounters()
            AuthManager().setPIN(testPIN)
        }
    }

    /// Seed enough entries to unlock every insight gate (seed_data.json:
    /// 40 entries across 39 distinct days). Idempotent — skipped when the
    /// store already has entries from a previous test launch.
    static func seedIfRequested(container: ModelContainer) {
        guard isActive, arguments.contains("UI_TESTING_SEED_ENTRIES") else { return }
        let context = container.mainContext
        let existing = (try? context.fetchCount(FetchDescriptor<Bit>())) ?? 0
        guard existing == 0 else { return }
        SeedDataManager.generateSeedData(context: context)
    }

    /// Remove any PIN-failure lockout left behind by a previous test run
    /// (the wrong-PIN test records one failure per run; lockout starts at 5).
    private static func clearPINLockoutCounters() {
        for account in ["pin_fail_count", "pin_last_fail_ts"] {
            let query: [String: Any] = [
                kSecClass as String:       kSecClassGenericPassword,
                kSecAttrService as String: "com.gjournal.auth",
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
#endif
