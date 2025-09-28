//
//  ReportDetailView.swift
//  StudyAI
//
//  Detailed view of a generated parent report
//  Displays comprehensive analytics and insights
//

import SwiftUI
import Charts

/// Convert ParentReportTrendDirection to TrendDirection for UI compatibility
private func convertTrendDirection(_ parentTrend: ParentReportTrendDirection) -> TrendDirection {
    switch parentTrend {
    case .improving:
        return .improving
    case .declining:
        return .declining
    case .stable:
        return .stable
    }
}

struct ReportDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let report: ParentReport
    @StateObject private var reportService = ParentReportService.shared

    @State private var selectedSection: ReportSection = .overview
    @State private var showingExportOptions = false
    @State private var narrativeContent: NarrativeReport?
    @State private var isLoadingNarrative = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Report Header
                    reportHeader

                    // Always try to show narrative content first if we have it
                    if let narrativeContent = narrativeContent {
                        // Show narrative content
                        narrativeReportContent
                            .padding()
                    } else if isLoadingNarrative {
                        // Show loading state while fetching narrative
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading narrative content...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                        .padding()
                    } else {
                        // Fallback to legacy analytics format if no narrative is available
                        VStack(spacing: 0) {
                            // Section Picker
                            sectionPicker

                            // Content
                            selectedSectionContent
                                .padding()
                        }
                    }
                }
            }
            .navigationTitle("Report Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingExportOptions = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingExportOptions) {
                ReportExportView(report: report)
            }
            .onAppear {
                print("🔍 ReportDetailView appeared for report: \(report.id)")
                print("🔍 Report type: \(report.reportType.rawValue)")
                print("🔍 Is narrative report: \(report.reportData.isNarrativeReport)")

                loadNarrativeContent()
            }
        }
    }

    // MARK: - Report Header
    private var reportHeader: some View {
        VStack(spacing: 16) {
            // Report Type and Date
            HStack {
                VStack(alignment: .leading) {
                    Text(report.reportTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(report.dateRange)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: report.reportType.icon)
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
            }

        }
        .padding()
        .background(Color(.systemGray6))
    }

    // MARK: - Section Picker
    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(ReportSection.allCases, id: \.self) { section in
                    Button(action: {
                        selectedSection = section
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: section.icon)
                                .font(.system(size: 16))

                            Text(section.title)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(selectedSection == section ? .blue : .secondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(selectedSection == section ? Color.blue.opacity(0.1) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    // MARK: - Narrative Report Content
    @ViewBuilder
    private var narrativeReportContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isLoadingNarrative {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading narrative content...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if let narrative = narrativeContent {
                // Narrative content
                VStack(alignment: .leading, spacing: 20) {
                    // Summary Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.blue)
                            Text("Summary")
                                .font(.title2)
                                .fontWeight(.bold)
                        }

                        Text(narrative.summary)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }

                    // Key Insights Section
                    if !narrative.keyInsights.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.orange)
                                Text("Key Insights")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(narrative.keyInsights.enumerated()), id: \.offset) { index, insight in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .frame(width: 20, height: 20)
                                            .background(Color.orange)
                                            .clipShape(Circle())

                                        Text(insight)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }

                    // Recommendations Section
                    if !narrative.recommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.green)
                                Text("Recommendations")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(narrative.recommendations.enumerated()), id: \.offset) { index, recommendation in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .frame(width: 20, height: 20)
                                            .background(Color.green)
                                            .clipShape(Circle())

                                        Text(recommendation)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                    }

                    // Full Narrative Content Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "text.document.fill")
                                .foregroundColor(.purple)
                            Text("Full Report")
                                .font(.title2)
                                .fontWeight(.bold)
                        }

                        ScrollView {
                            Text(narrative.content)
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 400)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                    }

                }
            } else {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Unable to Load Narrative")
                        .font(.headline)
                        .fontWeight(.medium)

                    Text("The narrative content could not be loaded. Please try again.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Retry") {
                        loadNarrativeContent()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }

    // MARK: - Section Content
    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .overview:
            OverviewSection(report: report)
        case .academic:
            AcademicSection(report: report)
        case .activity:
            ActivitySection(report: report)
        case .mentalHealth:
            MentalHealthSection(report: report)
        case .subjects:
            SubjectsSection(report: report)
        case .progress:
            ProgressSection(report: report)
        case .mistakes:
            MistakesSection(report: report)
        }
    }

    // MARK: - Narrative Loading
    private func loadNarrativeContent() {
        // Prevent multiple loads if already loading or loaded
        guard narrativeContent == nil && !isLoadingNarrative else {
            print("📝 Skipping narrative load - already loading or loaded")
            return
        }

        print("📝 === ATTEMPTING TO LOAD NARRATIVE CONTENT ===")
        print("📝 Report ID: \(report.id)")
        print("📝 Report Data Type: \(report.reportData.type ?? "nil")")
        print("📝 Is Narrative Report: \(report.reportData.isNarrativeReport)")
        print("📝 Narrative Available: \(report.reportData.narrativeAvailable ?? false)")
        print("📝 Narrative ID: \(report.reportData.narrativeId ?? "nil")")
        print("📝 Narrative URL: \(report.reportData.narrativeURL ?? "nil")")

        // Always attempt to load narrative content for any report
        // The backend may have narrative content even if the report_data doesn't indicate it
        print("📝 Proceeding with narrative fetch attempt...")

        isLoadingNarrative = true
        narrativeContent = nil

        Task {
            print("📝 Starting narrative fetch task for report: \(report.id)")
            let result = await reportService.fetchNarrative(reportId: report.id)

            await MainActor.run {
                isLoadingNarrative = false

                switch result {
                case .success(let narrative):
                    narrativeContent = narrative
                    print("✅ Narrative content loaded for UI display")
                    print("📝 Loaded narrative ID: \(narrative.id)")
                    print("📝 Content length: \(narrative.content.count) characters")
                    print("📝 Summary length: \(narrative.summary.count) characters")
                case .failure(let error):
                    print("❌ Failed to load narrative for UI: \(error.localizedDescription)")
                    print("❌ Error details: \(error)")
                    narrativeContent = nil

                    // If narrative fetch fails, we should still show the report
                    // but fall back to the legacy analytics format
                    print("📝 Narrative fetch failed - will show legacy analytics format")
                    print("📝 UI will now display: isLoadingNarrative=\(self.isLoadingNarrative), narrativeContent=\(self.narrativeContent != nil)")
                }
            }
        }
    }
}

