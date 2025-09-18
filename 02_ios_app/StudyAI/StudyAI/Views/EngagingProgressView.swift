//
//  EngagingProgressView.swift
//  StudyAI
//
//  Created by Claude Code on 9/18/25.
//

import SwiftUI

struct EngagingProgressView: View {
    @StateObject private var networkService = NetworkService.shared
    @State private var progressData: [String: Any]?
    @State private var isLoading = true
    @State private var selectedSection = 0
    @State private var showingAchievements = false
    @State private var animateOnAppear = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                // Gradient Background
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.1),
                        Color.purple.opacity(0.1),
                        Color.cyan.opacity(0.1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else if let progress = progressData {
                    mainProgressView(progress)
                } else {
                    errorView
                }
            }
            .navigationTitle("Your Progress")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadProgressData()
            withAnimation(.easeInOut(duration: 0.8).delay(0.2)) {
                animateOnAppear = true
            }
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.blue)
            
            Text("Loading your amazing progress...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Error View
    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Unable to load progress")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Please check your connection and try again")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                loadProgressData()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    // MARK: - Main Progress View
    @ViewBuilder
    private func mainProgressView(_ progress: [String: Any]) -> some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // Hero Stats Section
                heroStatsSection(progress)
                
                // Section Picker
                sectionPicker
                
                // Dynamic Content Based on Selection
                Group {
                    switch selectedSection {
                    case 0:
                        overviewSection(progress)
                    case 1:
                        streakSection(progress)
                    case 2:
                        achievementsSection(progress)
                    case 3:
                        subjectsSection(progress)
                    default:
                        overviewSection(progress)
                    }
                }
                .animation(.easeInOut(duration: 0.5), value: selectedSection)
                
                // AI Motivation Message
                aiMotivationSection(progress)
            }
            .padding(.horizontal)
            .padding(.bottom, 100)
        }
    }
    
    // MARK: - Hero Stats Section
    @ViewBuilder
    private func heroStatsSection(_ progress: [String: Any]) -> some View {
        VStack(spacing: 20) {
            // Level and XP
            levelAndXPCard(progress)
            
            // Today's Performance
            todayPerformanceCard(progress)
        }
        .scaleEffect(animateOnAppear ? 1.0 : 0.8)
        .opacity(animateOnAppear ? 1.0 : 0.0)
    }
    
    @ViewBuilder
    private func levelAndXPCard(_ progress: [String: Any]) -> some View {
        VStack(spacing: 16) {
            // Level Badge
            HStack {
                Text("Level")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("\(getCurrentLevel(progress))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            }
            
            // XP Progress Bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Experience Points")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("\(getTotalXP(progress)) XP")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 12)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geometry.size.width * (getXPProgress(progress) / 100.0),
                                height: 12
                            )
                            .animation(.easeInOut(duration: 1.5), value: getXPProgress(progress))
                    }
                }
                .frame(height: 12)
                
                Text("Next level in \(getXPToNextLevel(progress)) XP")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .blue.opacity(0.1), radius: 10, x: 0, y: 5)
    }
    
    @ViewBuilder
    private func todayPerformanceCard(_ progress: [String: Any]) -> some View {
        HStack(spacing: 20) {
            // XP Ring
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: getDailyGoalProgress(progress) / 100.0)
                    .stroke(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 1.5), value: getDailyGoalProgress(progress))
                
                VStack(spacing: 2) {
                    Text("\(getTodayXP(progress))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("XP today")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Stats Grid
            VStack(alignment: .leading, spacing: 12) {
                statRow(
                    icon: "questionmark.circle.fill",
                    label: "Questions",
                    value: "\(getTodayQuestions(progress))",
                    color: .blue
                )
                
                statRow(
                    icon: "checkmark.circle.fill",
                    label: "Correct",
                    value: "\(getTodayCorrect(progress))",
                    color: .green
                )
                
                statRow(
                    icon: "target",
                    label: "Accuracy",
                    value: "\(getTodayAccuracy(progress))%",
                    color: .orange
                )
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .green.opacity(0.1), radius: 10, x: 0, y: 5)
    }
    
    @ViewBuilder
    private func statRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Section Picker
    private var sectionPicker: some View {
        Picker("Section", selection: $selectedSection) {
            Text("Overview").tag(0)
            Text("Streak").tag(1)
            Text("Achievements").tag(2)
            Text("Subjects").tag(3)
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal)
    }
    
    // MARK: - Overview Section
    @ViewBuilder
    private func overviewSection(_ progress: [String: Any]) -> some View {
        VStack(spacing: 20) {
            // Weekly Overview
            weeklyOverviewCard(progress)
            
            // Daily Goal
            dailyGoalCard(progress)
            
            // Recent Milestones
            milestonesCard(progress)
        }
    }
    
    @ViewBuilder
    private func weeklyOverviewCard(_ progress: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This Week")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            HStack(spacing: 20) {
                weekStatItem(
                    title: "Days Active",
                    value: "\(getWeekDaysActive(progress))/7",
                    icon: "calendar.badge.checkmark",
                    color: .blue
                )
                
                weekStatItem(
                    title: "Questions",
                    value: "\(getWeekQuestions(progress))",
                    icon: "questionmark.bubble.fill",
                    color: .green
                )
                
                weekStatItem(
                    title: "Accuracy",
                    value: "\(getWeekAccuracy(progress))%",
                    icon: "target",
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .blue.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    @ViewBuilder
    private func weekStatItem(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func dailyGoalCard(_ progress: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily Goal")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if getDailyGoalCompleted(progress) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
            
            Text(getDailyGoalMessage(progress))
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 16)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: getDailyGoalCompleted(progress) ? [.green, .mint] : [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * (getDailyGoalProgress(progress) / 100.0),
                            height: 16
                        )
                        .animation(.easeInOut(duration: 1.0), value: getDailyGoalProgress(progress))
                }
            }
            .frame(height: 16)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .blue.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    @ViewBuilder
    private func milestonesCard(_ progress: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Next Milestones")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            if let milestones = getNextMilestones(progress) {
                ForEach(0..<min(milestones.count, 3), id: \.self) { index in
                    let milestone = milestones[index]
                    milestoneRow(milestone)
                }
            } else {
                Text("Keep studying to unlock milestones!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .purple.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    @ViewBuilder
    private func milestoneRow(_ milestone: [String: Any]) -> some View {
        HStack(spacing: 12) {
            if let iconName = milestone["icon"] as? String {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(.purple)
                    .frame(width: 24)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(milestone["title"] as? String ?? "Milestone")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                let progress = milestone["progress"] as? Int ?? 0
                let target = milestone["target"] as? Int ?? 100
                let percentage = target > 0 ? Double(progress) / Double(target) : 0.0
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.purple)
                            .frame(
                                width: geometry.size.width * percentage,
                                height: 6
                            )
                            .animation(.easeInOut(duration: 0.8), value: percentage)
                    }
                }
                .frame(height: 6)
                
                Text("\(progress)/\(target)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Streak Section
    @ViewBuilder
    private func streakSection(_ progress: [String: Any]) -> some View {
        VStack(spacing: 20) {
            // Current Streak Card
            currentStreakCard(progress)
            
            // Streak Stats
            streakStatsCard(progress)
            
            // Streak Calendar (Mock Implementation)
            streakCalendarCard()
        }
    }
    
    @ViewBuilder
    private func currentStreakCard(_ progress: [String: Any]) -> some View {
        VStack(spacing: 20) {
            // Flame Animation
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                getFlameColor(streak: getCurrentStreak(progress)).opacity(0.2),
                                getFlameColor(streak: getCurrentStreak(progress)).opacity(0.05)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "flame.fill")
                    .font(.system(size: 60))
                    .foregroundColor(getFlameColor(streak: getCurrentStreak(progress)))
                    .scaleEffect(getFlameScale(streak: getCurrentStreak(progress)))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: getCurrentStreak(progress))
            }
            
            VStack(spacing: 8) {
                Text("\(getCurrentStreak(progress))")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("Day Streak")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Text(getStreakMessage(getCurrentStreak(progress)))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: getFlameColor(streak: getCurrentStreak(progress)).opacity(0.2), radius: 15, x: 0, y: 8)
    }
    
    @ViewBuilder
    private func streakStatsCard(_ progress: [String: Any]) -> some View {
        HStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("\(getCurrentStreak(progress))")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Current")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            VStack(spacing: 8) {
                Text("\(getLongestStreak(progress))")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Best Ever")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            VStack(spacing: 8) {
                Text("\(getStreakLevel(getCurrentStreak(progress)))")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Flame Level")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .orange.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    @ViewBuilder
    private func streakCalendarCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // Simple calendar grid (7x4 for 4 weeks)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(0..<28, id: \.self) { day in
                    Rectangle()
                        .fill(getDayActivityColor(day: day))
                        .frame(height: 30)
                        .cornerRadius(6)
                }
            }
            
            HStack {
                Text("Less")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    ForEach([Color.gray.opacity(0.2), Color.green.opacity(0.3), Color.green.opacity(0.6), Color.green.opacity(0.9), Color.green], id: \.self) { color in
                        Rectangle()
                            .fill(color)
                            .frame(width: 12, height: 12)
                            .cornerRadius(2)
                    }
                }
                
                Text("More")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .green.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Achievements Section
    @ViewBuilder
    private func achievementsSection(_ progress: [String: Any]) -> some View {
        VStack(spacing: 20) {
            // Achievements Header
            achievementsHeaderCard(progress)
            
            // Recent Achievements
            if let achievements = getRecentAchievements(progress), !achievements.isEmpty {
                recentAchievementsCard(achievements)
            }
            
            // Available Achievements (Mock)
            availableAchievementsCard()
        }
    }
    
    @ViewBuilder
    private func achievementsHeaderCard(_ progress: [String: Any]) -> some View {
        HStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.yellow)
                
                Text("\(getTotalAchievements(progress))")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Unlocked")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 8) {
                Text("Achievement Progress")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                let total = getTotalAchievements(progress)
                let available = getAvailableAchievements(progress)
                let percentage = available > 0 ? Double(total) / Double(available) : 0.0
                
                Text("\(total) of \(available)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 12)
                        
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geometry.size.width * percentage,
                                height: 12
                            )
                            .animation(.easeInOut(duration: 1.0), value: percentage)
                    }
                }
                .frame(height: 12)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .yellow.opacity(0.2), radius: 10, x: 0, y: 5)
    }
    
    @ViewBuilder
    private func recentAchievementsCard(_ achievements: [[String: Any]]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Achievements")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            ForEach(0..<min(achievements.count, 3), id: \.self) { index in
                let achievement = achievements[index]
                achievementRow(achievement)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .orange.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    @ViewBuilder
    private func achievementRow(_ achievement: [String: Any]) -> some View {
        HStack(spacing: 12) {
            if let iconName = achievement["icon"] as? String {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(.orange)
                    .frame(width: 32, height: 32)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(achievement["achievement_name"] as? String ?? "Achievement")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                if let description = achievement["description"] as? String {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(achievement["xp_reward"] as? Int ?? 0) XP")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                
                if let rarity = achievement["rarity"] as? String {
                    Text(rarity.capitalized)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func availableAchievementsCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Coming Soon")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // Mock upcoming achievements
            VStack(spacing: 12) {
                upcomingAchievementRow(
                    name: "Study Master",
                    description: "Answer 100 questions correctly",
                    icon: "graduationcap.fill",
                    progress: 67,
                    target: 100
                )
                
                upcomingAchievementRow(
                    name: "Math Wizard",
                    description: "Master 5 math topics",
                    icon: "function",
                    progress: 3,
                    target: 5
                )
                
                upcomingAchievementRow(
                    name: "Consistency King",
                    description: "Maintain a 30-day streak",
                    icon: "crown.fill",
                    progress: getCurrentStreak(progressData ?? [:]),
                    target: 30
                )
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .gray.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    @ViewBuilder
    private func upcomingAchievementRow(name: String, description: String, icon: String, progress: Int, target: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.gray)
                .frame(width: 28, height: 28)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue)
                            .frame(
                                width: geometry.size.width * (Double(progress) / Double(target)),
                                height: 6
                            )
                            .animation(.easeInOut(duration: 0.5), value: progress)
                    }
                }
                .frame(height: 6)
            }
            
            Spacer()
            
            Text("\(progress)/\(target)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Subjects Section
    @ViewBuilder
    private func subjectsSection(_ progress: [String: Any]) -> some View {
        VStack(spacing: 20) {
            if let subjects = getSubjects(progress), !subjects.isEmpty {
                ForEach(0..<subjects.count, id: \.self) { index in
                    let subject = subjects[index]
                    subjectCard(subject)
                }
            } else {
                Text("Start studying to see subject progress!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }
    
    @ViewBuilder
    private func subjectCard(_ subject: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(subject["name"] as? String ?? "Subject")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(subject["xp"] as? Int ?? 0) XP")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            
            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(subject["questions"] as? Int ?? 0)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Questions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 4) {
                    Text("\(subject["correct"] as? Int ?? 0)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    Text("Correct")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 4) {
                    Text("\(subject["accuracy"] as? Int ?? 0)%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    
                    Text("Accuracy")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Proficiency Bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Proficiency")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(subject["proficiency"] as? String ?? "Beginner")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 10)
                        
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geometry.size.width * (Double(subject["accuracy"] as? Int ?? 0) / 100.0),
                                height: 10
                            )
                            .animation(.easeInOut(duration: 1.0), value: subject["accuracy"] as? Int ?? 0)
                    }
                }
                .frame(height: 10)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .purple.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - AI Motivation Section
    @ViewBuilder
    private func aiMotivationSection(_ progress: [String: Any]) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundColor(.cyan)
                
                Text("AI Study Companion")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Text(getAIMessage(progress))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.cyan.opacity(0.1), Color.blue.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Helper Functions
    
    private func loadProgressData() {
        isLoading = true
        
        Task {
            let result = await networkService.getEnhancedProgress()
            
            await MainActor.run {
                isLoading = false
                if result.success, let data = result.progress?["data"] as? [String: Any] {
                    progressData = data
                } else {
                    progressData = nil
                }
            }
        }
    }
    
    // Data extraction helpers
    private func getCurrentLevel(_ progress: [String: Any]) -> Int {
        return progress.dig("overall", "current_level") as? Int ?? 1
    }
    
    private func getTotalXP(_ progress: [String: Any]) -> Int {
        return progress.dig("overall", "total_xp") as? Int ?? 0
    }
    
    private func getXPProgress(_ progress: [String: Any]) -> Double {
        return progress.dig("overall", "xp_progress") as? Double ?? 0.0
    }
    
    private func getXPToNextLevel(_ progress: [String: Any]) -> Int {
        return progress.dig("overall", "xp_to_next_level") as? Int ?? 100
    }
    
    private func getTodayXP(_ progress: [String: Any]) -> Int {
        return progress.dig("today", "xp_earned") as? Int ?? 0
    }
    
    private func getTodayQuestions(_ progress: [String: Any]) -> Int {
        return progress.dig("today", "questions_answered") as? Int ?? 0
    }
    
    private func getTodayCorrect(_ progress: [String: Any]) -> Int {
        return progress.dig("today", "correct_answers") as? Int ?? 0
    }
    
    private func getTodayAccuracy(_ progress: [String: Any]) -> Int {
        return progress.dig("today", "accuracy") as? Int ?? 0
    }
    
    private func getCurrentStreak(_ progress: [String: Any]) -> Int {
        return progress.dig("streak", "current") as? Int ?? 0
    }
    
    private func getLongestStreak(_ progress: [String: Any]) -> Int {
        return progress.dig("streak", "longest") as? Int ?? 0
    }
    
    private func getWeekDaysActive(_ progress: [String: Any]) -> Int {
        return progress.dig("week", "days_active") as? Int ?? 0
    }
    
    private func getWeekQuestions(_ progress: [String: Any]) -> Int {
        return progress.dig("week", "total_questions") as? Int ?? 0
    }
    
    private func getWeekAccuracy(_ progress: [String: Any]) -> Int {
        return progress.dig("week", "accuracy") as? Int ?? 0
    }
    
    private func getDailyGoalProgress(_ progress: [String: Any]) -> Double {
        return progress.dig("daily_goal", "progress_percentage") as? Double ?? 0.0
    }
    
    private func getDailyGoalCompleted(_ progress: [String: Any]) -> Bool {
        return progress.dig("daily_goal", "completed") as? Bool ?? false
    }
    
    private func getDailyGoalMessage(_ progress: [String: Any]) -> String {
        let current = progress.dig("daily_goal", "current") as? Int ?? 0
        let target = progress.dig("daily_goal", "target") as? Int ?? 5
        let completed = getDailyGoalCompleted(progress)
        
        if completed {
            return "🎯 Amazing! You've completed your daily goal!"
        } else {
            let remaining = target - current
            return "Keep going! \(remaining) more question\(remaining == 1 ? "" : "s") to reach your goal."
        }
    }
    
    private func getNextMilestones(_ progress: [String: Any]) -> [[String: Any]]? {
        return progress["next_milestones"] as? [[String: Any]]
    }
    
    private func getRecentAchievements(_ progress: [String: Any]) -> [[String: Any]]? {
        return progress.dig("achievements", "recent") as? [[String: Any]]
    }
    
    private func getTotalAchievements(_ progress: [String: Any]) -> Int {
        return progress.dig("achievements", "total_unlocked") as? Int ?? 0
    }
    
    private func getAvailableAchievements(_ progress: [String: Any]) -> Int {
        return progress.dig("achievements", "available_count") as? Int ?? 10
    }
    
    private func getSubjects(_ progress: [String: Any]) -> [[String: Any]]? {
        return progress["subjects"] as? [[String: Any]]
    }
    
    private func getAIMessage(_ progress: [String: Any]) -> String {
        return progress["ai_message"] as? String ?? "Keep up the great work! Every question you answer makes you stronger. 💪"
    }
    
    private func getFlameColor(streak: Int) -> Color {
        switch streak {
        case 0: return .gray
        case 1...2: return .orange
        case 3...6: return .red
        case 7...13: return .purple
        default: return .blue
        }
    }
    
    private func getFlameScale(streak: Int) -> Double {
        switch streak {
        case 0: return 0.8
        case 1...2: return 1.0
        case 3...6: return 1.1
        case 7...13: return 1.2
        default: return 1.3
        }
    }
    
    private func getStreakLevel(_ streak: Int) -> Int {
        return min(streak / 3, 4)
    }
    
    private func getStreakMessage(_ streak: Int) -> String {
        switch streak {
        case 0:
            return "Start your learning journey today!"
        case 1:
            return "Great start! Keep the momentum going."
        case 2...6:
            return "You're building a solid habit!"
        case 7...13:
            return "Incredible consistency! You're on fire!"
        case 14...29:
            return "Amazing dedication! You're a study champion!"
        default:
            return "Legendary commitment! You're unstoppable!"
        }
    }
    
    private func getDayActivityColor(day: Int) -> Color {
        // Mock activity data - in real app this would come from heatmap data
        let activity = Int.random(in: 0...4)
        switch activity {
        case 0: return Color.gray.opacity(0.2)
        case 1: return Color.green.opacity(0.3)
        case 2: return Color.green.opacity(0.6)
        case 3: return Color.green.opacity(0.9)
        default: return Color.green
        }
    }
}

// MARK: - Dictionary Extension for Safe Access
extension Dictionary {
    func dig(_ keys: Any...) -> Any? {
        var current: Any = self
        
        for key in keys {
            if let dict = current as? [String: Any], let stringKey = key as? String {
                current = dict[stringKey] ?? NSNull()
            } else if let dict = current as? [AnyHashable: Any], let hashableKey = key as? AnyHashable {
                current = dict[hashableKey] ?? NSNull()
            } else {
                return nil
            }
            
            if current is NSNull {
                return nil
            }
        }
        
        return current
    }
}

#Preview {
    EngagingProgressView()
}