//
//  APIClient.swift
//  GJournal
//
//  Created for API communication
//

import Foundation

class APIClient {
    static let shared = APIClient()
    
    var baseURL: String {
        return UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://localhost:8000"
    }
    
    private init() {}
    
    // MARK: - Health Check
    
    func healthCheck() async throws -> Bool {
        let url = URL(string: "\(baseURL)/health")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return false
        }
        
        // Try to decode the health response
        if let json = try? JSONDecoder().decode([String: String].self, from: data),
           json["status"] == "ok" {
            return true
        }
        
        return false
    }
    
    // MARK: - Authentication
    
    func register(email: String, password: String) async throws -> AuthResponse {
        let url = URL(string: "\(baseURL)/auth/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    func login(email: String, password: String) async throws -> TokenResponse {
        let url = URL(string: "\(baseURL)/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.invalidResponse
        }
        
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
    
    // MARK: - Bits
    
    func getBits(token: String) async throws -> [BitResponse] {
        let url = URL(string: "\(baseURL)/bits/")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([BitResponse].self, from: data)
    }
    
    func createBit(token: String, bit: BitCreate) async throws -> BitResponse {
        let url = URL(string: "\(baseURL)/bits/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONEncoder().encode(bit)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(BitResponse.self, from: data)
    }
    
    func updateBit(token: String, bitId: Int, bit: BitUpdate) async throws -> BitResponse {
        let url = URL(string: "\(baseURL)/bits/\(bitId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONEncoder().encode(bit)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(BitResponse.self, from: data)
    }
    
    func deleteBit(token: String, bitId: Int) async throws {
        let url = URL(string: "\(baseURL)/bits/\(bitId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }
    
    func toggleHideBit(token: String, bitId: Int) async throws -> BitResponse {
        let url = URL(string: "\(baseURL)/bits/\(bitId)/toggle-hide")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(BitResponse.self, from: data)
    }
}

// MARK: - API Models

struct AuthResponse: Codable {
    let id: Int
    let email: String
    let created_at: String
}

struct TokenResponse: Codable {
    let access_token: String
    let token_type: String
}

struct BitCreate: Codable {
    let title: String?
    let text: String
    let emotion: String
    let intensity: Int
}

struct BitUpdate: Codable {
    let title: String?
    let text: String
    let emotion: String
    let intensity: Int
}

struct BitResponse: Codable {
    let id: Int
    let title: String?
    let text: String
    let emotion: String
    let intensity: Int
    let is_hidden: Bool
    let created_at: String
    let last_modified: String
    let user_id: Int
}

enum APIError: Error {
    case invalidResponse
    case unauthorized
    case serverError(String)
}
