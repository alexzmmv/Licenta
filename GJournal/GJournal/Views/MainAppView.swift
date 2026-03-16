//
//  MainAppView.swift
//  GJournal
//
//  Main authenticated app view
//

import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        ContentView(repository: LocalJournalRepository())
    }
}
