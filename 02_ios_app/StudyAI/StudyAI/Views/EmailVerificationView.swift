//
//  EmailVerificationView.swift
//  StudyAI
//
//  Email verification screen with 6-digit code input
//

import SwiftUI

struct EmailVerificationView: View {
    let email: String
    let name: String
    let password: String
    let onVerificationSuccess: () -> Void

    @StateObject private var authService = AuthenticationService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var verificationCode = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isVerifying = false
    @State private var canResend = false
    @State private var resendCountdown = 60
    @State private var resendTimer: Timer?

    @FocusState private var isCodeFieldFocused: Bool

    private let codeLength = 6

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Header section
                    headerSection

                    // Code input section
                    codeInputSection

                    // Verify button
                    verifyButton

                    // Resend section
                    resendSection

                    // Email display and change option
                    emailInfoSection

                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            .background(Color.white)
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
        .alert("Verification Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            startResendTimer()
            isCodeFieldFocused = true
        }
        .onDisappear {
            stopResendTimer()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
            }

            // Title and description
            VStack(spacing: 8) {
                Text("Verify Your Email")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)  // ✅ Adaptive color for dark mode

                Text("We've sent a 6-digit verification code to")
                    .font(.body)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                Text(email)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Code Input Section

    private var codeInputSection: some View {
        VStack(spacing: 16) {
            // Code input boxes
            HStack(spacing: 12) {
                ForEach(0..<codeLength, id: \.self) { index in
                    CodeDigitBox(
                        digit: digitAt(index),
                        isFocused: index == verificationCode.count && isCodeFieldFocused
                    )
                }
            }

            // Hidden text field for actual input
            TextField("", text: $verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isCodeFieldFocused)
                .opacity(0)
                .frame(height: 0)
                .onChange(of: verificationCode) { _, newValue in
                    // Limit to digits only and max length
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered.count <= codeLength {
                        verificationCode = filtered
                    } else {
                        verificationCode = String(filtered.prefix(codeLength))
                    }

                    // Auto-verify when all digits entered
                    if verificationCode.count == codeLength {
                        verifyCode()
                    }
                }

            // Hint text
            Text("Enter the 6-digit code")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Verify Button

    private var verifyButton: some View {
        Button {
            verifyCode()
        } label: {
            HStack {
                if isVerifying {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }

                Text(isVerifying ? "Verifying..." : "Verify Email")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                isCodeValid ? Color.blue : Color.gray.opacity(0.5)
            )
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: .blue.opacity(isCodeValid ? 0.4 : 0), radius: 10, y: 5)
        }
        .disabled(!isCodeValid || isVerifying)
    }

    // MARK: - Resend Section

    private var resendSection: some View {
        VStack(spacing: 8) {
            if canResend {
                Button {
                    resendCode()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text("Resend Code")
                            .font(.headline)
                    }
                    .foregroundColor(.blue)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("Resend code in \(resendCountdown)s")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }

            Text("Didn't receive the code? Check your spam folder")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Email Info Section

    private var emailInfoSection: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.vertical, 8)

            HStack {
                Text("Wrong email?")
                    .font(.caption)
                    .foregroundColor(.gray)

                Button("Change") {
                    dismiss()
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Helper Properties

    private var isCodeValid: Bool {
        verificationCode.count == codeLength && verificationCode.allSatisfy { $0.isNumber }
    }

    private func digitAt(_ index: Int) -> String {
        guard index < verificationCode.count else { return "" }
        return String(verificationCode[verificationCode.index(verificationCode.startIndex, offsetBy: index)])
    }

    // MARK: - Actions

    private func verifyCode() {
        guard isCodeValid && !isVerifying else { return }

        isCodeFieldFocused = false
        isVerifying = true

        Task {
            do {
                try await authService.verifyEmailCode(
                    email: email,
                    code: verificationCode,
                    name: name,
                    password: password
                )

                // Verification successful - user is now authenticated
                await MainActor.run {
                    isVerifying = false

                    // Clear any error messages
                    authService.errorMessage = nil

                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)

                    // Dismiss the verification view
                    // The parent view will handle navigation since user is now authenticated
                    dismiss()
                }

            } catch {
                await MainActor.run {
                    isVerifying = false
                    errorMessage = error.localizedDescription
                    showingError = true
                    verificationCode = ""
                    isCodeFieldFocused = true

                    // Haptic feedback for error
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
                try await authService.resendVerificationCode(email: email)

                await MainActor.run {
                    // Show success message
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true

                    // Allow immediate retry on error
                    canResend = true
                    stopResendTimer()
                }
            }
        }
    }

    // MARK: - Timer Management

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

// MARK: - Code Digit Box

struct CodeDigitBox: View {
    let digit: String
    let isFocused: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isFocused ? Color.blue : Color.gray.opacity(0.3),
                    lineWidth: isFocused ? 2 : 1.5
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(digit.isEmpty ? Color.white : Color.blue.opacity(0.05))
                )
                .frame(width: 45, height: 55)

            if !digit.isEmpty {
                Text(digit)
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            } else if isFocused {
                // Blinking cursor
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 2, height: 30)
                    .opacity(0.7)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: digit)
        .animation(.easeInOut(duration: 0.3), value: isFocused)
    }
}

// MARK: - Preview

#Preview {
    EmailVerificationView(
        email: "test@example.com",
        name: "Test User",
        password: "password123",
        onVerificationSuccess: {}
    )
}
