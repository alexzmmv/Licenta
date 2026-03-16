//
//  RegisterView.swift
//  GJournal
//
//  Created for user registration
//

import SwiftUI

struct RegisterView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccessMessage = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 60))
                                .foregroundColor(.pink)
                            
                            Text("Create Account")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Start your emotional journey")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
                        .padding(.bottom, 20)
                        
                        // Registration Form
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                TextField("email@example.com", text: $email)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.emailAddress)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                
                                if !email.isEmpty && !isValidEmail(email) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.caption)
                                        Text("Invalid email format")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.orange)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                SecureField("Enter password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.newPassword)
                                
                                if !password.isEmpty && password.count < 6 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.caption)
                                        Text("Minimum 6 characters")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.orange)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Confirm Password")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                SecureField("Confirm password", text: $confirmPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.newPassword)
                                
                                if !confirmPassword.isEmpty && password != confirmPassword {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.caption)
                                        Text("Passwords don't match")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.orange)
                                }
                            }
                            
                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                            }
                            
                            Button {
                                Task {
                                    await register()
                                }
                            } label: {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                } else {
                                    Text("Create Account")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.pink.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .disabled(isLoading || !isValidForm)
                            
                            Button {
                                dismiss()
                            } label: {
                                Text("Already have an account? Log in")
                                    .font(.subheadline)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var isValidForm: Bool {
        !email.isEmpty &&
        isValidEmail(email) &&
        !password.isEmpty &&
        password.count >= 6 &&
        !confirmPassword.isEmpty &&
        password == confirmPassword
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailPattern = "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", emailPattern)
        return predicate.evaluate(with: email)
    }
    
    private func register() async {
        isLoading = true
        errorMessage = nil
        
        // Simulate network delay for better UX
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        do {
            try authManager.registerLocal(email: email, password: password)
            
            // Enable biometric by default for new users
            if authManager.canUseBiometric() {
                authManager.isBiometricEnabled = true
            }
            
            showSuccessMessage = true
            
            // Dismiss after a short delay to show success
            try? await Task.sleep(nanoseconds: 500_000_000)
            dismiss()
        } catch let error as AuthError {
            errorMessage = error.errorDescription ?? "Registration failed"
        } catch {
            errorMessage = "Registration failed. Please try again."
        }
        
        isLoading = false
    }
}

#Preview {
    RegisterView()
        .environmentObject(AuthManager())
}
