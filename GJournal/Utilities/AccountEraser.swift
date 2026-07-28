import Foundation
import SwiftData

/// Single source of truth for "erase everything on this device".
///
/// This lives in one place deliberately. The previous Settings-only wipe deleted
/// `Bit` and `Cluster` but left every `BehavioralTag` row behind, so a user who
/// deleted all their data still had a tag registry describing it. Any new model
/// added to `SchemaV2` must be added here too.
enum AccountEraser {

    /// Deletes all journal data. Returns false if the store could not be cleared.
    @discardableResult
    static func eraseData(modelContext: ModelContext) -> Bool {
        do {
            try modelContext.delete(model: Bit.self)
            try modelContext.delete(model: Cluster.self)
            try modelContext.delete(model: BehavioralTag.self)
            try modelContext.save()
            return true
        } catch {
            AppLogger.error("[AccountEraser] Failed to erase journal data: \(error)")
            return false
        }
    }

    /// Deletes all journal data *and* tears down the account: PIN, salt, lockout
    /// counters, name, biometric preference, reminders, and the onboarding flag,
    /// returning the app to a genuine first-run state.
    @discardableResult
    static func eraseAll(modelContext: ModelContext, authManager: AuthManager) -> Bool {
        let dataCleared = eraseData(modelContext: modelContext)

        ReminderScheduler.shared.isEnabled = false
        authManager.eraseAccount()
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")

        return dataCleared
    }
}
