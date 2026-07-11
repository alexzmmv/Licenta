# Developer Triggers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a set of debug buttons in GJournal's `DebugSettingsView` to manually trigger notifications, crash scenarios, mock diagnostics, and safety warning views.

**Architecture:** Add a new "Manual Diagnostic Triggers" Section to `DebugSettingsView` wrapped in `#if DEBUG`, with handlers to dispatch local notifications, trigger deliberate crashes, mock MetricKit JSON files on disk, and present the `CrisisResourcesView` sheet.

**Tech Stack:** SwiftUI, UserNotifications, MetricKit, SwiftData

## Global Constraints
* iOS version minimum: iOS 18.0
* Target environment: Xcode iPhone 17 Pro simulator
* Code blocks must compile only in `#if DEBUG` configuration where appropriate.

---

### Task 1: Add Developer View Buttons & Simulated Triggers

**Files:**
* Modify: [DebugSettingsView.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournal/Views/DebugSettingsView.swift)
* Create: [GJournalTests/DeveloperTriggersTests.swift](file:///Users/constantin-alexandrudumitrascu/Desktop/GJournal/GJournalTests/DeveloperTriggersTests.swift)

**Interfaces:**
* Consumes: `ReminderScheduler`, `CrashReporter`, `CrisisResourcesView`
* Produces: Interactive buttons in `DebugSettingsView` list layout.

- [ ] **Step 1: Write the DeveloperTriggersTests file**
  Create a test to verify the directory verification and mock report generation.

  ```swift
  import XCTest
  @testable import GJournal

  final class DeveloperTriggersTests: XCTestCase {
      func testMockDiagnosticReportGenerationAndCleanup() throws {
          guard let dir = CrashReporter.reportsDirectory else {
              XCTFail("Crash reports directory should be accessible")
              return
          }
          let fm = FileManager.default
          
          // Clear current files to isolate test
          let initialFiles = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
          for file in initialFiles {
              try? fm.removeItem(at: file)
          }

          // Write mock diagnostic file
          let stamp = UInt(Date().timeIntervalSince1970)
          let fileURL = dir.appendingPathComponent("diagnostic-\(stamp)-mocktest.json")
          let mockJSON = "{\"crashes\": [{\"exceptionType\": 1, \"terminationReason\": \"Developer test\"}]}"
          try mockJSON.write(to: fileURL, atomically: true, encoding: .utf8)

          let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
          XCTAssertTrue(files.contains(fileURL), "Mock diagnostic report was not generated on disk")

          // Clear files
          for file in files {
              try fm.removeItem(at: file)
          }
          let filesAfter = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
          XCTAssertTrue(filesAfter.isEmpty, "Failed to clear the reports directory")
      }
  }
  ```

- [ ] **Step 2: Add test to target build and verify failing test**
  Wait, the test will pass because `CrashReporter.reportsDirectory` is public. Run:
  `xcodebuild test -workspace GJournal.xcworkspace -scheme GJournal -destination "platform=iOS Simulator,name=iPhone 17 Pro"`
  *(Note: Since we are running outside Xcode GUI, we can run this command to build and verify tests).*

- [ ] **Step 3: Modify DebugSettingsView to add Manual Diagnostic Triggers Section**
  Add state variable `@State private var showingCrisisResources = false` at the top of the struct.
  Add the section at the end of the `List` container:

  ```swift
  Section {
      // Notification triggers
      Button {
          triggerTestNotification()
      } label: {
          HStack {
              Image(systemName: "bell.badge")
                  .foregroundColor(.yellow)
              VStack(alignment: .leading) {
                  Text("Trigger Test Notification (5s)")
                  Text("Schedules a daily reminder after a 5s delay")
                      .font(.caption2)
                      .foregroundColor(.secondary)
              }
          }
      }

      Button {
          printPendingNotifications()
      } label: {
          HStack {
              Image(systemName: "list.bullet")
                  .foregroundColor(.blue)
              VStack(alignment: .leading) {
                  Text("Print Pending Notifications")
                  Text("Print scheduled alerts to log console")
                      .font(.caption2)
                      .foregroundColor(.secondary)
              }
          }
      }

      Button {
          cancelAllNotifications()
      } label: {
          HStack {
              Image(systemName: "bell.slash")
                  .foregroundColor(.red)
              VStack(alignment: .leading) {
                  Text("Cancel All Notifications")
                  Text("Removes all pending notifications")
                      .font(.caption2)
                      .foregroundColor(.secondary)
              }
          }
      }

      // Crash triggers
      Button(role: .destructive) {
          forceAppCrash()
      } label: {
          HStack {
              Image(systemName: "exclamationmark.triangle")
              VStack(alignment: .leading) {
                  Text("Force App Crash")
                  Text("Immediately crash the app with fatalError")
                      .font(.caption2)
                      .foregroundColor(.secondary)
              }
          }
      }

      Button {
          generateMockCrashReport()
      } label: {
          HStack {
              Image(systemName: "doc.badge.plus")
                  .foregroundColor(.green)
              VStack(alignment: .leading) {
                  Text("Generate Mock Crash Report")
                  Text("Writes a dummy MetricKit payload to disk")
                      .font(.caption2)
                      .foregroundColor(.secondary)
              }
          }
      }

      Button(role: .destructive) {
          clearSavedCrashReports()
      } label: {
          HStack {
              Image(systemName: "trash")
              VStack(alignment: .leading) {
                  Text("Clear Saved Crash Reports")
                  Text("Deletes all files in CrashReports directory")
                      .font(.caption2)
                      .foregroundColor(.secondary)
              }
          }
      }

      // Safety trigger
      Button {
          showingCrisisResources = true
      } label: {
          HStack {
              Image(systemName: "heart.text.square")
                  .foregroundColor(.red)
              VStack(alignment: .leading) {
                  Text("Simulate Self-Harm Warning")
                  Text("Triggers the Crisis Resources sheet immediately")
                      .font(.caption2)
                      .foregroundColor(.secondary)
              }
          }
      }
  } header: {
      Text("Manual Diagnostic Triggers")
  }
  ```

  And append the sheet modifier to the `List`:
  ```swift
  .sheet(isPresented: $showingCrisisResources) {
      CrisisResourcesView()
  }
  ```

  And add the private methods to the `DebugSettingsView` struct:
  ```swift
  private func triggerTestNotification() {
      let content = UNMutableNotificationContent()
      content.title = "A moment for yourself"
      content.body = "How are you feeling today? Your journal is waiting."
      content.sound = .default
      content.interruptionLevel = .passive
      
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
      let request = UNNotificationRequest(identifier: "gjournal.test.reminder", content: content, trigger: trigger)
      
      UNUserNotificationCenter.current().add(request) { error in
          await MainActor.run {
              if let error = error {
                  debugStatusMessage = "Notification failed: \(error.localizedDescription)"
              } else {
                  debugStatusMessage = "Test notification scheduled (5s)"
              }
          }
      }
  }

  private func printPendingNotifications() {
      UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
          let summary = requests.map { "\($0.identifier): \($0.content.title)" }.joined(separator: ", ")
          await MainActor.run {
              debugStatusMessage = requests.isEmpty ? "No pending notifications" : "Pending: \(summary)"
              AppLogger.log("[Debug] Pending notification requests: \(summary)")
          }
      }
  }

  private func cancelAllNotifications() {
      ReminderScheduler.shared.cancel()
      UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["gjournal.test.reminder"])
      debugStatusMessage = "All notifications cancelled"
  }

  private func forceAppCrash() {
      fatalError("Developer triggered deliberate crash for testing CrashReporter")
  }

  private func generateMockCrashReport() {
      guard let dir = CrashReporter.reportsDirectory else {
          debugStatusMessage = "Error accessing reports directory"
          return
      }
      let fm = FileManager.default
      let stamp = UInt(Date().timeIntervalSince1970)
      let fileURL = dir.appendingPathComponent("diagnostic-\(stamp)-mock.json")
      
      // A mock payload to simulate standard crash report metadata
      let mockJSON = """
      {
        "crashDiagnostics": [
          {
            "signal": 11,
            "exceptionType": 1,
            "exceptionCode": 0,
            "terminationReason": "NAMESPACE=SIGNAL CODE=0x0b",
            "virtualMemoryAddress": 0
          }
        ],
        "timeStampBegin": "2026-07-11T12:00:00Z",
        "timeStampEnd": "2026-07-11T12:05:00Z"
      }
      """
      do {
          try mockJSON.write(to: fileURL, atomically: true, encoding: .utf8)
          debugStatusMessage = "Generated mock report on disk"
          AppLogger.log("[Debug] Persisted mock diagnostic payload to \(fileURL.lastPathComponent)")
      } catch {
          debugStatusMessage = "Failed to generate mock: \(error.localizedDescription)"
      }
  }

  private func clearSavedCrashReports() {
      guard let dir = CrashReporter.reportsDirectory else {
          debugStatusMessage = "Error accessing reports directory"
          return
      }
      let fm = FileManager.default
      do {
          let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
          for file in files {
              try fm.removeItem(at: file)
          }
          debugStatusMessage = "Cleared \(files.count) reports"
          AppLogger.log("[Debug] Cleared saved crash reports")
      } catch {
          debugStatusMessage = "Failed to clear reports: \(error.localizedDescription)"
      }
  }
  ```

- [ ] **Step 4: Run test to verify it passes**
  Verify the test target compiles and passes successfully.
  Run: `xcodebuild test -workspace GJournal.xcworkspace -scheme GJournal -destination "platform=iOS Simulator,name=iPhone 17 Pro"`

- [ ] **Step 5: Commit**
  ```bash
  git add GJournal/Views/DebugSettingsView.swift GJournalTests/DeveloperTriggersTests.swift
  git commit -m "feat: implement manual developer triggers in DebugSettingsView with tests"
  ```
