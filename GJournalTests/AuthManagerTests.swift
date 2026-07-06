import XCTest
import CryptoKit
@testable import GJournal

/// Tests the PIN storage paths in AuthManager, including the silent upgrade
/// from the legacy unsalted SHA-256 format to PBKDF2.
final class AuthManagerTests: XCTestCase {

    private let service = "com.gjournal.auth"
    private let pinHashKey = "user_pin_hash"
    private let pinSaltKey = "user_pin_salt"
    private let failCountKey = "pin_fail_count"
    private let lastFailKey = "pin_last_fail_ts"

    override func setUp() {
        super.setUp()
        clearAllAuthKeychainItems()
    }

    override func tearDown() {
        clearAllAuthKeychainItems()
        super.tearDown()
    }

    func testSetAndVerifyPINUsesPBKDF2() {
        let auth = AuthManager()
        XCTAssertTrue(auth.setPIN("482913"))

        // PBKDF2 format stores a salt alongside the derived key
        XCTAssertNotNil(readKeychain(pinSaltKey))
        XCTAssertNotNil(readKeychain(pinHashKey))

        XCTAssertEqual(auth.verifyPIN("482913"), .correct)
        XCTAssertEqual(auth.verifyPIN("000000"), .incorrect)
    }

    func testLegacySHA256IsUpgradedOnSuccessfulVerify() {
        // Simulate a pre-PBKDF2 install: unsalted SHA-256 hex in the keychain,
        // and no salt entry.
        let pin = "135790"
        let legacyHash = SHA256.hash(data: Data(pin.utf8))
            .map { String(format: "%02hhx", $0) }.joined()
        writeKeychain(pinHashKey, legacyHash)
        XCTAssertNil(readKeychain(pinSaltKey))

        let auth = AuthManager()
        XCTAssertEqual(auth.verifyPIN(pin), .correct)

        // The successful verify must have re-hashed in place (salt now present,
        // stored key no longer the legacy hex digest).
        XCTAssertNotNil(readKeychain(pinSaltKey))
        XCTAssertNotEqual(readKeychain(pinHashKey), legacyHash)

        // And the upgraded credentials still verify
        XCTAssertEqual(auth.verifyPIN(pin), .correct)
        XCTAssertEqual(auth.verifyPIN("999999"), .incorrect)
    }

    func testLegacyWrongPINDoesNotUpgrade() {
        let legacyHash = SHA256.hash(data: Data("111111".utf8))
            .map { String(format: "%02hhx", $0) }.joined()
        writeKeychain(pinHashKey, legacyHash)

        let auth = AuthManager()
        XCTAssertEqual(auth.verifyPIN("222222"), .incorrect)

        // Wrong PIN must not create PBKDF2 material
        XCTAssertNil(readKeychain(pinSaltKey))
        XCTAssertEqual(readKeychain(pinHashKey), legacyHash)
    }

    func testClearPINRemovesAllMaterial() {
        let auth = AuthManager()
        auth.setPIN("246800")
        auth.clearPIN()

        XCTAssertNil(readKeychain(pinHashKey))
        XCTAssertNil(readKeychain(pinSaltKey))
        XCTAssertFalse(auth.hasPIN())
    }

    // MARK: - Keychain helpers (mirror AuthManager's storage attributes)

    private func writeKeychain(_ key: String, _ value: String) {
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:      Data(value.utf8),
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func readKeychain(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func clearAllAuthKeychainItems() {
        [pinHashKey, pinSaltKey, failCountKey, lastFailKey].forEach(deleteKeychain)
    }
}
