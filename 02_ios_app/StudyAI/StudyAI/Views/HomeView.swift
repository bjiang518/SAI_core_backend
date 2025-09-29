//
//  HomeView.swift
//  StudyAI
//
//  Created by Claude Code on 8/31/25.
//

import SwiftUI
import os.log

struct HomeView: View {
    let onSelectTab: (MainTab) -> Void
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var voiceService = VoiceInteractionService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @State private var userName = UserDefaults.standard.string(forKey: "user_name") ?? "Student"
    @State private var navigateToSession = false
    @State private var showingProfile = false
    @State private var showingMistakeReview = false
    @State private var showingQuestionGeneration = false
    @State private var showingParentReports = false
    
    private let logger = Logger(subsystem: "com.studyai", category: "HomeView")
    
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

                            #if DEBUG
                            // Debug Reset Button (only in debug builds)
                            VStack(spacing: 4) {
                                Button(action: {
                                    print("🔄 DEBUG: Forcing daily reset...")
                                    pointsManager.clearLastResetDate()
                                    pointsManager.forceCheckDailyReset()
                                    print("🔄 DEBUG: Daily reset completed!")
                                }) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                Text("Reset")
                                    .font(.system(size: 8))
                                    .foregroundColor(.red)
                            }
                            #endif
                        }
                        
                        // AI Assistant Status
                        HStack(spacing: 12) {
                            CharacterAvatar(
                                voiceType: voiceService.voiceSettings.voiceType,
                                isAnimating: voiceService.interactionState == .speaking,
                                size: 40
                            )
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Assistant: \(voiceService.voiceSettings.voiceType.displayName)")
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
                        .background(getCharacterColor().opacity(0.1))
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
                            Button(action: {
                                onSelectTab(.chat)
                            }) {
                                QuickActionCard(
                                    icon: "message.fill",
                                    title: "Chat Session",
                                    subtitle: "Conversation AI",
                                    color: .blue
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                showingQuestionGeneration = true
                            }) {
                                QuickActionCard(
                                    icon: "brain.head.profile.fill",
                                    title: "Generate Questions",
                                    subtitle: "AI Practice",
                                    color: .mint
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                onSelectTab(.library)
                            }) {
                                QuickActionCard(
                                    icon: "books.vertical.fill",
                                    title: "Library",
                                    subtitle: "Study sessions",
                                    color: .teal
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                onSelectTab(.grader)
                            }) {
                                QuickActionCard(
                                    icon: "magnifyingglass",
                                    title: "AI Homework",
                                    subtitle: "Scan & Parse",
                                    color: .purple
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                onSelectTab(.progress)
                            }) {
                                QuickActionCard(
                                    icon: "chart.bar.fill",
                                    title: "Progress",
                                    subtitle: "Track learning",
                                    color: .indigo
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: { showingMistakeReview = true }) {
                                QuickActionCard(
                                    icon: "arrow.uturn.backward.circle.fill",
                                    title: "Mistake Review",
                                    subtitle: "Learn & improve",
                                    color: .orange
                                )
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: { showingParentReports = true }) {
                                QuickActionCard(
                                    icon: "doc.text.fill",
                                    title: "Parent Reports",
                                    subtitle: "Study insights",
                                    color: .teal
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal)
                    }
                    
                    // Today's Progress
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today's Progress")
                            .font(.headline)
                            .padding(.horizontal)

                        if let todayProgress = pointsManager.todayProgress {
                            TodayProgressCard(todayProgress: todayProgress)
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
            .onAppear {
                logger.info("🏠 === HOME VIEW BODY onAppear CALLED ===")
                logger.info("🏠 HomeView main content is loading")
            }
            .onDisappear {
                logger.info("🏠 === HOME VIEW BODY onDisappear CALLED ===")
                logger.info("🏠 HomeView main content is disappearing")
            }
            .sheet(isPresented: $showingProfile) {
                ModernProfileView(onLogout: {
                    // Handle logout - this should trigger app-wide logout
                    AuthenticationService.shared.signOut()
                    showingProfile = false
                })
            }
            .sheet(isPresented: $showingMistakeReview) {
                MistakeReviewView()
            }
            .sheet(isPresented: $showingQuestionGeneration) {
                QuestionGenerationView()
            }
            .sheet(isPresented: $showingParentReports) {
                ParentReportsView()
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

    private func getCharacterColor() -> Color {
        switch voiceService.voiceSettings.voiceType {
        case .adam: return .blue      // Boy color
        case .eva: return .pink       // Girl color
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
    let todayProgress: DailyProgress
    @ObservedObject private var pointsManager = PointsEarningManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Learning Stats")
                    .font(.headline)
                Spacer()
                #if DEBUG
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Daily pts: \(pointsManager.dailyPointsEarned)")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                }
                #else
                Text("Today")
                    .font(.caption)
                    .foregroundColor(.secondary)
                #endif
            }

            HStack(spacing: 20) {
                ProgressStat(
                    title: "Questions",
                    value: "\(todayProgress.totalQuestions)",
                    icon: "questionmark.circle.fill",
                    color: .blue
                )

                ProgressStat(
                    title: "Accuracy",
                    value: "\(Int(todayProgress.accuracy))%",
                    icon: "target",
                    color: .green
                )

                ProgressStat(
                    title: "Streak",
                    value: "\(pointsManager.currentStreak)",
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
    HomeView(onSelectTab: { _ in })
}