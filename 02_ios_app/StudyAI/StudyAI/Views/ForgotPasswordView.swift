//
//  ForgotPasswordView.swift
//  StudyAI
//
//  Two-step password reset flow: email entry → code + new password
//

import SwiftUI

struct ForgotPasswordView: View {
    @StateObject private var authService = AuthenticationService.shared
    @Environment(\.dismiss) private var dismiss

    enum Step { case emailEntry, codeAndPassword }
    @State private var step: Step = .emailEntry

    // Step 1
    @State private var email = ""
    @State private var isSending = false

    // Step 2
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isResetting = false
    @State private var canResend = false
    @State private var resendCountdown = 60
    @State private var resendTimer: Timer?
    @State private var isNewPasswordVisible = false
    @State private var isConfirmPasswordVisible = false

    // Alerts
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false

    @FocusState private var isCodeFieldFocused: Bool

    private let codeLength = 6

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    headerSection

                    if step == .emailEntry {
                        emailEntrySection
                    } else {
                        codeAndPasswordSection
                    }

                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                    .font(.headline)
                }
            }
            .onTapGesture { hideKeyboard() }
        .onChange(of: step) { _, newStep in
            if newStep == .codeAndPassword {
                startResendTimer()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isCodeFieldFocused = true
                }
            }
        }
        }
        .alert(NSLocalizedString("emailVerification.error.title", comment: ""), isPresented: $showingError) {
            Button(NSLocalizedString("common.ok", comment: "")) { }
        } message: {
            Text(errorMessage)
        }
        .alert(NSLocalizedString("reset_password_title", comment: ""), isPresented: $showingSuccess) {
            Button(NSLocalizedString("common.ok", comment: "")) {
                dismiss()
            }
        } message: {
            Text(NSLocalizedString("password_reset_success", comment: ""))
        }
        .onDisappear {
            stopResendTimer()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.2), .blue.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)

                Image(systemName: step == .emailEntry ? "lock.rotation" : "key.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                Text(NSLocalizedString("reset_password_title", comment: ""))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(step == .emailEntry
                    ? NSLocalizedString("reset_password_email_prompt", comment: "")
                    : NSLocalizedString("reset_code_sent", comment: ""))
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                if step == .codeAndPassword {
                    Text(email)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Step 1: Email Entry

    private var emailEntrySection: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("auth.emailAddress", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField(NSLocalizedString("auth.enterEmail", comment: ""), text: $email)
                    .textFieldStyle(PlayfulTextFieldStyle())
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }

            Button {
                sendResetCode()
            } label: {
                HStack {
                    if isSending {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(NSLocalizedString("send_reset_code", comment: ""))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isEmailValid ? Color.blue : Color.gray.opacity(0.5))
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: .blue.opacity(isEmailValid ? 0.4 : 0), radius: 10, y: 5)
            }
            .disabled(!isEmailValid || isSending)
        }
    }

    // MARK: - Step 2: Code + New Password

    private var codeAndPasswordSection: some View {
        VStack(spacing: 24) {
            // Code input
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    ForEach(0..<codeLength, id: \.self) { index in
                        CodeDigitBox(
                            digit: digitAt(index),
                            isFocused: index == resetCode.count && isCodeFieldFocused
                        )
                    }
                }
                .onTapGesture {
                    isCodeFieldFocused = true
                }

                TextField("", text: $resetCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isCodeFieldFocused)
                    .opacity(0)
                    .frame(height: 0)
                    .onChange(of: resetCode) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        resetCode = filtered.count <= codeLength
                            ? filtered
                            : String(filtered.prefix(codeLength))
                    }

                Text(NSLocalizedString("emailVerification.enterCode", comment: ""))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .onAppear {
                isCodeFieldFocused = true
            }

            // New password field
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("new_password", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    if isNewPasswordVisible {
                        TextField(NSLocalizedString("new_password", comment: ""), text: $newPassword)
                            .textContentType(.newPassword)
                    } else {
                        SecureField(NSLocalizedString("new_password", comment: ""), text: $newPassword)
                            .textContentType(.newPassword)
                    }
                    Button(action: { isNewPasswordVisible.toggle() }) {
                        Image(systemName: isNewPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .padding(.trailing, 12)
                }
                .textFieldStyle(PlayfulTextFieldStyle())
            }

            // Confirm password field
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("confirm_new_password", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    if isConfirmPasswordVisible {
                        TextField(NSLocalizedString("confirm_new_password", comment: ""), text: $confirmPassword)
                            .textContentType(.newPassword)
                    } else {
                        SecureField(NSLocalizedString("confirm_new_password", comment: ""), text: $confirmPassword)
                            .textContentType(.newPassword)
                    }
                    Button(action: { isConfirmPasswordVisible.toggle() }) {
                        Image(systemName: isConfirmPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                    .padding(.trailing, 12)
                }
                .textFieldStyle(PlayfulTextFieldStyle())
            }

            // Reset button
            Button {
                resetPassword()
            } label: {
                HStack {
                    if isResetting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(NSLocalizedString("reset_password_button", comment: ""))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isResetFormValid ? Color.blue : Color.gray.opacity(0.5))
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: .blue.opacity(isResetFormValid ? 0.4 : 0), radius: 10, y: 5)
            }
            .disabled(!isResetFormValid || isResetting)

            // Resend section
            VStack(spacing: 8) {
                if canResend {
                    Button {
                        resendCode()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                            Text(NSLocalizedString("emailVerification.resendCode", comment: ""))
                                .font(.headline)
                        }
                        .foregroundColor(.blue)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(String(format: NSLocalizedString("emailVerification.resendCountdown", comment: ""), resendCountdown))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                Text(NSLocalizedString("emailVerification.checkSpam", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Validation

    private var isEmailValid: Bool {
        !email.isEmpty && email.contains("@")
    }

    private var isResetFormValid: Bool {
        resetCode.count == codeLength &&
        newPassword.count >= 6 &&
        newPassword == confirmPassword
    }

    private func digitAt(_ index: Int) -> String {
        guard index < resetCode.count else { return "" }
        return String(resetCode[resetCode.index(resetCode.startIndex, offsetBy: index)])
    }

    // MARK: - Actions

    private func sendResetCode() {
        guard isEmailValid && !isSending else { return }
        hideKeyboard()
        isSending = true

        Task {
            do {
                try await authService.sendPasswordResetCode(email: email)
                await MainActor.run {
                    isSending = false
                    step = .codeAndPassword
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    // Always advance to step 2 (don't leak whether email exists)
                    step = .codeAndPassword
                }
            }
        }
    }

    private func resetPassword() {
        guard isResetFormValid && !isResetting else { return }
        hideKeyboard()
        isResetting = true

        Task {
            do {
                // The backend reset-password endpoint re-verifies the code itself.
                // Don't call verifyPasswordResetCode separately — it would burn
                // an attempt from the 5-attempt limit before the actual reset call.
                try await authService.resetPassword(email: email, code: resetCode, newPassword: newPassword)

                await MainActor.run {
                    isResetting = false
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    showingSuccess = true
                }
            } catch {
                await MainActor.run {
                    isResetting = false
                    errorMessage = error.localizedDescription
                    showingError = true
                    resetCode = ""
                    isCodeFieldFocused = true
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }

    private func resendCode() {
        guard canResend else { return }
        canResend = false
        resendCountdown = 60
        startResendTimer()

        Task {
            do {
                try await authService.sendPasswordResetCode(email: email)
                await MainActor.run {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } catch {
                await MainActor.run {
                    canResend = true
                    stopResendTimer()
                }
            }
        }
    }

    // MARK: - Timer

    private func startResendTimer() {
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if resendCountdown > 0 {
                resendCountdown -= 1
            } else {
                canResend = true
                stopResendTimer()
            }
        }
    }

    private func stopResendTimer() {
        resendTimer?.invalidate()
        resendTimer = nil
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    ForgotPasswordView()
}
