//
//  HomeProgressSketch.swift
//  StudyAI
//
//  Created by Claude Code on 9/18/25.
//

import SwiftUI

struct HomeProgressSketch: View {
    @StateObject private var networkService = NetworkService.shared
    @State private var progressData: [String: Any]?
    @State private var isLoading = false
    @State private var showingProgressView = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Today's Progress")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { showingProgressView = true }) {
                    Text("View All")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading progress...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 100)
            } else if let progress = progressData {
                progressContent(progress)
            } else {
                emptyProgressState
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
        .onAppear {
            loadProgress()
        }
        .sheet(isPresented: $showingProgressView) {
            EngagingProgressView()
        }
    }
    
    @ViewBuilder
    private func progressContent(_ progress: [String: Any]) -> some View {
        VStack(spacing: 16) {
            // Top Row: XP Ring and Streak
            HStack(spacing: 20) {
                // Daily XP Ring
                dailyXPRing(progress)
                
                Spacer()
                
                // Streak Counter
                streakCounter(progress)
            }
            
            // Bottom Row: Daily Goal Progress
            dailyGoalProgress(progress)
            
            // Recent Achievement (if any)
            if let achievements = getRecentAchievements(progress), !achievements.isEmpty {
                recentAchievementBanner(achievements.first!)
            }
        }
    }
    
    @ViewBuilder
    private func dailyXPRing(_ progress: [String: Any]) -> some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.blue.opacity(0.2), lineWidth: 6)
                .frame(width: 60, height: 60)
            
            // Progress circle
            Circle()
                .trim(from: 0, to: getXPProgress(progress))
                .stroke(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 60, height: 60)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 1.0), value: getXPProgress(progress))
            
            // XP Text
            VStack(spacing: 2) {
                Text("\(getTodayXP(progress))")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("XP")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func streakCounter(_ progress: [String: Any]) -> some View {
        VStack(spacing: 4) {
            // Flame icon with dynamic size
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundColor(getFlameColor(streak: getCurrentStreak(progress)))
                .scaleEffect(getFlameScale(streak: getCurrentStreak(progress)))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: getCurrentStreak(progress))
            
            // Streak number
            Text("\(getCurrentStreak(progress))")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("day streak")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
    }
    
    @ViewBuilder
    private func dailyGoalProgress(_ progress: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily Goal")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(getDailyGoalCurrent(progress))/\(getDailyGoalTarget(progress))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: getDailyGoalCompleted(progress) ? [.green, .mint] : [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * getDailyGoalProgress(progress),
                            height: 8
                        )
                        .animation(.easeInOut(duration: 0.8), value: getDailyGoalProgress(progress))
                }
            }
            .frame(height: 8)
            
            // Goal status message
            Text(getDailyGoalMessage(progress))
                .font(.caption)
                .foregroundColor(getDailyGoalCompleted(progress) ? .green : .blue)
                .fontWeight(.medium)
        }
    }
    
    @ViewBuilder
    private func recentAchievementBanner(_ achievement: [String: Any]) -> some View {
        HStack(spacing: 12) {
            // Achievement icon
            if let iconName = achievement["icon"] as? String {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(.orange)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("🎉 New Achievement!")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                
                Text(achievement["achievement_name"] as? String ?? "Achievement")
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text("+\(achievement["xp_reward"] as? Int ?? 0) XP")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var emptyProgressState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Start studying to see your progress!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 100)
    }
    
    // MARK: - Helper Functions
    
    private func loadProgress() {
        guard !isLoading else { return }
        
        isLoading = true
        
        Task {
            let result = await networkService.getEnhancedProgress()
            
            await MainActor.run {
                isLoading = false
                if result.success {
                    progressData = result.progress
                } else {
                    progressData = nil
                }
            }
        }
    }
    
    private func getXPProgress(_ progress: [String: Any]) -> Double {
        guard let overall = progress["overall"] as? [String: Any],
              let xpProgress = overall["xp_progress"] as? Double else {
            return 0.0
        }
        return min(xpProgress / 100.0, 1.0)
    }
    
    private func getTodayXP(_ progress: [String: Any]) -> Int {
        guard let today = progress["today"] as? [String: Any],
              let xp = today["xp_earned"] as? Int else {
            return 0
        }
        return xp
    }
    
    private func getCurrentStreak(_ progress: [String: Any]) -> Int {
        guard let streak = progress["streak"] as? [String: Any],
              let current = streak["current"] as? Int else {
            return 0
        }
        return current
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
    
    private func getDailyGoalCurrent(_ progress: [String: Any]) -> Int {
        guard let dailyGoal = progress["daily_goal"] as? [String: Any],
              let current = dailyGoal["current"] as? Int else {
            return 0
        }
        return current
    }
    
    private func getDailyGoalTarget(_ progress: [String: Any]) -> Int {
        guard let dailyGoal = progress["daily_goal"] as? [String: Any],
              let target = dailyGoal["target"] as? Int else {
            return 5
        }
        return target
    }
    
    private func getDailyGoalProgress(_ progress: [String: Any]) -> Double {
        guard let dailyGoal = progress["daily_goal"] as? [String: Any],
              let progressPercent = dailyGoal["progress_percentage"] as? Double else {
            return 0.0
        }
        return min(progressPercent / 100.0, 1.0)
    }
    
    private func getDailyGoalCompleted(_ progress: [String: Any]) -> Bool {
        guard let dailyGoal = progress["daily_goal"] as? [String: Any],
              let completed = dailyGoal["completed"] as? Bool else {
            return false
        }
        return completed
    }
    
    private func getDailyGoalMessage(_ progress: [String: Any]) -> String {
        let current = getDailyGoalCurrent(progress)
        let target = getDailyGoalTarget(progress)
        let completed = getDailyGoalCompleted(progress)
        
        if completed {
            return "🎯 Daily goal completed! Great job!"
        } else {
            let remaining = target - current
            return "\(remaining) more question\(remaining == 1 ? "" : "s") to reach your goal"
        }
    }
    
    private func getRecentAchievements(_ progress: [String: Any]) -> [[String: Any]]? {
        guard let achievements = progress["achievements"] as? [String: Any],
              let recent = achievements["recent"] as? [[String: Any]] else {
            return nil
        }
        return recent
    }
}

#Preview {
    VStack {
        HomeProgressSketch()
        Spacer()
    }
    .padding()
    .background(Color(.systemBackground))
}