//
//  ContentView.swift
//  StudyAI
//
//  Created by Bo Jiang on 8/28/25.
//  Updated by Claude Code on 9/5/25.
//

import SwiftUI

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
    
    var body: some View {
        TabView {
            NavigationView {
                HomeView()
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("Home")
            }
            
            NavigationView {
                QuestionView()
            }
            .tabItem {
                Image(systemName: "questionmark.circle.fill")
                Text("Ask AI")
            }
            
            NavigationView {
                LearningProgressView()
            }
            .tabItem {
                Image(systemName: "chart.bar.fill")
                Text("Progress")
            }
            
            NavigationView {
                SessionHistoryView()
            }
            .tabItem {
                Image(systemName: "clock.fill")
                Text("History")
            }
            
            NavigationView {
                ModernProfileView(onLogout: onLogout)
            }
            .tabItem {
                Image(systemName: "person.fill")
                Text("Profile")
            }
        }
        .tint(.blue) // Modern iOS 26+ accent color
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
