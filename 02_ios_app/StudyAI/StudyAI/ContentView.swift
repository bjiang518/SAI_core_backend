//
//  ContentView.swift
//  StudyAI
//
//  Created by Bo Jiang on 8/28/25.
//  Updated by Claude Code on 9/5/25.
//

import SwiftUI
import Combine

// MARK: - Main Tab Enum
enum MainTab: Int, CaseIterable {
    case home = 0
    case grader = 1
    case chat = 2
    case progress = 3
    case library = 4

    var title: String {
        switch self {
        case .home: return NSLocalizedString("tab.home", comment: "")
        case .grader: return NSLocalizedString("tab.grader", comment: "")
        case .chat: return NSLocalizedString("tab.chat", comment: "")
        case .progress: return NSLocalizedString("tab.progress", comment: "")
        case .library: return NSLocalizedString("tab.library", comment: "")
        }
    }
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .grader: return "magnifyingglass"
        case .chat: return "message.fill"
        case .progress: return "chart.bar.fill"
        case .library: return "books.vertical.fill"
        }
    }
}

struct ContentView: View {
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var sessionManager = SessionManager.shared  // ✅ NEW: Session management
    @StateObject private var networkService = NetworkService.shared
    @Environment(\.scenePhase) private var scenePhase  // ✅ NEW: Monitor app lifecycle
    @State private var showingFaceIDReauth = false  // ✅ NEW: Face ID re-auth sheet

    // COPPA Parental Consent
    @State private var showingParentalConsent = false
    @State private var requiresParentalConsent = false
    @State private var isCheckingConsent = false
    @State private var hasCheckedConsentOnce = false

    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainTabView(onLogout: {
                    authService.signOut()
                })
                .onAppear {
                    // MainTabView appeared
                }
                .fullScreenCover(isPresented: $showingParentalConsent) {
                    ParentalConsentView(
                        childEmail: authService.currentUser?.email ?? "",
                        childDateOfBirth: getUserDateOfBirth(),
                        onConsentGranted: {
                            // Consent granted - dismiss and refresh
                            showingParentalConsent = false
                            requiresParentalConsent = false

                            // User data will be updated automatically after consent verification
                        }
                    )
                }
            } else {
                ModernLoginView(onLoginSuccess: {
                    // Authentication is handled by the service
                })
                .onAppear {
                    // ModernLoginView appeared
                }
            }
        }
        .animationIfNotPowerSaving(.easeInOut(duration: 0.3), value: authService.isAuthenticated)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showingFaceIDReauth) {
            FaceIDReauthView(onSuccess: {
                showingFaceIDReauth = false
            }, onCancel: {
                showingFaceIDReauth = false
                authService.signOut()  // Sign out if user cancels Face ID
            })
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(oldPhase: oldPhase, newPhase: newPhase)
        }
        .onChange(of: authService.requiresFaceIDReauth) { _, requiresReauth in
            // Show Face ID re-auth sheet when session expires
            if requiresReauth && authService.currentUser != nil {
                print("🔐 [ContentView] Session expired, showing Face ID re-authentication")
                showingFaceIDReauth = true
            }
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            // Check parental consent when user authenticates
            if isAuthenticated {
                checkParentalConsent()
            } else {
                // Reset consent state on logout
                hasCheckedConsentOnce = false
                requiresParentalConsent = false
            }
        }
        .onAppear {
            // ContentView appeared - check consent if authenticated
            if authService.isAuthenticated && !hasCheckedConsentOnce {
                checkParentalConsent()
            }
        }
    }

    // MARK: - Parental Consent Check

    private func checkParentalConsent() {
        guard !isCheckingConsent && !hasCheckedConsentOnce else { return }

        isCheckingConsent = true
        hasCheckedConsentOnce = true

        print("🔍 [ContentView] Checking parental consent status...")

        Task {
            let result = await networkService.checkConsentStatus()

            await MainActor.run {
                isCheckingConsent = false

                print("📋 [ContentView] Consent check result: requires=\(result.requiresConsent), status=\(result.consentStatus ?? "none"), restricted=\(result.isRestricted)")

                // Show consent screen if:
                // 1. User requires parental consent AND
                // 2. Consent is not yet granted (pending, required, or denied)
                if result.requiresConsent && result.isRestricted {
                    let needsConsent = result.consentStatus != "granted"
                    if needsConsent {
                        print("⚠️ [ContentView] Parental consent required - showing consent screen")
                        requiresParentalConsent = true
                        showingParentalConsent = true
                    } else {
                        print("✅ [ContentView] Parental consent already granted")
                    }
                }
            }
        }
    }

    private func getUserDateOfBirth() -> String? {
        // Date of birth is verified on the backend based on profile data
        // Pass nil here - backend will use stored profile information
        return nil
    }

    // MARK: - App Lifecycle Handling

    private func handleScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) {
        print("🔐 [ContentView] Scene phase changed: \(oldPhase) → \(newPhase)")

        switch newPhase {
        case .background:
            // App is going to background - session will be ended immediately
            print("🔐 [ContentView] App entering background - session will be ended (Face ID required on reopen)")
            sessionManager.appWillResignActive()

        case .active:
            // App is returning to foreground - session was ended, so Face ID is required
            print("🔐 [ContentView] App returning to foreground - checking if re-authentication is needed")
            let isSessionValid = sessionManager.appDidBecomeActive()

            if !isSessionValid && authService.currentUser != nil {
                // Session expired (either from background or timeout)
                print("🔐 [ContentView] Session expired - triggering Face ID re-authentication")
                Task { @MainActor in
                    authService.isAuthenticated = false
                    authService.requiresFaceIDReauth = true
                }
            }

        case .inactive:
            // App is temporarily inactive (e.g., during transition)
            print("🔐 [ContentView] App inactive (transition state)")

        @unknown default:
            break
        }
    }
}

