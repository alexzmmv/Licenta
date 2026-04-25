//
//  LoginView.swift
//  GJournal
//
//  Simplified auth: email entry only, then biometric or passcode.
//  No password required — privacy-first, device-secured access.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Rich dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                    Color(red: 0.10, green: 0.04, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle radial glow
            Circle()
                .fill(Color.pink.opacity(0.15))
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: -60, y: -120)

            VStack(spacing: 0) {
                Spacer()

                // Logo & branding
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

                // Name form
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
                                .autocapitalization(.words)
                                .disableAutocorrection(true)
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
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                            Text(error)
                                .font(.caption)
                        }
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(10)
                    }

                    // Continue button
                    Button {
                        Task { await continueWithName() }
                    } label: {
                        HStack(spacing: 10) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .scaleEffect(0.85)
                            } else {
                                Image(systemName: authManager.canUseBiometric() ? "faceid" : "lock.fill")
                                Text("Continue")
                                    .fontWeight(.semibold)
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
                    .disabled(isLoading || !isValidName(name))
                    .opacity(isValidName(name) ? 1.0 : 0.5)
                    .animation(.easeInOut(duration: 0.2), value: isValidName(name))
                }
                .padding(.horizontal, 32)

                Spacer()

                // Privacy note
                VStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.6))

                    Text("All data stays on your device")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.5))
                }
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func continueWithName() async {
        guard isValidName(name) else {
            errorMessage = "Please enter a valid name (at least 2 characters)"
            return
        }

        isLoading = true
        errorMessage = nil

        // Brief haptic feedback simulation delay
        try? await Task.sleep(nanoseconds: 200_000_000)

        do {
            // Register if new user, login if existing
            if authManager.isUserRegistered() {
                try authManager.loginWithNameOnly(name: name)
            } else {
                try authManager.registerWithNameOnly(name: name)
            }

            // Enable biometric if available
            if authManager.canUseBiometric() {
                authManager.isBiometricEnabled = true
            }
        } catch let error as AuthError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }

        isLoading = false
    }

    private func isValidName(_ name: String) -> Bool {
        return name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
