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
    @State private var exportedFileURL: URL? = nil
    @State private var isExporting = false
    @State private var showingExportShare = false
    @State private var exportError: String? = nil
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
                                Text(NSLocalizedString("privacy.parentReports.automatedReports", comment: ""))
                                    .font(.headline)
                                Text(NSLocalizedString("privacy.parentReports.automatedReportsDesc", comment: ""))
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
                                    Text(NSLocalizedString("privacy.parentReports.backgroundSync", comment: ""))
                                        .font(.subheadline)
                                    Text(NSLocalizedString("privacy.parentReports.backgroundSyncDesc", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Divider()
                                .padding(.vertical, 4)

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("privacy.parentReports.lastSync", comment: ""))
                                        .font(.subheadline)
                                    if let lastSync = parentReportsSettings.lastSyncTimestamp {
                                        Text(lastSync, style: .relative)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text(NSLocalizedString("privacy.parentReports.never", comment: ""))
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
                                        Text(NSLocalizedString("privacy.parentReports.syncNow", comment: ""))
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
                                    Text(NSLocalizedString("privacy.parentReports.nextReport", comment: ""))
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
                    Text(NSLocalizedString("privacy.parentReports.sectionHeader", comment: ""))
                } footer: {
                    Text(parentReportsSettings.parentReportsEnabled ?
                         NSLocalizedString("privacy.parentReports.footerEnabled", comment: "") :
                         NSLocalizedString("privacy.parentReports.footerDisabled", comment: ""))
                }

                // Data Privacy Section
                Section {
                    Button(action: {
                        Task { await performExportUserData() }
                    }) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .frame(width: 24)
                            } else {
                                Image(systemName: "arrow.down.doc.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                            }

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
                    .disabled(isExporting)

                    Button(action: {
                        showingClearData = true
                    }) {
                        HStack {
                            Image(systemName: "xmark.bin.fill")
                                .foregroundColor(.orange)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("privacy.clearData.title", comment: ""))
                                    .foregroundColor(.primary)
                                Text(NSLocalizedString("privacy.clearData.desc", comment: ""))
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
                    onEnable: {
                        parentReportsSettings.parentReportsEnabled = true
                        handleParentReportsToggle(enabled: true)
                        showingOnboarding = false
                    },
                    onDecline: {
                        parentReportsSettings.parentReportsEnabled = false
                        showingOnboarding = false
                    }
                )
            }
            .sheet(isPresented: $showingExportShare, onDismiss: {
                if let url = exportedFileURL {
                    try? FileManager.default.removeItem(at: url)
                    exportedFileURL = nil
                }
            }) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
            .alert(NSLocalizedString("common.error", comment: ""), isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
            } message: {
                Text(exportError ?? "")
            }
            .alert(NSLocalizedString("privacy.clearData.alertTitle", comment: ""), isPresented: $showingClearData) {
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
                Button(NSLocalizedString("privacy.clearData.alertButton", comment: ""), role: .destructive) {
                    clearMyData()
                }
            } message: {
                Text(NSLocalizedString("privacy.clearData.alertMessage", comment: ""))
            }
            .alert(NSLocalizedString("privacy.settings.deleteAccountAlert.title", comment: ""), isPresented: $showingDeleteAccount) {
                TextField(NSLocalizedString("privacy.deleteAccount.emailPlaceholder", comment: ""), text: $confirmEmailText)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {
                    confirmEmailText = ""
                }
                Button(NSLocalizedString("privacy.settings.deleteAccountAlert.button", comment: ""), role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text(NSLocalizedString("privacy.deleteAccount.alertMessage", comment: ""))
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

    private func performExportUserData() async {
        await MainActor.run { isExporting = true }

        let result = await networkService.exportUserData()

        await MainActor.run {
            isExporting = false
            switch result {
            case .success(let data):
                // Write to a temp file so share sheet can offer Save/AirDrop/Mail
                let fileName = "StudyMates_DataExport_\(DateFormatter.exportDateFormatter.string(from: Date())).json"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                do {
                    try data.write(to: url)
                    exportedFileURL = url
                    showingExportShare = true
                } catch {
                    exportError = error.localizedDescription
                }
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
    }

    private func clearMyData() {
        Task {
            let result = await networkService.clearMyData()
            await MainActor.run {
                clearDataResult = result.success
                    ? "All server data has been cleared. Local data remains intact."
                    : "Failed to clear data: \(result.message)"
            }
        }
    }

    private func deleteAccount() {
        Task {
            let result = await networkService.deleteAccount(confirmEmail: confirmEmailText)
            await MainActor.run {
                if result.success {
                    currentUserQuestionStorage().clearAll()
                    currentUserConversationStorage().clearAll()
                    AuthenticationService.shared.signOut()
                    deleteAccountResult = "Account deleted successfully"
                    confirmEmailText = ""
                } else {
                    deleteAccountResult = "Failed: \(result.message)"
                    confirmEmailText = ""
                }
            }
        }
    }

    // MARK: - Parent Reports Methods

    private func handleParentReportsToggle(enabled: Bool) {
        if enabled {
            // Show agreement screen if not already enabled
            let settings = ParentReportSettings.load()
            if !settings.parentReportsEnabled {
                debugPrint("📊 [PrivacySettings] Showing onboarding before enabling reports")
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
                        debugPrint("✅ [PrivacySettings] Parent reports enabled successfully")
                        parentReportsSettings.parentReportsEnabled = true
                        parentReportsSettings.autoSyncEnabled = true
                        parentReportsSettings.save()
                    } else {
                        debugPrint("❌ [PrivacySettings] Failed to enable parent reports: \(result.message)")
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
                        debugPrint("✅ [PrivacySettings] Parent reports disabled successfully")
                        parentReportsSettings.parentReportsEnabled = false
                        parentReportsSettings.autoSyncEnabled = false
                        parentReportsSettings.save()
                    } else {
                        debugPrint("❌ [PrivacySettings] Failed to disable parent reports: \(result.message)")
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
                debugPrint("🔄 [PrivacySettings] Starting manual sync...")
                let result = try await StorageSyncService.shared.syncAllToServer()

                await MainActor.run {
                    isSyncing = false
                    parentReportsSettings.updateLastSync()
                    parentReportsSettings.save()
                    lastSyncDate = Date()

                    debugPrint("✅ [PrivacySettings] Manual sync completed: \(result.totalSynced) items synced")
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    debugPrint("❌ [PrivacySettings] Manual sync failed: \(error.localizedDescription)")
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

// MARK: - Helpers

private extension DateFormatter {
    static let exportDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
