//
//  APISettings.swift
//  GJournal
//
//  API configuration management
//

import Foundation
import Combine

final class APISettings: ObservableObject {
    private static let storageKey = "apiBaseURL"
    static let defaultURL = "http://localhost:8000"

    static let shared = APISettings()

    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: APISettings.storageKey)
        }
    }
    
    private init() {
        self.baseURL = UserDefaults.standard.string(forKey: APISettings.storageKey) ?? APISettings.defaultURL
        // Ensure downstream consumers always have a value set in UserDefaults
        UserDefaults.standard.register(defaults: [APISettings.storageKey: self.baseURL])
    }
    
    func resetToDefault() {
        baseURL = APISettings.defaultURL
    }
}
