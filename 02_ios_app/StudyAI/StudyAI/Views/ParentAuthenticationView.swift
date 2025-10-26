//
//  ParentAuthenticationView.swift
//  StudyAI
//
//  Reusable Parent Authentication Modal
//

import SwiftUI

// MARK: - Secure PIN Field Component (for Authentication)
struct AuthSecurePINField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isSecure: Bool = true

    var body: some View {
        HStack {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title3)
                    .multilineTextAlignment(.center)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.title3)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                isSecure.toggle()
            }) {
                Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

/// Reusable view for parent authentication before accessing protected features
struct ParentAuthenticationView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var parentModeManager = ParentModeManager.shared

    let title: String
    let message: String
    let onSuccess: () -> Void

    @State private var password = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var attempts = 0
    @State private var isLocked = false
    @State private var isAuthenticatingWithBiometrics = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                // Lock Icon
                Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 70))
                    .foregroundColor(isLocked ? .red : .purple)
                    .padding(.bottom, 8)

                // Title
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                // Message
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Face ID Button (shown only if biometric auth is available and enabled)
                if !isLocked && parentModeManager.canUseParentBiometrics() {
                    Button(action: {
                        authenticateWithBiometrics()
                    }) {
                        HStack {
                            if isAuthenticatingWithBiometrics {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: biometricIcon)
                                    .font(.system(size: 20))
                                Text(localizedBiometricButtonText)
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    .disabled(isAuthenticatingWithBiometrics)
                    .padding(.horizontal, 32)

                    // Divider with "OR" text
                    HStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                        Text(NSLocalizedString("parentAuth.or", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 32)
                }

                // PIN Input
                if !isLocked {
                    VStack(spacing: 16) {
                        AuthSecurePINField(placeholder: "Enter 6-Digit PIN", text: $password)
                            .onChange(of: password) { _, newValue in
                                if newValue.count > 6 {
                                    password = String(newValue.prefix(6))
                                }
                                if newValue.count == 6 {
                                    verifyPassword()
                                }
                            }

                        // Verify Button
                        Button(action: {
                            verifyPassword()
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Verify")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [Color.purple, Color.purple.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                        }
                        .disabled(password.count != 6)
                        .opacity(password.count == 6 ? 1.0 : 0.5)
                    }
                    .padding(.horizontal, 32)
                } else {
                    VStack(spacing: 12) {
                        Text("Too Many Failed Attempts")
                            .font(.headline)
                            .foregroundColor(.red)

                        Text("Please try again later")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Verification Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func verifyPassword() {
        if parentModeManager.verifyParentPassword(password) {
            // Success - call completion handler and dismiss
            onSuccess()
            dismiss()
        } else {
            // Failed - show error
            attempts += 1
            password = ""

            if attempts >= 3 {
                isLocked = true
                errorMessage = "Too many failed attempts. Please try again later."
            } else {
                errorMessage = "Incorrect PIN. \(3 - attempts) attempts remaining."
            }

            showingError = true

            // Haptic feedback for error
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }

    private func authenticateWithBiometrics() {
        Task {
            isAuthenticatingWithBiometrics = true

            do {
                let success = try await parentModeManager.verifyWithBiometrics()

                await MainActor.run {
                    isAuthenticatingWithBiometrics = false

                    if success {
                        // Haptic feedback for success
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)

                        // Success - call completion handler and dismiss
                        onSuccess()
                        dismiss()
                    } else {
                        // Failed - show error
                        errorMessage = NSLocalizedString("parentAuth.biometricFailed", comment: "")
                        showingError = true

                        // Haptic feedback for error
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.error)
                    }
                }
            } catch {
                await MainActor.run {
                    isAuthenticatingWithBiometrics = false
                    errorMessage = String(format: NSLocalizedString("parentAuth.biometricError", comment: ""), error.localizedDescription)
                    showingError = true

                    // Haptic feedback for error
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }

    private var biometricIcon: String {
        let type = parentModeManager.getBiometricType()
        switch type {
        case "Face ID":
            return "faceid"
        case "Touch ID":
            return "touchid"
        case "Optic ID":
            return "opticid"
        default:
            return "faceid"
        }
    }

    private var localizedBiometricButtonText: String {
        let type = parentModeManager.getBiometricType()
        switch type {
        case "Face ID":
            return NSLocalizedString("parentAuth.useFaceID", comment: "")
        case "Touch ID":
            return NSLocalizedString("parentAuth.useTouchID", comment: "")
        case "Optic ID":
            return NSLocalizedString("parentAuth.useOpticID", comment: "")
        default:
            return NSLocalizedString("parentAuth.useFaceID", comment: "")
        }
    }
}

// MARK: - View Modifier for Parent Protection

struct ParentProtectedModifier: ViewModifier {
    @StateObject private var parentModeManager = ParentModeManager.shared
    @State private var showingAuthView = false

    let title: String
    let message: String
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onTapGesture {
                if parentModeManager.requiresParentAuthentication() {
                    showingAuthView = true
                } else {
                    action()
                }
            }
            .sheet(isPresented: $showingAuthView) {
                ParentAuthenticationView(
                    title: title,
                    message: message,
                    onSuccess: action
                )
            }
    }
}

extension View {
    /// Protect a view with parent authentication
    /// - Parameters:
    ///   - title: Title shown in auth dialog
    ///   - message: Message explaining why auth is needed
    ///   - action: Action to perform after successful authentication
    func parentProtected(
        title: String = "Parent Verification Required",
        message: String = "This feature requires parent permission",
        action: @escaping () -> Void
    ) -> some View {
        self.modifier(ParentProtectedModifier(
            title: title,
            message: message,
            action: action
        ))
    }
}

#Preview {
    ParentAuthenticationView(
        title: "Parent Verification",
        message: "This feature requires parent permission",
        onSuccess: {
            print("Authentication successful")
        }
    )
}