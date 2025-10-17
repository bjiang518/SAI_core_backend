//
//  SubjectDetailView.swift
//  StudyAI
//
//  Detailed view for individual subject analytics
//

import SwiftUI
import Charts

struct SubjectDetailView: View {
    let subject: SubjectCategory
    let timeframe: TimeframeOption

    private let localProgressService = LocalProgressService.shared
    @State private var subjectData: SubjectProgressData?
    @State private var subjectTrends: [SubjectTrendData] = []
    @State private var isLoading = true
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if isLoading {
                        ProgressView("Loading \(subject.rawValue) details...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                    } else if !errorMessage.isEmpty {
                        ErrorStateView(message: errorMessage) {
                            loadSubjectDetails()
                        }
                    } else if let data = subjectData {
                        subjectDetailContent(data)
                    }
                }
                .padding()
            }
            .navigationTitle(subject.rawValue)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .refreshable {
                loadSubjectDetails()
            }
            .onAppear {
                loadSubjectDetails()
            }
        }
    }
    
    @ViewBuilder
    private func subjectDetailContent(_ data: SubjectProgressData) -> some View {
        // Subject Overview Card
        SubjectOverviewCard(data: data)
        
        // Performance Breakdown
        PerformanceBreakdownCard(data: data)
        
        // Topic Analysis
        if !data.topicBreakdown.isEmpty {
            TopicAnalysisCard(topicBreakdown: data.topicBreakdown)
        }
        
        // Difficulty Progression
        if !data.difficultyProgression.isEmpty {
            DifficultyProgressionCard(difficultyProgression: data.difficultyProgression)
        }
        
        // Recent Activity
        if !data.recentActivity.isEmpty {
            SubjectRecentActivityCard(activities: data.recentActivity)
        }
        
        // Strengths and Weaknesses
        StrengthsWeaknessesCard(data: data)
        
        // Learning Tips
        LearningTipsCard(subject: subject)
    }
    
    private func loadSubjectDetails() {
        isLoading = true
        errorMessage = ""

        Task {
            // ✅ Use LocalProgressService to calculate from local storage
            let data = await localProgressService.calculateSubjectBreakdown(
                timeframe: timeframe.apiValue
            )

            await MainActor.run {
                // Find the specific subject data
                self.subjectData = data.subjectProgress.first { $0.subject == subject }
                self.subjectTrends = data.trends.filter { $0.subject == subject }
                self.isLoading = false
            }
        }
    }
}

// MARK: - Subject Overview Card

struct SubjectOverviewCard: View {
    let data: SubjectProgressData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: data.subject.icon)
                    .font(.title)
                    .foregroundColor(data.subject.swiftUIColor)
                
                VStack(alignment: .leading) {
                    Text(data.subject.rawValue)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Performance Level: \(data.performanceLevel.rawValue)")
                        .font(.subheadline)
                        .foregroundColor(data.performanceLevel.color)
                }
                
                Spacer()
                
                VStack {
                    Text("\(Int(data.averageAccuracy))%")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(data.performanceLevel.color)
                    
                    Text("Accuracy")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                OverviewMetric(
                    title: "Questions",
                    value: "\(data.questionsAnswered)",
                    icon: "questionmark.circle.fill",
                    color: .blue
                )
                
                OverviewMetric(
                    title: "Correct",
                    value: "\(data.correctAnswers)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                OverviewMetric(
                    title: "Study Time",
                    value: formatStudyTime(data.totalStudyTime),
                    icon: "clock.fill",
                    color: .orange
                )
                
                OverviewMetric(
                    title: "Streak",
                    value: "\(data.streakDays)d",
                    icon: "flame.fill",
                    color: .red
                )
            }
            
            let lastStudied = data.lastStudiedDate
            if !lastStudied.isEmpty {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                    Text("Last studied: \(formatDate(lastStudied))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if data.isActivelyStudied {
                        HStack {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)
                            Text("Active today")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func formatStudyTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval / 60)
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        return outputFormatter.string(from: date)
    }
}

