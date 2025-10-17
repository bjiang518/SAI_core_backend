//
//  SubjectBreakdownView.swift
//  StudyAI
//
//  Subject breakdown analytics and visualization
//

import SwiftUI
import Charts

struct SubjectBreakdownView: View {
    @StateObject private var localProgressService = LocalProgressService.shared
    @State private var subjectBreakdownData: SubjectBreakdownData?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var selectedTimeframe: TimeframeOption = .currentWeek
    @State private var selectedSubject: SubjectCategory?
    @State private var showingSubjectDetail = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if isLoading {
                        ProgressView("Loading subject breakdown...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                    } else if !errorMessage.isEmpty {
                        ErrorStateView(message: errorMessage) {
                            loadSubjectBreakdown()
                        }
                    } else if let data = subjectBreakdownData {
                        subjectBreakdownContent(data)
                    }
                }
                .padding()
            }
            .navigationTitle("📚 Subject Breakdown")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(TimeframeOption.allCases, id: \.self) { option in
                            Button(option.displayName) {
                                selectedTimeframe = option
                                loadSubjectBreakdown()
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedTimeframe.displayName)
                            Image(systemName: "chevron.down")
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .refreshable {
                loadSubjectBreakdown()
            }
            .onAppear {
                loadSubjectBreakdown()
            }
            .sheet(isPresented: $showingSubjectDetail) {
                if let subject = selectedSubject {
                    SubjectDetailView(subject: subject, timeframe: selectedTimeframe)
                }
            }
        }
    }
    
    @ViewBuilder
    private func subjectBreakdownContent(_ data: SubjectBreakdownData) -> some View {
        // Summary Cards
        OverallSummaryCard(summary: data.summary)
        
        // Subject Performance Grid
        SubjectPerformanceGrid(
            subjectProgress: data.subjectProgress,
            onSubjectTap: { subject in
                selectedSubject = subject.subject
                showingSubjectDetail = true
            }
        )
        
        // Insights and Recommendations
        if !data.insights.personalizedTips.isEmpty {
            InsightsCard(insights: data.insights)
        }
        
        // Subject Distribution Chart
        if !data.subjectProgress.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Subject Distribution")
                    .font(.headline)
                    .fontWeight(.bold)
                
                VStack(spacing: 8) {
                    ForEach(data.subjectProgress.prefix(5), id: \.id) { subject in
                        HStack {
                            Image(systemName: subject.subject.icon)
                                .foregroundColor(subject.subject.swiftUIColor)
                                .frame(width: 20)
                            
                            Text(subject.subject.displayName)
                                .font(.subheadline)
                            
                            Spacer()
                            
                            Text("\(subject.questionsAnswered) questions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
        }
        
        // Performance Trends
        if !data.trends.isEmpty {
            SubjectTrendsView(trends: data.trends)
        }
    }
    
    private func loadSubjectBreakdown() {
        isLoading = true
        errorMessage = ""

        Task {
            // ✅ Use LocalProgressService to calculate from local storage
            let data = await localProgressService.calculateSubjectBreakdown(
                timeframe: selectedTimeframe.apiValue
            )

            await MainActor.run {
                self.subjectBreakdownData = data
                self.isLoading = false
            }
        }
    }
}

// MARK: - Summary Card

struct OverallSummaryCard: View {
    let summary: SubjectBreakdownSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overall Summary")
                .font(.headline)
                .fontWeight(.bold)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                SummaryMetric(
                    title: "Subjects Studied",
                    value: "\(summary.totalSubjectsStudied)",
                    icon: "book.fill",
                    color: .blue
                )
                
                SummaryMetric(
                    title: "Total Questions",
                    value: "\(summary.totalQuestionsAcrossSubjects)",
                    icon: "questionmark.circle.fill",
                    color: .green
                )
                
                SummaryMetric(
                    title: "Overall Accuracy",
                    value: "\(Int(summary.overallAccuracy))%",
                    icon: "target",
                    color: .orange
                )
                
                SummaryMetric(
                    title: "Diversity Score",
                    value: "\(Int(summary.diversityScore))%",
                    icon: "chart.pie.fill",
                    color: .purple
                )
            }
            
            if let mostStudied = summary.mostStudiedSubject,
               let topPerforming = summary.highestPerformingSubject {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("Most Studied: \(mostStudied.displayName)")
                            .font(.subheadline)
                    }
                    
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(.gold)
                        Text("Top Performing: \(topPerforming.displayName)")
                            .font(.subheadline)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Subject Performance Grid

struct SubjectPerformanceGrid: View {
    let subjectProgress: [SubjectProgressData]
    let onSubjectTap: (SubjectProgressData) -> Void
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subject Performance")
                .font(.headline)
                .fontWeight(.bold)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(subjectProgress.sorted(by: { $0.averageAccuracy > $1.averageAccuracy })) { progress in
                    SubjectPerformanceCard(progress: progress) {
                        onSubjectTap(progress)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct SubjectPerformanceCard: View {
    let progress: SubjectProgressData
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Subject icon and name
                VStack(spacing: 6) {
                    Image(systemName: progress.subject.icon)
                        .font(.title2)
                        .foregroundColor(progress.subject.swiftUIColor)
                    
                    Text(progress.subject.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                
                // Performance metrics
                VStack(spacing: 4) {
                    Text("\(Int(progress.averageAccuracy))%")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(progress.performanceLevel.color)
                    
                    Text("\(progress.questionsAnswered) questions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Performance level indicator
                HStack(spacing: 4) {
                    Image(systemName: progress.performanceLevel.icon)
                        .font(.caption2)
                        .foregroundColor(progress.performanceLevel.color)
                    
                    Text(progress.performanceLevel.rawValue)
                        .font(.caption2)
                        .foregroundColor(progress.performanceLevel.color)
                }
            }
            .padding(12)
            .frame(height: 120)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(progress.performanceLevel.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Insights Card

struct InsightsCard: View {
    let insights: SubjectInsights
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personalized Insights")
                .font(.headline)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 12) {
                // Focus subjects
                if !insights.subjectToFocus.isEmpty {
                    InsightSection(
                        title: "Focus Areas",
                        subjects: insights.subjectToFocus,
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
                
                // Maintain subjects
                if !insights.subjectsToMaintain.isEmpty {
                    InsightSection(
                        title: "Keep It Up",
                        subjects: insights.subjectsToMaintain,
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                }
                
                // Personalized tips
                if !insights.personalizedTips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                            Text("Tips for You")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        ForEach(insights.personalizedTips.prefix(3), id: \.self) { tip in
                            HStack(alignment: .top) {
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(tip)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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

struct InsightSection: View {
    let title: String
    let subjects: [SubjectCategory]
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(subjects, id: \.self) { subject in
                        SubjectChip(subject: subject, color: color.opacity(0.2))
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }
}

struct SubjectChip: View {
    let subject: SubjectCategory
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: subject.icon)
                .font(.caption2)
            Text(subject.displayName)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color)
        .cornerRadius(6)
    }
}

// MARK: - Subject Trends View

struct SubjectTrendsView: View {
    let trends: [SubjectTrendData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Trends")
                .font(.headline)
                .fontWeight(.bold)
            
            ForEach(trends.prefix(5), id: \.subject) { trendData in
                SubjectTrendRow(trendData: trendData)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct SubjectTrendRow: View {
    let trendData: SubjectTrendData
    
    var body: some View {
        HStack {
            // Subject info
            HStack {
                Image(systemName: trendData.subject.icon)
                    .foregroundColor(trendData.subject.swiftUIColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(trendData.subject.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Projected: \(Int(trendData.projectedPerformance))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Trend indicator
            HStack(spacing: 4) {
                Image(systemName: trendData.trendDirection.icon)
                    .foregroundColor(trendData.trendDirection.color)
                    .font(.caption)
                
                Text(trendData.trendDirection.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(trendData.trendDirection.color)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Supporting Views

struct SummaryMetric: View {
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
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SubjectBreakdownView()
}