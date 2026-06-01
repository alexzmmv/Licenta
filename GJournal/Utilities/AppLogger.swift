import Foundation
import os.log

enum AppLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "GJournal",
        category: "App"
    )

    private static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "debugLoggingEnabled")
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        guard isEnabled else { return }
        logger.error("\(message, privacy: .public)")
    }
}