// MARK: - Report Sections

enum ReportSection: CaseIterable {
    case overview
    case academic
    case activity
    case mentalHealth
    case subjects
    case progress
    case mistakes

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .academic: return "Academic"
        case .activity: return "Activity"
        case .mentalHealth: return "Wellbeing"
        case .subjects: return "Subjects"
        case .progress: return "Progress"
        case .mistakes: return "Mistakes"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "doc.text"
        case .academic: return "graduationcap"
        case .activity: return "figure.walk"
        case .mentalHealth: return "heart"
        case .subjects: return "books.vertical"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .mistakes: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Supporting Views

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

// MARK: - Section Views

struct OverviewSection: View {
    let report: ParentReport

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Report Summary", icon: "doc.text.fill")

            // Trend Overview
            if report.reportData.academic?.trendDirection != .stable {
                TrendCard(
                    title: "Overall Progress",
                    trend: convertTrendDirection(report.reportData.academic?.trendDirection ?? .stable),
                    description: getTrendDescription()
                )
            }

            // Key Insights
            VStack(alignment: .leading, spacing: 16) {
                Text("Key Insights")
                    .font(.headline)

                InsightCard(
                    icon: "target",
                    title: "Academic Performance",
                    description: "Answered \(report.reportData.academic?.totalQuestions ?? 0) questions with \(report.reportData.academic?.accuracyPercentage ?? "N/A") accuracy",
                    color: .green
                )

                InsightCard(
                    icon: "clock.fill",
                    title: "Study Activity",
                    description: "Studied for \(Int(report.reportData.activity?.totalStudyHours ?? 0)) hours across \(report.reportData.activity?.studyTime.activeDays ?? 0) days",
                    color: .blue
                )

                InsightCard(
                    icon: "heart.fill",
                    title: "Mental Wellbeing",
                    description: "Overall wellbeing is \(report.reportData.mentalHealth?.wellbeingLevel.lowercased() ?? "unknown")",
                    color: report.reportData.mentalHealth?.wellbeingColor ?? .gray
                )
            }
        }
    }

    private func getTrendDescription() -> String {
        switch report.reportData.academic?.trendDirection {
        case .improving: return "Performance is improving compared to the previous period"
        case .declining: return "Performance has declined compared to the previous period"
        case .stable: return "Performance remains consistent"
        case .none: return "Performance data not available"
        }
    }
}

struct AcademicSection: View {
    let report: ParentReport

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Academic Performance", icon: "graduationcap.fill")

            // Performance Metrics
            VStack(alignment: .leading, spacing: 16) {
                PerformanceMetricRow(
                    title: "Overall Accuracy",
                    value: report.reportData.academic?.accuracyPercentage ?? "N/A",
                    progress: report.reportData.academic?.overallAccuracy ?? 0.0
                )

                PerformanceMetricRow(
                    title: "Average Confidence",
                    value: report.reportData.academic?.confidencePercentage ?? "N/A",
                    progress: report.reportData.academic?.averageConfidence ?? 0.0
                )

                PerformanceMetricRow(
                    title: "Consistency Score",
                    value: String(format: "%.1f%%", (report.reportData.academic?.consistencyScore ?? 0.0) * 100),
                    progress: report.reportData.academic?.consistencyScore ?? 0.0
                )
            }

