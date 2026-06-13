import SwiftUI
import LocalAuthentication

struct BiometricLockView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showPINEntry = false
    @State private var pinError: String?
    @State private var showLogoutConfirmation = false

    var body: some View {
        Group {
            if authManager.isSessionAuthenticated {
                MainAppView()
                    .environmentObject(authManager)
            } else {
                lockScreenView
            }
        }
        .onAppear {
            guard authManager.isAuthenticated && !authManager.isSessionAuthenticated else { return }
            if authManager.isBiometricEnabled && authManager.canUseBiometric() {
                Task { await attemptBiometric() }
            } else {
                showPINEntry = true
            }
        }
    }

    // MARK: - Lock screen

    private var lockScreenView: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

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

            Image(systemName: authManager.canUseBiometric() ? "faceid" : "lock.fill")
                .font(.system(size: 80))
                .foregroundColor(.pink)

            VStack(spacing: 12) {
                Text("GJournal")
                    .font(.system(size: 36, weight: .bold))
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
                        Text("Unlock with Face ID")
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

                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    Text("Log Out")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.bottom, 20)
            }
        }
        .confirmationDialog("Log Out", isPresented: $showLogoutConfirmation) {
            Button("Log Out", role: .destructive) { authManager.logout() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove your session. Your journal data stays on the device.")
        }
    }

    private var pinUnlockView: some View {
        VStack {
            Spacer()

            PINKeypadView(
                title: "Enter PIN",
                subtitle: authManager.currentUser.map { "Welcome back, \($0)" },
                errorMessage: pinError,
                onCancel: (authManager.isBiometricEnabled && authManager.canUseBiometric()) ? {
                    pinError = nil
                    withAnimation { showPINEntry = false }
                } : nil
            ) { pin in
                if authManager.verifyPIN(pin) {
                    pinError = nil
                    authManager.completeSessionAuthentication()
                } else {
                    pinError = "Incorrect PIN — try again"
                }
            }

            Spacer()

            Button(role: .destructive) {
                showLogoutConfirmation = true
            } label: {
                Text("Log Out")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .padding(.bottom, 32)
        }
        .confirmationDialog("Log Out", isPresented: $showLogoutConfirmation) {
            Button("Log Out", role: .destructive) { authManager.logout() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove your session. Your journal data stays on the device.")
        }
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
