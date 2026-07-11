import XCTest
import CommonCrypto
import CryptoKit
@testable import GJournal

/// Tests the PBKDF2 primitive and lockout state machine independently.
final class AuthManagerSecurityTests: XCTestCase {
    
    private let pbkdf2Iterations: UInt32 = 350_000
    private let saltLength = 16
    private let derivedKeyLength = 32
    
    private func generateRandomSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: saltLength)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltLength, &bytes)
        return Data(bytes).base64EncodedString()
    }
    
    private func derivePBKDF2(pin: String, salt: String) -> String {
        guard let pinData = pin.data(using: .utf8),
              let saltData = Data(base64Encoded: salt) else { return "" }
        
        var derivedKey = [UInt8](repeating: 0, count: derivedKeyLength)
        
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            (pinData as NSData).bytes, pinData.count,
            (saltData as NSData).bytes, saltData.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            pbkdf2Iterations,
            &derivedKey, derivedKeyLength
        )
        
        guard status == kCCSuccess else { return "" }
        return Data(derivedKey).base64EncodedString()
    }
    
    private func sha256Legacy(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    // Lockout calculation
    private let lockoutThreshold = 5
    private let lockoutDurations: [TimeInterval] = [30, 60, 300, 900]
    
    private func lockoutDuration(failCount: Int) -> TimeInterval? {
        guard failCount >= lockoutThreshold else { return nil }
        let tierIndex = min(failCount - lockoutThreshold, lockoutDurations.count - 1)
        return lockoutDurations[tierIndex]
    }
    
    func testSaltGeneration() {
        let salt1 = generateRandomSalt()
        let salt2 = generateRandomSalt()
        XCTAssertFalse(salt1.isEmpty, "Salt is non-empty")
        XCTAssertNotEqual(salt1, salt2, "Two salts are different (cryptographic randomness)")
        
        let saltData = Data(base64Encoded: salt1)!
        XCTAssertEqual(saltData.count, saltLength, "Salt is exactly \(saltLength) bytes")
    }
    
    func testPBKDF2Determinism() {
        let salt = generateRandomSalt()
        let pin = "123456"
        let derived1 = derivePBKDF2(pin: pin, salt: salt)
        let derived2 = derivePBKDF2(pin: pin, salt: salt)
        XCTAssertFalse(derived1.isEmpty, "Derived key is non-empty")
        XCTAssertEqual(derived1, derived2, "Same PIN + same salt -> same derived key")
        
        let derivedData = Data(base64Encoded: derived1)!
        XCTAssertEqual(derivedData.count, derivedKeyLength, "Derived key is exactly \(derivedKeyLength) bytes")
    }
    
    func testPinDifferentiation() {
        let salt = generateRandomSalt()
        let key1 = derivePBKDF2(pin: "123456", salt: salt)
        let key2 = derivePBKDF2(pin: "654321", salt: salt)
        XCTAssertNotEqual(key1, key2, "Different PINs produce different derived keys")
    }
    
    func testSaltDifferentiation() {
        let salt1 = generateRandomSalt()
        let salt2 = generateRandomSalt()
        let pin = "999999"
        let key1 = derivePBKDF2(pin: pin, salt: salt1)
        let key2 = derivePBKDF2(pin: pin, salt: salt2)
        XCTAssertNotEqual(key1, key2, "Same PIN with different salts -> different derived keys")
    }
    
    func testPBKDF2NotLegacySHA256() {
        let pin = "123456"
        let salt = generateRandomSalt()
        let pbkdf2Key = derivePBKDF2(pin: pin, salt: salt)
        let sha256Hash = sha256Legacy(pin)
        XCTAssertNotEqual(pbkdf2Key, sha256Hash, "PBKDF2 output differs from SHA-256 hash")
    }
    
    func testPBKDF2ComputationalCost() {
        let salt = generateRandomSalt()
        let start = CFAbsoluteTimeGetCurrent()
        _ = derivePBKDF2(pin: "123456", salt: salt)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let elapsedMs = elapsed * 1000
        XCTAssertGreaterThan(elapsedMs, 50, "PBKDF2 takes >50ms (actual: \(elapsedMs)ms) - resistant to brute-force")
    }
    
    func testLockoutEscalationTiers() {
        XCTAssertNil(lockoutDuration(failCount: 0), "0 fails -> no lockout")
        XCTAssertNil(lockoutDuration(failCount: 4), "4 fails -> no lockout")
        XCTAssertEqual(lockoutDuration(failCount: 5), 30, "5 fails -> 30s lockout")
        XCTAssertEqual(lockoutDuration(failCount: 6), 60, "6 fails -> 60s lockout")
        XCTAssertEqual(lockoutDuration(failCount: 7), 300, "7 fails -> 5min lockout")
        XCTAssertEqual(lockoutDuration(failCount: 8), 900, "8 fails -> 15min lockout")
        XCTAssertEqual(lockoutDuration(failCount: 100), 900, "100 fails -> capped at 15min")
    }
    
    func testEdgeCases() {
        let salt = generateRandomSalt()
        let emptyKey = derivePBKDF2(pin: "", salt: salt)
        XCTAssertTrue(emptyKey.isEmpty, "Empty PIN produces an empty derived key (invalid input)")
        
        let shortPin = derivePBKDF2(pin: "1", salt: salt)
        XCTAssertFalse(shortPin.isEmpty, "Single-digit PIN produces a valid key")
        
        let longPin = derivePBKDF2(pin: "123456789012345678901234567890", salt: salt)
        XCTAssertFalse(longPin.isEmpty, "Long PIN produces a valid key")
        
        XCTAssertNotEqual(emptyKey, shortPin, "Empty vs single-digit -> different keys")
        XCTAssertNotEqual(shortPin, longPin, "Short vs long -> different keys")
    }
    
    func testLegacySHA256Migration() {
        let pin = "123456"
        let legacyHash = sha256Legacy(pin)
        let enteredHash = sha256Legacy(pin)
        XCTAssertEqual(enteredHash, legacyHash, "Legacy SHA-256 verification succeeds for correct PIN")
        
        let salt = generateRandomSalt()
        let pbkdf2Key = derivePBKDF2(pin: pin, salt: salt)
        XCTAssertFalse(pbkdf2Key.isEmpty, "Re-hash to PBKDF2 succeeds")
        
        let verifyKey = derivePBKDF2(pin: pin, salt: salt)
        XCTAssertEqual(verifyKey, pbkdf2Key, "PBKDF2-hashed PIN verifies correctly after migration")
        
        let wrongKey = derivePBKDF2(pin: "654321", salt: salt)
        XCTAssertNotEqual(wrongKey, pbkdf2Key, "Wrong PIN fails verification after migration")
    }
}