struct MainTabView: View {
    let onLogout: () -> Void
    @StateObject private var appState = AppState.shared
    @StateObject private var sessionManager = SessionManager.shared  // ✅ Track user activity

    var body: some View {
        TabView(selection: Binding(
            get: { appState.selectedTab.rawValue },
            set: { appState.selectedTab = MainTab(rawValue: $0) ?? .home }
        )) {
            // Home Tab
            NavigationStack {
                HomeView(onSelectTab: selectTab)
                    .onAppear {
                        sessionManager.updateActivity()
                    }
            }
            .tabItem {
                Image(systemName: MainTab.home.icon)
                Text(MainTab.home.title)
                    .font(.caption2)
            }
            .tag(MainTab.home.rawValue)

            // Grader Tab
            NavigationStack {
                DirectAIHomeworkView()
                    .environmentObject(appState)  // ✅ FIX: Inject AppState environment object
                    .onAppear {
                        sessionManager.updateActivity()
                    }
            }
            .tabItem {
                Image(systemName: MainTab.grader.icon)
                Text(MainTab.grader.title)
                    .font(.caption2)
            }
            .tag(MainTab.grader.rawValue)

            // Chat Tab
            NavigationStack {
                SessionChatView()
                    .onAppear {
                        sessionManager.updateActivity()
                    }
            }
            .tabItem {
                Image(systemName: MainTab.chat.icon)
                Text(MainTab.chat.title)
                    .font(.caption2)
            }
            .tag(MainTab.chat.rawValue)

            // Progress Tab
            NavigationStack {
                LearningProgressView()
                    .onAppear {
                        sessionManager.updateActivity()
                    }
            }
            .tabItem {
                Image(systemName: MainTab.progress.icon)
                Text(MainTab.progress.title)
                    .font(.caption2)
            }
            .tag(MainTab.progress.rawValue)

            // Library Tab
            NavigationStack {
                UnifiedLibraryView()
                    .environmentObject(appState)  // ✅ FIX: Inject AppState for "Ask AI" feature
                    .onAppear {
                        sessionManager.updateActivity()
                    }
            }
            .tabItem {
                Image(systemName: MainTab.library.icon)
                Text(MainTab.library.title)
                    .font(.caption2)
            }
            .tag(MainTab.library.rawValue)
        }
        .tint(.blue)
        .onChange(of: appState.selectedTab) { oldTab, newTab in
            // Tab selection changed - update session activity
            sessionManager.updateActivity()
            print("🔐 [MainTabView] Tab changed: \(oldTab) → \(newTab), session activity updated")
        }
        .onAppear {
            // MainTabView appeared - update session activity
            sessionManager.updateActivity()
            print("🔐 [MainTabView] MainTabView appeared, session activity updated")
        }
    }

