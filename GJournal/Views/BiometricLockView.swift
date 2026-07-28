import SwiftUI
import LocalAuthentication

struct BiometricLockView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showPINEntry = false
    @State private var pinError: String?
    @State private var biometricAvailable = false
    @State private var showForgotPIN = false
    /// Brand title scales with the user's Dynamic Type setting (base 36pt).
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 36

    var body: some View {
        Group {
            if authManager.isSessionAuthenticated {
                MainAppView()
                    .environmentObject(authManager)
            } else {
                lockScreenView
            }
        }
        .onAppear { armLockScreen() }
        // `.onAppear` fires once for the enclosing Group, which never disappears
        // when the session relocks on backgrounding — without this the user
        // returns to a stale lock screen that never prompts for biometrics.
        .onChange(of: authManager.isSessionAuthenticated) { _, isAuthenticated in
            guard !isAuthenticated else { return }
            armLockScreen()
        }
        .sheet(isPresented: $showForgotPIN) {
            ForgotPINView()
                .environmentObject(authManager)
        }
    }

    /// Reset transient lock-screen state and choose the unlock affordance.
    private func armLockScreen() {
        biometricAvailable = authManager.canUseBiometric()
        pinError = nil
        authManager.refreshLockoutState()
        guard authManager.isAuthenticated && !authManager.isSessionAuthenticated else { return }
        if authManager.isBiometricEnabled && biometricAvailable {
            showPINEntry = false
            Task { await attemptBiometric() }
        } else {
            showPINEntry = true
        }
    }

    // MARK: - Lock screen

    private var lockScreenView: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if showPINEntry {
                pinUnlockView
            } else {
                biometricUnlockView
            }
        }
    }

    private var biometricUnlockView: some View {
        VStack(spacing: 40) {
            Spacer()

            Image(systemName: biometricAvailable ? "faceid" : "lock.fill")
                .font(.system(size: 80))
                .foregroundColor(.pink)

            VStack(spacing: 12) {
                Text("GJournal")
                    .font(.system(size: titleSize, weight: .bold))
                Text("Use Face ID to unlock")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(spacing: 16) {
                Button {
                    Task { await attemptBiometric() }
                } label: {
                    HStack {
                        Image(systemName: "faceid")
                        Text("Unlock with \(authManager.biometryDisplayName)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.pink.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)

                Button("Use PIN instead") {
                    withAnimation { showPINEntry = true }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 20)
            }
        }
    }

    private var pinUnlockView: some View {
        VStack {
            Spacer()

            if authManager.lockoutRemainingSeconds > 0 {
                // ── Lockout state ──
                VStack(spacing: 24) {
                    Image(systemName: "lock.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.orange)

                    Text("Too many attempts")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Try again in \(formattedLockout(authManager.lockoutRemainingSeconds))")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .monospacedDigit()

                    Text("For your security, PIN entry is temporarily disabled.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                PINKeypadView(
                    title: "Enter PIN",
                    subtitle: authManager.currentUser.map { "Welcome back, \($0)" },
                    errorMessage: pinError,
                    onCancel: (authManager.isBiometricEnabled && biometricAvailable) ? {
                        pinError = nil
                        withAnimation { showPINEntry = false }
                    } : nil
                ) { pin in
                    let result = authManager.verifyPIN(pin)
                    switch result {
                    case .correct:
                        pinError = nil
                        authManager.completeSessionAuthentication()
                    case .incorrect:
                        pinError = "Incorrect PIN — try again"
                    case .lockedOut:
                        // The lockout UI swaps in automatically via the published
                        // lockoutRemainingSeconds.
                        pinError = nil
                        authManager.refreshLockoutState()
                    }
                }
            }

            Spacer()

            Button {
                showForgotPIN = true
            } label: {
                Text("Forgot PIN?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 32)
        }
        .onAppear {
            authManager.refreshLockoutState()
        }
    }

    private func formattedLockout(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 {
            return String(format: "%d:%02d", m, s)
        }
        return "\(s)s"
    }

    // MARK: - Biometric attempt

    private func attemptBiometric() async {
        do {
            let success = try await authManager.authenticateWithBiometric()
            if success {
                authManager.completeSessionAuthentication()
            }
        } catch let error as LAError {
            switch error.code {
            case .userFallback:
                withAnimation { showPINEntry = true }
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                withAnimation { showPINEntry = true }
            case .userCancel, .appCancel, .systemCancel:
                break
            default:
                withAnimation { showPINEntry = true }
            }
        } catch {
            withAnimation { showPINEntry = true }
        }
    }
}

#Preview {
    BiometricLockView()
        .environmentObject(AuthManager())
}
