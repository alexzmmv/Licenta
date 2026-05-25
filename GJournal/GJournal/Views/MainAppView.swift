//
//  MainAppView.swift
//  GJournal
//
//  Main authenticated app view with service container injection
//

import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var authManager: AuthManager

    /// Repository with AI processing manager — single production ServiceContainer instance
    @StateObject private var repository: LocalJournalRepository = {
        let repo = LocalJournalRepository()
        let services = ServiceContainer.makeProduction()
        repo.aiProcessingManager = AIProcessingManager(services: services)
        return repo
    }()

    var body: some View {
        ContentView(repository: repository)
            .environmentObject(authManager)
    }
}
