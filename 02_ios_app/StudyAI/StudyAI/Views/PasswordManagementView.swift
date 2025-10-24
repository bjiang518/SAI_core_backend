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
        NavigationView {
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
                                Text("Change Account Password")
                                    .font(.body)
                                    .foregroundColor(.primary)

                                Text("Update your login password")
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
                    Text("Account Security")
                } footer: {
                    Text("Manage your StudyMates account password for login")
                }

                // Parent Mode Section
                Section {
                    // Parent Mode Status
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.purple)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Parent Mode")
                                .font(.body)
                                .foregroundColor(.primary)

                            Text(parentModeManager.isParentModeEnabled ? "Enabled" : "Not Set")
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
                                    Text("Set Parent Password")
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Text("Create a 6-digit PIN")
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
                                    Text("Change Parent Password")
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Text("Update your 6-digit PIN")
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
                                    Text("Remove Parent Password")
                                        .font(.body)
                                        .foregroundColor(.red)

                                    Text("Disable parent mode")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Parent Controls")
                } footer: {
                    Text("Parent mode restricts access to sensitive features with a 6-digit PIN. Once enabled, certain features will require parent authentication.")
                }
            }
            .navigationTitle("Password Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
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
        NavigationView {
            Form {
                Section {
                    SecureField("Current Password", text: $currentPassword)
                        .textContentType(.password)

                    SecureField("New Password", text: $newPassword)
                        .textContentType(.newPassword)

                    SecureField("Confirm New Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                } header: {
                    Text("Change Password")
                } footer: {
                    Text("Password must be at least 8 characters")
                }

                Section {
                    Button(action: {
                        // Placeholder - will implement actual password change
                        alertMessage = "Password change functionality will be implemented soon"
                        showingAlert = true
                    }) {
                        Text("Change Password")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.blue)
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Change Password", isPresented: $showingAlert) {
                Button("OK", role: .cancel) {
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
        NavigationView {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.purple)

                        Text("Set Parent Password")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Create a 6-digit PIN to protect sensitive features")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)

                Section {
                    SecurePINField(placeholder: "6-Digit PIN", text: $password)
                        .onChange(of: password) { _, newValue in
                            if newValue.count > 6 {
                                password = String(newValue.prefix(6))
                            }
                        }

                    SecurePINField(placeholder: "Confirm PIN", text: $confirmPassword)
                        .onChange(of: confirmPassword) { _, newValue in
                            if newValue.count > 6 {
                                confirmPassword = String(newValue.prefix(6))
                            }
                        }
                } header: {
                    Text("Create PIN")
                } footer: {
                    Text("Enter a 6-digit number that only parents/guardians know")
                }

                Section {
                    Button(action: {
                        setParentPassword()
                    }) {
                        Text("Set Parent Password")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.purple)
                    .disabled(password.count != 6 || confirmPassword.count != 6)
                }
            }
            .navigationTitle("Parent Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Parent Mode", isPresented: $showingAlert) {
                Button("OK", role: .cancel) {
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
            alertMessage = "PINs do not match. Please try again."
            showingAlert = true
            return
        }

        guard password.count == 6, password.allSatisfy({ $0.isNumber }) else {
            alertMessage = "PIN must be exactly 6 digits."
            showingAlert = true
            return
        }

        if parentModeManager.setParentPassword(password) {
            alertMessage = "✅ Parent password set successfully!"
            showingAlert = true
        } else {
            alertMessage = "Failed to set parent password. Please try again."
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

    var body: some View {
        NavigationView {
            Form {
                Section {
                    SecurePINField(placeholder: "Current PIN", text: $currentPassword)
                        .onChange(of: currentPassword) { _, newValue in
                            if newValue.count > 6 {
                                currentPassword = String(newValue.prefix(6))
                            }
                        }
                } header: {
                    Text("Current Password")
                }

                Section {
                    SecurePINField(placeholder: "New 6-Digit PIN", text: $newPassword)
                        .onChange(of: newPassword) { _, newValue in
                            if newValue.count > 6 {
                                newPassword = String(newValue.prefix(6))
                            }
                        }

                    SecurePINField(placeholder: "Confirm New PIN", text: $confirmPassword)
                        .onChange(of: confirmPassword) { _, newValue in
                            if newValue.count > 6 {
                                confirmPassword = String(newValue.prefix(6))
                            }
                        }
                } header: {
                    Text("New Password")
                } footer: {
                    Text("Enter a new 6-digit PIN")
                }

                Section {
                    Button(action: {
                        changeParentPassword()
                    }) {
                        Text("Change Password")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.orange)
                    .disabled(currentPassword.count != 6 || newPassword.count != 6 || confirmPassword.count != 6)
                }
            }
            .navigationTitle("Change Parent Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Change Password", isPresented: $showingAlert) {
                Button("OK", role: .cancel) {
                    if alertMessage.contains("success") {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func changeParentPassword() {
        guard newPassword == confirmPassword else {
            alertMessage = "New PINs do not match. Please try again."
            showingAlert = true
            return
        }

        let result = parentModeManager.changeParentPassword(
            currentPassword: currentPassword,
            newPassword: newPassword
        )

        if result.success {
            alertMessage = "✅ Parent password changed successfully!"
            showingAlert = true
        } else {
            alertMessage = result.error ?? "Failed to change password"
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

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.red)

                        Text("Remove Parent Mode")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("This will disable parent mode and remove all restrictions")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)

                Section {
                    SecurePINField(placeholder: "Enter Current PIN", text: $password)
                        .onChange(of: password) { _, newValue in
                            if newValue.count > 6 {
                                password = String(newValue.prefix(6))
                            }
                        }
                } header: {
                    Text("Verify Password")
                } footer: {
                    Text("Enter your current parent PIN to confirm removal")
                }

                Section {
                    Button(action: {
                        removeParentPassword()
                    }) {
                        Text("Remove Parent Mode")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(Color.red)
                    .disabled(password.count != 6)
                }
            }
            .navigationTitle("Remove Parent Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Remove Parent Mode", isPresented: $showingAlert) {
                Button("OK", role: .cancel) {
                    if alertMessage.contains("success") {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func removeParentPassword() {
        if parentModeManager.removeParentPassword(password: password) {
            alertMessage = "✅ Parent mode has been removed"
            showingAlert = true
        } else {
            alertMessage = "❌ Incorrect PIN. Please try again."
            showingAlert = true
        }
    }
}

#Preview {
    PasswordManagementView()
}