            // Study Statistics
            VStack(alignment: .leading, spacing: 12) {
                Text("Study Statistics")
                    .font(.headline)

                HStack {
                    StatisticItem(
                        title: "Questions",
                        value: "\(report.reportData.academic?.totalQuestions ?? 0)"
                    )

                    StatisticItem(
                        title: "Correct",
                        value: "\(report.reportData.academic?.correctAnswers ?? 0)"
                    )

                    StatisticItem(
                        title: "Time",
                        value: "\(report.reportData.academic?.timeSpentMinutes ?? 0)m"
                    )

                    StatisticItem(
                        title: "Per Day",
                        value: "\(report.reportData.academic?.questionsPerDay ?? 0)"
                    )
                }
            }
        }
    }
}

struct ActivitySection: View {
    let report: ParentReport

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Learning Activity", icon: "figure.walk")

            // Study Time Overview
            VStack(alignment: .leading, spacing: 16) {
                Text("Study Time")
                    .font(.headline)

                StudyTimeCard(
                    totalHours: report.reportData.activity?.totalStudyHours ?? 0,
                    activeDays: report.reportData.activity?.studyTime.activeDays ?? 0,
                    averageSession: Double(report.reportData.activity?.studyTime.averageSessionMinutes ?? 0) / 60.0
                )
            }

            // Engagement Metrics
            VStack(alignment: .leading, spacing: 16) {
                Text("Engagement")
                    .font(.headline)

                if let engagement = report.reportData.activity?.engagement {
                    EngagementCard(engagement: engagement)
                }
            }

            // Study Patterns
            if !(report.reportData.activity?.patterns.subjectPreferences.isEmpty ?? true) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Study Patterns")
                        .font(.headline)

                    if let patterns = report.reportData.activity?.patterns {
                        StudyPatternsCard(patterns: patterns)
                    }
                }
            }
        }
    }
}

struct MentalHealthSection: View {
    let report: ParentReport

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Mental Wellbeing", icon: "heart.fill")

            // Overall Wellbeing
            if let mentalHealth = report.reportData.mentalHealth {
                WellbeingOverviewCard(mentalHealth: mentalHealth)
            }

            // Alerts (if any)
            if let mentalHealth = report.reportData.mentalHealth, !mentalHealth.alerts.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Attention Areas")
                        .font(.headline)

                    ForEach(mentalHealth.alerts) { alert in
                        AlertCard(alert: alert)
                    }
                }
            }

            // Data Quality
            if let mentalHealth = report.reportData.mentalHealth,
               let dataQuality = mentalHealth.dataQuality {
                DataQualityCard(dataQuality: dataQuality)
            }
        }
    }
}

struct SubjectsSection: View {
    let report: ParentReport

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Subject Breakdown", icon: "books.vertical.fill")

            if report.reportData.subjects?.isEmpty ?? true {
                EmptyStateCard(
                    icon: "books.vertical",
                    title: "No Subject Data",
                    description: "No subject-specific data available for this period"
                )
            } else {
                ForEach(Array(report.reportData.subjects?.keys.sorted() ?? []), id: \.self) { subject in
                    if let metrics = report.reportData.subjects?[subject] {
                        ReportSubjectCard(subject: subject, metrics: metrics)
                    }
                }
            }
        }
    }
}

struct MistakesSection: View {
    let report: ParentReport

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Mistake Analysis", icon: "exclamationmark.triangle.fill")

            // Mistakes Overview
            if let mistakes = report.reportData.mistakes {
                MistakesOverviewCard(mistakes: mistakes)
            }

            // Mistake Patterns
            if let mistakes = report.reportData.mistakes, !mistakes.patterns.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Mistake Patterns")
                        .font(.headline)

                    ForEach(mistakes.patterns) { pattern in
                        MistakePatternCard(pattern: pattern)
                    }
                }
            }

            // Recommendations
            if let mistakes = report.reportData.mistakes, !mistakes.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recommendations")
                        .font(.headline)

                    ForEach(mistakes.recommendations, id: \.self) { recommendation in
                        RecommendationCard(text: recommendation)
                    }
                }
            }
        }
    }
}

// MARK: - Additional Supporting Views

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
        }
    }
}

struct TrendCard: View {
    let title: String
    let trend: TrendDirection
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trend.icon)
                .font(.system(size: 24))
                .foregroundColor(trend.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(trend.rawValue)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(trend.color.opacity(0.1))
                .foregroundColor(trend.color)
                .cornerRadius(6)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct InsightCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

struct ProgressSection: View {
    let report: ParentReport

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Progress Overview", icon: "chart.line.uptrend.xyaxis.circle.fill")

            VStack(alignment: .leading, spacing: 16) {
                Text("Learning Progress")
                    .font(.headline)

                Text("Progress tracking shows overall improvement in academic performance over the selected time period.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// Additional card views would continue here...

#Preview {
    ReportDetailView(report: ParentReport.sampleReport)
}