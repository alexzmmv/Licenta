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
    
    private let nameKey = "user_name"
    private let passwordHashKey = "user_password_hash"
    private let saltKey = "password_salt"
    private let biometricEnabledKey = "biometric_enabled"
    private let userRegisteredKey = "user_registered"
    private let userLoggedInKey = "user_logged_in"
    private let sessionAuthenticatedKey = "session_authenticated"
    
    private let keychainService = "com.gjournal.auth"
    
    init() {
        migrateCredentialsToKeychainIfNeeded()
        if UserDefaults.standard.bool(forKey: userRegisteredKey) {
            let isLoggedIn = UserDefaults.standard.bool(forKey: userLoggedInKey)
            if isLoggedIn, let name = UserDefaults.standard.string(forKey: nameKey), !name.isEmpty {
                currentUser = name
                isAuthenticated = true
                isSessionAuthenticated = UserDefaults.standard.bool(forKey: sessionAuthenticatedKey)
            }
        }
    }

    // One-time migration: move password_hash + password_salt from UserDefaults to Keychain
    private func migrateCredentialsToKeychainIfNeeded() {
        guard readFromKeychain(key: passwordHashKey) == nil else { return }  // already migrated
        if let hash = UserDefaults.standard.string(forKey: passwordHashKey) {
            storeInKeychain(key: passwordHashKey, value: hash)
            UserDefaults.standard.removeObject(forKey: passwordHashKey)
        }
        if let salt = UserDefaults.standard.string(forKey: saltKey) {
            storeInKeychain(key: saltKey, value: salt)
            UserDefaults.standard.removeObject(forKey: saltKey)
        }
    }
    
    // MARK: - Local Authentication
    
    func registerLocal(email: String, password: String) throws {
        // Validate name format
        guard isValidName(email.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AuthError.invalidName
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
        
        // Store non-sensitive fields in UserDefaults; secrets in Keychain
        UserDefaults.standard.set(email.trimmingCharacters(in: .whitespacesAndNewlines), forKey: nameKey)
        UserDefaults.standard.set(true, forKey: userRegisteredKey)
        UserDefaults.standard.set(true, forKey: userLoggedInKey)
        storeInKeychain(key: passwordHashKey, value: hashedPassword)
        storeInKeychain(key: saltKey, value: salt.base64EncodedString())
        
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
        let storedEmail = UserDefaults.standard.string(forKey: nameKey) ?? ""
        guard email.trimmingCharacters(in: .whitespacesAndNewlines) == storedEmail else {
            throw AuthError.unauthorized
        }
        
        // Verify password — read hash+salt from Keychain
        guard let storedHash = readFromKeychain(key: passwordHashKey),
              let saltString = readFromKeychain(key: saltKey),
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
        // Local mode doesn't use tokens, but return name as identifier
        return UserDefaults.standard.string(forKey: nameKey)
    }

    // MARK: - Email-Only Auth (no password, device-secured)

    /// Register a new user using name as identifier only.
    /// Security is handled entirely by device biometrics/passcode.
    func registerWithNameOnly(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidName(trimmed) else { throw AuthError.invalidName }

        if UserDefaults.standard.bool(forKey: userRegisteredKey) {
            throw AuthError.userAlreadyExists
        }

        UserDefaults.standard.set(trimmed, forKey: nameKey)
        UserDefaults.standard.set(true, forKey: userRegisteredKey)
        UserDefaults.standard.set(true, forKey: userLoggedInKey)

        currentUser = trimmed
        isAuthenticated = true
        isSessionAuthenticated = true
    }

    /// Login an existing user by name identifier only.
    func loginWithNameOnly(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidName(trimmed) else { throw AuthError.invalidName }

        guard UserDefaults.standard.bool(forKey: userRegisteredKey) else {
            throw AuthError.userNotFound
        }

        let storedName = UserDefaults.standard.string(forKey: nameKey) ?? ""
        guard trimmed == storedName else { throw AuthError.unauthorized }

        currentUser = trimmed
        isAuthenticated = true
        UserDefaults.standard.set(true, forKey: userLoggedInKey)
        isSessionAuthenticated = true
    }
    
    func logout() {
        let name = UserDefaults.standard.string(forKey: nameKey) ?? ""
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deletePasswordFromKeychain(email: name) // Method parameter kept for internal consistency if needed
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
    
    private func isValidName(_ name: String) -> Bool {
        return name.count >= 2
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
    
    // MARK: - Keychain Helpers

    @discardableResult
    private func storeInKeychain(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String:                kSecClassGenericPassword,
            kSecAttrService as String:          keychainService,
            kSecAttrAccount as String:          key,
            kSecAttrAccessible as String:       kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:            data,
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func readFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func deletePasswordFromKeychain(email: String) {
        deleteFromKeychain(key: passwordHashKey)
        deleteFromKeychain(key: saltKey)
    }
}

// MARK: - Authentication Errors

enum AuthError: LocalizedError {
    case emptyEmail
    case emptyPassword
    case passwordTooShort
    case invalidName
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
        case .invalidName:
            return "Please enter a valid name (at least 2 characters)"
        case .unauthorized:
            return "Invalid name or password"
        case .userNotFound:
            return "User not found"
        case .userAlreadyExists:
            return "An account already exists"
        case .keychainError:
            return "Security error. Please try again"
        }
    }
}
