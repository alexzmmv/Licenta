import SwiftUI
import SwiftData

private enum ForgotPINStep {
    case options
    case enterNew
    case confirmNew(first: String)
    case success
    case confirmErase
}

/// Recovery for a forgotten PIN.
///
/// Before this existed, a user who forgot their PIN with biometrics disabled had
/// no path back into the app at all — the only escape was deleting the app,
/// which destroyed the journal. There is deliberately no backdoor into the data:
/// either you prove identity with biometrics, or you erase and start over.
struct ForgotPINView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var step: ForgotPINStep = .options
    @State private var errorMessage: String?
    @State private var eraseConfirmation = ""
    @State private var isAuthenticating = false

    private var biometricAvailable: Bool {
        authManager.isBiometricEnabled && authManager.canUseBiometric()
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .options:              optionsView
                case .enterNew:             enterNewView
                case .confirmNew(let first): confirmNewView(first: first)
                case .success:              successView
                case .confirmErase:         confirmEraseView
                }
            }
            .navigationTitle("Forgot PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .success = step { } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Options

    private var optionsView: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: biometricAvailable ? "faceid" : "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundColor(biometricAvailable ? .pink : .orange)

            VStack(spacing: 10) {
                Text(biometricAvailable ? "Verify it's you" : "No way to verify you")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(biometricAvailable
                     ? "Unlock with \(authManager.biometryDisplayName) to choose a new PIN. Your entries stay exactly as they are."
                     : "Your entries are encrypted behind your PIN and there's no way to recover them without it. You can start over with a new account, but everything currently in your journal will be permanently erased.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                if biometricAvailable {
                    Button {
                        Task { await verifyBiometric() }
                    } label: {
                        Group {
                            if isAuthenticating {
                                ProgressView().tint(.white)
                            } else {
                                Text("Unlock with \(authManager.biometryDisplayName)")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.pink)
                        .cornerRadius(14)
                    }
                    .disabled(isAuthenticating)
                }

                Button(role: .destructive) {
                    eraseConfirmation = ""
                    withAnimation { step = .confirmErase }
                } label: {
                    Text("Erase & Start Over")
                        .fontWeight(biometricAvailable ? .regular : .semibold)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.red.opacity(biometricAvailable ? 0.0 : 0.15))
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - New PIN

    private var enterNewView: some View {
        PINKeypadView(
            title: "New PIN",
            subtitle: "Choose a new 6-digit PIN",
            errorMessage: errorMessage,
            onCancel: { withAnimation { step = .options } }
        ) { pin in
            errorMessage = nil
            withAnimation { step = .confirmNew(first: pin) }
        }
    }

    private func confirmNewView(first: String) -> some View {
        PINKeypadView(
            title: "Confirm new PIN",
            subtitle: "Re-enter the new PIN",
            errorMessage: errorMessage,
            onCancel: { withAnimation { step = .enterNew } }
        ) { pin in
            guard pin == first else {
                errorMessage = "PINs don't match — try again"
                withAnimation { step = .enterNew }
                return
            }
            do {
                try authManager.resetPINAfterBiometric(newPIN: pin)
                errorMessage = nil
                withAnimation { step = .success }
            } catch let error as AuthError {
                errorMessage = error.errorDescription
                withAnimation { step = .enterNew }
            } catch {
                errorMessage = "Couldn't set your new PIN. Please try again."
                withAnimation { step = .enterNew }
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)
            Text("PIN updated")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Your journal is unchanged.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Done") {
                authManager.completeSessionAuthentication()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
    }

    // MARK: - Destructive erase

    private var confirmEraseView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "trash.fill")
                .font(.system(size: 56))
                .foregroundColor(.red)

            VStack(spacing: 10) {
                Text("Erase everything?")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("This permanently deletes every journal entry, all AI analysis, and your account on this device. It cannot be undone.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 8) {
                Text("Type DELETE to confirm")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("DELETE", text: $eraseConfirmation)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 200)
            }

            Button(role: .destructive) {
                eraseEverything()
            } label: {
                Text("Erase Everything")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(eraseConfirmation == "DELETE" ? Color.red : Color.red.opacity(0.3))
                    .cornerRadius(14)
            }
            .disabled(eraseConfirmation != "DELETE")
            .padding(.horizontal, 32)

            Button("Back") { withAnimation { step = .options } }
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    // MARK: - Actions

    private func verifyBiometric() async {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }
        do {
            let success = try await authManager.authenticateWithBiometric()
            if success {
                withAnimation { step = .enterNew }
            } else {
                errorMessage = "Couldn't verify you. Please try again."
            }
        } catch {
            errorMessage = "Couldn't verify you. Please try again."
        }
    }

    private func eraseEverything() {
        AccountEraser.eraseAll(modelContext: modelContext, authManager: authManager)
        dismiss()
    }
}

#Preview {
    ForgotPINView()
        .environmentObject(AuthManager())
}
