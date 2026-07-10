import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @ObservedObject var repository: BaseJournalRepository
    @State private var showingLogoutAlert = false
    @State private var showingDeleteAllAlert = false
    @State private var exportFileURL: URL?
    @State private var showingExportSheet = false
    @State private var isExporting = false
    @State private var exportErrorMessage: String?
    @State private var showingChangePIN = false
    @State private var reminderEnabled = ReminderScheduler.shared.isEnabled

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundColor(.pink)
                        VStack(alignment: .leading) {
                            Text("Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(authManager.currentUser ?? "Unknown")
                                .font(.body)
                        }
                    }
                    .padding(.vertical, 4)
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
                                if !granted { reminderEnabled = false }
                            } else {
                                ReminderScheduler.shared.isEnabled = false
                            }
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

                    Button(role: .destructive) {
                        showingDeleteAllAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Delete All Data")
                        }
                    }

                    Button(role: .destructive) {
                        showingLogoutAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.square")
                            Text("Log Out")
                        }
                    }
                } footer: {
                    Text("Exports include your entries and AI analysis as JSON. Everything stays on your device unless you choose to share it.")
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
            .alert("Log Out", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    authManager.logout()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to log out?")
            }
            .alert("Delete All Data", isPresented: $showingDeleteAllAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Everything", role: .destructive) {
                    do {
                        try modelContext.delete(model: Bit.self)
                        try modelContext.delete(model: Cluster.self)
                        try modelContext.save()
                        (repository as? LocalJournalRepository)?.aiProcessingManager?.resetState()
                        (repository as? LocalJournalRepository)?.loadBitsFromContext()
                        AppLogger.log("[Settings] Deleted all data.")
                    } catch {
                        AppLogger.error("[Settings] Failed to delete all data: \(error)")
                    }
                }
            } message: {
                Text("This will permanently delete all your journal entries. This action cannot be undone.")
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportFileURL {
                    ActivityView(items: [url])
                }
            }
        }
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
