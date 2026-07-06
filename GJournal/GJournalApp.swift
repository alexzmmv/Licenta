import SwiftUI
import SwiftData

@main
struct GJournalApp: App {
    @StateObject private var authManager = AuthManager()
    @State private var entitlementManager = EntitlementManager()
    @Environment(\.scenePhase) var scenePhase

    /// Holds either a successfully created ModelContainer or the error that
    /// prevented creation. The wipe-and-retry fallback has been intentionally
    /// removed — on failure we show a recovery UI instead of silently
    /// destroying the user's journal data.
    private let containerResult: Result<ModelContainer, Error>

    init() {
        containerResult = Result { try Self.makeModelContainer() }
    }

    private static func makeModelContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: false)

        // Use the versioned schema + migration plan so that future schema
        // changes (SchemaV2+) are handled via lightweight/custom migration
        // stages instead of crashing or wiping.
        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: GJournalMigrationPlan.self,
            configurations: config
        )

        // File-level encryption: data is accessible while the device is
        // unlocked or while our process holds a file handle.
        let storeURL = config.url
        try? (storeURL as NSURL).setResourceValue(
            URLFileProtection.completeUnlessOpen,
            forKey: .fileProtectionKey
        )

        return container
    }

    var body: some Scene {
        WindowGroup {
            switch containerResult {
            case .success(let container):
                Group {
                    if authManager.isAuthenticated {
                        BiometricLockView()
                            .environmentObject(authManager)
                            .environment(entitlementManager)
                    } else {
                        LoginView()
                            .environmentObject(authManager)
                            .environment(entitlementManager)
                    }
                }
                .modelContainer(container)
                .task { await entitlementManager.refreshEntitlements() }

            case .failure(let error):
                StoreRecoveryView(error: error)
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                authManager.requireSessionAuthentication()
            }
        }
    }
}

// Note: ContentView preview removed as it requires authentication context