    private func selectTab(_ tab: MainTab) {
        appState.selectedTab = tab
    }
}

struct ModernProfileView: View {
    let onLogout: () -> Void
    @ObservedObject private var authService = AuthenticationService.shared
    @ObservedObject private var profileService = ProfileService.shared
    @ObservedObject private var appState = AppState.shared
    @State private var showingBiometricSetup = false
    @State private var showingEditProfile = false
    @State private var showingLearningGoals = false
    @State private var showingVoiceSettings = false
    @State private var showingNotificationSettings = false
    @State private var showingLanguageSettings = false
    @State private var showingPasswordManagement = false
    @State private var showingParentControls = false
    @State private var showingHelpCenter = false
    @State private var showingContactSupport = false
    @State private var showingShareSheet = false
    @State private var showingStorageControl = false
    @State private var showingPrivacySettings = false

    var body: some View {
        NavigationView {
            List {
                // PROFILE HEADER SECTION (Tappable to Edit Profile)
                Section {
                    Button(action: { showingEditProfile = true }) {
                        HStack(spacing: 16) {
                            // Profile Image / Avatar
                            if let profile = profileService.currentProfile,
                               let avatarId = profile.avatarId,
                               let avatar = ProfileAvatar.from(id: avatarId) {
                                // Display selected avatar
                                Image(avatar.imageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                            } else {
                                // Fallback to gradient circle with initial
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        .frame(width: 60, height: 60)

                                    if let user = authService.currentUser {
                                        Text(String(user.name.prefix(1)))
                                            .font(.title)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    } else {
                                        Image(systemName: "person.fill")
                                            .font(.title)
                                            .foregroundColor(.white)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                // Display full name from profile if available
                                if let profile = profileService.currentProfile {
                                    Text(profile.fullName)
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                } else {
                                    Text(authService.currentUser?.name ?? "User")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                }

                                Text(authService.currentUser?.email ?? "user@example.com")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                // Auth provider badge
                                if let provider = authService.currentUser?.authProvider {
                                    HStack(spacing: 4) {
                                        Image(systemName: authProviderIcon(provider))
                                            .font(.caption)
                                        Text(provider.rawValue.capitalized)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(8)
                                }
                            }

                            Spacer()

                            // Chevron to indicate tappable
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }

                // STUDY SETTINGS SECTION (Voice + Learning Goals combined)
                Section(NSLocalizedString("settings.studySettings", comment: "Study Settings")) {
                    Button(action: {
                        showingVoiceSettings = true
                    }) {
                        SettingsRow(icon: "waveform", title: NSLocalizedString("settings.voiceSettings", comment: ""), color: .indigo)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        showingLearningGoals = true
                    }) {
                        SettingsRow(icon: "target", title: NSLocalizedString("settings.learningGoals", comment: ""), color: .red)
                    }
                    .buttonStyle(.plain)
                }

                // APP SETTINGS SECTION
                Section(NSLocalizedString("settings.appSettings", comment: "")) {
                    Button(action: {
                        showingNotificationSettings = true
                    }) {
                        SettingsRow(icon: "bell.fill", title: NSLocalizedString("settings.studyReminders", comment: ""), color: .orange)
                    }
                    .buttonStyle(.plain)

                    SettingsRow(icon: "textformat.size", title: NSLocalizedString("settings.textSize", comment: ""), color: .green)

                    Button(action: {
                        showingLanguageSettings = true
                    }) {
                        SettingsRow(icon: "globe", title: NSLocalizedString("settings.language", comment: ""), color: .blue)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        showingStorageControl = true
                    }) {
                        SettingsRow(icon: "externaldrive.fill", title: NSLocalizedString("settings.storageControl", comment: ""), color: .purple)
                    }
                    .buttonStyle(.plain)

                    // Power Saving Mode Toggle
                    HStack(spacing: 12) {
                        Image(systemName: "battery.100")
                            .foregroundColor(.green)
                            .frame(width: 20)

                        Text(NSLocalizedString("settings.powerSavingMode", comment: ""))
                            .font(.body)

                        Spacer()

                        Toggle("", isOn: $appState.isPowerSavingMode)
                            .tint(.green)
                    }
                }

                // SECURITY SECTION
                Section(NSLocalizedString("settings.security", comment: "")) {
                    if authService.getBiometricType() != "None" {
                        HStack(spacing: 12) {
                            Image(systemName: authService.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                                .foregroundColor(.green)
                                .frame(width: 20)

                            Text("\(authService.getBiometricType()) Login")
                                .font(.body)

                            Spacer()

                            Toggle("", isOn: .constant(authService.canUseBiometrics()))
                                .disabled(true)
                        }
                    }

                    Button(action: {
                        showingPasswordManagement = true
                    }) {
                        SettingsRow(icon: "key.fill", title: NSLocalizedString("settings.passwordManager", comment: ""), color: .blue)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        showingParentControls = true
                    }) {
                        SettingsRow(icon: "person.2.fill", title: NSLocalizedString("settings.parentControls", comment: ""), color: .purple)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        showingPrivacySettings = true
                    }) {
                        SettingsRow(icon: "lock.shield.fill", title: NSLocalizedString("settings.privacySettings", comment: ""), color: .orange)
                    }
                    .buttonStyle(.plain)
                }

                // SUPPORT SECTION
                Section(NSLocalizedString("settings.support", comment: "")) {
                    Button(action: {
                        showingHelpCenter = true
                    }) {
                        SettingsRow(icon: "questionmark.circle.fill", title: NSLocalizedString("settings.help", comment: ""), color: .blue)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        showingContactSupport = true
                    }) {
                        SettingsRow(icon: "envelope.fill", title: NSLocalizedString("settings.contact", comment: ""), color: .green)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        rateApp()
                    }) {
                        SettingsRow(icon: "star.fill", title: NSLocalizedString("settings.rateApp", comment: ""), color: .yellow)
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        showingShareSheet = true
                    }) {
                        SettingsRow(icon: "square.and.arrow.up.fill", title: NSLocalizedString("settings.shareApp", comment: ""), color: .cyan)
                    }
                    .buttonStyle(.plain)
                }

                // SIGN OUT SECTION (separate at bottom)
                Section {
                    Button(action: onLogout) {
                        HStack {
                            Image(systemName: "arrow.right.square.fill")
                                .foregroundColor(.red)
                                .frame(width: 20)
                            Text(NSLocalizedString("settings.signOut", comment: ""))
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                // APP INFO SECTION
                Section {
                    VStack(spacing: 8) {
                        Text("StudyMates v1.0")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Enhanced with Modern Authentication")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Powered by OpenAI GPT-4")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(NSLocalizedString("settings.title", comment: ""))
            .onAppear {
                Task {
                    await profileService.loadProfileAfterLogin()
                }
            }
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
        }
        .onChange(of: showingEditProfile) { oldValue, newValue in
            // Reload profile when returning from Edit Profile
            if oldValue == true && newValue == false {
                Task {
                    try? await profileService.getUserProfile()
                }
            }
        }
        .sheet(isPresented: $showingLearningGoals) {
            LearningGoalsSettingsView()
        }
        .sheet(isPresented: $showingVoiceSettings) {
            VoiceSettingsView()
        }
        .sheet(isPresented: $showingNotificationSettings) {
            NotificationSettingsView()
        }
        .sheet(isPresented: $showingLanguageSettings) {
            LanguageSettingsView()
        }
        .sheet(isPresented: $showingStorageControl) {
            StorageControlView()
        }
        .sheet(isPresented: $showingPasswordManagement) {
            PasswordManagementView()
        }
        .sheet(isPresented: $showingParentControls) {
            ParentAuthenticationView(
                title: "Parent Controls",
                message: "Verify parental access to manage settings",
                onSuccess: {
                    // Parent authenticated - show controls
                    showingParentControls = false
                }
            )
        }
        .sheet(isPresented: $showingHelpCenter) {
            HelpCenterView()
        }
        .sheet(isPresented: $showingContactSupport) {
            ContactSupportView()
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareAppView()
        }
        .sheet(isPresented: $showingPrivacySettings) {
            PrivacySettingsView()
        }
    }

    private func rateApp() {
        if let url = URL(string: "https://apps.apple.com/app/id6504105201?action=write-review") {
            UIApplication.shared.open(url)
        }
    }

    private func authProviderIcon(_ provider: AuthProvider) -> String {
        switch provider {
        case .email:
            return "envelope.fill"
        case .google:
            return "globe"
        case .apple:
            return "applelogo"
        case .phone:
            return "phone.fill"
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)

            Text(title)
                .font(.body)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    ContentView()
}
