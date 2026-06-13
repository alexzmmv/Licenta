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

    private static func makeModelContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: false)

        func tryCreate() throws -> ModelContainer {
            let container = try ModelContainer(
                for: Bit.self, Cluster.self,
                configurations: config
            )
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
                    BiometricLockView()
                        .environmentObject(authManager)
                } else {
                    LoginView()
                        .environmentObject(authManager)
                }
            }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                authManager.requireSessionAuthentication()
            }
        }
    }
}

// Note: ContentView preview removed as it requires authentication context

