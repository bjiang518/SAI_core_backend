//
//  LearningProgressView.swift
//  StudyAI
//
//  Created by Claude Code on 9/10/25.
//

import SwiftUI

struct LearningProgressView: View {
    @StateObject private var networkService = NetworkService.shared
    @State private var progressData: [String: Any] = [:]
    @State private var isLoading = true
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
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
            .refreshable {
                loadProgressData()
            }
            .onAppear {
                loadProgressData()
            }
        }
    }
    
    private var progressContent: some View {
        VStack(spacing: 24) {
            // Overall Progress Card
            VStack(alignment: .leading, spacing: 16) {
                Text("Overall Learning Progress")
                    .font(.headline)
                    .fontWeight(.bold)
                
                HStack(spacing: 20) {
                    ProgressMetric(
                        title: "Sessions",
                        value: "\(progressData["totalSessions"] as? Int ?? 0)",
                        icon: "book.fill",
                        color: .blue
                    )
                    
                    ProgressMetric(
                        title: "Questions",
                        value: "\(progressData["totalQuestions"] as? Int ?? 0)",
                        icon: "questionmark.circle.fill",
                        color: .green
                    )
                    
                    ProgressMetric(
                        title: "Accuracy",
                        value: "\(Int((progressData["averageAccuracy"] as? Double ?? 0) * 100))%",
                        icon: "target",
                        color: .orange
                    )
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
            
            // Subject Progress
            if let subjects = progressData["subjects"] as? [[String: Any]], !subjects.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Subject Progress")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    ForEach(subjects.indices, id: \.self) { index in
                        let subject = subjects[index]
                        SubjectProgressRow(subject: subject)
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .cornerRadius(12)
            }
            
            // Recent Activity
            VStack(alignment: .leading, spacing: 16) {
                Text("Recent Activity")
                    .font(.headline)
                    .fontWeight(.bold)
                
                if let recentSessions = progressData["recentSessions"] as? [[String: Any]], !recentSessions.isEmpty {
                    ForEach(recentSessions.indices, id: \.self) { index in
                        let session = recentSessions[index]
                        RecentActivityRow(session: session)
                    }
                } else {
                    Text("No recent activity")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
        }
    }
    
    private func loadProgressData() {
        isLoading = true
        errorMessage = ""
        
        Task {
            // Simulate loading progress data
            // In a real app, this would fetch from your analytics service
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            await MainActor.run {
                // Mock data for demonstration
                progressData = [
                    "totalSessions": 12,
                    "totalQuestions": 45,
                    "averageAccuracy": 0.85,
                    "subjects": [
                        ["name": "Mathematics", "progress": 0.75, "sessions": 8],
                        ["name": "Physics", "progress": 0.60, "sessions": 3],
                        ["name": "Chemistry", "progress": 0.40, "sessions": 1]
                    ],
                    "recentSessions": [
                        ["title": "Algebra Problems", "date": "Today", "accuracy": 0.90],
                        ["title": "Physics Quiz", "date": "Yesterday", "accuracy": 0.80],
                        ["title": "Chemistry Basics", "date": "2 days ago", "accuracy": 0.70]
                    ]
                ]
                
                isLoading = false
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

struct SubjectProgressRow: View {
    let subject: [String: Any]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(subject["name"] as? String ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\((subject["sessions"] as? Int ?? 0)) sessions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: subject["progress"] as? Double ?? 0)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
    }
}

struct RecentActivityRow: View {
    let session: [String: Any]
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session["title"] as? String ?? "Unknown Session")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(session["date"] as? String ?? "Unknown")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(Int((session["accuracy"] as? Double ?? 0) * 100))%")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .foregroundColor(.green)
                .cornerRadius(8)
        }
    }
}

#Preview {
    LearningProgressView()
}