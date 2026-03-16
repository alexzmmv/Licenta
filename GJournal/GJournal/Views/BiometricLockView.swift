//
//  BiometricLockView.swift
//  GJournal
//
//  Biometric/Passcode authentication screen
//

import SwiftUI
import LocalAuthentication

struct BiometricLockView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showLogoutConfirmation = false
    
    var body: some View {
        Group {
            // Show main app if session is authenticated
            if authManager.isSessionAuthenticated {
                MainAppView()
                    .environmentObject(authManager)
            } else {
                // Show lock screen
                lockScreenView
            }
        }
        .onAppear {
            // Auto-trigger authentication if we need it
            if authManager.isAuthenticated && !authManager.isSessionAuthenticated {
                if authManager.isBiometricEnabled {
                    Task {
                        await authenticate()
                    }
                } else {
                    // Biometrics disabled, allow access immediately
                    authManager.completeSessionAuthentication()
                }
            }
        }
    }
    
    private var lockScreenView: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Lock icon
                Image(systemName: authManager.canUseBiometric() ? "faceid" : "lock.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.pink)
                
                VStack(spacing: 12) {
                    Text("GJournal")
                        .font(.system(size: 36, weight: .bold))
                    
                    Text(authManager.canUseBiometric() ? "Use Face ID to unlock" : "Use Passcode to unlock")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Unlock button
                Button {
                    Task {
                        await authenticate()
                    }
                } label: {
                    HStack {
                        Image(systemName: authManager.canUseBiometric() ? "faceid" : "lock.open")
                        Text("Unlock")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.pink.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                
                // Logout button
                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    Text("Log Out")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .alert("Authentication Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .confirmationDialog("Log Out", isPresented: $showLogoutConfirmation) {
                Button("Log Out", role: .destructive) {
                    authManager.logout()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to log out?")
            }
        }
    }
    
    private func authenticate() async {
        do {
            let success = try await authManager.authenticateWithBiometric()
            if success {
                authManager.completeSessionAuthentication()
            } else {
                errorMessage = "Authentication failed. Please try again."
                showError = true
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                errorMessage = "Authentication was canceled."
                showError = true
            case .biometryNotAvailable, .biometryNotEnrolled:
                // Fallback to passcode for this session
                do {
                    let success = try await authManager.authenticateWithPasscode()
                    if success {
                        authManager.completeSessionAuthentication()
                    }
                } catch {
                    errorMessage = "Passcode authentication failed."
                    showError = true
                }
            case .passcodeNotSet:
                // No passcode set - allow access
                authManager.completeSessionAuthentication()
            default:
                errorMessage = "Authentication failed: \(error.localizedDescription)"
                showError = true
            }
        } catch {
            errorMessage = "Authentication failed. Please try again."
            showError = true
        }
    }
}

#Preview {
    BiometricLockView()
        .environmentObject(AuthManager())
        .preferredColorScheme(.light)
}
