import SwiftUI
import SwiftData

@main
struct GJournalApp: App {
    @StateObject private var authManager = AuthManager()
    @State private var entitlementManager = EntitlementManager()
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var isObscured = false

    /// Holds either a successfully created ModelContainer or the error that
    /// prevented creation. The wipe-and-retry fallback has been intentionally
    /// removed — on failure we show a recovery UI instead of silently
    /// destroying the user's journal data.
    private let containerResult: Result<ModelContainer, Error>

    init() {
        #if DEBUG
        UITestSupport.configureLaunchState()   // no-op without the UI_TESTING launch argument
        #endif
        containerResult = Result { try Self.makeModelContainer() }
        CrashReporter.shared.start()
        #if DEBUG
        if case .success(let container) = containerResult {
            UITestSupport.seedIfRequested(container: container)
        }
        #endif
    }

    private static func makeModelContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: false)

        // Use the versioned schema + migration plan so that schema changes are
        // handled via lightweight/custom migration stages instead of crashing or
        // wiping. Current head is SchemaV2 (adds BehavioralTag + Bit.tagLemmas).
        let schema = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: GJournalMigrationPlan.self,
            configurations: config
        )

        // File-level encryption: data is accessible while the device is
        // unlocked or while our process holds a file handle. A failure here
        // leaves the journal unprotected at rest, so it must not be swallowed.
        let storeURL = config.url
        do {
            try (storeURL as NSURL).setResourceValue(
                URLFileProtection.completeUnlessOpen,
                forKey: .fileProtectionKey
            )
        } catch {
            AppLogger.error("[App] Failed to apply file protection to the store: \(error)")
        }

        return container
    }

    var body: some Scene {
        WindowGroup {
            switch containerResult {
            case .success(let container):
                Group {
                    if !hasCompletedOnboarding {
                        OnboardingView { hasCompletedOnboarding = true }
                            .environmentObject(authManager)
                            .environment(entitlementManager)
                    } else if authManager.isAuthenticated {
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
                // Journal content must not appear in the iOS app-switcher
                // snapshot, which is taken while the scene is inactive.
                .overlay {
                    if isObscured {
                        PrivacyShieldView()
                    }
                }
                .task {
                    await entitlementManager.refreshEntitlements()
                    ReminderScheduler.shared.refreshOnLaunch()
                }

            case .failure(let error):
                StoreRecoveryView(error: error)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                isObscured = true
                authManager.requireSessionAuthentication()
            case .inactive:
                isObscured = true
            case .active:
                isObscured = false
            @unknown default:
                isObscured = false
            }
        }
    }
}

/// Opaque cover shown while the app is inactive or backgrounded.
private struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundColor(.pink)
        }
        .transition(.opacity)
    }
}

// Note: ContentView preview removed as it requires authentication context
