//
//  HomeView.swift
//  StudyAI
//
//  Created by Claude Code on 8/31/25.
//

import SwiftUI

struct HomeView: View {
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var voiceService = VoiceInteractionService.shared
    @State private var userName = UserDefaults.standard.string(forKey: "user_name") ?? "Student"
    @State private var todayProgress: [String: Any]?
    @State private var isLoadingProgress = false
    @State private var navigateToSession = false
    @State private var showingProfile = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Welcome Header with AI Assistant
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Welcome back,")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(userName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            Spacer()
                            
                            // Settings Button
                            Button(action: { showingProfile = true }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        // AI Assistant Status
                        HStack(spacing: 12) {
                            CharacterAvatar(
                                voiceType: voiceService.voiceSettings.voiceType,
                                isAnimating: voiceService.interactionState == .speaking,
                                size: 40
                            )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Assistant: \\(voiceService.voiceSettings.voiceType.displayName)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Text(voiceService.interactionState.displayText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if voiceService.isVoiceEnabled {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "speaker.slash.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(voiceService.voiceSettings.voiceType == .elsa ? 
                                   Color.blue.opacity(0.1) : getCharacterColor().opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(16)
                    
                    // Quick Actions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quick Actions")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            NavigationLink(destination: SessionChatView()) {
                                QuickActionCard(
                                    icon: "message.fill",
                                    title: "Chat Session",
                                    subtitle: "Conversation AI",
                                    color: .blue
                                )
                            }
                            
                            NavigationLink(destination: QuestionView(onNavigateToSession: {
                                navigateToSession = true
                            })) {
                                QuickActionCard(
                                    icon: "questionmark.circle.fill",
                                    title: "Ask Question",
                                    subtitle: "Single Q&A",
                                    color: .green
                                )
                            }
                            
                            NavigationLink(destination: AIHomeworkTestView()) {
                                QuickActionCard(
                                    icon: "brain.head.profile.fill",
                                    title: "AI Homework",
                                    subtitle: "Scan & Parse",
                                    color: .purple
                                )
                            }
                            
                            NavigationLink(destination: ArchivedQuestionsView()) {
                                QuickActionCard(
                                    icon: "archivebox.fill",
                                    title: "Archive",
                                    subtitle: "Saved questions",
                                    color: .orange
                                )
                            }
                            
                            NavigationLink(destination: LearningProgressView()) {
                                QuickActionCard(
                                    icon: "chart.bar.fill",
                                    title: "Progress",
                                    subtitle: "Track learning",
                                    color: .indigo
                                )
                            }
                            
                            NavigationLink(destination: SessionHistoryView()) {
                                QuickActionCard(
                                    icon: "clock.fill",
                                    title: "History",
                                    subtitle: "Past sessions",
                                    color: .pink
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Today's Progress
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today's Progress")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if isLoadingProgress {
                            ProgressView()
                                .frame(height: 100)
                        } else if let progress = todayProgress {
                            TodayProgressCard(progress: progress)
                                .padding(.horizontal)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No progress data yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Start by asking your first question!")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 100)
                        }
                    }
                    
                    // Recent Activity
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Activity")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        RecentActivityCard()
                            .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.vertical)
            }
            .navigationTitle("StudyAI")
            .navigationBarTitleDisplayMode(.large)
            .task {
                loadTodayProgress()
            }
            .sheet(isPresented: $showingProfile) {
                UserProfileView()
            }
            .background {
                // Use NavigationLink without isActive (modern approach)
                if navigateToSession {
                    NavigationLink(destination: SessionChatView()) {
                        EmptyView()
                    }
                    .hidden()
                    .onAppear {
                        navigateToSession = false
                    }
                }
            }
        }
    }
    
    private func loadTodayProgress() {
        // Prevent multiple concurrent calls
        guard !isLoadingProgress else { return }
        
        isLoadingProgress = true
        
        Task {
            let result = await networkService.getProgress()
            
            await MainActor.run {
                isLoadingProgress = false
                if result.success {
                    todayProgress = result.progress
                } else {
                    // Gracefully handle progress API not being available
                    print("⚠️ Progress API not available, using mock data for demo")
                    todayProgress = [
                        "totalQuestions": 0,
                        "accuracy": 0,
                        "streak": 0
                    ]
                }
            }
        }
    }
    
    private func getCharacterColor() -> Color {
        switch voiceService.voiceSettings.voiceType {
        case .elsa: return .blue
        case .optimusPrime: return .blue
        case .spiderman: return .red
        case .groot: return .green
        case .yoda: return .green
        case .ironMan: return .red
        case .friendly: return .pink
        case .teacher: return .indigo
        case .encouraging: return .orange
        case .playful: return .purple
        }
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 100)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.1))
        .cornerRadius(16)
    }
}

struct TodayProgressCard: View {
    let progress: [String: Any]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Learning Stats")
                    .font(.headline)
                Spacer()
                Text("Today")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                ProgressStat(
                    title: "Questions",
                    value: "\(progress["totalQuestions"] as? Int ?? 0)",
                    icon: "questionmark.circle.fill",
                    color: .blue
                )
                
                ProgressStat(
                    title: "Accuracy",
                    value: "\(progress["accuracy"] as? Int ?? 0)%",
                    icon: "target",
                    color: .green
                )
                
                ProgressStat(
                    title: "Streak",
                    value: "\(progress["streak"] as? Int ?? 0)",
                    icon: "flame.fill",
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
}

struct ProgressStat: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecentActivityCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No recent activity")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Your question history will appear here")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
}

#Preview {
    HomeView()
}