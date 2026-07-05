#!/usr/bin/env swift
//
// AuthManagerSecurityTests.swift
// Standalone validation of the PBKDF2 and lockout logic in AuthManager.
// Run: swift AuthManagerSecurityTests.swift
//
// NOTE: This tests the PBKDF2 primitive and lockout state machine independently.
// Keychain operations can't be tested outside of an app context, so we test the
// pure cryptographic functions and the lockout math.
//

import Foundation
import CommonCrypto
import CryptoKit

// ============================================================================
// MARK: - Extracted testable functions (mirror AuthManager internals)
// ============================================================================

let pbkdf2Iterations: UInt32 = 350_000
let saltLength = 16
let derivedKeyLength = 32

func generateRandomSalt() -> String {
    var bytes = [UInt8](repeating: 0, count: saltLength)
    _ = SecRandomCopyBytes(kSecRandomDefault, saltLength, &bytes)
    return Data(bytes).base64EncodedString()
}

func derivePBKDF2(pin: String, salt: String) -> String {
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

func sha256Legacy(_ input: String) -> String {
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { String(format: "%02hhx", $0) }.joined()
}

// Lockout calculation
let lockoutThreshold = 5
let lockoutDurations: [TimeInterval] = [30, 60, 300, 900]

func lockoutDuration(failCount: Int) -> TimeInterval? {
    guard failCount >= lockoutThreshold else { return nil }
    let tierIndex = min(failCount - lockoutThreshold, lockoutDurations.count - 1)
    return lockoutDurations[tierIndex]
}

// ============================================================================
// MARK: - Test runner
// ============================================================================

var passCount = 0
var failCount = 0

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passCount += 1
        print("  ✅ \(message)")
    } else {
        failCount += 1
        print("  ❌ FAIL: \(message) (line \(line))")
    }
}

// ============================================================================
// MARK: - Tests
// ============================================================================

print("╔══════════════════════════════════════════════════════╗")
print("║  AuthManager Security Tests (PBKDF2 + Lockout)     ║")
print("╚══════════════════════════════════════════════════════╝")
print()

// ── Test 1: Salt generation ──
print("▸ Salt generation")
do {
    let salt1 = generateRandomSalt()
    let salt2 = generateRandomSalt()
    assert(!salt1.isEmpty, "Salt is non-empty")
    assert(salt1 != salt2, "Two salts are different (cryptographic randomness)")
    
    let saltData = Data(base64Encoded: salt1)!
    assert(saltData.count == saltLength, "Salt is exactly \(saltLength) bytes (\(saltData.count))")
}
print()

// ── Test 2: PBKDF2 derivation determinism ──
print("▸ PBKDF2 determinism")
do {
    let salt = generateRandomSalt()
    let pin = "123456"
    let derived1 = derivePBKDF2(pin: pin, salt: salt)
    let derived2 = derivePBKDF2(pin: pin, salt: salt)
    assert(!derived1.isEmpty, "Derived key is non-empty")
    assert(derived1 == derived2, "Same PIN + same salt → same derived key")
    
    let derivedData = Data(base64Encoded: derived1)!
    assert(derivedData.count == derivedKeyLength, "Derived key is exactly \(derivedKeyLength) bytes")
}
print()

// ── Test 3: Different PINs → different keys ──
print("▸ PIN differentiation")
do {
    let salt = generateRandomSalt()
    let key1 = derivePBKDF2(pin: "123456", salt: salt)
    let key2 = derivePBKDF2(pin: "654321", salt: salt)
    assert(key1 != key2, "Different PINs produce different derived keys")
}
print()

// ── Test 4: Different salts → different keys ──
print("▸ Salt differentiation")
do {
    let salt1 = generateRandomSalt()
    let salt2 = generateRandomSalt()
    let pin = "999999"
    let key1 = derivePBKDF2(pin: pin, salt: salt1)
    let key2 = derivePBKDF2(pin: pin, salt: salt2)
    assert(key1 != key2, "Same PIN with different salts → different derived keys")
}
print()

// ── Test 5: PBKDF2 is NOT the same as SHA-256 ──
print("▸ PBKDF2 ≠ SHA-256")
do {
    let pin = "123456"
    let salt = generateRandomSalt()
    let pbkdf2Key = derivePBKDF2(pin: pin, salt: salt)
    let sha256Hash = sha256Legacy(pin)
    assert(pbkdf2Key != sha256Hash, "PBKDF2 output differs from SHA-256 hash")
}
print()

