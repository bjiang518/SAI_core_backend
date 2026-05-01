//
//  PasswordManagementView.swift
//  StudyAI
//
//  Password Management & Parent Mode Settings
//

import SwiftUI

// MARK: - Secure PIN Field Component
struct SecurePINField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isSecure: Bool = true

    var body: some View {
        HStack {
            if isSecure {
                SecureField(placeholder, text: $text)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            }

            Button(action: {
                isSecure.toggle()
            }) {
                Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
    }
}

struct PasswordManagementView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var parentModeManager = ParentModeManager.shared
    @StateObject private var authService = AuthenticationService.shared

    @State private var showingChangePassword = false
    @State private var showingParentPasswordSetup = false
    @State private var showingParentPasswordChange = false
    @State private var showingRemoveParentPassword = false
    @State private var showingParentPasswordAuth = false

    var body: some View {
        NavigationStack {
            List {
                // Account Password Section
                Section {
                    // Change Account Password (placeholder)
                    Button(action: {
                        showingChangePassword = true
                    }) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("accountPassword.title", comment: ""))
                                    .font(.body)
                                    .foregroundColor(.primary)

                                Text(NSLocalizedString("accountPassword.subtitle", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(NSLocalizedString("accountPassword.sectionHeader", comment: ""))
                } footer: {
                    Text(NSLocalizedString("accountPassword.sectionFooter", comment: ""))
                }

                // Parent Mode Section
                Section {
                    // Parent Mode Status
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.purple)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("parentPassword.title", comment: ""))
                                .font(.body)
                                .foregroundColor(.primary)

                            Text(parentModeManager.isParentModeEnabled ? NSLocalizedString("parentPassword.statusEnabled", comment: "") : NSLocalizedString("parentPassword.statusNotSet", comment: ""))
                                .font(.caption)
                                .foregroundColor(parentModeManager.isParentModeEnabled ? .green : .secondary)
                        }

                        Spacer()

                        if parentModeManager.isParentModeEnabled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }

                    // Set or Change Parent Password
                    if !parentModeManager.isParentModeEnabled {
                        Button(action: {
                            showingParentPasswordSetup = true
                        }) {
                            HStack {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("parentPassword.set", comment: ""))
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Text(NSLocalizedString("parentPassword.setSubtitle", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Change Parent Password
                        Button(action: {
                            showingParentPasswordChange = true
                        }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.orange)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("parentPassword.change", comment: ""))
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Text(NSLocalizedString("parentPassword.changeSubtitle", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        // Remove Parent Password
                        Button(action: {
                            showingRemoveParentPassword = true
                        }) {
                            HStack {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.red)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("parentPassword.remove", comment: ""))
                                        .font(.body)
                                        .foregroundColor(.red)

                                    Text(NSLocalizedString("parentPassword.removeSubtitle", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        // Face ID Toggle
                        HStack {
                            Image(systemName: parentModeManager.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                                .foregroundColor(.blue)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(localizedBiometricTitle)
                                    .font(.body)
                                    .foregroundColor(.primary)

                                Text(parentModeManager.isParentFaceIDEnabled() ? NSLocalizedString("parentMode.enabled", comment: "") : NSLocalizedString("parentMode.disabled", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(parentModeManager.isParentFaceIDEnabled() ? .green : .secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { parentModeManager.isParentFaceIDEnabled() },
                                set: { isEnabled in
                                    if isEnabled {
                                        Task {
                                            do {
                                                try await parentModeManager.enableParentFaceID()
                                            } catch {
                                                debugPrint("❌ Failed to enable Face ID: \(error.localizedDescription)")
                                            }
                                        }
                                    } else {
                                        parentModeManager.disableParentFaceID()
                                    }
                                }
                            ))
                            .tint(.blue)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("parentPassword.controlsHeader", comment: ""))
                } footer: {
                    Text(NSLocalizedString("parentPassword.controlsFooter", comment: ""))
                }

                // Access Control Section
                if parentModeManager.isParentModeEnabled {
                    Section {
                        ForEach(ProtectedFeature.allCases, id: \.self) { feature in
                            Toggle(isOn: Binding(
                                get: { parentModeManager.isFeatureProtected(feature) },
                                set: { parentModeManager.setFeatureProtection(feature, protected: $0) }
                            )) {
                                HStack(spacing: 12) {
                                    Image(systemName: feature.icon)
                                        .foregroundColor(.blue)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(feature.displayName)
                                            .font(.body)
                                            .foregroundColor(.primary)

                                        Text(feature.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .tint(.purple)
                        }
                    } header: {
                        Text(NSLocalizedString("parentPassword.featureAccessHeader", comment: ""))
                    } footer: {
                        Text(NSLocalizedString("parentPassword.featureAccessFooter", comment: ""))
                    }
                }
            }
            .navigationTitle(NSLocalizedString("settings.passwordManager", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingChangePassword) {
                ChangeAccountPasswordView()
            }
            .sheet(isPresented: $showingParentPasswordSetup) {
                SetParentPasswordView()
            }
            .sheet(isPresented: $showingParentPasswordChange) {
                ChangeParentPasswordView()
            }
            .sheet(isPresented: $showingRemoveParentPassword) {
                RemoveParentPasswordView()
            }
        }
    }

    private var localizedBiometricTitle: String {
        let type = parentModeManager.getBiometricType()
        switch type {
        case "Face ID":
            return NSLocalizedString("parentMode.faceIDForParentMode", comment: "")
        case "Touch ID":
            return NSLocalizedString("parentMode.touchIDForParentMode", comment: "")
        case "Optic ID":
            return NSLocalizedString("parentMode.opticIDForParentMode", comment: "")
        default:
            return NSLocalizedString("parentMode.faceIDForParentMode", comment: "")
        }
    }
}

// MARK: - Change Account Password View (Placeholder)
struct ChangeAccountPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(NSLocalizedString("accountPassword.current", comment: ""), text: $currentPassword)
                        .textContentType(.password)

                    SecureField(NSLocalizedString("accountPassword.new", comment: ""), text: $newPassword)
                        .textContentType(.newPassword)

                    SecureField(NSLocalizedString("accountPassword.confirm", comment: ""), text: $confirmPassword)
                        .textContentType(.newPassword)
                } header: {
                    Text(NSLocalizedString("accountPassword.changeHeader", comment: ""))
                } footer: {
                    Text(NSLocalizedString("accountPassword.requirementFooter", comment: ""))
                }

                Section {
                    Button(action: {
                        // Placeholder - will implement actual password change
                        alertMessage = NSLocalizedString("accountPassword.comingSoon", comment: "")
                        showingAlert = true
                    }) {
                        Text(NSLocalizedString("accountPassword.button", comment: ""))
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.blue)
                }
            }
            .navigationTitle(NSLocalizedString("accountPassword.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
            .alert(NSLocalizedString("accountPassword.changeHeader", comment: ""), isPresented: $showingAlert) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
}

// MARK: - Set Parent Password View
struct SetParentPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var parentModeManager = ParentModeManager.shared
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.purple)

                        Text(NSLocalizedString("parentPasswordSet.title", comment: ""))
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(NSLocalizedString("parentPasswordSet.description", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)

                Section {
                    SecurePINField(placeholder: NSLocalizedString("parentPasswordSet.pinPlaceholder", comment: ""), text: $password)
                        .onChange(of: password) { _, newValue in
                            if newValue.count > 6 {
                                password = String(newValue.prefix(6))
                            }
                        }

                    SecurePINField(placeholder: NSLocalizedString("parentPasswordSet.confirmPlaceholder", comment: ""), text: $confirmPassword)
                        .onChange(of: confirmPassword) { _, newValue in
                            if newValue.count > 6 {
                                confirmPassword = String(newValue.prefix(6))
                            }
                        }
                } header: {
                    Text(NSLocalizedString("parentPasswordSet.header", comment: ""))
                } footer: {
                    Text(NSLocalizedString("parentPasswordSet.footer", comment: ""))
                }

                Section {
                    Button(action: {
                        setParentPassword()
                    }) {
                        Text(NSLocalizedString("parentPasswordSet.button", comment: ""))
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.purple)
                    .disabled(password.count != 6 || confirmPassword.count != 6)
                }
            }
            .navigationTitle(NSLocalizedString("parentPassword.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
            .alert(NSLocalizedString("parentPassword.title", comment: ""), isPresented: $showingAlert) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {
                    if alertMessage.contains("success") {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func setParentPassword() {
        guard password == confirmPassword else {
            alertMessage = NSLocalizedString("parentPasswordSet.mismatch", comment: "")
            showingAlert = true
            return
        }

        guard password.count == 6, password.allSatisfy({ $0.isNumber }) else {
            alertMessage = NSLocalizedString("parentPasswordSet.invalid", comment: "")
            showingAlert = true
            return
        }

        if parentModeManager.setParentPassword(password) {
            alertMessage = NSLocalizedString("parentPasswordSet.success", comment: "")
            showingAlert = true
        } else {
            alertMessage = NSLocalizedString("parentPasswordSet.failed", comment: "")
            showingAlert = true
        }
    }
}

// MARK: - Change Parent Password View
struct ChangeParentPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var parentModeManager = ParentModeManager.shared
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingForgotPIN = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecurePINField(placeholder: NSLocalizedString("parentPasswordChange.currentPlaceholder", comment: ""), text: $currentPassword)
                        .onChange(of: currentPassword) { _, newValue in
                            if newValue.count > 6 {
                                currentPassword = String(newValue.prefix(6))
                            }
                        }
                } header: {
                    Text(NSLocalizedString("parentPasswordChange.currentHeader", comment: ""))
                } footer: {
                    Button(NSLocalizedString("parentPINReset.forgotPIN", comment: "")) {
                        showingForgotPIN = true
                    }
                    .font(.footnote)
                    .foregroundColor(.purple)
                }

                Section {
                    SecurePINField(placeholder: NSLocalizedString("parentPasswordChange.newPlaceholder", comment: ""), text: $newPassword)
                        .onChange(of: newPassword) { _, newValue in
                            if newValue.count > 6 {
                                newPassword = String(newValue.prefix(6))
                            }
                        }

                    SecurePINField(placeholder: NSLocalizedString("parentPasswordChange.confirmPlaceholder", comment: ""), text: $confirmPassword)
                        .onChange(of: confirmPassword) { _, newValue in
                            if newValue.count > 6 {
                                confirmPassword = String(newValue.prefix(6))
                            }
                        }
                } header: {
                    Text(NSLocalizedString("parentPasswordChange.newHeader", comment: ""))
                } footer: {
                    Text(NSLocalizedString("parentPasswordChange.footer", comment: ""))
                }

                Section {
                    Button(action: {
                        changeParentPassword()
                    }) {
                        Text(NSLocalizedString("parentPasswordChange.button", comment: ""))
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.orange)
                    .disabled(currentPassword.count != 6 || newPassword.count != 6 || confirmPassword.count != 6)
                }
            }
            .navigationTitle(NSLocalizedString("parentPasswordChange.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
            .alert(NSLocalizedString("parentPasswordChange.title", comment: ""), isPresented: $showingAlert) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {
                    if alertMessage.contains("success") {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showingForgotPIN) {
                ForgotParentPINView()
            }
        }
    }

    private func changeParentPassword() {
        guard newPassword == confirmPassword else {
            alertMessage = NSLocalizedString("parentPasswordChange.mismatch", comment: "")
            showingAlert = true
            return
        }

        let result = parentModeManager.changeParentPassword(
            currentPassword: currentPassword,
            newPassword: newPassword
        )

        if result.success {
            alertMessage = NSLocalizedString("parentPasswordChange.success", comment: "")
            showingAlert = true
        } else {
            alertMessage = result.error ?? NSLocalizedString("parentPasswordChange.failed", comment: "")
            showingAlert = true
        }
    }
}

// MARK: - Remove Parent Password View
struct RemoveParentPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var parentModeManager = ParentModeManager.shared
    @State private var password = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingForgotPIN = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)

                        Text(NSLocalizedString("parentPasswordRemove.title", comment: ""))
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(NSLocalizedString("parentPasswordRemove.description", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)

                Section {
                    SecurePINField(placeholder: NSLocalizedString("parentPasswordRemove.pinPlaceholder", comment: ""), text: $password)
                        .onChange(of: password) { _, newValue in
                            if newValue.count > 6 {
                                password = String(newValue.prefix(6))
                            }
                        }
                } header: {
                    Text(NSLocalizedString("parentPasswordRemove.header", comment: ""))
                } footer: {
                    Button(NSLocalizedString("parentPINReset.forgotPIN", comment: "")) {
                        showingForgotPIN = true
                    }
                    .font(.footnote)
                    .foregroundColor(.purple)
                }

                Section {
                    Button(action: {
                        removeParentPassword()
                    }) {
                        Text(NSLocalizedString("parentPasswordRemove.button", comment: ""))
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.red)
                    .disabled(password.count != 6)
                }
            }
            .navigationTitle(NSLocalizedString("parentPasswordRemove.navigationTitle", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
            .alert(NSLocalizedString("parentPasswordRemove.alertTitle", comment: ""), isPresented: $showingAlert) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) {
                    if alertMessage.contains("success") {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showingForgotPIN) {
                ForgotParentPINView()
            }
        }
    }

    private func removeParentPassword() {
        if parentModeManager.removeParentPassword(password: password) {
            alertMessage = NSLocalizedString("parentPasswordRemove.success", comment: "")
            showingAlert = true
        } else {
            alertMessage = NSLocalizedString("parentPasswordRemove.incorrectPin", comment: "")
            showingAlert = true
        }
    }
}

// MARK: - Forgot Parent PIN View
struct ForgotParentPINView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var parentModeManager = ParentModeManager.shared

    private enum ResetStep {
        case sendCode
        case verifyCode(maskedEmail: String)
        case setNewPIN
    }

    @State private var step: ResetStep = .sendCode
    @State private var verificationCode = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .sendCode:
                    sendCodeSection
                case .verifyCode(let maskedEmail):
                    verifyCodeSection(maskedEmail: maskedEmail)
                case .setNewPIN:
                    setNewPINSection
                }
            }
            .navigationTitle(NSLocalizedString("parentPINReset.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // Step 1: send code
    @ViewBuilder
    private var sendCodeSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "lock.open.rotation")
                    .font(.system(size: 60))
                    .foregroundColor(.purple)

                Text(NSLocalizedString("parentPINReset.step1Title", comment: ""))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(NSLocalizedString("parentPINReset.step1Description", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                appleProviderNote
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
        .listRowBackground(Color.clear)

        if let error = errorMessage {
            Section {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            .listRowBackground(Color.clear)
        }

        Section {
            Button(action: { Task { await sendCode() } }) {
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(NSLocalizedString("parentPINReset.sendCodeButton", comment: ""))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.purple)
            .disabled(isLoading)
        }
    }

    // Step 2: enter code
    @ViewBuilder
    private func verifyCodeSection(maskedEmail: String) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.purple)

                Text(String(format: NSLocalizedString("parentPINReset.step2Description", comment: ""), maskedEmail))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .listRowBackground(Color.clear)

        Section {
            SecurePINField(placeholder: NSLocalizedString("parentPINReset.codePlaceholder", comment: ""), text: $verificationCode)
                .onChange(of: verificationCode) { _, newValue in
                    if newValue.count > 6 { verificationCode = String(newValue.prefix(6)) }
                }
        } header: {
            Text(NSLocalizedString("parentPINReset.codeHeader", comment: ""))
        }

        if let error = errorMessage {
            Section {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            .listRowBackground(Color.clear)
        }

        Section {
            Button(action: { Task { await verifyCode() } }) {
                HStack {
                    Spacer()
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(NSLocalizedString("parentPINReset.verifyButton", comment: ""))
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.purple)
            .disabled(verificationCode.count != 6 || isLoading)
        }

        Section {
            Button(NSLocalizedString("parentPINReset.resendCode", comment: "")) {
                Task { await sendCode() }
            }
            .foregroundColor(.secondary)
            .disabled(isLoading)
        }
    }

    // Step 3: set new PIN
    @ViewBuilder
    private var setNewPINSection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.purple)

                Text(NSLocalizedString("parentPINReset.step3Title", comment: ""))
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .listRowBackground(Color.clear)

        Section {
            SecurePINField(placeholder: NSLocalizedString("parentPINReset.newPINPlaceholder", comment: ""), text: $newPIN)
                .onChange(of: newPIN) { _, newValue in
                    if newValue.count > 6 { newPIN = String(newValue.prefix(6)) }
                }

            SecurePINField(placeholder: NSLocalizedString("parentPINReset.confirmPINPlaceholder", comment: ""), text: $confirmPIN)
                .onChange(of: confirmPIN) { _, newValue in
                    if newValue.count > 6 { confirmPIN = String(newValue.prefix(6)) }
                }
        } header: {
            Text(NSLocalizedString("parentPINReset.newPINHeader", comment: ""))
        }

        if let error = errorMessage {
            Section {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            .listRowBackground(Color.clear)
        }

        Section {
            Button(action: { setNewPIN() }) {
                Text(NSLocalizedString("parentPINReset.setPINButton", comment: ""))
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
            }
            .listRowBackground(Color.purple)
            .disabled(newPIN.count != 6 || confirmPIN.count != 6)
        }
    }

    @ViewBuilder
    private var appleProviderNote: some View {
        let provider = AuthenticationService.shared.currentUser?.authProvider
        if provider == .apple {
            Text(NSLocalizedString("parentPINReset.appleEmailNote", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        } else if provider == .google {
            Text(NSLocalizedString("parentPINReset.googleEmailNote", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func sendCode() async {
        isLoading = true
        errorMessage = nil
        let (success, maskedEmail, error) = await NetworkService.shared.sendParentPINResetCode()
        await MainActor.run {
            isLoading = false
            if success, let email = maskedEmail {
                step = .verifyCode(maskedEmail: email)
            } else if error == "NO_EMAIL" {
                errorMessage = NSLocalizedString("parentPINReset.noEmail", comment: "")
            } else {
                errorMessage = error ?? NSLocalizedString("parentPINReset.sendFailed", comment: "")
            }
        }
    }

    private func verifyCode() async {
        isLoading = true
        errorMessage = nil
        let (success, error) = await NetworkService.shared.verifyParentPINResetCode(verificationCode)
        await MainActor.run {
            isLoading = false
            if success {
                step = .setNewPIN
            } else {
                errorMessage = error ?? NSLocalizedString("parentPINReset.invalidCode", comment: "")
            }
        }
    }

    private func setNewPIN() {
        guard newPIN == confirmPIN else {
            errorMessage = NSLocalizedString("parentPINReset.mismatch", comment: "")
            return
        }
        guard newPIN.count == 6, newPIN.allSatisfy({ $0.isNumber }) else {
            errorMessage = NSLocalizedString("parentPINReset.invalidPIN", comment: "")
            return
        }
        if parentModeManager.forceResetParentPassword(newPIN) {
            dismiss()
        } else {
            errorMessage = NSLocalizedString("parentPINReset.setPINFailed", comment: "")
        }
    }
}

#Preview {
    PasswordManagementView()
}