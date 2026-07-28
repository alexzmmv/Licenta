import Foundation
import os.log

enum AppLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "GJournal",
        category: "App"
    )

    nonisolated private static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "debugLoggingEnabled")
    }

    /// Verbose tracing. Off unless debug logging is switched on, which is only
    /// reachable from `DebugSettingsView` (`#if DEBUG`).
    nonisolated static func log(_ message: String) {
        guard isEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }

    /// Failures. Always recorded, including in Release.
    ///
    /// This used to be gated behind the same debug-only toggle as `log`, which
    /// meant every production failure path — export errors, delete failures,
    /// Keychain problems — recorded nothing at all, leaving no way to diagnose a
    /// user report.
    ///
    /// Interpolation is `.private` so journal text or names caught up in an
    /// error description are redacted in the system log; attach a Console-visible
    /// device only when actively debugging.
    nonisolated static func error(_ message: String) {
        logger.error("\(message, privacy: .private)")
    }
}