// ── Test 6: PBKDF2 performance (should take ~100ms+ per derivation) ──
print("▸ PBKDF2 computational cost (brute-force resistance)")
do {
    let salt = generateRandomSalt()
    let start = CFAbsoluteTimeGetCurrent()
    _ = derivePBKDF2(pin: "123456", salt: salt)
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    let elapsedMs = elapsed * 1000
    assert(elapsedMs > 50, "PBKDF2 takes >\(Int(50))ms (actual: \(Int(elapsedMs))ms) — resistant to brute-force")
    print("    ℹ  Single derivation: \(String(format: "%.1f", elapsedMs))ms")
    
    // Estimate time to brute-force 6-digit PIN space (10^6 = 1,000,000)
    let bruteForceSeconds = elapsed * 1_000_000
    let bruteForceHours = bruteForceSeconds / 3600
    print("    ℹ  Estimated brute-force of 6-digit space: \(String(format: "%.1f", bruteForceHours)) hours")
    assert(bruteForceHours > 1, "Brute-force 6-digit PIN takes >1 hour")
}
print()

print("▸ Lockout escalation tiers")
do {
    assert(lockoutDuration(failCount: 0) == nil, "0 fails → no lockout")
    assert(lockoutDuration(failCount: 4) == nil, "4 fails → no lockout")
    assert(lockoutDuration(failCount: 5) == 30, "5 fails → 30s lockout")
    assert(lockoutDuration(failCount: 6) == 60, "6 fails → 60s lockout")
    assert(lockoutDuration(failCount: 7) == 300, "7 fails → 5min lockout")
    assert(lockoutDuration(failCount: 8) == 900, "8 fails → 15min lockout")
    assert(lockoutDuration(failCount: 100) == 900, "100 fails → capped at 15min")
}
print()

// ── Test 8: Edge cases ──
print("▸ Edge cases")
do {
    let salt = generateRandomSalt()
    let emptyKey = derivePBKDF2(pin: "", salt: salt)
    assert(emptyKey.isEmpty, "Empty PIN produces an empty derived key (invalid input)")
    
    let shortPin = derivePBKDF2(pin: "1", salt: salt)
    assert(!shortPin.isEmpty, "Single-digit PIN produces a valid key")
    
    let longPin = derivePBKDF2(pin: "123456789012345678901234567890", salt: salt)
    assert(!longPin.isEmpty, "Long PIN produces a valid key")
    
    // Verify valid keys are different
    assert(emptyKey != shortPin, "Empty vs single-digit → different keys")
    assert(shortPin != longPin, "Short vs long → different keys")
}
print()

// ── Test 9: SHA-256 legacy verification simulation ──
print("▸ Legacy SHA-256 → PBKDF2 migration")
do {
    let pin = "123456"
    let legacyHash = sha256Legacy(pin)
    
    // Simulate: user enters correct PIN, legacy hash matches
    let enteredHash = sha256Legacy(pin)
    assert(enteredHash == legacyHash, "Legacy SHA-256 verification succeeds for correct PIN")
    
    // Simulate: after success, re-hash with PBKDF2
    let salt = generateRandomSalt()
    let pbkdf2Key = derivePBKDF2(pin: pin, salt: salt)
    assert(!pbkdf2Key.isEmpty, "Re-hash to PBKDF2 succeeds")
    
    // Verify the PBKDF2 key now works
    let verifyKey = derivePBKDF2(pin: pin, salt: salt)
    assert(verifyKey == pbkdf2Key, "PBKDF2-hashed PIN verifies correctly after migration")
    
    // Verify wrong PIN fails
    let wrongKey = derivePBKDF2(pin: "654321", salt: salt)
    assert(wrongKey != pbkdf2Key, "Wrong PIN fails verification after migration")
}
print()

// ============================================================================
// MARK: - Summary
// ============================================================================

print("═══════════════════════════════════════════════════════")
if failCount == 0 {
    print(" All \(passCount) tests passed!")
} else {
    print(" \(failCount) test(s) failed out of \(passCount + failCount)")
}
print("═══════════════════════════════════════════════════════")

exit(failCount > 0 ? 1 : 0)
