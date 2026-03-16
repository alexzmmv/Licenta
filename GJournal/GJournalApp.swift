//
//  GJournalApp.swift
//  GJournal
//
//  Created by Constantin-Alexandru Dumitrascu on 21.10.2025.
//

import SwiftUI
import SwiftData

@main
struct GJournalApp: App {
    @StateObject private var authManager = AuthManager()
    @Environment(\.scenePhase) var scenePhase
    
    let modelContainer: ModelContainer
    
    init() {
        do {
            modelContainer = try ModelContainer(
                for: Bit.self, SyncOperationModel.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false)
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    // User is logged in - show biometric lock screen or main app
                    BiometricLockView()
                        .environmentObject(authManager)
                        .onAppear {
                            // Configure SyncQueue with ModelContext
                            let context = modelContainer.mainContext
                            SyncQueue.shared.configure(with: context)
                        }
                } else {
                    // User not logged in - show login screen
                    LoginView()
                        .environmentObject(authManager)
                }
            }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                // Mark session as requiring re-authentication when app enters background
                authManager.requireSessionAuthentication()
            }
        }
    }
}

// Note: ContentView preview removed as it requires authentication context
