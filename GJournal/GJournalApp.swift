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
        modelContainer = Self.makeModelContainer()
    }

    /// Creates the SwiftData ModelContainer, wiping the store on schema-migration failure.
    /// Safe for development — no production data exists yet.
    private static func makeModelContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: false)

        func tryCreate() throws -> ModelContainer {
            let container = try ModelContainer(
                for: Bit.self, Cluster.self, EmotionConfiguration.self,
                configurations: config
            )
            // Encrypt the store file at rest
            let storeURL = config.url
            try? (storeURL as NSURL).setResourceValue(
                URLFileProtection.completeUnlessOpen,
                forKey: .fileProtectionKey
            )
            return container
        }

        do {
            return try tryCreate()
        } catch {
            // Schema changed (e.g. new fields added) — destroy the store and rebuild
            let storeURL = config.url
            let dir = storeURL.deletingLastPathComponent()
            let name = storeURL.lastPathComponent
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: dir.appendingPathComponent(name + suffix)
                )
            }
            do {
                return try tryCreate()
            } catch {
                fatalError("Cannot create ModelContainer after store reset: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    // User is logged in - show biometric lock screen or main app
                    BiometricLockView()
                        .environmentObject(authManager)
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

