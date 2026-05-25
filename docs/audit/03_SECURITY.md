# Security Audit — Credentials & Data Protection

---

## 1. Current Threat Model

GJournal stores **highly sensitive personal data** — emotional states, life events, and behavioral patterns. For a privacy-focused thesis app, the security posture must be defensible.

### What's Stored Where (Current State)

| Data | Storage | Encrypted at rest? | Risk |
|:-----|:--------|:------------------:|:-----|
| User name | `UserDefaults` | ❌ No | Low — not secret |
| Password hash (SHA256) | `UserDefaults` | ❌ No | 🔴 **High** — hash+salt extractable |
| Password salt | `UserDefaults` | ❌ No | 🔴 **High** — enables offline brute-force |
| Session flags | `UserDefaults` | ❌ No | Low — booleans only |
| Journal entries (text) | SwiftData SQLite | ❌ No | 🔴 **High** — full emotional history readable |
| Embedding vectors (JSON) | SwiftData SQLite | ❌ No | Medium — mathematical vectors, not human-readable |
| Keychain password copy | iOS Keychain | ✅ Yes (hardware) | 🟢 Secure |

### Attack Vectors

1. **Device backup extraction**: iTunes/Finder backups include UserDefaults plist and SQLite databases in plaintext. Anyone with backup access can read all journal entries.
2. **Jailbroken device**: Full filesystem access to the app sandbox.
3. **Forensic tools**: Tools like iMazing can extract app data from unencrypted backups.

---

## 2. Fix: Migrate Credentials to Keychain

Move the password hash and salt from UserDefaults to Keychain. Keep only non-sensitive flags in UserDefaults.

### What Stays in UserDefaults
```
user_registered: Bool
user_logged_in: Bool
biometric_enabled: Bool
user_name: String  (display name — not secret)
```

### What Moves to Keychain
```
user_password_hash: String  → Keychain
password_salt: String       → Keychain
```

### Implementation

```swift
// In AuthManager.swift — add these Keychain helper methods

private func storeCredentialInKeychain(key: String, value: String) throws {
    guard let data = value.data(using: .utf8) else {
        throw AuthError.keychainError
    }
    
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: key,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    
    SecItemDelete(query as CFDictionary)  // remove old if exists
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw AuthError.keychainError }
}

private func readCredentialFromKeychain(key: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: key,
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecReturnData as String: true
    ]
    
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data,
          let value = String(data: data, encoding: .utf8) else {
        return nil
    }
    return value
}
```

Then update `registerLocal` and `loginLocal` to use these instead of `UserDefaults.set/string(forKey:)` for the hash and salt.

> [!NOTE]
> The `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` flag means:
> - Data is only accessible when the device is unlocked
> - Data is NOT included in device backups  
> - Data is NOT transferred to a new device
> 
> This is the highest practical security level for personal credentials.

---

## 3. Fix: Enable iOS Data Protection on SwiftData

iOS provides file-level encryption via **Data Protection**. When enabled with `NSFileProtectionComplete`, the SQLite file is encrypted with a key derived from the user's passcode and the device's hardware key (Secure Enclave).

### Implementation

```swift
// In GJournalApp.swift — update ModelContainer creation

init() {
    do {
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        modelContainer = try ModelContainer(
            for: Bit.self, Cluster.self, EmotionConfiguration.self,
            configurations: config
        )
        
        // Enable Data Protection on the SQLite store
        if let storeURL = modelContainer.configurations.first?.url {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: storeURL.path
            )
        }
    } catch {
        fatalError("Failed to create ModelContainer: \(error)")
    }
}
```

### Protection Levels

| Level | Accessible | Backup encrypted? | Recommendation |
|:------|:-----------|:------------------:|:---------------|
| `complete` | Only when device unlocked | ✅ | Too restrictive — blocks background AI processing |
| **`completeUnlessOpen`** | While app has file handle open | ✅ | **Best for GJournal** — allows background clustering |
| `completeUntilFirstUserAuthentication` | After first unlock since boot | ✅ | Acceptable fallback |

Use **`completeUnlessOpen`** — it encrypts the file at rest but allows the app to finish background AI processing if the user locks the device mid-operation.

---

## 4. Additional Hardening (Optional)

### SHA256 → PBKDF2

Current password hashing uses a single SHA256 pass. For thesis defense, you could upgrade to PBKDF2 (Password-Based Key Derivation Function 2) which is the industry standard for password hashing:

```swift
import CommonCrypto

private func hashPassword(_ password: String, with salt: Data) -> String {
    guard let passwordData = password.data(using: .utf8) else { return "" }
    
    var derivedKey = [UInt8](repeating: 0, count: 32) // 256-bit key
    let result = passwordData.withUnsafeBytes { passwordBytes in
        salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes.bindMemory(to: Int8.self).baseAddress,
                passwordData.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress,
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                100_000,  // 100K iterations — ~200ms on iPhone 11
                &derivedKey,
                derivedKey.count
            )
        }
    }
    
    guard result == kCCSuccess else { return "" }
    return Data(derivedKey).base64EncodedString()
}
```

> [!TIP]
> This is a "nice to have" for thesis defense. SHA256 with salt is acceptable for personal use. PBKDF2 adds academic rigor if your thesis has a security chapter.

---

## 5. Summary of Changes

| Change | Effort | Impact | Priority |
|:-------|:------:|:------:|:--------:|
| Move hash+salt to Keychain | 30 min | Credentials no longer in plaintext backups | **High** |
| Data Protection on SQLite | 15 min | Journal entries encrypted at rest | **High** |
| PBKDF2 password hashing | 20 min | Brute-force resistant | Medium |
| Include `Cluster.self` in ModelContainer | 5 min | Bug fix — Cluster model may not be registered | **High** |

---

## 🎓 PhD Review

1. **The privacy-by-design argument** is strong for a thesis. Frame it as: *"All computation occurs on-device. No personal data leaves the device at any point — not during inference, training, or synchronization."* This is a concrete differentiator from cloud-based journaling apps.
2. **iOS Data Protection** leverages the Secure Enclave (hardware-backed encryption). Cite Apple's Platform Security Guide (2024) for the cryptographic details.
3. **Keychain** uses AES-256-GCM encryption with a key derived from the user's passcode and the device's UID key (burned into silicon). This is hardware-grade security that you can cite directly.
4. **Consider adding a threat model diagram** in the thesis showing: (a) what data exists, (b) where it's stored, (c) what encryption protects it, (d) what attack vectors are mitigated. This shows security thinking.

## 🔴 Red-Hat Review

1. **Keychain migration is a one-way door**. Once you move credentials to Keychain, old UserDefaults data should be explicitly deleted to avoid leaving copies. Don't forget: `UserDefaults.standard.removeObject(forKey: "user_password_hash")`.
2. **Data Protection `completeUnlessOpen`** requires the app to have an open file handle before the device locks. If the user locks the device and the app hasn't opened the DB yet, the next background clustering attempt will fail with a file access error. **Test this scenario explicitly**.
3. **PBKDF2 with 100K iterations** adds ~200ms delay on login. On iPhone 11 this is fine but perceptible. Don't set iterations higher without testing on the slowest target device.
4. **The Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` flag** means that if the user restores from backup to a new device, their credentials are LOST. They'll need to re-register. This is probably fine for a personal thesis app, but document this behavior.
