//
//  LoginView.swift
//  GJournal
//
//  Created for user authentication
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingRegister = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Logo/Header
                        VStack(spacing: 12) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.pink)
                            
                            Text("GJournal")
                                .font(.system(size: 36, weight: .bold))
                            
                            Text("Your emotional journey")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
                        .padding(.bottom, 20)
                        
                        // Login Form
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
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                SecureField("Enter password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.password)
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
                                    await login()
                                }
                            } label: {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                } else {
                                    Text("Log In")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.pink.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .disabled(isLoading || email.isEmpty || password.isEmpty)
                            
                            Button {
                                showingRegister = true
                            } label: {
                                Text("Don't have an account? Sign up")
                                    .font(.subheadline)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 32)
                        
                        Spacer()
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingRegister) {
                RegisterView()
            }
        }
    }
    
    private func login() async {
        isLoading = true
        errorMessage = nil
        
        // Simulate network delay for better UX
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        do {
            try authManager.loginLocal(email: email, password: password)
            
            // Enable biometric by default if available
            if authManager.canUseBiometric() {
                authManager.isBiometricEnabled = true
            }
        } catch let error as AuthError {
            errorMessage = error.errorDescription ?? "Login failed"
        } catch {
            errorMessage = "Login failed. Please try again."
        }
        
        isLoading = false
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
