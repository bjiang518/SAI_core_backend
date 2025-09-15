//
//  ContentView.swift
//  StudyAI
//
//  Created by Bo Jiang on 8/28/25.
//  Updated by Claude Code on 9/5/25.
//

import SwiftUI
import os.log

// MARK: - Main Tab Enum
enum MainTab: Int, CaseIterable {
    case home = 0
    case chat = 1
    case progress = 2
    case library = 3
    case profile = 4
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .chat: return "Chat"
        case .progress: return "Progress"
        case .library: return "Library"
        case .profile: return "Profile"
        }
    }
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .chat: return "message.fill"
        case .progress: return "chart.bar.fill"
        case .library: return "books.vertical.fill"
        case .profile: return "person.fill"
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
            } else {
                ModernLoginView(onLoginSuccess: {
                    // Authentication is handled by the service
                })
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.isAuthenticated)
        .ignoresSafeArea(.keyboard, edges: .bottom) // Modern keyboard handling
    }
}

struct MainTabView: View {
    let onLogout: () -> Void
    @State private var selectedTab: MainTab = .home
    
    private let logger = Logger(subsystem: "com.studyai", category: "MainTabView")
    
    var body: some View {
        TabView(selection: Binding(
            get: { selectedTab.rawValue },
            set: { selectedTab = MainTab(rawValue: $0) ?? .home }
        )) {
            // Home Tab
            NavigationStack {
                HomeView(onSelectTab: selectTab)
                    .onAppear {
                        logger.info("🏠 === HOME VIEW APPEARED ===")
                        logger.info("🏠 HomeView is now displayed (Tab 0)")
                    }
            }
            .tabItem {
                Image(systemName: MainTab.home.icon)
                Text(MainTab.home.title)
            }
            .tag(MainTab.home.rawValue)
            
            // Chat Tab  
            NavigationStack {
                DirectAIHomeworkView()
                    .onAppear {
                        logger.info("🤖 === AI HOMEWORK VIEW APPEARED ===")
                        logger.info("🤖 DirectAIHomeworkView is now displayed (Tab 1)")
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
                        logger.info("📊 === LEARNING PROGRESS VIEW APPEARED ===")
                        logger.info("📊 LearningProgressView is now displayed (Tab 2)")
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
                        logger.info("📚 === UNIFIED LIBRARY VIEW APPEARED ===")
                        logger.info("📚 UnifiedLibraryView is now displayed (Tab 3)")
                    }
            }
            .tabItem {
                Image(systemName: MainTab.library.icon)
                Text(MainTab.library.title)
            }
            .tag(MainTab.library.rawValue)
            
            // Profile Tab
            NavigationStack {
                ModernProfileView(onLogout: onLogout)
                    .onAppear {
                        logger.info("👤 === MODERN PROFILE VIEW APPEARED ===")
                        logger.info("👤 ModernProfileView is now displayed (Tab 4)")
                    }
            }
            .tabItem {
                Image(systemName: MainTab.profile.icon)
                Text(MainTab.profile.title)
            }
            .tag(MainTab.profile.rawValue)
        }
        .tint(.blue) // Modern iOS accent color
        .onChange(of: selectedTab) { oldTab, newTab in
            logger.info("🔄 === TAB SELECTION CHANGED ===")
            logger.info("🔄 Previous tab: \(oldTab.rawValue) → New tab: \(newTab.rawValue)")
            
            switch newTab {
            case .home:
                logger.info("📍 User pressed HOME button (Tab 0) - should show HomeView")
            case .chat:
                logger.info("📍 User pressed CHAT button (Tab 1) - should show DirectAIHomeworkView")
            case .progress:
                logger.info("📍 User pressed PROGRESS button (Tab 2) - should show LearningProgressView")
            case .library:
                logger.info("📍 User pressed LIBRARY button (Tab 3) - should show UnifiedLibraryView")
            case .profile:
                logger.info("📍 User pressed PROFILE button (Tab 4) - should show ModernProfileView")
            }
        }
        .onAppear {
            logger.info("🚀 === MAIN TAB VIEW APPEARED ===")
            logger.info("🚀 Initial selected tab: \(selectedTab.rawValue)")
        }
    }
    
    private func selectTab(_ tab: MainTab) {
        selectedTab = tab
        logger.info("🎯 Programmatically selected tab: \(tab.title)")
    }
}

struct ModernProfileView: View {
    let onLogout: () -> Void
    @StateObject private var authService = AuthenticationService.shared
    @State private var showingBiometricSetup = false
    
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
                            Text(authService.currentUser?.name ?? "User")
                                .font(.title2)
                                .fontWeight(.bold)
                            
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
                    }
                    .padding(.vertical, 8)
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
                    SettingsRow(icon: "moon.fill", title: "Dark Mode", color: .indigo)
                    SettingsRow(icon: "textformat.size", title: "Text Size", color: .green)
                    SettingsRow(icon: "globe", title: "Language", color: .blue)
                }
                
                // Learning Section
                Section("Learning") {
                    SettingsRow(icon: "target", title: "Daily Goals", color: .red)
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
                
                // Account Section
                Section("Account") {
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
            .navigationTitle("Profile")
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
