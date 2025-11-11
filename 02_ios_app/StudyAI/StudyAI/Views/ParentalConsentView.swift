//
//  ParentalConsentView.swift
//  StudyAI
//
//  Parental consent screen for COPPA compliance (users under 13)
//

import SwiftUI

struct ParentalConsentView: View {
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var authService = AuthenticationService.shared
    @Environment(\.dismiss) private var dismiss

    // User information
    let childEmail: String
    let childDateOfBirth: String?

    // Callback for successful consent
    let onConsentGranted: () -> Void

    // UI State
    @State private var currentStep: ConsentStep = .explanation
    @State private var parentEmail = ""
    @State private var parentName = ""
    @State private var verificationCode = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var canResend = false
    @State private var resendCountdown = 60
    @State private var resendTimer: Timer?

    @FocusState private var focusedField: Field?

    private let codeLength = 6

    enum ConsentStep {
        case explanation
        case parentInfo
        case verification
    }

    enum Field: Hashable {
        case parentEmail
        case parentName
        case verificationCode
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Progress indicator
                    progressIndicator

                    // Content based on current step
                    switch currentStep {
                    case .explanation:
                        explanationContent
                    case .parentInfo:
                        parentInfoContent
                    case .verification:
                        verificationContent
                    }

                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Parental Consent Required")
                        .font(.headline)
                }
            }
            .onTapGesture {
                hideKeyboard()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onDisappear {
            stopResendTimer()
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { step in
                Circle()
                    .fill(progressColor(for: step))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 8)
    }

    private func progressColor(for step: Int) -> Color {
        let currentStepNumber: Int
        switch currentStep {
        case .explanation: currentStepNumber = 1
        case .parentInfo: currentStepNumber = 2
        case .verification: currentStepNumber = 3
        }

        return step <= currentStepNumber ? Color.blue : Color.gray.opacity(0.3)
    }

    // MARK: - Explanation Content (Step 1)

    private var explanationContent: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "checkmark.shield.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
                .padding(.top, 20)

            // Title
            Text("Parental Consent Required")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Explanation
            VStack(alignment: .leading, spacing: 16) {
                infoRow(icon: "person.2.fill", title: "Why is this needed?",
                       text: "Federal law (COPPA) requires parental consent for users under 13 years old.")

                infoRow(icon: "envelope.fill", title: "How it works",
                       text: "We'll send a verification code to your parent's email. They'll enter it to grant consent.")

                infoRow(icon: "lock.shield.fill", title: "Your privacy matters",
                       text: "We only collect data with your parent's permission. They can revoke consent at any time.")

                infoRow(icon: "calendar.badge.clock", title: "Quick process",
                       text: "This only takes a few minutes. The verification code expires in 24 hours.")
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)

            // Continue button
            Button(action: {
                withAnimation {
                    currentStep = .parentInfo
                    focusedField = .parentEmail
                }
            }) {
                Text("Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
        }
    }

    private func infoRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Parent Info Content (Step 2)

    private var parentInfoContent: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.fill.badge.plus")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.blue)

                Text("Parent Information")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Enter your parent or guardian's information")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)

            // Form fields
            VStack(spacing: 16) {
                // Parent name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Parent/Guardian Name")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("Full name", text: $parentName)
                        .textContentType(.name)
                        .autocapitalization(.words)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .parentName)
                }

                // Parent email field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Parent/Guardian Email")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    TextField("parent@example.com", text: $parentEmail)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .parentEmail)
                }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)

            // Info box
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)

                Text("A 6-digit verification code will be sent to this email address. Make sure it's correct!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)

            // Buttons
            VStack(spacing: 12) {
                Button(action: sendConsentRequest) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .cornerRadius(12)
                    } else {
                        Text("Send Verification Code")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(isFormValid ? Color.blue : Color.gray)
                            .cornerRadius(12)
                    }
                }
                .disabled(!isFormValid || isLoading)

                Button(action: {
                    withAnimation {
                        currentStep = .explanation
                    }
                }) {
                    Text("Back")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
        }
    }

    private var isFormValid: Bool {
        !parentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        parentEmail.contains("@") && parentEmail.contains(".")
    }

    // MARK: - Verification Content (Step 3)

    private var verificationContent: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.blue)

                Text("Verification Code Sent!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("We've sent a 6-digit code to:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(parentEmail)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
            .padding(.top, 20)

            // Code input
            VStack(spacing: 16) {
                Text("Enter Verification Code")
                    .font(.headline)

                HStack(spacing: 12) {
                    ForEach(0..<codeLength, id: \.self) { index in
                        Text(codeDigit(at: index))
                            .font(.title)
                            .fontWeight(.semibold)
                            .frame(width: 45, height: 55)
                            .background(Color(.systemBackground))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(verificationCode.count == index ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                            )
                    }
                }

                // Hidden text field for code input
                TextField("", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .focused($focusedField, equals: .verificationCode)
                    .onChange(of: verificationCode) { _, newValue in
                        // Limit to 6 digits
                        if newValue.count > codeLength {
                            verificationCode = String(newValue.prefix(codeLength))
                        }

                        // Auto-verify when 6 digits entered
                        if verificationCode.count == codeLength {
                            verifyCode()
                        }
                    }
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .onTapGesture {
                focusedField = .verificationCode
            }

            // Info and resend
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.orange)
                        .font(.caption)

                    Text("Code expires in 24 hours")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !canResend {
                    Text("Resend code in \(resendCountdown)s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Button(action: resendCode) {
                        Text("Resend Code")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(10)

            // Verify button
            Button(action: verifyCode) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .cornerRadius(12)
                } else {
                    Text("Verify Consent")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(verificationCode.count == codeLength ? Color.blue : Color.gray)
                        .cornerRadius(12)
                }
            }
            .disabled(verificationCode.count != codeLength || isLoading)

            // Back button
            Button(action: {
                withAnimation {
                    currentStep = .parentInfo
                    verificationCode = ""
                }
            }) {
                Text("Change Parent Email")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
        .onAppear {
            startResendTimer()
            focusedField = .verificationCode
        }
    }

    private func codeDigit(at index: Int) -> String {
        guard index < verificationCode.count else { return "" }
        let digitIndex = verificationCode.index(verificationCode.startIndex, offsetBy: index)
        return String(verificationCode[digitIndex])
    }

    // MARK: - Actions

    private func sendConsentRequest() {
        guard let dateOfBirth = childDateOfBirth else {
            showError("Date of birth is required")
            return
        }

        isLoading = true

        Task {
            let result = await networkService.requestParentalConsent(
                childEmail: childEmail,
                childDateOfBirth: dateOfBirth,
                parentEmail: parentEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                parentName: parentName.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            await MainActor.run {
                isLoading = false

                if result.success {
                    withAnimation {
                        currentStep = .verification
                    }
                } else {
                    showError(result.message)
                }
            }
        }
    }

    private func verifyCode() {
        guard verificationCode.count == codeLength else { return }

        isLoading = true

        Task {
            let result = await networkService.verifyParentalConsent(code: verificationCode)

            await MainActor.run {
                isLoading = false

                if result.success {
                    // Success! Consent granted
                    onConsentGranted()
                } else {
                    showError(result.message)
                    // Clear code on error
                    verificationCode = ""
                }
            }
        }
    }

    private func resendCode() {
        sendConsentRequest()
        canResend = false
        resendCountdown = 60
        startResendTimer()
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }

    // MARK: - Timer Management

    private func startResendTimer() {
        stopResendTimer()

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
        focusedField = nil
    }
}

// MARK: - Preview

struct ParentalConsentView_Previews: PreviewProvider {
    static var previews: some View {
        ParentalConsentView(
            childEmail: "student@example.com",
            childDateOfBirth: "2012-05-15",
            onConsentGranted: {
                print("Consent granted!")
            }
        )
    }
}
