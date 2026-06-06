//
//  AuthManager.swift
//  GJournal
//
//  Local-only authentication: name identifier + app PIN + biometrics.
//

import Foundation
import Combine
import LocalAuthentication
import CryptoKit

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isSessionAuthenticated = false {
        didSet {
            UserDefaults.standard.set(isSessionAuthenticated, forKey: sessionAuthenticatedKey)
        }
    }
    @Published var currentUser: String?

    private let nameKey                = "user_name"
    private let biometricEnabledKey    = "biometric_enabled"
    private let userRegisteredKey      = "user_registered"
    private let userLoggedInKey        = "user_logged_in"
    private let sessionAuthenticatedKey = "session_authenticated"
    private let pinHashKey             = "user_pin_hash"

    private let keychainService = "com.gjournal.auth"

    init() {
        if UserDefaults.standard.bool(forKey: userRegisteredKey),
           let name = UserDefaults.standard.string(forKey: nameKey), !name.isEmpty {
            currentUser = name
            isAuthenticated = true
            isSessionAuthenticated = UserDefaults.standard.bool(forKey: sessionAuthenticatedKey)
        }
    }

    // MARK: - Registration & Login

    /// First-time setup: stores name + PIN atomically, marks session authenticated.
    func completeRegistration(name: String, pin: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidName(trimmed) else { throw AuthError.invalidName }
        guard !UserDefaults.standard.bool(forKey: userRegisteredKey) else { throw AuthError.userAlreadyExists }

        UserDefaults.standard.set(trimmed, forKey: nameKey)
        UserDefaults.standard.set(true, forKey: userRegisteredKey)
        UserDefaults.standard.set(true, forKey: userLoggedInKey)
        storeInKeychain(key: pinHashKey, value: sha256(pin))

        currentUser = trimmed
        isAuthenticated = true
        isSessionAuthenticated = true
    }

    /// Re-login after logout. Name must match stored name.
    /// Session is NOT authenticated — BiometricLockView handles that.
    func loginWithNameOnly(name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidName(trimmed) else { throw AuthError.invalidName }
        guard UserDefaults.standard.bool(forKey: userRegisteredKey) else { throw AuthError.userNotFound }

        let stored = UserDefaults.standard.string(forKey: nameKey) ?? ""
        guard trimmed == stored else { throw AuthError.unauthorized }

        currentUser = trimmed
        isAuthenticated = true
        UserDefaults.standard.set(true, forKey: userLoggedInKey)
        isSessionAuthenticated = false   // BiometricLockView will require PIN or biometric
    }

    func logout() {
        UserDefaults.standard.set(false, forKey: userLoggedInKey)
        UserDefaults.standard.set(false, forKey: sessionAuthenticatedKey)
        currentUser = nil
        isAuthenticated = false
        isSessionAuthenticated = false
    }

    func requireSessionAuthentication() {
        isSessionAuthenticated = false
    }

    func completeSessionAuthentication() {
        isSessionAuthenticated = true
    }

    func isUserRegistered() -> Bool {
        UserDefaults.standard.bool(forKey: userRegisteredKey)
    }

    func getToken() -> String? {
        UserDefaults.standard.string(forKey: nameKey)
    }

    // MARK: - PIN

    @discardableResult
    func setPIN(_ pin: String) -> Bool {
        storeInKeychain(key: pinHashKey, value: sha256(pin))
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let stored = readFromKeychain(key: pinHashKey) else { return false }
        return sha256(pin) == stored
    }

    func hasPIN() -> Bool {
        readFromKeychain(key: pinHashKey) != nil
    }

    func clearPIN() {
        deleteFromKeychain(key: pinHashKey)
    }

    // MARK: - Biometric

    var isBiometricEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: biometricEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: biometricEnabledKey) }
    }

    func canUseBiometric() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticateWithBiometric() async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Use PIN"
        return try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock GJournal"
        )
    }

    // MARK: - Private Helpers

    private func isValidName(_ name: String) -> Bool {
        name.count >= 2
    }

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - Keychain

    @discardableResult
    private func storeInKeychain(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    keychainService,
            kSecAttrAccount as String:    key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:      data,
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
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case invalidName
    case unauthorized
    case userNotFound
    case userAlreadyExists
    case keychainError

    var errorDescription: String? {
        switch self {
        case .invalidName:       return "Please enter a valid name (at least 2 characters)"
        case .unauthorized:      return "Name does not match the account on this device"
        case .userNotFound:      return "No account found on this device"
        case .userAlreadyExists: return "An account already exists on this device"
        case .keychainError:     return "Security error — please try again"
        }
    }
}
