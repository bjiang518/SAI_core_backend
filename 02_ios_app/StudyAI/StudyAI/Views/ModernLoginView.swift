//
//  ModernLoginView.swift
//  StudyAI
//
//  Created by Claude Code on 9/5/25.
//

import SwiftUI
import AuthenticationServices

struct ModernLoginView: View {
    @StateObject private var authService = AuthenticationService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var showingSignUp = false
    @State private var showingError = false
    @FocusState private var focusedField: Field?
    
    var onLoginSuccess: () -> Void
    
    enum Field {
        case email, password
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // Header Section
                    headerSection
                        .frame(height: geometry.size.height * 0.35)
                    
                    // Authentication Section
                    authenticationSection
                        .frame(minHeight: geometry.size.height * 0.65)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .alert("Authentication Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(authService.errorMessage ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showingSignUp) {
            ModernSignUpView(onSignUpSuccess: onLoginSuccess)
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                onLoginSuccess()
            }
        }
        .onChange(of: authService.errorMessage) { _, errorMessage in
            if errorMessage != nil {
                showingError = true
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.blue.opacity(0.8), .purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 16) {
                Spacer()
                
                // App icon and title
                VStack(spacing: 12) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                    
                    Text("StudyAI")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Your AI-Powered Learning Companion")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Authentication Section
    
    private var authenticationSection: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                // Welcome text
                VStack(spacing: 8) {
                    Text("Welcome Back")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Sign in to continue your learning journey")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                
                // Biometric authentication (if available)
                if authService.canUseBiometrics() {
                    biometricSignInButton
                }
                
                // Social authentication buttons
                socialAuthButtons
                
                // Divider
                dividerWithText("or continue with email")
                
                // Email authentication form
                emailAuthForm
                
                // Sign up prompt
                signUpPrompt
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .offset(y: -25)
    }
    
    // MARK: - Biometric Sign In
    
    private var biometricSignInButton: some View {
        Button {
            Task {
                do {
                    try await authService.signInWithBiometrics()
                } catch {
                    authService.errorMessage = error.localizedDescription
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: authService.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                    .font(.title2)
                
                Text("Sign in with \(authService.getBiometricType())")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green.opacity(0.1))
            .foregroundColor(.green)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .disabled(authService.isLoading)
    }
    
    // MARK: - Social Authentication
    
    private var socialAuthButtons: some View {
        VStack(spacing: 12) {
            // Apple Sign In - Only show if capability is available
            if isAppleSignInAvailable {
                SignInWithAppleButton(
                    onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                    },
                    onCompletion: { result in
                        Task {
                            do {
                                try await authService.signInWithApple()
                            } catch {
                                authService.errorMessage = error.localizedDescription
                            }
                        }
                    }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 45)
                .cornerRadius(12)
            }
            
            // Google Sign In (placeholder)
            Button {
                Task {
                    do {
                        try await authService.signInWithGoogle()
                    } catch {
                        authService.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.title2)
                    
                    Text("Continue with Google")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }
            .disabled(authService.isLoading)
        }
    }
    
    // MARK: - Email Authentication Form
    
    private var emailAuthForm: some View {
        VStack(spacing: 16) {
            // Email field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                TextField("Enter your email", text: $email)
                    .textFieldStyle(ModernTextFieldStyle())
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                    .onSubmit {
                        focusedField = .password
                    }
            }
            
            // Password field
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                SecureField("Enter your password", text: $password)
                    .textFieldStyle(ModernTextFieldStyle())
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit {
                        signInWithEmail()
                    }
            }
            
            // Sign in button
            Button {
                signInWithEmail()
            } label: {
                HStack {
                    if authService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    isFormValid ? Color.blue : Color.gray.opacity(0.3)
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!isFormValid || authService.isLoading)
        }
    }
    
    // MARK: - Sign Up Prompt
    
    private var signUpPrompt: some View {
        HStack {
            Text("Don't have an account?")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Sign Up") {
                showingSignUp = true
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.blue)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helper Views
    
    private func dividerWithText(_ text: String) -> some View {
        HStack {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.3))
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
            
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.3))
        }
    }
    
