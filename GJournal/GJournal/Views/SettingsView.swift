//
//  SettingsView.swift
//  GJournal
//
//  Settings and account management
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) var dismiss
    @State private var showingLogoutAlert = false
    @State private var showingDeleteAllAlert = false
    
    var body: some View {
        NavigationView {
            List {
                // Account Section
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundColor(.pink)
                        
                        VStack(alignment: .leading) {
                            Text("Account")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(authManager.currentUser ?? "Unknown")
                                .font(.body)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Account")
                }
                
                // Security Section
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
                    } else {
                        Toggle(isOn: Binding(
                            get: { authManager.isBiometricEnabled },
                            set: { authManager.isBiometricEnabled = $0 }
                        )) {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.pink)
                                Text("Require Passcode")
                            }
                        }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text(authManager.canUseBiometric() 
                         ? "Use Face ID or Touch ID to unlock the app" 
                         : "Require device passcode to unlock the app")
                }
                
                // Actions Section
                Section {
                    Button {
                        SeedDataManager.generateSeedData(context: modelContext)
                    } label: {
                        HStack {
                            Image(systemName: "leaf.fill")
                                .foregroundColor(.green)
                            Text("Generate Seed Data")
                        }
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
                }
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
                        try modelContext.save()
                        print("[Settings] Successfully deleted all data.")
                    } catch {
                        print("[Settings] Failed to delete all data: \(error)")
                    }
                }
            } message: {
                Text("This will permanently delete all your journal entries. This action cannot be undone.")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AuthManager())
}