struct OverviewMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Performance Breakdown Card

struct PerformanceBreakdownCard: View {
    let data: SubjectProgressData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Analysis")
                .font(.headline)
                .fontWeight(.bold)
            
            VStack(spacing: 12) {
                // Accuracy Progress Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Accuracy")
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(data.averageAccuracy))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    ProgressView(value: data.averageAccuracy, total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: data.performanceLevel.color))
                }
                
                // Questions per Day Average
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Avg Questions/Day")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f", data.averageQuestionsPerDay))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    
                    ProgressView(value: min(data.averageQuestionsPerDay, 20), total: 20)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                }
            }
            
            // Performance Insights
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Insights")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                PerformanceInsight(
                    icon: data.performanceLevel.icon,
                    color: data.performanceLevel.color,
                    text: getPerformanceFeedback(for: data.performanceLevel)
                )
                
                if data.streakDays > 0 {
                    PerformanceInsight(
                        icon: "flame.fill",
                        color: .orange,
                        text: getStreakFeedback(for: data.streakDays)
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func getPerformanceFeedback(for level: PerformanceLevel) -> String {
        switch level {
        case .excellent:
            return "Outstanding work! You've mastered this subject."
        case .good:
            return "Great job! Your understanding is solid."
        case .average:
            return "Good progress! Keep practicing to improve."
        case .needsImprovement:
            return "Focus more on this subject to see better results."
        case .beginner:
            return "You're just getting started. Every expert was once a beginner!"
        }
    }
    
    private func getStreakFeedback(for days: Int) -> String {
        switch days {
        case 1...2:
            return "Good start! Keep the momentum going."
        case 3...6:
            return "Nice streak! Consistency is key to success."
        case 7...13:
            return "Impressive dedication! You're building great habits."
        case 14...29:
            return "Amazing streak! Your consistency is paying off."
        default:
            return "Incredible dedication! You're a study superstar!"
        }
    }
}

struct PerformanceInsight: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Topic Analysis Card

struct TopicAnalysisCard: View {
    let topicBreakdown: [String: Int]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Topic Breakdown")
                .font(.headline)
                .fontWeight(.bold)
            
            let sortedTopics = topicBreakdown.sorted { $0.value > $1.value }
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(Array(sortedTopics.prefix(8)), id: \.key) { topic in
                        BarMark(
                            x: .value("Questions", topic.value),
                            y: .value("Topic", topic.key)
                        )
                        .foregroundStyle(.blue.gradient)
                    }
                }
                .frame(height: max(120, CGFloat(sortedTopics.prefix(8).count) * 25))
            } else {
                // Fallback for iOS 15
                VStack(spacing: 6) {
                    ForEach(Array(sortedTopics.prefix(6)), id: \.key) { topic in
                        HStack {
                            Text(topic.key)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("\(topic.value)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Difficulty Progression Card

struct DifficultyProgressionCard: View {
    let difficultyProgression: [DifficultyLevel: Int]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Difficulty Progression")
                .font(.headline)
                .fontWeight(.bold)
            
            let difficultyOrder: [DifficultyLevel] = [.beginner, .intermediate, .advanced, .expert]
            let totalQuestions = difficultyProgression.values.reduce(0, +)
            
            VStack(spacing: 8) {
                ForEach(difficultyOrder, id: \.self) { difficulty in
                    if let count = difficultyProgression[difficulty], count > 0 {
                        DifficultyProgressRow(
                            difficulty: difficulty,
                            count: count,
                            percentage: totalQuestions > 0 ? Double(count) / Double(totalQuestions) : 0
                        )
                    }
                }
            }
            
            if totalQuestions > 0 {
                Text("Total: \(totalQuestions) questions across all difficulty levels")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct DifficultyProgressRow: View {
    let difficulty: DifficultyLevel
    let count: Int
    let percentage: Double
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(difficulty.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(count) (\(Int(percentage * 100))%)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: percentage)
                .progressViewStyle(LinearProgressViewStyle(tint: difficultyColor(for: difficulty)))
        }
    }
    
    private func difficultyColor(for difficulty: DifficultyLevel) -> Color {
        switch difficulty {
        case .beginner: return .green
        case .intermediate: return .blue
        case .advanced: return .orange
        case .expert: return .red
        }
    }
}

// MARK: - Recent Activity Card

struct SubjectRecentActivityCard: View {
    let activities: [DailySubjectActivity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.headline)
                .fontWeight(.bold)
            
            let recentActivities = Array(activities.suffix(7))
            
            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(recentActivities, id: \.id) { activity in
                        LineMark(
                            x: .value("Date", activity.date),
                            y: .value("Questions", activity.questionCount)
                        )
                        .foregroundStyle(.blue)
                        
                        PointMark(
                            x: .value("Date", activity.date),
                            y: .value("Questions", activity.questionCount)
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .frame(height: 120)
            } else {
                // Fallback for iOS 15
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recentActivities, id: \.id) { activity in
                            ActivityDayCard(activity: activity)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct ActivityDayCard: View {
    let activity: DailySubjectActivity
    
    var body: some View {
        VStack(spacing: 4) {
            Text(formatShortDate(activity.date))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Rectangle()
                .fill(activity.intensityLevel.color)
                .frame(width: 20, height: max(4, CGFloat(activity.questionCount) * 2))
                .cornerRadius(2)
            
            Text("\(activity.questionCount)")
                .font(.caption2)
                .fontWeight(.semibold)
        }
    }
    
    private func formatShortDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "M/d"
        return outputFormatter.string(from: date)
    }
}

// MARK: - Strengths and Weaknesses Card

struct StrengthsWeaknessesCard: View {
    let data: SubjectProgressData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Strengths & Areas for Improvement")
                .font(.headline)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                // Strengths
                if !data.strongAreas.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Strengths")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        FlowLayout(items: data.strongAreas) { area in
                            StrengthWeaknessChip(text: area, color: .green.opacity(0.2))
                        }
                    }
                }
                
                // Weaknesses
                if !data.weakAreas.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Areas for Improvement")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        FlowLayout(items: data.weakAreas) { area in
                            StrengthWeaknessChip(text: area, color: .orange.opacity(0.2))
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct StrengthWeaknessChip: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(6)
    }
}

// MARK: - Learning Tips Card

struct LearningTipsCard: View {
    let subject: SubjectCategory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Learning Tips for \(subject.rawValue)")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(subject.learningTips.prefix(4), id: \.self) { tip in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(tip)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Flow Layout Helper

struct FlowLayout<T: Hashable, V: View>: View {
    let items: [T]
    let content: (T) -> V
    
    @State private var totalHeight = CGFloat.zero
    
    var body: some View {
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
        .frame(height: totalHeight)
    }
    
    private func generateContent(in geometry: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .alignmentGuide(.leading, computeValue: { d in
                        if (abs(width - d.width) > geometry.size.width) {
                            width = 0
                            height -= d.height
                        }
                        let result = width
                        if item == items.last {
                            width = 0
                        } else {
                            width -= d.width
                        }
                        return result
                    })
                    .alignmentGuide(.top, computeValue: { d in
                        let result = height
                        if item == items.last {
                            height = 0
                        }
                        return result
                    })
            }
        }
        .background(viewHeightReader($totalHeight))
    }
    
    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        return GeometryReader { geometry -> Color in
            let rect = geometry.frame(in: .local)
            DispatchQueue.main.async {
                binding.wrappedValue = rect.size.height
            }
            return Color.clear
        }
    }
}

#Preview {
    SubjectDetailView(subject: SubjectCategory.mathematics, timeframe: TimeframeOption.currentWeek)
}