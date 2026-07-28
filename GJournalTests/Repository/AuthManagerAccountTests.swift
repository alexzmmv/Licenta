import XCTest
@testable import GJournal

/// Tests the account-management surface: renaming, erasing, and the Keychain
/// failure contract.
///
/// None of these operations existed before — a user could not change their
/// display name, and a forgotten PIN meant the journal was unreachable forever
/// because nothing ever called `clearPIN()`.
final class AuthManagerAccountTests: XCTestCase {

    private let service = "com.gjournal.auth"
    private let nameKey = "user_name"
    private let registeredKey = "user_registered"
    private let biometricKey = "biometric_enabled"

    override func setUp() {
        super.setUp()
        resetState()
    }

    override func tearDown() {
        resetState()
        super.tearDown()
    }

    private func resetState() {
        for key in ["user_pin_hash", "user_pin_salt", "pin_fail_count", "pin_last_fail_ts"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
            ]
            SecItemDelete(query as CFDictionary)
        }
        for key in [nameKey, registeredKey, biometricKey, "hasCompletedOnboarding"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func makeRegisteredManager(name: String = "Alex", pin: String = "482913") throws -> AuthManager {
        let auth = AuthManager()
        try auth.completeRegistration(name: name, pin: pin)
        return auth
    }

    // MARK: - Rename

    func testUpdateNameChangesStoredAndPublishedName() throws {
        let auth = try makeRegisteredManager(name: "Alex")
        XCTAssertEqual(auth.currentUser, "Alex")

        try auth.updateName("Constantin")

        XCTAssertEqual(auth.currentUser, "Constantin")
        XCTAssertEqual(UserDefaults.standard.string(forKey: nameKey), "Constantin")
    }

    func testUpdateNameTrimsWhitespace() throws {
        let auth = try makeRegisteredManager()
        try auth.updateName("   Sam   ")
        XCTAssertEqual(auth.currentUser, "Sam")
    }

    func testUpdateNameRejectsTooShortName() throws {
        let auth = try makeRegisteredManager(name: "Alex")
        XCTAssertThrowsError(try auth.updateName("A")) { error in
            XCTAssertEqual(error as? AuthError, .invalidName)
        }
        XCTAssertEqual(auth.currentUser, "Alex", "a rejected rename must not change the stored name")
    }

    func testUpdateNameRejectsWhitespaceOnlyName() throws {
        let auth = try makeRegisteredManager(name: "Alex")
        XCTAssertThrowsError(try auth.updateName("    "))
        XCTAssertEqual(auth.currentUser, "Alex")
    }

    func testUpdateNameFailsWithoutAnAccount() {
        let auth = AuthManager()
        XCTAssertThrowsError(try auth.updateName("Alex")) { error in
            XCTAssertEqual(error as? AuthError, .userNotFound)
        }
    }

    // MARK: - Erase

    func testEraseAccountClearsCredentialsAndIdentity() throws {
        let auth = try makeRegisteredManager(name: "Alex", pin: "482913")
        auth.isBiometricEnabled = true
        XCTAssertTrue(auth.hasPIN())

        auth.eraseAccount()

        XCTAssertFalse(auth.hasPIN(), "the PIN must be removed from the Keychain")
        XCTAssertNil(auth.currentUser)
        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertFalse(auth.isSessionAuthenticated)
        XCTAssertFalse(auth.isUserRegistered())
        XCTAssertNil(UserDefaults.standard.string(forKey: nameKey))
        XCTAssertFalse(auth.isBiometricEnabled)
    }

    func testEraseAccountAllowsRegisteringAgain() throws {
        let auth = try makeRegisteredManager(name: "Alex")
        auth.eraseAccount()

        // Previously impossible: completeRegistration threw userAlreadyExists
        // forever because nothing ever cleared user_registered.
        XCTAssertNoThrow(try auth.completeRegistration(name: "Sam", pin: "112233"))
        XCTAssertEqual(auth.currentUser, "Sam")
        XCTAssertEqual(auth.verifyPIN("112233"), .correct)
    }

    func testEraseAccountClearsLockoutSoTheNewAccountIsUsable() throws {
        let auth = try makeRegisteredManager(pin: "482913")
        for _ in 0..<6 { _ = auth.verifyPIN("000000") }
        XCTAssertTrue(auth.isLockedOut, "precondition: repeated failures lock the account")

        auth.eraseAccount()
        try auth.completeRegistration(name: "Sam", pin: "112233")

        XCTAssertFalse(auth.isLockedOut, "a fresh account must not inherit the old lockout")
        XCTAssertEqual(auth.verifyPIN("112233"), .correct)
    }

    // MARK: - Registration contract

    func testRegistrationRejectsDuplicateAccount() throws {
        let auth = try makeRegisteredManager(name: "Alex")
        XCTAssertThrowsError(try auth.completeRegistration(name: "Sam", pin: "112233")) { error in
            XCTAssertEqual(error as? AuthError, .userAlreadyExists)
        }
    }

    func testRegistrationDoesNotMarkAccountRegisteredWhenNameIsInvalid() {
        let auth = AuthManager()
        XCTAssertThrowsError(try auth.completeRegistration(name: "A", pin: "482913"))
        XCTAssertFalse(auth.isUserRegistered(), "a failed registration must leave no account behind")
        XCTAssertFalse(auth.hasPIN())
    }
}

extension AuthError: @retroactive Equatable {
    public static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        String(describing: lhs) == String(describing: rhs)
    }
}
