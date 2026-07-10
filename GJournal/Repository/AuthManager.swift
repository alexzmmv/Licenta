import Foundation
import Combine
import LocalAuthentication
import CryptoKit
import CommonCrypto

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isSessionAuthenticated = false
    @Published var currentUser: String?

    /// Published lockout state so views can react
    @Published var lockoutRemainingSeconds: Int = 0

    private let nameKey                = "user_name"
    private let biometricEnabledKey    = "biometric_enabled"
    private let userRegisteredKey      = "user_registered"
    private let userLoggedInKey        = "user_logged_in"

    // MARK: - Keychain keys
    private let pinHashKey             = "user_pin_hash"       // legacy SHA-256 or PBKDF2-derived key
    private let pinSaltKey             = "user_pin_salt"       // PBKDF2 salt (presence indicates PBKDF2)
    private let failCountKey           = "pin_fail_count"      // escalating lockout
    private let lastFailTimestampKey   = "pin_last_fail_ts"    // lockout timestamp

    private let keychainService = "com.gjournal.auth"

    // MARK: - PBKDF2 parameters
    private static let pbkdf2Iterations: UInt32 = 350_000
    private static let saltLength = 16       // bytes
    private static let derivedKeyLength = 32 // bytes (256-bit)

    // MARK: - Lockout thresholds
    /// After 5 failures: 30 s, then 1 m, 5 m, 15 m (capped)
    private static let lockoutThreshold = 5
    private static let lockoutDurations: [TimeInterval] = [30, 60, 300, 900]

    private var lockoutTimer: Timer?

    init() {
        if UserDefaults.standard.bool(forKey: userRegisteredKey),
           let name = UserDefaults.standard.string(forKey: nameKey), !name.isEmpty {
            currentUser = name
            isAuthenticated = true
            // isSessionAuthenticated intentionally not restored — always require biometric/PIN after any launch/crash
        }
        refreshLockoutState()
    }

    // MARK: - Registration & Login

    func completeRegistration(name: String, pin: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidName(trimmed) else { throw AuthError.invalidName }
        guard !UserDefaults.standard.bool(forKey: userRegisteredKey) else { throw AuthError.userAlreadyExists }

        UserDefaults.standard.set(trimmed, forKey: nameKey)
        UserDefaults.standard.set(true, forKey: userRegisteredKey)
        UserDefaults.standard.set(true, forKey: userLoggedInKey)
        storePBKDF2(pin: pin)

        currentUser = trimmed
        isAuthenticated = true
        isSessionAuthenticated = true
    }

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
        storePBKDF2(pin: pin)
    }

    /// Verify PIN with PBKDF2 (or legacy SHA-256 with silent re-hash).
    /// Returns `.success(true)` on match, `.success(false)` on mismatch,
    /// `.failure(.lockedOut(seconds:))` if locked out.
    func verifyPIN(_ pin: String) -> PINVerificationResult {
        // ── Lockout gate ──
        if let remaining = lockoutRemaining(), remaining > 0 {
            return .lockedOut(seconds: Int(ceil(remaining)))
        }

        let matched: Bool

        if let salt = readFromKeychain(key: pinSaltKey),
           let storedDerivedKey = readFromKeychain(key: pinHashKey) {
            // ── PBKDF2 path ──
            let derived = derivePBKDF2(pin: pin, salt: salt)
            matched = (derived == storedDerivedKey)
        } else if let legacyHash = readFromKeychain(key: pinHashKey) {
            // ── Legacy SHA-256 path → silent re-hash on success ──
            let hash = sha256(pin)
            matched = (hash == legacyHash)
            if matched {
                storePBKDF2(pin: pin)   // upgrade in-place
            }
        } else {
            return .incorrect
        }

        if matched {
            clearFailCounter()
            return .correct
        } else {
            recordFailure()
            return checkLockoutAfterFailure()
        }
    }

    /// Convenience for call-sites that don't need lockout info
    func verifyPINBool(_ pin: String) -> Bool {
        if case .correct = verifyPIN(pin) { return true }
        return false
    }

    func hasPIN() -> Bool {
        readFromKeychain(key: pinHashKey) != nil
    }

    func clearPIN() {
        deleteFromKeychain(key: pinHashKey)
        deleteFromKeychain(key: pinSaltKey)
    }

    // MARK: - Lockout

    /// Whether the user is currently locked out. Returns nil if not locked out, or remaining seconds.
    func lockoutRemaining() -> TimeInterval? {
        let failCount = readIntFromKeychain(key: failCountKey)
        guard failCount >= Self.lockoutThreshold else { return nil }

        guard let tsString = readFromKeychain(key: lastFailTimestampKey),
              let ts = TimeInterval(tsString) else { return nil }

        let tierIndex = min(failCount - Self.lockoutThreshold, Self.lockoutDurations.count - 1)
        let duration = Self.lockoutDurations[tierIndex]
        let elapsed = Date().timeIntervalSince1970 - ts
        let remaining = duration - elapsed

        return remaining > 0 ? remaining : nil
    }

    var isLockedOut: Bool {
        if let r = lockoutRemaining(), r > 0 { return true }
        return false
    }

    /// Refresh the published lockoutRemainingSeconds and schedule a timer to count down.
    func refreshLockoutState() {
        lockoutTimer?.invalidate()
        if let remaining = lockoutRemaining(), remaining > 0 {
            lockoutRemainingSeconds = Int(ceil(remaining))
            startLockoutTimer()
        } else {
            lockoutRemainingSeconds = 0
        }
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

    // MARK: - Private — PBKDF2

    /// Generate a new random salt, derive key with PBKDF2, and store both in Keychain.
    @discardableResult
    private func storePBKDF2(pin: String) -> Bool {
        let salt = generateRandomSalt()
        let derived = derivePBKDF2(pin: pin, salt: salt)
        let saltStored = storeInKeychain(key: pinSaltKey, value: salt)
        let keyStored  = storeInKeychain(key: pinHashKey, value: derived)
        return saltStored && keyStored
    }

    /// Derive a key from a PIN + salt using PBKDF2-HMAC-SHA256.
    private func derivePBKDF2(pin: String, salt: String) -> String {
        guard let pinData = pin.data(using: .utf8),
              let saltData = Data(base64Encoded: salt) else { return "" }

        var derivedKey = [UInt8](repeating: 0, count: Self.derivedKeyLength)

        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            (pinData as NSData).bytes, pinData.count,
            (saltData as NSData).bytes, saltData.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            Self.pbkdf2Iterations,
            &derivedKey, Self.derivedKeyLength
        )

        guard status == kCCSuccess else { return "" }
        return Data(derivedKey).base64EncodedString()
    }

    /// Generate a 16-byte cryptographically random salt, returned as base64.
    private func generateRandomSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: Self.saltLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, Self.saltLength, &bytes)
        return Data(bytes).base64EncodedString()
    }

    // MARK: - Private — Lockout helpers

    private func recordFailure() {
        let current = readIntFromKeychain(key: failCountKey)
        let newCount = current + 1
        storeInKeychain(key: failCountKey, value: String(newCount))
        storeInKeychain(key: lastFailTimestampKey, value: String(Date().timeIntervalSince1970))
    }

    private func clearFailCounter() {
        deleteFromKeychain(key: failCountKey)
        deleteFromKeychain(key: lastFailTimestampKey)
        lockoutTimer?.invalidate()
        lockoutRemainingSeconds = 0
    }

    private func checkLockoutAfterFailure() -> PINVerificationResult {
        let failCount = readIntFromKeychain(key: failCountKey)
        if failCount >= Self.lockoutThreshold {
            let tierIndex = min(failCount - Self.lockoutThreshold, Self.lockoutDurations.count - 1)
            let duration = Int(Self.lockoutDurations[tierIndex])
            refreshLockoutState()
            return .lockedOut(seconds: duration)
        }
        return .incorrect
    }

    private func startLockoutTimer() {
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            DispatchQueue.main.async {
                if let remaining = self.lockoutRemaining(), remaining > 0 {
                    self.lockoutRemainingSeconds = Int(ceil(remaining))
                } else {
                    self.lockoutRemainingSeconds = 0
                    timer.invalidate()
                }
            }
        }
    }

    // MARK: - Private — Legacy SHA-256

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    // MARK: - Private — Name validation

    private func isValidName(_ name: String) -> Bool {
        name.count >= 2
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

    private func readIntFromKeychain(key: String) -> Int {
        guard let str = readFromKeychain(key: key), let val = Int(str) else { return 0 }
        return val
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

// MARK: - PIN Verification Result

enum PINVerificationResult: Equatable {
    case correct
    case incorrect
    case lockedOut(seconds: Int)
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