    // MARK: - Helper Properties
    
    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }
    
    private var isAppleSignInAvailable: Bool {
        // Check if the app has Apple Sign-In capability
        // This will be false for personal development teams
        return Bundle.main.bundleIdentifier != nil && Bundle.main.object(forInfoDictionaryKey: "com.apple.developer.applesignin") != nil
    }
    
    // MARK: - Actions
    
    private func signInWithEmail() {
        guard isFormValid else { return }
        
        focusedField = nil
        
        Task {
            do {
                try await authService.signInWithEmail(email, password: password)
            } catch {
                authService.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Modern Text Field Style

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
    }
}

// MARK: - Modern Sign Up View

struct ModernSignUpView: View {
    @StateObject private var authService = AuthenticationService.shared
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showingError = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss
    
    var onSignUpSuccess: () -> Void
    
    enum Field {
        case name, email, password, confirmPassword
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Create Account")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Join StudyAI and start your learning journey")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)
                    
                    // Form fields
                    VStack(spacing: 16) {
                        // Name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Full Name")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            TextField("Enter your full name", text: $name)
                                .textFieldStyle(ModernTextFieldStyle())
                                .textContentType(.name)
                                .focused($focusedField, equals: .name)
                                .onSubmit { focusedField = .email }
                        }
                        
                        // Email field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            TextField("Enter your email", text: $email)
                                .textFieldStyle(ModernTextFieldStyle())
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .focused($focusedField, equals: .email)
                                .onSubmit { focusedField = .password }
                        }
                        
                        // Password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            SecureField("Create a password", text: $password)
                                .textFieldStyle(ModernTextFieldStyle())
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .password)
                                .onSubmit { focusedField = .confirmPassword }
                        }
                        
                        // Confirm password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            SecureField("Confirm your password", text: $confirmPassword)
                                .textFieldStyle(ModernTextFieldStyle())
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .confirmPassword)
                                .onSubmit { signUp() }
                        }
                        
                        // Password validation
                        if !password.isEmpty {
                            passwordValidationView
                        }
                    }
                    
                    // Sign up button
                    Button {
                        signUp()
                    } label: {
                        HStack {
                            if authService.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            
                            Text("Create Account")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            isFormValid ? Color.green : Color.gray.opacity(0.3)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!isFormValid || authService.isLoading)
                    
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Sign Up Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(authService.errorMessage ?? "An unknown error occurred")
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                dismiss()
                onSignUpSuccess()
            }
        }
        .onChange(of: authService.errorMessage) { _, errorMessage in
            if errorMessage != nil {
                showingError = true
            }
        }
    }
    
    // MARK: - Password Validation View
    
    private var passwordValidationView: some View {
        VStack(alignment: .leading, spacing: 4) {
            PasswordRequirement(
                text: "At least 6 characters",
                isMet: password.count >= 6
            )
            
            PasswordRequirement(
                text: "Passwords match",
                isMet: !confirmPassword.isEmpty && password == confirmPassword
            )
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helper Properties
    
    private var isFormValid: Bool {
        !name.isEmpty &&
        !email.isEmpty &&
        email.contains("@") &&
        password.count >= 6 &&
        password == confirmPassword
    }
    
    // MARK: - Actions
    
    private func signUp() {
        guard isFormValid else { return }
        
        focusedField = nil
        
        Task {
            do {
                try await authService.signUpWithEmail(name, email: email, password: password)
            } catch {
                authService.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Password Requirement View

struct PasswordRequirement: View {
    let text: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(isMet ? .green : .gray)
            
            Text(text)
                .font(.caption)
                .foregroundColor(isMet ? .green : .secondary)
        }
    }
}

#Preview {
    ModernLoginView(onLoginSuccess: {})
}