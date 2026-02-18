//
//  PrivacySettingsView.swift
//  StudyAI
//
//  Privacy and consent management settings
//

import SwiftUI

struct PrivacySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var authService = AuthenticationService.shared

    @State private var isLoadingConsent = false
    @State private var consentStatus: ConsentStatusInfo?
    @State private var showingParentalConsent = false
    @State private var showingDataExport = false
    @State private var showingClearData = false
    @State private var showingDeleteAccount = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false
    @State private var confirmEmailText = ""
    @State private var clearDataResult: String? = nil
    @State private var deleteAccountResult: String? = nil

    // Parent Reports State
    @State private var parentReportsSettings = ParentReportSettings.load()
    @State private var isEnablingReports = false
    @State private var isSyncing = false
    @State private var lastSyncDate: Date?
    @State private var showingOnboarding = false

    var body: some View {
        NavigationView {
            List {
                // COPPA Parental Consent Section
                if let consent = consentStatus, consent.requiresConsent {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "person.2.fill")
                                    .foregroundColor(.blue)
                                    .font(.title2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("privacy.settings.parentalConsent", comment: ""))
                                        .font(.headline)

                                    Text(consentStatusText)
                                        .font(.subheadline)
                                        .foregroundColor(consentStatusColor)
                                }
                            }
                            .padding(.bottom, 4)

                            if consent.isRestricted {
                                Text(NSLocalizedString("privacy.settings.coppaNotice", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.bottom, 8)

                                Button(action: {
                                    showingParentalConsent = true
                                }) {
                                    HStack {
                                        Image(systemName: "envelope.fill")
                                        Text(NSLocalizedString("privacy.settings.requestConsent", comment: ""))
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                            } else {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(NSLocalizedString("privacy.settings.consentGranted", comment: ""))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text(NSLocalizedString("privacy.settings.coppaCompliance", comment: ""))
                    }
                }

                // Parent Reports Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $parentReportsSettings.parentReportsEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Automated Weekly Reports")
                                    .font(.headline)
                                Text("Generate parent reports every Sunday at 9 PM")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .disabled(isEnablingReports)
                        .onChange(of: parentReportsSettings.parentReportsEnabled) { _, newValue in
                            handleParentReportsToggle(enabled: newValue)
                        }

                        if parentReportsSettings.parentReportsEnabled {
                            Divider()
                                .padding(.vertical, 4)

                            Toggle(isOn: $parentReportsSettings.autoSyncEnabled) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Background Homework Sync")
                                        .font(.subheadline)
                                    Text("Automatically sync homework data for reports")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Divider()
                                .padding(.vertical, 4)

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Last Sync")
                                        .font(.subheadline)
                                    if let lastSync = parentReportsSettings.lastSyncTimestamp {
                                        Text(lastSync, style: .relative)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Never")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Button(action: {
                                    manualSync()
                                }) {
                                    if isSyncing {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                    } else {
                                        Text("Sync Now")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                    }
                                }
                                .disabled(isSyncing)
                            }

                            if parentReportsSettings.parentReportsEnabled {
                                Divider()
                                    .padding(.vertical, 4)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Next Report")
                                        .font(.subheadline)
                                    Text(parentReportsSettings.nextReportDescription())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Parent Reports")
                } footer: {
                    Text(parentReportsSettings.parentReportsEnabled ?
                         "Reports are generated every Sunday at 9 PM using homework data synced throughout the week." :
                         "Enable automated weekly parent reports to track learning progress.")
                }

                // Data Privacy Section
                Section {
                    Button(action: {
                        showingDataExport = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.doc.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("privacy.settings.exportData", comment: ""))
                                    .foregroundColor(.primary)
                                Text(NSLocalizedString("privacy.settings.exportDataDesc", comment: ""))
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

                    Button(action: {
                        showingClearData = true
                    }) {
                        HStack {
                            Image(systemName: "xmark.bin.fill")
                                .foregroundColor(.orange)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Clear Server Data")
                                    .foregroundColor(.primary)
                                Text("Delete all learning data from server (keeps local data)")
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

                    Button(action: {
                        showingDeleteAccount = true
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                                .foregroundColor(.red)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("privacy.settings.deleteAccount", comment: ""))
                                    .foregroundColor(.red)
                                Text(NSLocalizedString("privacy.settings.deleteAccountDesc", comment: ""))
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
                    Text(NSLocalizedString("privacy.settings.dataManagement", comment: ""))
                } footer: {
                    Text(NSLocalizedString("privacy.settings.dataManagementFooter", comment: ""))
                }

                // Privacy Information Section
                Section {
                    Button(action: {
                        showingPrivacyPolicy = true
                    }) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)

                            Text(NSLocalizedString("privacy.settings.privacyPolicy", comment: ""))
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        showingTermsOfService = true
                    }) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.blue)
                                .frame(width: 24)

                            Text(NSLocalizedString("privacy.settings.termsOfService", comment: ""))
                                .foregroundColor(.primary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(NSLocalizedString("privacy.settings.legal", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("privacy.settings.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadConsentStatus()
            }
            .refreshable {
                loadConsentStatus()
            }
            .sheet(isPresented: $showingParentalConsent) {
                ParentalConsentView(
                    childEmail: authService.currentUser?.email ?? "",
                    childDateOfBirth: nil,
                    onConsentGranted: {
                        showingParentalConsent = false
                        // Reload consent status
                        loadConsentStatus()
                    }
                )
            }
            .sheet(isPresented: $showingPrivacyPolicy) {
                PrivacyPolicyView()
            }
            .sheet(isPresented: $showingTermsOfService) {
                TermsOfServiceView()
            }
            .sheet(isPresented: $showingOnboarding) {
                ParentReportsOnboardingView(
                    onComplete: {
                        // Save completion state and enable reports
                        var settings = ParentReportSettings.load()
                        settings.hasSeenOnboarding = true
                        settings.save()
                        showingOnboarding = false

                        // Now actually enable the reports since onboarding completed
                        parentReportsSettings.parentReportsEnabled = true
                        handleParentReportsToggle(enabled: true)
                    },
                    onSkip: {
                        // Mark as seen but don't enable
                        var settings = ParentReportSettings.load()
                        settings.hasSeenOnboarding = true
                        settings.save()
                        showingOnboarding = false

                        // Revert toggle since they skipped
                        parentReportsSettings.parentReportsEnabled = false
                    }
                )
            }
            .alert(NSLocalizedString("privacy.settings.exportDataAlert.title", comment: ""), isPresented: $showingDataExport) {
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("privacy.settings.exportDataAlert.button", comment: "")) {
                    exportUserData()
                }
            } message: {
                Text(NSLocalizedString("privacy.settings.exportDataAlert.message", comment: ""))
            }
            .alert("Clear My Data", isPresented: $showingClearData) {
                Button("Cancel", role: .cancel) { }
                Button("Clear Server Data", role: .destructive) {
                    clearMyData()
                }
            } message: {
                Text("This will permanently delete all your learning data from the SERVER:\n\n• Homework questions (784 questions)\n• Chat conversations\n• Parent reports\n• Progress tracking\n\nYour LOCAL data will remain intact. Your account will remain active. This action cannot be undone.")
            }
            .alert(NSLocalizedString("privacy.settings.deleteAccountAlert.title", comment: ""), isPresented: $showingDeleteAccount) {
                TextField("Enter your email to confirm", text: $confirmEmailText)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                    confirmEmailText = ""
                }
                Button(NSLocalizedString("privacy.settings.deleteAccountAlert.button", comment: ""), role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("This will permanently delete your account and ALL data. Please enter your email to confirm.")
            }
        }
    }

    private var consentStatusText: String {
        guard let consent = consentStatus else { return NSLocalizedString("privacy.settings.consentStatus.loading", comment: "") }

        if !consent.requiresConsent {
            return NSLocalizedString("privacy.settings.consentStatus.notRequired", comment: "")
        }

        switch consent.consentStatus {
        case "granted":
            return NSLocalizedString("privacy.settings.consentStatus.granted", comment: "")
        case "pending":
            return NSLocalizedString("privacy.settings.consentStatus.pending", comment: "")
        case "expired":
            return NSLocalizedString("privacy.settings.consentStatus.expired", comment: "")
        case "denied":
            return NSLocalizedString("privacy.settings.consentStatus.denied", comment: "")
        default:
            return NSLocalizedString("privacy.settings.consentStatus.required", comment: "")
        }
    }

    private var consentStatusColor: Color {
        guard let consent = consentStatus else { return .secondary }

        if !consent.requiresConsent {
            return .secondary
        }

        switch consent.consentStatus {
        case "granted":
            return .green
        case "pending":
            return .orange
        case "expired":
            return .red
        case "denied":
            return .red
        default:
            return .red
        }
    }

    private func loadConsentStatus() {
        isLoadingConsent = true

        Task {
            let result = await networkService.checkConsentStatus()

            await MainActor.run {
                consentStatus = ConsentStatusInfo(
                    requiresConsent: result.requiresConsent,
                    consentStatus: result.consentStatus,
                    isRestricted: result.isRestricted
                )
                isLoadingConsent = false
            }
        }
    }

    private func exportUserData() {
        // TODO: Implement data export
        // Call /api/user/export-data endpoint
        print("Export user data requested")
    }

    private func clearMyData() {
        Task {
            do {
                guard let token = AuthenticationService.shared.getAuthToken() else {
                    print("❌ No authentication token")
                    return
                }

                guard let url = URL(string: "https://sai-backend-production.up.railway.app/api/user/clear-my-data") else {
                    print("❌ Invalid URL")
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                print("🗑️ Calling clear-my-data endpoint...")
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid response")
                    return
                }

                print("📡 Response status: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("✅ Server data cleared successfully:")
                        print(json)

                        await MainActor.run {
                            clearDataResult = "All server data has been cleared. Local data remains intact."
                            // ✅ DO NOT clear local storage - only server data is cleared
                            // Local data will remain for offline access
                        }
                    }
                } else {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("❌ Failed to clear data: \(errorText)")
                    await MainActor.run {
                        clearDataResult = "Failed to clear data: \(errorText)"
                    }
                }
            } catch {
                print("❌ Error clearing data: \(error.localizedDescription)")
                await MainActor.run {
                    clearDataResult = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteAccount() {
        Task {
            do {
                guard let token = AuthenticationService.shared.getAuthToken() else {
                    print("❌ No authentication token")
                    return
                }

                guard let url = URL(string: "https://sai-backend-production.up.railway.app/api/user/delete-account") else {
                    print("❌ Invalid URL")
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let requestBody: [String: Any] = [
                    "confirmEmail": confirmEmailText
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                print("🗑️ Calling delete-account endpoint with email: \(confirmEmailText)")
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid response")
                    return
                }

                print("📡 Response status: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 200 {
                    print("✅ Account deleted successfully")

                    await MainActor.run {
                        // Clear local storage
                        QuestionLocalStorage.shared.clearAll()
                        ConversationLocalStorage.shared.clearAll()

                        // Log out user
                        AuthenticationService.shared.signOut()

                        deleteAccountResult = "Account deleted successfully"
                        confirmEmailText = ""
                    }
                } else {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("❌ Failed to delete account: \(errorText)")
                    await MainActor.run {
                        deleteAccountResult = "Failed: \(errorText)"
                        confirmEmailText = ""
                    }
                }
            } catch {
                print("❌ Error deleting account: \(error.localizedDescription)")
                await MainActor.run {
                    deleteAccountResult = "Error: \(error.localizedDescription)"
                    confirmEmailText = ""
                }
            }
        }
    }

    // MARK: - Parent Reports Methods

    private func handleParentReportsToggle(enabled: Bool) {
        if enabled {
            // Check if onboarding has been seen
            let settings = ParentReportSettings.load()
            if !settings.hasSeenOnboarding {
                print("📊 [PrivacySettings] Showing onboarding before enabling reports")
                showingOnboarding = true
                return  // Don't proceed with enabling yet - onboarding will handle it
            }
        }

        // Proceed with actual enable/disable
        isEnablingReports = true

        Task {
            if enabled {
                // Enable parent reports on backend
                let result = await networkService.enableParentReports(
                    timezone: TimeZone.current.identifier,
                    reportDay: 0,  // Sunday
                    reportHour: 21  // 9 PM
                )

                await MainActor.run {
                    isEnablingReports = false

                    if result.success {
                        print("✅ [PrivacySettings] Parent reports enabled successfully")
                        parentReportsSettings.parentReportsEnabled = true
                        parentReportsSettings.autoSyncEnabled = true
                        parentReportsSettings.save()
                    } else {
                        print("❌ [PrivacySettings] Failed to enable parent reports: \(result.message)")
                        // Revert toggle
                        parentReportsSettings.parentReportsEnabled = false
                    }
                }
            } else {
                // Disable parent reports on backend
                let result = await networkService.disableParentReports()

                await MainActor.run {
                    isEnablingReports = false

                    if result.success {
                        print("✅ [PrivacySettings] Parent reports disabled successfully")
                        parentReportsSettings.parentReportsEnabled = false
                        parentReportsSettings.autoSyncEnabled = false
                        parentReportsSettings.save()
                    } else {
                        print("❌ [PrivacySettings] Failed to disable parent reports: \(result.message)")
                        // Revert toggle
                        parentReportsSettings.parentReportsEnabled = true
                    }
                }
            }
        }
    }

    private func manualSync() {
        isSyncing = true

        Task {
            do {
                print("🔄 [PrivacySettings] Starting manual sync...")
                let result = try await StorageSyncService.shared.syncAllToServer()

                await MainActor.run {
                    isSyncing = false
                    parentReportsSettings.updateLastSync()
                    parentReportsSettings.save()
                    lastSyncDate = Date()

                    print("✅ [PrivacySettings] Manual sync completed: \(result.totalSynced) items synced")
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    print("❌ [PrivacySettings] Manual sync failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct ConsentStatusInfo {
    let requiresConsent: Bool
    let consentStatus: String?
    let isRestricted: Bool
}

#Preview {
    PrivacySettingsView()
}
