import SwiftUI

private enum LoginStep {
    case name
    case pinSetup
    case pinConfirm(first: String)
    case biometricOptIn(pin: String)
}

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var step: LoginStep = .name
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// Brand title scales with the user's Dynamic Type setting (base 38pt).
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 38

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                    Color(red: 0.10, green: 0.04, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.pink.opacity(0.15))
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: -60, y: -120)

            switch step {
            case .name:
                nameView
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity))
            case .pinSetup:
                pinSetupView
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .pinConfirm(let first):
                pinConfirmView(first: first)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .biometricOptIn(let pin):
                biometricOptInView(pin: pin)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: stepIndex)
    }

    private var stepIndex: Int {
        switch step {
        case .name:           return 0
        case .pinSetup:       return 1
        case .pinConfirm:     return 2
        case .biometricOptIn: return 3
        }
    }

    // MARK: - Name step

    private var nameView: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.pink.opacity(0.15))
                        .frame(width: 100, height: 100)
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                VStack(spacing: 8) {
                    Text("GJournal")
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Your private emotional journal")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, 52)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's your name?")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.gray)
                    HStack {
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                            .frame(width: 20)
                        TextField("Alex", text: $name)
                            .foregroundColor(.white)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled(true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                }

                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill").font(.caption)
                        Text(error).font(.caption)
                    }
                    .foregroundColor(.red.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(10)
                }

                Button {
                    Task { await continueWithName() }
                } label: {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(0.85)
                        } else {
                            Image(systemName: "arrow.right")
                            Text("Continue").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.pink, .purple.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(16)
                    .shadow(color: .pink.opacity(0.4), radius: 12, y: 6)
                }
                .disabled(isLoading || !isNameValid)
                .opacity(isNameValid ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.2), value: isNameValid)
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 4) {
                Image(systemName: "lock.shield.fill").font(.caption).foregroundColor(.gray.opacity(0.6))
                Text("All data stays on your device").font(.caption2).foregroundColor(.gray.opacity(0.5))
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - PIN setup step

    private var pinSetupView: some View {
        VStack {
            Spacer()
            PINKeypadView(
                title: "Create a PIN",
                subtitle: "Choose a 6-digit PIN to secure your journal",
                errorMessage: errorMessage,
                onCancel: { withAnimation { step = .name } }
            ) { pin in
                errorMessage = nil
                withAnimation { step = .pinConfirm(first: pin) }
            }
            Spacer()
        }
    }

    // MARK: - PIN confirm step

    private func pinConfirmView(first: String) -> some View {
        VStack {
            Spacer()
            PINKeypadView(
                title: "Confirm PIN",
                subtitle: "Re-enter the same PIN to confirm",
                errorMessage: errorMessage,
                onCancel: {
                    errorMessage = nil
                    withAnimation { step = .pinSetup }
                }
            ) { pin in
                if pin == first {
                    if authManager.canUseBiometric() {
                        withAnimation { step = .biometricOptIn(pin: pin) }
                    } else {
                        finishRegistration(pin: pin, enableBiometric: false)
                    }
                } else {
                    errorMessage = "PINs don't match — try again"
                    withAnimation { step = .pinSetup }
                }
            }
            Spacer()
        }
    }

    // MARK: - Biometric opt-in step

    /// Shown only when the device has biometrics enrolled. Previously the app
    /// switched Face ID on silently at registration, which is a consent problem
    /// for a journal.
    private func biometricOptInView(pin: String) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "faceid")
                .font(.system(size: 64))
                .foregroundColor(.pink)

            VStack(spacing: 12) {
                Text("Unlock faster?")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Use \(authManager.biometryDisplayName) to open GJournal instead of typing your PIN each time. Your PIN still works, and you can change this later in Settings.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                Button {
                    finishRegistration(pin: pin, enableBiometric: true)
                } label: {
                    Text("Enable \(authManager.biometryDisplayName)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.pink)
                        .cornerRadius(14)
                }

                Button {
                    finishRegistration(pin: pin, enableBiometric: false)
                } label: {
                    Text("Not now")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 32)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    // MARK: - Actions

    /// This screen is only reachable when no account exists — `GJournalApp`
    /// routes registered users straight to `BiometricLockView`. So there is no
    /// login branch here, only registration.
    private func continueWithName() async {
        guard isNameValid else { return }
        isLoading = true
        errorMessage = nil

        try? await Task.sleep(nanoseconds: 200_000_000)

        withAnimation { step = .pinSetup }

        isLoading = false
    }

    /// Registration is the last step: `completeRegistration` flips
    /// `isAuthenticated`, at which point `GJournalApp` replaces this view. So the
    /// biometric choice has to be collected *before* we call it.
    private func finishRegistration(pin: String, enableBiometric: Bool) {
        do {
            try authManager.completeRegistration(name: name, pin: pin)
            authManager.isBiometricEnabled = enableBiometric
        } catch let error as AuthError {
            errorMessage = error.errorDescription
            withAnimation { step = .name }
        } catch {
            errorMessage = "Registration failed. Please try again."
            withAnimation { step = .name }
        }
    }

    private var isNameValid: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
