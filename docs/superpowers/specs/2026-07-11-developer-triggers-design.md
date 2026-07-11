# Developer View Triggers Design Document

## 1. Overview
This specification details the implementation of a dedicated "Developer Triggers" section in GJournal's `DebugSettingsView` (compiled only `#if DEBUG`). The goal is to provide buttons to trigger events that are otherwise difficult or impossible to run on-demand (such as daily notifications, crash diagnostics, and safety warning sheets).

---

## 2. Target Triggers & APIs

### 2.1 Notifications
* **Trigger Test Notification (5s delay):** Schedules a local notification to fire in 5 seconds.
  * *API:* Utilizes `UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)` instead of the daily calendar trigger, reuse the content from `ReminderScheduler.shared.schedule()`.
* **Print Pending Notification Requests:** Prints scheduled notification details to `AppLogger` / console.
  * *API:* `UNUserNotificationCenter.current().getPendingNotificationRequests { requests in ... }`
* **Cancel All Notifications:** Cancels all pending notifications immediately.
  * *API:* `ReminderScheduler.shared.cancel()`

### 2.2 Crash & Diagnostics
* **Force App Crash:** Simulates a hard crash to test MetricKit diagnostic reports on the next launch.
  * *API:* Call `fatalError("Developer triggered test crash")`.
* **Generate Mock Diagnostic Payload:** Writes a mock MetricKit diagnostic JSON payload to the application's `CrashReports` directory to test the sharing sheet without having to crash the app.
  * *API:* Write a dummy JSON structure to `CrashReporter.reportsDirectory`.
* **Clear Crash Directory:** Deletes all persisted files in the `CrashReports` directory.
  * *API:* Iterate over contents of `CrashReporter.reportsDirectory` and call `removeItem(at:)`.

### 2.3 User Safety
* **Trigger Safety Filter Alert:** Displays the Crisis Resources sheet immediately.
  * *API:* Toggle a new debug binding or state variable that simulates `SafetyFilter.isSelfHarmSignal` being true.

---

## 3. UI Placement & State Management

All triggers will be appended to [DebugSettingsView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/DebugSettingsView.swift) as a new section labeled **"Manual Diagnostic Triggers"**.

```swift
Section {
    // 1. Notification Buttons
    Button("Trigger Test Notification (5s)") { ... }
    Button("Print Pending Notifications") { ... }
    Button("Cancel All Notifications") { ... }
    
    // 2. Crash / Diagnostic Buttons
    Button(role: .destructive, "Force App Crash") { ... }
    Button("Generate Mock Crash Report") { ... }
    Button(role: .destructive, "Clear Saved Crash Reports") { ... }
    
    // 3. Safety Alert Trigger
    Button("Simulate Self-Harm Warning") { ... }
} header: {
    Text("Manual Diagnostic Triggers")
}
```

State changes (such as displaying status messages) will reuse the existing `debugStatusMessage` state variable. To simulate the self-harm warning, a new debug sheet trigger will be wired into `DebugSettingsView`.

---

## 4. Testing Strategy
1. Verify "Trigger Test Notification (5s)" shows a notification banner when the app is placed in the background.
2. Verify "Print Pending Notifications" output in Xcode console.
3. Verify "Force App Crash" terminates the app and that a diagnostic payload is registered.
4. Verify "Generate Mock Crash Report" enables the "Export Crash Diagnostics" button in Settings.
5. Verify "Simulate Self-Harm Warning" opens the [CrisisResourcesView](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/CrisisResourcesView.swift) sheet.
