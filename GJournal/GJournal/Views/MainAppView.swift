//
//  MainAppView.swift
//  GJournal
//
//  Main authenticated app view with service container injection
//

import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var authManager: AuthManager

    /// Shared service container with AI services
    @StateObject private var serviceContainer = ServiceContainer.makeMock()

    /// Repository with AI processing manager attached
    @StateObject private var repository: LocalJournalRepository = {
        let repo = LocalJournalRepository()
        let services = ServiceContainer.makeMock()
        repo.aiProcessingManager = AIProcessingManager(services: services)
        return repo
    }()

    var body: some View {
        ContentView(repository: repository)
            .environmentObject(authManager)
            .environmentObject(serviceContainer)
    }
}
