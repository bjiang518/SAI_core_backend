//
//  ProgressView.swift
//  StudyAI
//
//  Created by Claude Code on 8/31/25.
//

import SwiftUI

struct LearningProgressView: View {
    @StateObject private var networkService = NetworkService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @State private var progressData: [String: Any]?
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    private let viewId = UUID().uuidString.prefix(8)
    
    var body: some View {
        print("🎯 DEBUG: [View \(viewId)] OLD ProgressView.swift LearningProgressView body building")
        print("🎯 DEBUG: [View \(viewId)] Current points from pointsManager: \(pointsManager.currentPoints)")
        print("🎯 DEBUG: [View \(viewId)] Current learning goals from pointsManager:")
        for (index, goal) in pointsManager.learningGoals.enumerated() {
            print("🎯 DEBUG: [View \(viewId)]   Goal \(index): \(goal.type.displayName) - Progress: \(goal.currentProgress)/\(goal.targetValue)")
        }
        
        return ScrollView {
            VStack(spacing: 24) {
                if isLoading {
                    ProgressView("Loading your progress...")
                        .frame(height: 200)
                } else if let progress = progressData {
                    // Main Stats
                    VStack(spacing: 20) {
                        Text("Your Learning Journey")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            StatCard(
                                title: "Total Points",
                                value: "\(pointsManager.currentPoints)",
                                icon: "star.fill",
                                color: .blue
                            )
                            
                            StatCard(
                                title: "Current Streak",
                                value: "\(pointsManager.currentStreak)",
                                icon: "flame.fill",
                                color: .orange
                            )
                            
                            StatCard(
                                title: "Total Earned",
                                value: "\(pointsManager.totalPointsEarned)",
                                icon: "trophy.fill",
                                color: .green
                            )
                            
                            StatCard(
                                title: "Today's Accuracy",
                                value: "\(Int(pointsManager.todayProgress?.accuracy ?? 0))%",
                                icon: "target",
                                color: .purple
                            )
                        }
                    }
                    
                    // Weekly Progress Section
                    WeeklyProgressGrid()
                    
                    // Subject Breakdown
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Subject Breakdown")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            SubjectProgressRow(subject: "Mathematics", progress: 0.8, questions: 15)
                            SubjectProgressRow(subject: "Physics", progress: 0.6, questions: 8)
                            SubjectProgressRow(subject: "Chemistry", progress: 0.9, questions: 12)
                            SubjectProgressRow(subject: "Biology", progress: 0.4, questions: 5)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(16)
                    }
                    
                    // Learning Goals Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Learning Goals")
                            .font(.headline)
                        
                        VStack(spacing: 12) {
                            ForEach(pointsManager.learningGoals) { goal in
                                GoalCard(
                                    title: goal.title,
                                    current: goal.currentProgress,
                                    target: goal.targetValue,
                                    icon: goal.type.icon,
                                    color: goal.type.color
                                )
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(16)
                    }
                    
                } else {
                    // Empty State
                    VStack(spacing: 16) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Progress Data Yet")
                            .font(.title3)
                            .fontWeight(.medium)
                        
                        Text("Start asking questions to see your learning progress!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                        
                        Button("Ask Your First Question") {
                            // Navigation would be handled by parent
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding()
                }
                
                Spacer(minLength: 50)
            }
            .padding()
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            print("🎯 DEBUG: [View \(viewId)] OLD ProgressView.swift LearningProgressView onAppear called")
            print("🎯 DEBUG: [View \(viewId)] Final points check on appear: \(pointsManager.currentPoints)")
            print("🎯 DEBUG: [View \(viewId)] Final learning goals check on appear:")
            for (index, goal) in pointsManager.learningGoals.enumerated() {
                print("🎯 DEBUG: [View \(viewId)]   Goal \(index): \(goal.type.displayName) - Progress: \(goal.currentProgress)/\(goal.targetValue)")
            }
            loadProgress()
        }
        .refreshable {
            print("🎯 DEBUG: [View \(viewId)] Manual refresh triggered in OLD ProgressView.swift")
            await loadProgressAsync()
        }
    }
    
    private func loadProgress() {
        // Prevent multiple concurrent calls
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            await loadProgressAsync()
        }
    }
    
    private func loadProgressAsync() async {
        let result = await networkService.getProgress()
        
        await MainActor.run {
            isLoading = false
            
            if result.success {
                progressData = result.progress
            } else {
                errorMessage = "Failed to load progress data"
            }
        }
    }
}

struct SubjectProgressRow: View {
    let subject: String
    let progress: Double
    let questions: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(subject)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(questions) questions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(progressColor(for: progress))
                        .frame(width: geometry.size.width * progress, height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
        }
    }
    
    private func progressColor(for progress: Double) -> Color {
        if progress >= 0.8 { return .green }
        else if progress >= 0.6 { return .orange }
        else { return .red }
    }
}

struct GoalCard: View {
    let title: String
    let current: Int
    let target: Int
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(current) / \(target)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            CircularProgressView(
                progress: Double(current) / Double(target),
                color: color
            )
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 4)
                .frame(width: 40, height: 40)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(-90))
            
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .fontWeight(.bold)
        }
    }
}

#Preview {
    NavigationView {
        LearningProgressView()
    }
}