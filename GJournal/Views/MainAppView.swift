import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var repository: LocalJournalRepository = {
        let repo = LocalJournalRepository()
        let services = ServiceContainer.makeProduction()
        repo.aiProcessingManager = AIProcessingManager(services: services)
        return repo
    }()

    var body: some View {
        ContentView(repository: repository)
            .environmentObject(authManager)
            .onReceive(NotificationCenter.default.publisher(for: .embeddingModelDidChange)) { _ in
                rebuildServices()
            }
            .onReceive(NotificationCenter.default.publisher(for: .clusteringStrategyDidChange)) { _ in
                rebuildServices()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Entries whose retention elapsed while the app was backgrounded
                // must disappear on return, not linger until the next cold start.
                if newPhase == .active { repository.purgeExpiredBits() }
            }
    }

    private func rebuildServices() {
        repository.aiProcessingManager?.resetState()  // cancel any pending background tasks before swap
        let services = ServiceContainer.makeProduction()
        let manager = AIProcessingManager(services: services)
        if let ctx = repository.modelContext {
            manager.configure(with: ctx)
        }
        manager.onClusteringComplete = { [weak repository] in
            DispatchQueue.main.async { repository?.loadBitsFromContext() }
        }
        repository.aiProcessingManager = manager
        AppLogger.log("[MainAppView] Services rebuilt — \(EmbeddingModelChoice.current.displayName) + \(ClusteringStrategyChoice.current.displayName)")
    }
}
