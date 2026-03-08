//
//  FaceIDReauthView.swift
//  StudyAI
//
//  Face ID re-authentication view for expired sessions
//  Shows when session timeout occurs and requires biometric re-authentication
//

import SwiftUI

struct FaceIDReauthView: View {
    @StateObject private var authService = AuthenticationService.shared
    @Environment(\.dismiss) private var dismiss

    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var isAuthenticating = false
    @State private var authError: String?

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Icon
            Image(systemName: authService.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            // Title
            Text(NSLocalizedString("faceIDReauth.title", comment: ""))
                .font(.title)
                .fontWeight(.bold)

            // Message
            VStack(spacing: 12) {
                Text(NSLocalizedString("faceIDReauth.message", comment: ""))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text(String(format: NSLocalizedString("faceIDReauth.biometricPrompt", comment: ""), authService.getBiometricType()))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            // Error message
            if let error = authError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Authenticate button
            VStack(spacing: 16) {
                Button(action: authenticateWithBiometrics) {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: authService.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                            Text(String(format: NSLocalizedString("faceIDReauth.authenticateButton", comment: ""), authService.getBiometricType()))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isAuthenticating)

                // Sign out button
                Button(action: {
                    onCancel()
                    dismiss()
                }) {
                    Text(NSLocalizedString("faceIDReauth.signOut", comment: ""))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(12)
                }
                .disabled(isAuthenticating)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .interactiveDismissDisabled(true)  // Prevent dismissal by swiping
        .onAppear {
            // Automatically trigger Face ID on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                authenticateWithBiometrics()
            }
        }
    }

    private func authenticateWithBiometrics() {
        isAuthenticating = true
        authError = nil

        Task {
            do {
                try await authService.signInWithBiometrics()

                // Success
                await MainActor.run {
                    isAuthenticating = false
                    onSuccess()
                    dismiss()
                }
            } catch {
                // Handle error
                await MainActor.run {
                    isAuthenticating = false

                    if let authError = error as? AuthError {
                        switch authError {
                        case .userCancelled:
                            self.authError = NSLocalizedString("faceIDReauth.error.cancelled", comment: "")
                        case .biometricNotAvailable:
                            self.authError = String(format: NSLocalizedString("faceIDReauth.error.notAvailable", comment: ""), authService.getBiometricType())
                        case .biometricNotEnrolled:
                            self.authError = String(format: NSLocalizedString("faceIDReauth.error.notEnrolled", comment: ""), authService.getBiometricType())
                        case .biometricFailed:
                            self.authError = String(format: NSLocalizedString("faceIDReauth.error.failed", comment: ""), authService.getBiometricType())
                        default:
                            self.authError = String(format: NSLocalizedString("faceIDReauth.error.generic", comment: ""), error.localizedDescription)
                        }
                    } else {
                        self.authError = String(format: NSLocalizedString("faceIDReauth.error.generic", comment: ""), error.localizedDescription)
                    }
                }
            }
        }
    }
}

#Preview {
    FaceIDReauthView(onSuccess: {}, onCancel: {})
}
