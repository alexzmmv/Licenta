//
//  LoginView.swift
//  GJournal
//
//  First-launch: enter name, then set a 6-digit PIN.
//  Returning users: enter name to re-link, then BiometricLockView handles auth.
//

import SwiftUI

private enum LoginStep {
    case name
    case pinSetup
    case pinConfirm(first: String)
}

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var step: LoginStep = .name
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Background
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
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: stepIndex)
    }

    private var stepIndex: Int {
        switch step {
        case .name:        return 0
        case .pinSetup:    return 1
        case .pinConfirm:  return 2
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
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Your private emotional journal")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .padding(.bottom, 52)

            // Form
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
                    finishRegistration(pin: pin)
                } else {
                    errorMessage = "PINs don't match — try again"
                    withAnimation { step = .pinSetup }
                }
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func continueWithName() async {
        guard isNameValid else { return }
        isLoading = true
        errorMessage = nil

        try? await Task.sleep(nanoseconds: 200_000_000)

        do {
            if authManager.isUserRegistered() {
                // Returning user: verify name, then BiometricLockView handles auth
                try authManager.loginWithNameOnly(name: name)
            } else {
                // New user: go to PIN setup
                withAnimation { step = .pinSetup }
            }
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }

        isLoading = false
    }

    private func finishRegistration(pin: String) {
        do {
            try authManager.completeRegistration(name: name, pin: pin)
            if authManager.canUseBiometric() {
                authManager.isBiometricEnabled = true
            }
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
