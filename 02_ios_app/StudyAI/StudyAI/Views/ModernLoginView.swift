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
    @State private var showingFaceIDPrompt = false
    @State private var isPasswordVisible = false  // ✅ Password visibility toggle
    @FocusState private var focusedField: Field?
    @State private var keyboardHeight: CGFloat = 0  // Track keyboard height

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
            .scrollDismissesKeyboard(.interactively)  // ✅ Dismiss keyboard on scroll
            .onTapGesture {
                // ✅ Dismiss keyboard when tapping whitespace
                hideKeyboard()
            }
            .ignoresSafeArea(.container, edges: .top)
            .background(Color(.systemBackground))  // ✅ Adaptive background for dark mode
        }
        .alert(NSLocalizedString("auth.error.title", comment: "Authentication error alert title"), isPresented: $showingError) {
            Button(NSLocalizedString("common.ok", comment: "OK button")) { }
        } message: {
            Text(authService.errorMessage ?? NSLocalizedString("auth.error.unknown", comment: "Unknown error message"))
        }
        .alert(String(format: NSLocalizedString("login.enableBiometric", comment: "Enable biometric prompt"), authService.getBiometricType()), isPresented: $showingFaceIDPrompt) {
            Button(NSLocalizedString("login.enable", comment: "Enable button")) {
                Task {
                    do {
                        try await authService.enableFaceID()
                        // Navigate to main app after enabling
                        onLoginSuccess()
                    } catch {
                        print("Failed to enable Face ID: \(error.localizedDescription)")
                        // Navigate anyway even if Face ID setup failed
                        onLoginSuccess()
                    }
                }
            }
            Button(NSLocalizedString("login.notNow", comment: "Not now button"), role: .cancel) {
                // Navigate to main app without enabling Face ID
                onLoginSuccess()
            }
        } message: {
            Text(String(format: NSLocalizedString("login.biometricMessage", comment: "Biometric signin message"), authService.getBiometricType()))
        }
        .sheet(isPresented: $showingSignUp) {
            ModernSignUpView(onSignUpSuccess: onLoginSuccess)
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                // Clear any error messages
                authService.errorMessage = nil

                // Check if we should prompt for Face ID setup
                if authService.shouldPromptForFaceIDSetup() {
                    showingFaceIDPrompt = true
                } else {
                    // User is authenticated, navigate to main app
                    onLoginSuccess()
                }
            }
        }
        .onChange(of: authService.errorMessage) { _, newValue in
            // Only show error alerts for actual errors, not nil
            showingError = newValue != nil
        }
        .onAppear {
            // Pre-fill email if user just registered successfully
            if let registeredEmail = authService.lastRegisteredEmail {
                email = registeredEmail
                // Clear the stored email after using it
                authService.lastRegisteredEmail = nil
                // Focus on password field since email is already filled
                focusedField = .password
            }

            // Clear any error messages when view appears
            authService.errorMessage = nil

            // Auto-trigger Face ID if enabled
            if authService.isFaceIDEnabled() {
                Task {
                    do {
                        try await authService.signInWithBiometrics()
                    } catch {
                        // If Face ID fails, just show the login screen
                        // Don't show error to avoid annoying the user
                        print("Face ID auto-login failed: \(error.localizedDescription)")
                    }
                }
            }

            // Monitor keyboard notifications
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillShowNotification,
                object: nil,
                queue: .main
            ) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    keyboardHeight = keyboardFrame.height
                }
            }

            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { _ in
                keyboardHeight = 0
            }
        }
        .onDisappear {
            // Clean up keyboard observers
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        ZStack {
            // Background - Cute mode blue
            DesignTokens.Colors.Cute.blue
            
            VStack(spacing: 16) {
                Spacer()
                
                // App icon and title
                VStack(spacing: 12) {
                    Text("StudyMates")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text(NSLocalizedString("app.tagline", comment: "App tagline"))
                        .font(.title2)
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
                    Text(NSLocalizedString("auth.login.welcome", comment: "Welcome back title"))
                        .font(.title)
                        .foregroundColor(.primary)

                    Text(NSLocalizedString("auth.login.subtitle", comment: "Welcome message"))
                        .font(.body)
                        .foregroundColor(.secondary)  // ✅ Adaptive for dark mode
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                // Biometric authentication (if enabled)
                if authService.isFaceIDEnabled() && authService.canUseBiometrics() {
                    biometricSignInButton
                }

                // Social authentication buttons
                socialAuthButtons

                // Divider
                dividerWithText(NSLocalizedString("auth.login.orContinueWithEmail", comment: "Or continue with email divider text"))

                // Email authentication form
                emailAuthForm

                // Sign up prompt
                signUpPrompt
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .background(Color(.systemBackground))  // ✅ Adaptive background
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .offset(y: -30)
        .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - 50 : 0)  // ✅ Push content up when keyboard appears
        .animation(.easeOut(duration: 0.3), value: keyboardHeight)  // ✅ Smooth keyboard animation
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

                Text(String(format: NSLocalizedString("login.signInWithBiometric", comment: "Sign in with biometric"), authService.getBiometricType()))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green.opacity(0.1))
            .foregroundColor(.green)
            .clipShape(Capsule())
        }
        .disabled(authService.isLoading)
    }
    
    // MARK: - Social Authentication
    
    private var socialAuthButtons: some View {
        VStack(spacing: 12) {
            // Apple Sign In - Custom styled button
            Button {
                print("🍎🍎🍎 === CUSTOM APPLE BUTTON TAPPED ===")
                // Trigger Apple Sign-In
                Task {
                    await performAppleSignIn()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)

                    Text(NSLocalizedString("login.continueWithApple", comment: "Continue with Apple button"))
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)  // ✅ Add visible white border
                )
                .shadow(color: Color.white.opacity(0.15), radius: 8, x: 0, y: 2)  // ✅ Add glow effect
            }
            .disabled(authService.isLoading)

            // Google Sign In
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
                    // Google logo
                    GoogleLogoView()
                        .frame(width: 20, height: 20)

                    Text(NSLocalizedString("auth.continueWithGoogle", comment: "Continue with Google button"))
                        .font(.headline)
                        .foregroundColor(.primary)  // ✅ Adaptive text color
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))  // ✅ Adaptive background
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)  // ✅ Adaptive border
                )
                .shadow(color: Color.primary.opacity(0.1), radius: 5, x: 0, y: 5)  // ✅ Adaptive shadow
            }
            .disabled(authService.isLoading)
        }
    }
    
    // MARK: - Email Authentication Form

    private var emailAuthForm: some View {
        VStack(spacing: 16) {
            // Email field
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("auth.emailAddress", comment: "Email address label"))
                    .font(.caption)
                    .foregroundColor(.secondary)  // ✅ Adaptive

                TextField(NSLocalizedString("auth.enterEmail", comment: "Enter email placeholder"), text: $email)
                    .textFieldStyle(PlayfulTextFieldStyle())
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
                Text(NSLocalizedString("auth.password", comment: "Password label"))
                    .font(.caption)
                    .foregroundColor(.secondary)  // ✅ Adaptive

                HStack {
                    if isPasswordVisible {
                        TextField(NSLocalizedString("auth.enterPassword", comment: "Enter password placeholder"), text: $password)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit {
                                signInWithEmail()
                            }
                    } else {
                        SecureField(NSLocalizedString("auth.enterPassword", comment: "Enter password placeholder"), text: $password)
                            .textContentType(.password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit {
                                signInWithEmail()
                            }
                    }

                    // ✅ Password visibility toggle button
                    Button(action: {
                        isPasswordVisible.toggle()
                    }) {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary)  // ✅ Adaptive
                            .font(.system(size: 16))
                    }
                    .padding(.trailing, 12)
                }
                .textFieldStyle(PlayfulTextFieldStyle())
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

                    Text(NSLocalizedString("auth.signIn", comment: "Sign in button"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    isFormValid ? Color.blue : Color.gray.opacity(0.5)
                )
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: .blue.opacity(isFormValid ? 0.4 : 0), radius: 10, y: 5)
            }
            .disabled(!isFormValid || authService.isLoading)
        }
    }
    
    // MARK: - Sign Up Prompt
    
    private var signUpPrompt: some View {
        HStack {
            Text(NSLocalizedString("auth.dontHaveAccount", comment: "Don't have account text"))
                .font(.caption)
                .foregroundColor(.secondary)  // ✅ Adaptive

            Button(NSLocalizedString("auth.signUp", comment: "Sign up button")) {
                showingSignUp = true
            }
            .font(.headline)
            .foregroundColor(.blue)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helper Views
    
    private func dividerWithText(_ text: String) -> some View {
        HStack {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.secondary.opacity(0.3))  // ✅ Adaptive

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)  // ✅ Adaptive
                .padding(.horizontal, 8)
                .fixedSize()

            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.secondary.opacity(0.3))  // ✅ Adaptive
        }
    }
    
    // MARK: - Helper Properties

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }

    // MARK: - Actions

    private func signInWithEmail() {
        guard isFormValid else { return }

        focusedField = nil

        // Clear any previous error messages
        authService.errorMessage = nil

        Task {
            do {
                try await authService.signInWithEmail(email, password: password)
            } catch {
                authService.errorMessage = error.localizedDescription
            }
        }
    }

    private func performAppleSignIn() async {
        print("🍎🍎🍎 === ModernLoginView: Performing Apple Sign-In ===")
        print("🍎🍎🍎 === Using AuthenticationService.signInWithApple() ===")

        do {
            // Use the proper authentication service method that calls the backend
            try await authService.signInWithApple()
            print("🍎🍎🍎 ✅ Apple Sign-In completed successfully via AuthenticationService")
        } catch {
            print("🍎🍎🍎 ❌ Apple Sign-In failed: \(error)")
            let nsError = error as NSError
            if nsError.code == ASAuthorizationError.canceled.rawValue {
                print("🍎🍎🍎 User cancelled")
                return
            }
            await MainActor.run {
                authService.errorMessage = error.localizedDescription
            }
        }
    }

    private func handleMinimalAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            switch result {
            case .success(let authorization):
                print("🍎🍎🍎 ✅ Success! Got authorization")

                guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    print("🍎🍎🍎 ❌ Invalid credential type")
                    await MainActor.run {
                        authService.errorMessage = "Invalid Apple ID credential"
                    }
                    return
                }

                print("🍎🍎🍎 User ID: \(appleIDCredential.user)")
                print("🍎🍎🍎 Email: \(appleIDCredential.email ?? "nil")")

                // Create user
                let user = User(
                    id: appleIDCredential.user,
                    email: appleIDCredential.email ?? "apple_user@icloud.com",
                    name: appleIDCredential.fullName?.givenName ?? "Apple User",
                    profileImageURL: nil,
                    authProvider: .apple,
                    createdAt: Date(),
                    lastLoginAt: Date()
                )

                // Save credentials
                let token = "apple_token_\(UUID().uuidString)"
                try KeychainService.shared.saveAuthToken(token)
                try KeychainService.shared.saveUser(user)

                print("🍎🍎🍎 ✅ Saved to keychain")

                // Update auth state
                await MainActor.run {
                    authService.currentUser = user
                    authService.isAuthenticated = true
                    print("🍎🍎🍎 ✅ Auth state updated")
                }

            case .failure(let error):
                print("🍎🍎🍎 ❌ Sign-in failed: \(error)")
                let nsError = error as NSError
                if nsError.code == ASAuthorizationError.canceled.rawValue {
                    print("🍎🍎🍎 User cancelled")
                    return
                }
                await MainActor.run {
                    authService.errorMessage = error.localizedDescription
                }
            }
        } catch {
            print("🍎🍎🍎 ❌ Exception: \(error)")
            await MainActor.run {
                authService.errorMessage = error.localizedDescription
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Playful Text Field Style

struct PlayfulTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) var colorScheme

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.body)
            .foregroundColor(.primary)  // ✅ Adaptive text color
            .padding()
            .background(Color(.secondarySystemBackground))  // ✅ Adaptive background
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 1.5)  // ✅ Adaptive border
            )
            .shadow(color: Color.primary.opacity(0.05), radius: 3, y: 2)  // ✅ Adaptive shadow
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
    @State private var showingVerification = false
    @State private var isPasswordVisible = false  // ✅ Password visibility toggle
    @State private var isConfirmPasswordVisible = false  // ✅ Confirm password visibility toggle
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
                        Text("Create Your Account")
                            .font(.title)
                            .foregroundColor(.primary)  // ✅ Adaptive for dark mode

                        Text("Join Study Mates to start your learning adventure!")
                            .font(.body)
                            .foregroundColor(.secondary)  // ✅ Adaptive for dark mode
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)

                    // Form fields
                    VStack(spacing: 16) {
                        // Name field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Full Name")
                                .font(.caption)
                                .foregroundColor(.secondary)  // ✅ Adaptive

                            TextField("Enter your full name", text: $name)
                                .textFieldStyle(PlayfulTextFieldStyle())
                                .textContentType(.name)
                                .focused($focusedField, equals: .name)
                                .onSubmit { focusedField = .email }
                        }

                        // Email field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email Address")
                                .font(.caption)
                                .foregroundColor(.secondary)  // ✅ Adaptive

                            TextField("Enter your email", text: $email)
                                .textFieldStyle(PlayfulTextFieldStyle())
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .focused($focusedField, equals: .email)
                                .onSubmit { focusedField = .password }
                        }

                        // Password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.caption)
                                .foregroundColor(.secondary)  // ✅ Adaptive

                            HStack {
                                if isPasswordVisible {
                                    TextField("Must include A-z, 0-9, !@#$", text: $password)
                                        .textContentType(.newPassword)
                                        .focused($focusedField, equals: .password)
                                        .onSubmit { focusedField = .confirmPassword }
                                } else {
                                    SecureField("Must include A-z, 0-9, !@#$", text: $password)
                                        .textContentType(.newPassword)
                                        .focused($focusedField, equals: .password)
                                        .onSubmit { focusedField = .confirmPassword }
                                }

                                // ✅ Password visibility toggle button
                                Button(action: {
                                    isPasswordVisible.toggle()
                                }) {
                                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.secondary)  // ✅ Adaptive
                                        .font(.system(size: 16))
                                }
                                .padding(.trailing, 12)
                            }
                            .textFieldStyle(PlayfulTextFieldStyle())
                        }

                        // Confirm password field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .font(.caption)
                                .foregroundColor(.secondary)  // ✅ Adaptive

                            HStack {
                                if isConfirmPasswordVisible {
                                    TextField("Confirm your password", text: $confirmPassword)
                                        .textContentType(.newPassword)
                                        .focused($focusedField, equals: .confirmPassword)
                                        .onSubmit { signUp() }
                                } else {
                                    SecureField("Confirm your password", text: $confirmPassword)
                                        .textContentType(.newPassword)
                                        .focused($focusedField, equals: .confirmPassword)
                                        .onSubmit { signUp() }
                                }

                                // ✅ Password visibility toggle button
                                Button(action: {
                                    isConfirmPasswordVisible.toggle()
                                }) {
                                    Image(systemName: isConfirmPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.secondary)  // ✅ Adaptive
                                        .font(.system(size: 16))
                                }
                                .padding(.trailing, 12)
                            }
                            .textFieldStyle(PlayfulTextFieldStyle())
                        }

                        // Password validation
                        if !password.isEmpty {
                            passwordValidationView
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: password.isEmpty)

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
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            isFormValid ? Color.green : Color.gray.opacity(0.5)
                        )
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: .green.opacity(isFormValid ? 0.4 : 0), radius: 10, y: 5)
                    }
                    .disabled(!isFormValid || authService.isLoading)

                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .scrollDismissesKeyboard(.interactively)  // ✅ Dismiss keyboard on scroll
            .background(Color(.systemBackground))  // ✅ Adaptive background for dark mode
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline)
                }
            }
            .onTapGesture {
                // Dismiss keyboard when tapping anywhere
                hideKeyboard()
            }
        }
        .alert("Sign Up Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(authService.errorMessage ?? "An unknown error occurred")
        }
        .sheet(isPresented: $showingVerification) {
            EmailVerificationView(
                email: email,
                name: name,
                password: password,
                onVerificationSuccess: {
                    // This callback is no longer needed since AuthenticationService
                    // automatically sets isAuthenticated = true on successful verification
                    // The .onChange(of: isAuthenticated) below will handle the navigation
                }
            )
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                // Clear any lingering error messages
                authService.errorMessage = nil

                // User is now authenticated, dismiss sign-up flow
                dismiss()
                onSignUpSuccess()
            }
        }
        .onAppear {
            // Clear any error messages when sign-up view appears
            authService.errorMessage = nil
        }
    }
    
    // MARK: - Password Validation View

    private var passwordValidationView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password Requirements:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            PasswordRequirement(
                text: "At least 8 characters",
                isMet: password.count >= 8
            )

            PasswordRequirement(
                text: "Contains uppercase letter (A-Z)",
                isMet: password.range(of: "[A-Z]", options: .regularExpression) != nil
            )

            PasswordRequirement(
                text: "Contains lowercase letter (a-z)",
                isMet: password.range(of: "[a-z]", options: .regularExpression) != nil
            )

            PasswordRequirement(
                text: "Contains number (0-9)",
                isMet: password.range(of: "[0-9]", options: .regularExpression) != nil
            )

            PasswordRequirement(
                text: "Contains symbol (!@#$%^&*)",
                isMet: password.range(of: "[!@#$%^&*()_+\\-=\\[\\]{};':\"\\\\|,.<>\\/?]", options: .regularExpression) != nil
            )

            PasswordRequirement(
                text: "Passwords match",
                isMet: !confirmPassword.isEmpty && password == confirmPassword
            )
        }
        .padding(.top, 8)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Helper Properties

    private var isFormValid: Bool {
        !name.isEmpty &&
        !email.isEmpty &&
        email.contains("@") &&
        isPasswordValid &&
        password == confirmPassword
    }

    private var isPasswordValid: Bool {
        // Enforce strong password requirements
        guard password.count >= 8 else { return false }
        guard password.range(of: "[A-Z]", options: .regularExpression) != nil else { return false }
        guard password.range(of: "[a-z]", options: .regularExpression) != nil else { return false }
        guard password.range(of: "[0-9]", options: .regularExpression) != nil else { return false }
        guard password.range(of: "[!@#$%^&*()_+\\-=\\[\\]{};':\"\\\\|,.<>\\/?]", options: .regularExpression) != nil else { return false }
        return true
    }
    
    // MARK: - Actions

    private func signUp() {
        guard isFormValid else { return }

        focusedField = nil

        // Clear any previous error messages
        authService.errorMessage = nil

        Task {
            do {
                // Send verification code to email
                try await authService.sendVerificationCode(email: email, name: name)

                // Show verification screen
                await MainActor.run {
                    showingVerification = true

                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }

            } catch {
                await MainActor.run {
                    authService.errorMessage = error.localizedDescription
                    showingError = true

                    // Haptic feedback for error
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                .foregroundColor(isMet ? .green : .secondary.opacity(0.5))
                .scaleEffect(isMet ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isMet)

            Text(text)
                .font(.caption)
                .foregroundColor(isMet ? .green : .secondary)
                .fontWeight(isMet ? .semibold : .regular)
                .animation(.easeInOut(duration: 0.2), value: isMet)
        }
    }
}

// MARK: - Google Logo View

struct GoogleLogoView: View {
    var body: some View {
        Image("google-logo")
            .resizable()
            .scaledToFit()
    }
}

#Preview {
    ModernLoginView(onLoginSuccess: {})
}