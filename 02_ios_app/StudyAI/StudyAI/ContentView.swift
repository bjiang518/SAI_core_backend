//
//  ContentView.swift
//  StudyAI
//
//  Created by Bo Jiang on 8/28/25.
//  Updated by Claude Code on 9/5/25.
//

import SwiftUI

// MARK: - Main Tab Enum
enum MainTab: Int, CaseIterable {
    case home = 0
    case grader = 1
    case chat = 2
    case progress = 3
    case library = 4
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .grader: return "Grader"
        case .chat: return "Chat"
        case .progress: return "Progress"
        case .library: return "Library"
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

    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainTabView(onLogout: {
                    authService.signOut()
                })
                .onAppear {
                    // MainTabView appeared
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
        .animation(.easeInOut(duration: 0.3), value: authService.isAuthenticated)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            // ContentView appeared
        }
    }
}

struct MainTabView: View {
    let onLogout: () -> Void
    @State private var selectedTab: MainTab = .home

    var body: some View {
        TabView(selection: Binding(
            get: { selectedTab.rawValue },
            set: { selectedTab = MainTab(rawValue: $0) ?? .home }
        )) {
            // Home Tab
            NavigationStack {
                HomeView(onSelectTab: selectTab)
                    .onAppear {
                        // HomeView appeared
                    }
            }
            .tabItem {
                Image(systemName: MainTab.home.icon)
                Text(MainTab.home.title)
            }
            .tag(MainTab.home.rawValue)
            
            // Grader Tab  
            NavigationStack {
                DirectAIHomeworkView()
                    .onAppear {
                        // DirectAIHomeworkView appeared
                    }
            }
            .tabItem {
                Image(systemName: MainTab.grader.icon)
                Text(MainTab.grader.title)
            }
            .tag(MainTab.grader.rawValue)
            
            // Chat Tab
            NavigationStack {
                SessionChatView()
                    .onAppear {
                        // SessionChatView appeared
                    }
            }
            .tabItem {
                Image(systemName: MainTab.chat.icon)
                Text(MainTab.chat.title)
            }
            .tag(MainTab.chat.rawValue)
            
            // Progress Tab
            NavigationStack {
                
                LearningProgressView()
                    .onAppear {
                        // LearningProgressView appeared
                    }
            }
            .tabItem {
                Image(systemName: MainTab.progress.icon)
                Text(MainTab.progress.title)
            }
            .tag(MainTab.progress.rawValue)
            
            // Library Tab
            NavigationStack {
                UnifiedLibraryView()
                    .onAppear {
                        // UnifiedLibraryView appeared
                    }
            }
            .tabItem {
                Image(systemName: MainTab.library.icon)
                Text(MainTab.library.title)
            }
            .tag(MainTab.library.rawValue)
        }
        .tint(.blue)
        .onChange(of: selectedTab) { oldTab, newTab in
            // Tab selection changed
        }
        .onAppear {
            // MainTabView appeared
        }
    }
    
    private func selectTab(_ tab: MainTab) {
        selectedTab = tab
    }
}

struct ModernProfileView: View {
    let onLogout: () -> Void
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var profileService = ProfileService.shared
    @State private var showingBiometricSetup = false
    @State private var showingEditProfile = false
    @State private var showingLearningGoals = false
    
    var body: some View {
        NavigationView {
            List {
                // User Profile Section
                Section {
                    HStack(spacing: 16) {
                        // Profile Image
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
                        
                        VStack(alignment: .leading, spacing: 4) {
                            // Display full name from profile if available
                            if let profile = profileService.currentProfile {
                                Text(profile.fullName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                            } else {
                                Text(authService.currentUser?.name ?? "User")
                                    .font(.title2)
                                    .fontWeight(.bold)
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
                            
                            // Profile completion indicator
                            if let profile = profileService.currentProfile {
                                HStack(spacing: 4) {
                                    Image(systemName: "person.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(profile.isProfileComplete ? .green : .orange)
                                    Text("Profile \(profile.profileCompletionPercentage)% complete")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                // Account Section
                Section("Account") {
                    Button(action: { showingEditProfile = true }) {
                        SettingsRow(
                            icon: "person.crop.circle.fill", 
                            title: "Edit Profile", 
                            color: .blue
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onLogout) {
                        HStack {
                            Image(systemName: "arrow.right.square.fill")
                                .foregroundColor(.red)
                                .frame(width: 20)
                            Text("Sign Out")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // Security Section
                Section("Security & Privacy") {
                    if authService.getBiometricType() != "None" {
                        HStack {
                            SettingsRow(
                                icon: authService.getBiometricType() == "Face ID" ? "faceid" : "touchid",
                                title: "\(authService.getBiometricType()) Login",
                                color: .green
                            )
                            
                            Spacer()
                            
                            Toggle("", isOn: .constant(authService.canUseBiometrics()))
                                .disabled(true)
                        }
                    }
                    
                    SettingsRow(icon: "key.fill", title: "Password Manager", color: .blue)
                    SettingsRow(icon: "lock.shield.fill", title: "Privacy Settings", color: .orange)
                }
                
                // App Settings Section
                Section("App Settings") {
                    SettingsRow(icon: "bell.fill", title: "Notifications", color: .orange)
                    SettingsRow(icon: "textformat.size", title: "Text Size", color: .green)
                    SettingsRow(icon: "globe", title: "Language", color: .blue)
                }
                
                // Learning Section
                Section("Learning") {
                    Button(action: {
                        showingLearningGoals = true
                    }) {
                        SettingsRow(icon: "target", title: "Learning Goals & Progress", color: .red)
                    }
                    .buttonStyle(.plain)
                    
                    SettingsRow(icon: "book.fill", title: "Subjects", color: .purple)
                    SettingsRow(icon: "clock.fill", title: "Study Reminders", color: .orange)
                    SettingsRow(icon: "archivebox.fill", title: "Question Archive", color: .teal)
                }
                
                // Support Section
                Section("Support") {
                    SettingsRow(icon: "questionmark.circle.fill", title: "Help & FAQ", color: .blue)
                    SettingsRow(icon: "envelope.fill", title: "Contact Support", color: .green)
                    SettingsRow(icon: "star.fill", title: "Rate App", color: .yellow)
                    SettingsRow(icon: "square.and.arrow.up.fill", title: "Share App", color: .cyan)
                }
                
                // App Info Section
                Section {
                    VStack(spacing: 8) {
                        Text("StudyAI v1.0")
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
            .navigationTitle("Settings")
            .onAppear {
                Task {
                    await profileService.loadProfileAfterLogin()
                }
            }
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
        }
        .sheet(isPresented: $showingLearningGoals) {
            LearningGoalsSettingsView()
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
