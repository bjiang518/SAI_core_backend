//
//  LearningProgressView.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import SwiftUI

struct LearningProgressView: View {
    @StateObject private var networkService = NetworkService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @State private var progressData: [String: Any] = [:]
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var showingDailyCheckout = false
    
    private let viewId = UUID().uuidString.prefix(8)
    
    var body: some View {
        print("🎯 DEBUG: [View \(viewId)] LearningProgressView body building")
        return NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if isLoading {
                        ProgressView("Loading your progress...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                    } else if !errorMessage.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 50))
                                .foregroundColor(.orange)
                            
                            Text("Unable to Load Progress")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(errorMessage)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Try Again") {
                                loadProgressData()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    } else {
                        progressContent
                    }
                }
                .padding()
            }
            .navigationTitle("📊 Progress")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Daily Checkout") {
                        showingDailyCheckout = true
                    }
                    .foregroundColor(.blue)
                }
            }
            .refreshable {
                print("🎯 DEBUG: LearningProgressView manual refresh triggered")
                print("🎯 DEBUG: Current points from pointsManager during refresh: \(pointsManager.currentPoints)")
                print("🎯 DEBUG: Current learning goals during refresh:")
                for (index, goal) in pointsManager.learningGoals.enumerated() {
                    print("🎯 DEBUG:   Refresh Goal \(index): \(goal.type.displayName) - Progress: \(goal.currentProgress)/\(goal.targetValue)")
                }
                loadProgressData()
            }
            .onAppear {
                print("🎯 DEBUG: [View \(viewId)] LearningProgressView onAppear called")
                print("🎯 DEBUG: [View \(viewId)] Current points from pointsManager: \(pointsManager.currentPoints)")
                print("🎯 DEBUG: [View \(viewId)] Current learning goals from pointsManager:")
                for (index, goal) in pointsManager.learningGoals.enumerated() {
                    print("🎯 DEBUG: [View \(viewId)]   Goal \(index): \(goal.type.displayName) - Progress: \(goal.currentProgress)/\(goal.targetValue)")
                }
                loadProgressData()
            }
            .sheet(isPresented: $showingDailyCheckout) {
                DailyCheckoutView()
            }
        }
    }
    
    private var progressContent: some View {
        VStack(spacing: 24) {
            // Points and Streak Card
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Learning Journey")
                    .font(.headline)
                    .fontWeight(.bold)
                
                HStack(spacing: 20) {
                    ProgressMetric(
                        title: "Points",
                        value: "\(pointsManager.currentPoints)",
                        icon: "star.fill",
                        color: .blue
                    )
                    
                    ProgressMetric(
                        title: "Streak",
                        value: "\(pointsManager.currentStreak)",
                        icon: "flame.fill",
                        color: .orange
                    )
                    
                    ProgressMetric(
                        title: "Total Earned",
                        value: "\(pointsManager.totalPointsEarned)",
                        icon: "trophy.fill",
                        color: .green
                    )
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
            
            // Learning Goals Progress
            VStack(alignment: .leading, spacing: 16) {
                Text("Learning Goals")
                    .font(.headline)
                    .fontWeight(.bold)
                
                ForEach(pointsManager.learningGoals) { goal in
                    LearningGoalProgressRow(goal: goal)
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
            
            // Today's Progress
            if let todayProgress = pointsManager.todayProgress {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Today's Activity")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    HStack(spacing: 20) {
                        ProgressMetric(
                            title: "Questions",
                            value: "\(todayProgress.totalQuestions)",
                            icon: "questionmark.circle.fill",
                            color: .blue
                        )
                        
                        ProgressMetric(
                            title: "Correct",
                            value: "\(todayProgress.correctAnswers)",
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                        
                        ProgressMetric(
                            title: "Accuracy",
                            value: "\(Int(todayProgress.accuracy))%",
                            icon: "target",
                            color: .orange
                        )
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .cornerRadius(12)
            }
            
            // Recent Checkouts
            if !pointsManager.dailyCheckoutHistory.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recent Checkouts")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    ForEach(pointsManager.dailyCheckoutHistory.suffix(5).reversed(), id: \.id) { checkout in
                        CheckoutHistoryRow(checkout: checkout)
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .cornerRadius(12)
            }
        }
    }
    
    private func loadProgressData() {
        print("🎯 DEBUG: loadProgressData() called")
        isLoading = true
        errorMessage = ""
        
        Task {
            print("🎯 DEBUG: loadProgressData() - Starting async task")
            // Since we're now using PointsEarningManager for real data,
            // we just need to simulate a brief loading time
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await MainActor.run {
                print("🎯 DEBUG: loadProgressData() - Setting isLoading = false")
                print("🎯 DEBUG: loadProgressData() - Final points value: \(pointsManager.currentPoints)")
                isLoading = false
                // No need to set progressData since we're using PointsEarningManager directly
            }
        }
    }
}

struct ProgressMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LearningGoalProgressRow: View {
    let goal: LearningGoal
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: goal.type.icon)
                    .foregroundColor(goal.type.color)
                    .frame(width: 24)
                
                Text(goal.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                if goal.isCompleted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("+\(goal.pointsEarned) pts")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                } else {
                    Text("\(goal.currentProgress)/\(goal.targetValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            ProgressView(value: Double(goal.currentProgress), total: Double(goal.targetValue))
                .progressViewStyle(LinearProgressViewStyle(tint: goal.type.color))
        }
    }
}

struct CheckoutHistoryRow: View {
    let checkout: DailyCheckout
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(checkout.displayDate)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(checkout.goalsCompleted) goals completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(checkout.finalPoints) pts")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                
                if checkout.isWeekend {
                    Text("Weekend 2x")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    LearningProgressView()
}