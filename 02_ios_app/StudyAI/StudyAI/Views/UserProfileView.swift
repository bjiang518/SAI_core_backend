//
//  UserProfileView.swift
//  StudyAI
//
//  Created by Claude Code on 9/9/25.
//

import SwiftUI

struct UserProfileView: View {
    @StateObject private var voiceService = VoiceInteractionService.shared
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var authService = AuthenticationService.shared
    @State private var userName = UserDefaults.standard.string(forKey: "user_name") ?? "Student"
    @State private var userEmail = UserDefaults.standard.string(forKey: "user_email") ?? ""
    @State private var isEditingName = false
    @State private var showingVoiceSettings = false
    @State private var showingLogoutConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    profileHeaderSection
                    
                    // Voice Assistant Section
                    voiceAssistantSection
                    
                    // Settings Sections
                    settingsSection
                    
                    // Account Section
                    accountSection
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Profile & Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showingVoiceSettings) {
            VoiceSettingsView()
        }
        .alert("Sign Out", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
    
    // MARK: - Profile Header Section
    
    private var profileHeaderSection: some View {
        VStack(spacing: 16) {
            // Profile Avatar with Current Voice Character
            CharacterAvatar(
                voiceType: voiceService.voiceSettings.voiceType,
                isAnimating: false,
                size: 100
            )
            
            // User Name
            if isEditingName {
                TextField("Your Name", text: $userName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        saveUserName()
                        isEditingName = false
                    }
            } else {
                HStack {
                    Text(userName)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Button(action: { isEditingName = true }) {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            // Email
            if !userEmail.isEmpty {
                Text(userEmail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Current Voice Character Info
            HStack {
                Image(systemName: voiceService.voiceSettings.voiceType.icon)
                    .foregroundColor(.blue)
                Text("AI Assistant: \\(voiceService.voiceSettings.voiceType.displayName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Voice Assistant Section
    
    private var voiceAssistantSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("AI Voice Assistant", icon: "person.wave.2.fill")
            
            VStack(spacing: 12) {
                // Current Voice Character
                HStack {
                    CharacterAvatar(
                        voiceType: voiceService.voiceSettings.voiceType,
                        isAnimating: voiceService.interactionState == .speaking,
                        size: 50
                    )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(voiceService.voiceSettings.voiceType.displayName)
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text(voiceService.voiceSettings.voiceType.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Change") {
                        showingVoiceSettings = true
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Voice Controls Quick Settings
                VStack(spacing: 12) {
                    // Auto-Speak Toggle
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Speak Responses")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Automatically read AI responses aloud")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { voiceService.voiceSettings.autoSpeakResponses },
                            set: { newValue in
                                var newSettings = voiceService.voiceSettings
                                newSettings.autoSpeakResponses = newValue
                                voiceService.updateVoiceSettings(newSettings)
                            }
                        ))
                        .tint(.blue)
                    }
                    
                    Divider()
                    
                    // Voice Enabled Toggle
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Voice Features")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Enable voice input and output")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { voiceService.isVoiceEnabled },
                            set: { _ in voiceService.toggleVoiceEnabled() }
                        ))
                        .tint(.blue)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Full Voice Settings Button
                Button(action: { showingVoiceSettings = true }) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundColor(.blue)
                        
                        Text("Advanced Voice Settings")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Settings Section
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("App Settings", icon: "gearshape.fill")
            
            VStack(spacing: 1) {
                settingsRow(
                    title: "Notifications",
                    subtitle: "Manage your notification preferences",
                    icon: "bell.fill",
                    action: { /* TODO: Implement notifications settings */ }
                )
                
                settingsRow(
                    title: "Privacy & Data",
                    subtitle: "Control your data and privacy settings",
                    icon: "lock.fill",
                    action: { /* TODO: Implement privacy settings */ }
                )
                
                settingsRow(
                    title: "Study Preferences",
                    subtitle: "Customize your learning experience",
                    icon: "book.fill",
                    action: { /* TODO: Implement study preferences */ }
                )
                
                settingsRow(
                    title: "Help & Support",
                    subtitle: "Get help and contact support",
                    icon: "questionmark.circle.fill",
                    action: { /* TODO: Implement help system */ }
                )
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Account Section
    
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Account", icon: "person.circle.fill")
            
            VStack(spacing: 1) {
                if authService.isAuthenticated {
                    settingsRow(
                        title: "Account Details",
                        subtitle: "View and edit your account information",
                        icon: "person.fill",
                        action: { /* TODO: Implement account details */ }
                    )
                    
                    settingsRow(
                        title: "Subscription",
                        subtitle: "Manage your StudyAI subscription",
                        icon: "creditcard.fill",
                        action: { /* TODO: Implement subscription management */ }
                    )
                    
                    settingsRow(
                        title: "Sign Out",
                        subtitle: "Sign out of your account",
                        icon: "arrow.right.square.fill",
                        textColor: .red,
                        action: { showingLogoutConfirmation = true }
                    )
                } else {
                    settingsRow(
                        title: "Sign In",
                        subtitle: "Sign in to sync your progress",
                        icon: "arrow.right.square.fill",
                        textColor: .blue,
                        action: { /* TODO: Navigate to login */ }
                    )
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)
            
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
        }
    }
    
    private func settingsRow(
        title: String,
        subtitle: String,
        icon: String,
        textColor: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(textColor)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func saveUserName() {
        UserDefaults.standard.set(userName, forKey: "user_name")
    }
    
    private func signOut() {
        authService.signOut()
        // TODO: Navigate back to login or main screen
        dismiss()
    }
}

#Preview {
    UserProfileView()
}