import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(EntitlementManager.self) private var entitlementManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @ObservedObject var repository: BaseJournalRepository
    @State private var showingDeleteAllAlert = false
    @State private var showingDeleteAccountAlert = false
    @State private var exportFileURL: URL?
    @State private var showingExportSheet = false
    @State private var isExporting = false
    @State private var exportErrorMessage: String?
    @State private var showingChangePIN = false
    @State private var reminderEnabled = ReminderScheduler.shared.isEnabled
    @State private var diagnosticFileURLs: [URL] = []
    @State private var showingDiagnosticsSheet = false
    @State private var diagnosticsStatusMessage: String?
    @State private var deleteErrorMessage: String?
    @State private var notificationsDenied = false
    @State private var reminderTime: Date = ReminderScheduler.shared.scheduledTime
    @State private var isRestoring = false
    @State private var restoreStatusMessage: String?

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        EditNameView()
                            .environmentObject(authManager)
                    } label: {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundColor(.pink)
                            VStack(alignment: .leading) {
                                Text("Name")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(authManager.currentUser ?? "Not set")
                                    .font(.body)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Profile")
                }

                Section {
                    if authManager.canUseBiometric() {
                        Toggle(isOn: Binding(
                            get: { authManager.isBiometricEnabled },
                            set: { authManager.isBiometricEnabled = $0 }
                        )) {
                            HStack {
                                Image(systemName: "faceid")
                                    .foregroundColor(.pink)
                                Text("Face ID / Touch ID")
                            }
                        }
                    }

                    Button {
                        showingChangePIN = true
                    } label: {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.pink)
                            Text("Change PIN")
                                .foregroundColor(.primary)
                        }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text(authManager.canUseBiometric()
                         ? "Face ID / Touch ID unlocks the app; PIN is the fallback."
                         : "PIN is required to unlock the app.")
                }
                .sheet(isPresented: $showingChangePIN) {
                    ChangePINView()
                        .environmentObject(authManager)
                }

                Section {
                    Toggle(isOn: $reminderEnabled) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                            Text("Daily Reminder")
                        }
                    }
                    .onChange(of: reminderEnabled) { _, enabled in
                        Task {
                            if enabled {
                                let granted = await ReminderScheduler.shared.requestPermissionAndEnable()
                                if !granted {
                                    reminderEnabled = false
                                    notificationsDenied = true
                                }
                            } else {
                                ReminderScheduler.shared.isEnabled = false
                            }
                        }
                    }

                    if reminderEnabled {
                        DatePicker(
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        ) {
                            HStack {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(Color(red: 0.55, green: 0.4, blue: 0.95))
                                Text("Reminder Time")
                            }
                        }
                        .onChange(of: reminderTime) { _, newTime in
                            ReminderScheduler.shared.scheduledTime = newTime
                        }
                    }

                    NavigationLink(destination: CrisisResourcesView()) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.55))
                            Text("Support Resources")
                                .foregroundColor(.primary)
                        }
                    }
                } header: {
                    Text("Wellbeing")
                } footer: {
                    Text("A gentle daily nudge to check in with yourself. Support resources offer free, confidential crisis help 24/7.")
                }

                Section {
                    NavigationLink(destination: RecentlyDeletedView(repository: repository)) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.pink)
                            Text("Recently Deleted")
                            Spacer()
                            if !repository.deletedBits.isEmpty {
                                Text("\(repository.deletedBits.count)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.pink.opacity(0.85))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    NavigationLink(destination: TagManagementView(repository: repository)) {
                        HStack {
                            Image(systemName: "tag")
                                .foregroundColor(.purple)
                            Text("Behavioral Tags")
                        }
                    }
                } header: {
                    Text("Data Management")
                }

                Section {
                    Button {
                        Task { await generateExportFile() }
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text(isExporting ? "Preparing export…" : "Export All Data")
                        }
                    }
                    .disabled(isExporting)

                    if let exportErrorMessage {
                        Text(exportErrorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button {
                        exportDiagnostics()
                    } label: {
                        HStack {
                            Image(systemName: "stethoscope")
                            Text("Export Crash Diagnostics")
                        }
                    }

                    if let diagnosticsStatusMessage {
                        Text(diagnosticsStatusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        authManager.requireSessionAuthentication()
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("Lock Now")
                        }
                    }
                } footer: {
                    Text("Exports include your entries and AI analysis as JSON. Everything stays on your device unless you choose to share it.")
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Delete All Entries")
                        }
                    }

                    Button(role: .destructive) {
                        showingDeleteAccountAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.xmark")
                            Text("Delete Account & All Data")
                        }
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Deleting your account removes your entries, your PIN, and your name from this device, and returns GJournal to a fresh install. Neither action can be undone.")
                }

                Section {
                    Button {
                        Task {
                            isRestoring = true
                            await entitlementManager.restore()
                            isRestoring = false
                            restoreStatusMessage = entitlementManager.hasInsights
                                ? "Insights restored."
                                : (entitlementManager.purchaseError ?? "No previous purchase found.")
                        }
                    } label: {
                        HStack {
                            if isRestoring {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Restore Purchases")
                        }
                    }
                    .disabled(isRestoring)

                    if let restoreStatusMessage {
                        Text(restoreStatusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Purchases")
                } footer: {
                    Text("Already bought GJournal Insights on another device? Restore it here.")
                }

                Section {
                    Link(destination: AppLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                    }
                    Link(destination: AppLinks.termsOfUse) {
                        Label("Terms of Use", systemImage: "doc.text.fill")
                    }
                    Link(destination: AppLinks.supportEmail) {
                        Label("Contact Support", systemImage: "envelope.fill")
                    }
                    HStack {
                        Label("Version", systemImage: "info.circle.fill")
                        Spacer()
                        Text(appVersionString)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }

                #if DEBUG
                Section {
                    NavigationLink(destination: DebugSettingsView(repository: repository)) {
                        HStack {
                            Image(systemName: "hammer.fill")
                                .foregroundColor(.orange)
                            Text("Developer")
                        }
                    }
                } header: {
                    Text("Development")
                } footer: {
                    Text("Debug builds only — not included in App Store releases.")
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete All Entries", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Everything", role: .destructive) {
                    if AccountEraser.eraseData(modelContext: modelContext) {
                        (repository as? LocalJournalRepository)?.aiProcessingManager?.resetState()
                        (repository as? LocalJournalRepository)?.loadBitsFromContext()
                    } else {
                        deleteErrorMessage = "Couldn't delete your entries. Please try again."
                    }
                }
            } message: {
                Text("This permanently deletes all your journal entries and AI analysis. Your account and PIN stay. This cannot be undone.")
            }
            .alert("Delete Account & All Data", isPresented: $showingDeleteAccountAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Everything", role: .destructive) {
                    AccountEraser.eraseAll(modelContext: modelContext, authManager: authManager)
                    (repository as? LocalJournalRepository)?.aiProcessingManager?.resetState()
                    (repository as? LocalJournalRepository)?.loadBitsFromContext()
                    dismiss()
                }
            } message: {
                Text("This permanently deletes your entries, your PIN, and your name, and returns GJournal to a fresh install. This cannot be undone.")
            }
            .alert("Couldn't Delete", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { deleteErrorMessage = nil }
            } message: {
                Text(deleteErrorMessage ?? "")
            }
            .alert("Notifications Are Off", isPresented: $notificationsDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not Now", role: .cancel) { }
            } message: {
                Text("GJournal can't send reminders because notifications are turned off for this app. You can enable them in iOS Settings.")
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportFileURL {
                    ActivityView(items: [url])
                }
            }
            .sheet(isPresented: $showingDiagnosticsSheet) {
                ActivityView(items: diagnosticFileURLs)
            }
        }
    }

    // MARK: - Diagnostics export

    /// Share the MetricKit diagnostic payloads persisted by `CrashReporter`.
    /// These contain call stacks and system metadata only — never journal content.
    private func exportDiagnostics() {
        guard let dir = CrashReporter.reportsDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
              !files.isEmpty else {
            diagnosticsStatusMessage = "No crash diagnostics recorded — nothing to export."
            return
        }
        diagnosticsStatusMessage = nil
        diagnosticFileURLs = files
        showingDiagnosticsSheet = true
    }

    // MARK: - Export

    @MainActor
    private func generateExportFile() async {
        isExporting = true
        exportErrorMessage = nil
        defer { isExporting = false }

        guard let localRepository = repository as? LocalJournalRepository else {
            exportErrorMessage = "Export isn't available right now."
            return
        }

        do {
            exportFileURL = try localRepository.generateExportFile()
            showingExportSheet = true
        } catch {
            exportErrorMessage = "Export failed. Please try again."
            AppLogger.error("[Settings] Export failed: \(error)")
        }
    }
}

// MARK: - Share Sheet wrapper

import UIKit

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView(repository: BaseJournalRepository())
        .environmentObject(AuthManager())
}
