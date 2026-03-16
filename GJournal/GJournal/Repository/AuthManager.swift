//
//  AuthManager.swift
//  GJournal
//
//  Authentication and session management (Local-only)
//

import Foundation
import Combine
import LocalAuthentication
import CryptoKit

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isSessionAuthenticated = false {
        didSet {
            // Save session state to local storage
            UserDefaults.standard.set(isSessionAuthenticated, forKey: sessionAuthenticatedKey)
        }
    }
    @Published var currentUser: String?
    
    private let emailKey = "user_email"
    private let passwordHashKey = "user_password_hash"
    private let saltKey = "password_salt"
    private let biometricEnabledKey = "biometric_enabled"
    private let userRegisteredKey = "user_registered"
    private let userLoggedInKey = "user_logged_in"
    private let sessionAuthenticatedKey = "session_authenticated"
    
    private let keychainService = "com.gjournal.auth"
    
    init() {
        // Check if user is already registered and logged in
        if UserDefaults.standard.bool(forKey: userRegisteredKey) {
            let isLoggedIn = UserDefaults.standard.bool(forKey: userLoggedInKey)
            if isLoggedIn, let email = UserDefaults.standard.string(forKey: emailKey), !email.isEmpty {
                currentUser = email
                isAuthenticated = true // User is logged in persistently
                // Restore session state from storage
                isSessionAuthenticated = UserDefaults.standard.bool(forKey: sessionAuthenticatedKey)
            }
        }
    }
    
    // MARK: - Local Authentication
    
    func registerLocal(email: String, password: String) throws {
        // Validate email format
        guard isValidEmail(email.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AuthError.invalidEmail
        }
        
        // Validate password requirements
        guard !email.isEmpty else {
            throw AuthError.emptyEmail
        }
        guard password.count >= 6 else {
            throw AuthError.passwordTooShort
        }
        
        // Check if user already exists
        if UserDefaults.standard.bool(forKey: userRegisteredKey) {
            throw AuthError.userAlreadyExists
        }
        
        // Generate salt and hash password
        let salt = generateSalt()
        let hashedPassword = hashPassword(password, with: salt)
        
        // Store credentials securely
        UserDefaults.standard.set(email.trimmingCharacters(in: .whitespacesAndNewlines), forKey: emailKey)
        UserDefaults.standard.set(hashedPassword, forKey: passwordHashKey)
        UserDefaults.standard.set(salt.base64EncodedString(), forKey: saltKey)
        UserDefaults.standard.set(true, forKey: userRegisteredKey)
        UserDefaults.standard.set(true, forKey: userLoggedInKey)
        
        // Store password in Keychain for reference
        _ = try? storePasswordInKeychain(email: email, password: password)
        
        currentUser = email.trimmingCharacters(in: .whitespacesAndNewlines)
        isAuthenticated = true
        isSessionAuthenticated = true  // Mark as authenticated in this session
    }
    
    func loginLocal(email: String, password: String) throws {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthError.emptyEmail
        }
        guard !password.isEmpty else {
            throw AuthError.emptyPassword
        }
        
        // Check if user is registered
        guard UserDefaults.standard.bool(forKey: userRegisteredKey) else {
            throw AuthError.userNotFound
        }
        
        // Verify email matches
        let storedEmail = UserDefaults.standard.string(forKey: emailKey) ?? ""
        guard email.trimmingCharacters(in: .whitespacesAndNewlines) == storedEmail else {
            throw AuthError.unauthorized
        }
        
        // Verify password
        guard let storedHash = UserDefaults.standard.string(forKey: passwordHashKey),
              let saltString = UserDefaults.standard.string(forKey: saltKey),
              let salt = Data(base64Encoded: saltString) else {
            throw AuthError.unauthorized
        }
        
        let inputHash = hashPassword(password, with: salt)
        guard inputHash == storedHash else {
            throw AuthError.unauthorized
        }
        
        currentUser = email.trimmingCharacters(in: .whitespacesAndNewlines)
        isAuthenticated = true
        UserDefaults.standard.set(true, forKey: userLoggedInKey)
        isSessionAuthenticated = true  // Mark as authenticated in this session
    }
    
    func getToken() -> String? {
        // Local mode doesn't use tokens, but return email as identifier
        return UserDefaults.standard.string(forKey: emailKey)
    }
    
    func logout() {
        let email = UserDefaults.standard.string(forKey: emailKey) ?? ""
        if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deletePasswordFromKeychain(email: email)
        }
        UserDefaults.standard.set(false, forKey: userLoggedInKey)
        UserDefaults.standard.set(false, forKey: sessionAuthenticatedKey)
        currentUser = nil
        isAuthenticated = false
        isSessionAuthenticated = false
    }
    
    /// Mark the session as requiring re-authentication (e.g., app enters background)
    func requireSessionAuthentication() {
        isSessionAuthenticated = false
    }
    
    /// Mark that the session is now authenticated (e.g., after Face ID success)
    func completeSessionAuthentication() {
        isSessionAuthenticated = true
    }
    
    func isUserRegistered() -> Bool {
        return UserDefaults.standard.bool(forKey: userRegisteredKey)
    }
    
    // MARK: - Biometric Authentication
    
    var isBiometricEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: biometricEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: biometricEnabledKey)
        }
    }
    
    func canUseBiometric() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    func authenticateWithBiometric() async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Use Passcode"
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock GJournal"
            )
            return success
        } catch let error as LAError {
            switch error.code {
            case .userFallback:
                // User chose to use passcode
                return try await authenticateWithPasscode()
            default:
                throw error
            }
        }
    }
    
    func authenticateWithPasscode() async throws -> Bool {
        let context = LAContext()
        
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock GJournal"
        )
        return success
    }
    
    // MARK: - Private Helper Methods
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailPattern = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailPattern)
        return predicate.evaluate(with: email)
    }
    
    private func generateSalt() -> Data {
        var salt = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        return Data(salt)
    }
    
    private func hashPassword(_ password: String, with salt: Data) -> String {
        guard let passwordData = password.data(using: .utf8) else { return "" }
        let combined = passwordData + salt
        let digest = SHA256.hash(data: combined)
        return digest.withUnsafeBytes {
            Data(Array($0)).base64EncodedString()
        }
    }
    
    // MARK: - Keychain Methods
    
    private func storePasswordInKeychain(email: String, password: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw AuthError.keychainError
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: email.trimmingCharacters(in: .whitespacesAndNewlines),
            kSecValueData as String: passwordData
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw AuthError.keychainError
        }
    }
    
    private func deletePasswordFromKeychain(email: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: email.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Authentication Errors

enum AuthError: LocalizedError {
    case emptyEmail
    case emptyPassword
    case passwordTooShort
    case invalidEmail
    case unauthorized
    case userNotFound
    case userAlreadyExists
    case keychainError
    
    var errorDescription: String? {
        switch self {
        case .emptyEmail:
            return "Email cannot be empty"
        case .emptyPassword:
            return "Password cannot be empty"
        case .passwordTooShort:
            return "Password must be at least 6 characters"
        case .invalidEmail:
            return "Please enter a valid email address"
        case .unauthorized:
            return "Invalid email or password"
        case .userNotFound:
            return "User not found"
        case .userAlreadyExists:
            return "An account already exists"
        case .keychainError:
            return "Security error. Please try again"
        }
    }
}
