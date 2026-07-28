import UserNotifications
import Foundation

final class ReminderScheduler {

    static let shared = ReminderScheduler()
    private init() {}

    private let notificationID = "gjournal.daily.reminder"
    private let enabledKey = "reminderEnabled"
    private let hourKey = "reminderHour"
    private let minuteKey = "reminderMinute"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey); newValue ? schedule() : cancel() }
    }

    var hour: Int {
        get { UserDefaults.standard.integer(forKey: hourKey) == 0 && !UserDefaults.standard.bool(forKey: "reminderHourSet")
              ? 20 : UserDefaults.standard.integer(forKey: hourKey) }
        set { UserDefaults.standard.set(newValue, forKey: hourKey); UserDefaults.standard.set(true, forKey: "reminderHourSet") }
    }

    var minute: Int {
        get { UserDefaults.standard.integer(forKey: minuteKey) }
        set { UserDefaults.standard.set(newValue, forKey: minuteKey) }
    }

    /// `hour`/`minute` as a `Date` for binding to a SwiftUI `DatePicker`.
    var scheduledTime: Date {
        get {
            Calendar.current.date(
                from: DateComponents(hour: hour, minute: minute)
            ) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = components.hour ?? 20
            minute = components.minute ?? 0
            if isEnabled { schedule() }
        }
    }

    /// Re-register the pending request on launch. iOS can drop pending
    /// notifications (restore from backup, reinstall), and the only previous
    /// call site was the `isEnabled` setter — so reminders silently stopped
    /// forever and never came back.
    func refreshOnLaunch() {
        guard isEnabled else { return }
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let alreadyScheduled = requests.contains { $0.identifier == self.notificationID }
            if !alreadyScheduled {
                AppLogger.error("[Reminder] Pending request missing — rescheduling")
                self.schedule()
            }
        }
    }

    func requestPermissionAndEnable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            if granted { isEnabled = true }
            return granted
        } catch {
            AppLogger.error("[Reminder] Permission request failed: \(error)")
            return false
        }
    }

    func schedule() {
        cancel()
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "A moment for yourself"
        content.body = "How are you feeling today? Your journal is waiting."
        content.sound = .default
        content.interruptionLevel = .passive

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error { AppLogger.error("[Reminder] Schedule failed: \(error)") }
        }
    }

    func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
}
