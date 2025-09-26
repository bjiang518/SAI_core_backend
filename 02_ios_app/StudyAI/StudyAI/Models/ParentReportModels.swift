//
//  ParentReportModels.swift
//  StudyAI
//
//  StudyAI Parent Report System Models
//  Corresponds to backend parent reports API structure
//

import Foundation
import SwiftUI

// MARK: - Parent Report Models

/// Main parent report structure matching backend API
struct ParentReport: Codable, Identifiable {
    let id: String
    let studentName: String?
    let reportType: ReportType
    let startDate: Date
    let endDate: Date
    let reportData: ReportData
    let generatedAt: Date
    let expiresAt: Date
    let aiAnalysisIncluded: Bool
    let viewedCount: Int?
    let exportedCount: Int?

    // Optional fields for different response formats
    let cached: Bool?
    let generationTimeMs: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case studentName = "student_name"
        case reportType = "report_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case reportData = "report_data"
        case generatedAt = "generated_at"
        case expiresAt = "expires_at"
        case aiAnalysisIncluded = "ai_analysis_included"
        case viewedCount = "viewed_count"
        case exportedCount = "exported_count"
        case cached
        case generationTimeMs = "generation_time_ms"
    }

    var dateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    var isExpired: Bool {
        return Date() > expiresAt
    }

    var reportTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        switch reportType {
        case .weekly:
            return "Weekly Report - \(formatter.string(from: startDate))"
        case .monthly:
            return "Monthly Report - \(formatter.string(from: startDate))"
        case .custom:
            return "Custom Report - \(dateRange)"
        case .progress:
            return "Progress Report - \(dateRange)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "userId"
        case reportType = "report_type"
        case startDate = "start_date"
        case endDate = "end_date"
        case reportData = "report_data"
        case generatedAt = "generated_at"
        case expiresAt = "expires_at"
        case aiAnalysisIncluded = "ai_analysis_included"
        case cached
        case generationTimeMs = "generation_time_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        studentName = try container.decodeIfPresent(String.self, forKey: .studentName)
        reportType = try container.decode(ReportType.self, forKey: .reportType)
        reportData = try container.decode(ReportData.self, forKey: .reportData)
        aiAnalysisIncluded = try container.decode(Bool.self, forKey: .aiAnalysisIncluded)
        viewedCount = try container.decodeIfPresent(Int.self, forKey: .viewedCount)
        exportedCount = try container.decodeIfPresent(Int.self, forKey: .exportedCount)
        cached = try container.decodeIfPresent(Bool.self, forKey: .cached)
        generationTimeMs = try container.decodeIfPresent(Int.self, forKey: .generationTimeMs)

        // Handle date parsing
        let dateFormatter = ISO8601DateFormatter()

        let startDateString = try container.decode(String.self, forKey: .startDate)
        startDate = dateFormatter.date(from: startDateString) ?? Date()

        let endDateString = try container.decode(String.self, forKey: .endDate)
        endDate = dateFormatter.date(from: endDateString) ?? Date()

        let generatedAtString = try container.decode(String.self, forKey: .generatedAt)
        generatedAt = dateFormatter.date(from: generatedAtString) ?? Date()

        let expiresAtString = try container.decode(String.self, forKey: .expiresAt)
        expiresAt = dateFormatter.date(from: expiresAtString) ?? Date()
    }

    // Memberwise initializer for sample data
    init(
        id: String,
        studentName: String?,
        reportType: ReportType,
        startDate: Date,
        endDate: Date,
        reportData: ReportData,
        generatedAt: Date,
        expiresAt: Date,
        aiAnalysisIncluded: Bool,
        viewedCount: Int? = nil,
        exportedCount: Int? = nil,
        cached: Bool? = nil,
        generationTimeMs: Int? = nil
    ) {
        self.id = id
        self.studentName = studentName
        self.reportType = reportType
        self.startDate = startDate
        self.endDate = endDate
        self.reportData = reportData
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.aiAnalysisIncluded = aiAnalysisIncluded
        self.viewedCount = viewedCount
        self.exportedCount = exportedCount
        self.cached = cached
        self.generationTimeMs = generationTimeMs
    }
}

/// Report type enumeration
enum ReportType: String, Codable, CaseIterable {
    case weekly = "weekly"
    case monthly = "monthly"
    case custom = "custom"
    case progress = "progress"

    var displayName: String {
        switch self {
        case .weekly: return "Weekly Report"
        case .monthly: return "Monthly Report"
        case .custom: return "Custom Report"
        case .progress: return "Progress Report"
        }
    }

    var icon: String {
        switch self {
        case .weekly: return "calendar.badge.clock"
        case .monthly: return "calendar"
        case .custom: return "calendar.badge.plus"
        case .progress: return "chart.line.uptrend.xyaxis"
        }
    }
}

/// Main report data structure - now supports both full analytics and narrative formats
struct ReportData: Codable {
    // Legacy full analytics data (optional for backward compatibility)
    let userId: String?
    let reportPeriod: ReportPeriod?
    let generatedAt: Date?
    let academic: AcademicMetrics?
    let activity: ActivityMetrics?
    let mentalHealth: MentalHealthMetrics?
    let subjects: [String: SubjectMetrics]?
    let progress: ProgressMetrics?
    let mistakes: MistakeAnalysis?
    let metadata: ReportMetadata?

    // New narrative report format
    let type: String?
    let narrativeAvailable: Bool?
    let narrativeId: String?
    let url: String? // URL to fetch the narrative content
    let fetchNarrativeUrl: String? // Alternative field name for backward compatibility

    // Computed property to get the narrative URL regardless of field name
    var narrativeURL: String? {
        return url ?? fetchNarrativeUrl
    }

    // Computed property to determine if this is a narrative report
    var isNarrativeReport: Bool {
        return type == "narrative_report" || narrativeURL != nil
    }

    enum CodingKeys: String, CodingKey {
        case userId, reportPeriod, generatedAt, academic, activity, mentalHealth, subjects, progress, mistakes, metadata
        case type, narrativeId = "narrative_id", url
        case narrativeAvailable = "narrative_available"
        case fetchNarrativeUrl = "fetch_narrative_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // New narrative format fields
        type = try container.decodeIfPresent(String.self, forKey: .type)
        narrativeAvailable = try container.decodeIfPresent(Bool.self, forKey: .narrativeAvailable)
        narrativeId = try container.decodeIfPresent(String.self, forKey: .narrativeId)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        fetchNarrativeUrl = try container.decodeIfPresent(String.self, forKey: .fetchNarrativeUrl)

        // Legacy full analytics fields (all optional for backward compatibility)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        reportPeriod = try container.decodeIfPresent(ReportPeriod.self, forKey: .reportPeriod)
        academic = try container.decodeIfPresent(AcademicMetrics.self, forKey: .academic)
        activity = try container.decodeIfPresent(ActivityMetrics.self, forKey: .activity)
        mentalHealth = try container.decodeIfPresent(MentalHealthMetrics.self, forKey: .mentalHealth)
        subjects = try container.decodeIfPresent([String: SubjectMetrics].self, forKey: .subjects)
        progress = try container.decodeIfPresent(ProgressMetrics.self, forKey: .progress)
        mistakes = try container.decodeIfPresent(MistakeAnalysis.self, forKey: .mistakes)
        metadata = try container.decodeIfPresent(ReportMetadata.self, forKey: .metadata)

        // Handle date parsing for backward compatibility
        if let generatedAtString = try container.decodeIfPresent(String.self, forKey: .generatedAt) {
            let formatter = ISO8601DateFormatter()
            generatedAt = formatter.date(from: generatedAtString) ?? Date()
        } else {
            generatedAt = nil
        }
    }

    // Memberwise initializer for sample data
    init(
        userId: String? = nil,
        reportPeriod: ReportPeriod? = nil,
        generatedAt: Date? = nil,
        academic: AcademicMetrics? = nil,
        activity: ActivityMetrics? = nil,
        mentalHealth: MentalHealthMetrics? = nil,
        subjects: [String: SubjectMetrics]? = nil,
        progress: ProgressMetrics? = nil,
        mistakes: MistakeAnalysis? = nil,
        metadata: ReportMetadata? = nil,
        type: String? = nil,
        narrativeAvailable: Bool? = nil,
        narrativeId: String? = nil,
        url: String? = nil,
        fetchNarrativeUrl: String? = nil
    ) {
        self.userId = userId
        self.reportPeriod = reportPeriod
        self.generatedAt = generatedAt
        self.academic = academic
        self.activity = activity
        self.mentalHealth = mentalHealth
        self.subjects = subjects
        self.progress = progress
        self.mistakes = mistakes
        self.metadata = metadata
        self.type = type
        self.narrativeAvailable = narrativeAvailable
        self.narrativeId = narrativeId
        self.url = url
        self.fetchNarrativeUrl = fetchNarrativeUrl
    }
}

/// Report period information
struct ReportPeriod: Codable {
    let startDate: Date
    let endDate: Date

    var duration: TimeInterval {
        return endDate.timeIntervalSince(startDate)
    }

    var durationDays: Int {
        return Int(duration / (24 * 60 * 60))
    }

    enum CodingKeys: String, CodingKey {
        case startDate, endDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let formatter = ISO8601DateFormatter()

        let startDateString = try container.decode(String.self, forKey: .startDate)
        startDate = formatter.date(from: startDateString) ?? Date()

        let endDateString = try container.decode(String.self, forKey: .endDate)
        endDate = formatter.date(from: endDateString) ?? Date()
    }

    // Memberwise initializer for sample data
    init(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
    }
}

/// Academic performance metrics
struct AcademicMetrics: Codable {
    let overallAccuracy: Double
    let averageConfidence: Double
    let totalQuestions: Int
    let correctAnswers: Int
    let improvementTrend: String
    let consistencyScore: Double
    let timeSpentMinutes: Int
    let questionsPerDay: Int

    var accuracyPercentage: String {
        return String(format: "%.1f%%", overallAccuracy * 100)
    }

    var confidencePercentage: String {
        return String(format: "%.1f%%", averageConfidence * 100)
    }

    var studyTimeHours: Double {
        return Double(timeSpentMinutes) / 60.0
    }

    var trendDirection: ParentReportTrendDirection {
        switch improvementTrend.lowercased() {
        case "improving": return .improving
        case "declining": return .declining
        case "stable": return .stable
        default: return .stable
        }
    }
}

/// Learning activity metrics
struct ActivityMetrics: Codable {
    let studyTime: StudyTimeMetrics
    let engagement: EngagementMetrics
    let patterns: StudyPatterns

    var totalStudyHours: Double {
        return Double(studyTime.totalMinutes) / 60.0
    }
}

/// Study time breakdown
struct StudyTimeMetrics: Codable {
    let totalMinutes: Int
    let averageSessionMinutes: Int
    let activeDays: Int
    let sessionsPerDay: Double

    var totalHours: Double {
        return Double(totalMinutes) / 60.0
    }

    var averageSessionHours: Double {
        return Double(averageSessionMinutes) / 60.0
    }
}

/// Student engagement metrics
struct EngagementMetrics: Codable {
    let totalConversations: Int
    let totalMessages: Int
    let averageMessagesPerConversation: Int
    let conversationEngagementScore: Double

    var engagementLevel: String {
        switch conversationEngagementScore {
        case 0.8...: return "Very High"
        case 0.6..<0.8: return "High"
        case 0.4..<0.6: return "Moderate"
        case 0.2..<0.4: return "Low"
        default: return "Very Low"
        }
    }
}

/// Study patterns analysis
struct StudyPatterns: Codable {
    let preferredStudyTimes: String
    let sessionLengthTrend: String
    let subjectPreferences: [String]

    var preferredTimeDisplay: String {
        switch preferredStudyTimes.lowercased() {
        case "morning": return "🌅 Morning"
        case "afternoon": return "☀️ Afternoon"
        case "evening": return "🌙 Evening"
        default: return "📅 No Clear Pattern"
        }
    }
}

/// Mental health and wellbeing metrics
struct MentalHealthMetrics: Codable {
    let overallWellbeing: Double
    let indicators: [String: MentalHealthIndicator]
    let trends: [String: String]
    let alerts: [MentalHealthAlert]
    let dataQuality: DataQualityMetrics

    var wellbeingPercentage: String {
        return String(format: "%.1f%%", overallWellbeing * 100)
    }

    var wellbeingLevel: String {
        switch overallWellbeing {
        case 0.8...: return "Excellent"
        case 0.6..<0.8: return "Good"
        case 0.4..<0.6: return "Fair"
        case 0.2..<0.4: return "Concerning"
        default: return "Needs Attention"
        }
    }

    var wellbeingColor: Color {
        switch overallWellbeing {
        case 0.8...: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        case 0.2..<0.4: return .red
        default: return .red
        }
    }
}

/// Individual mental health indicator
struct MentalHealthIndicator: Codable {
    let averageScore: Double
    let latestScore: Double
    let count: Int
    let trend: String

    var trendDirection: ParentReportTrendDirection {
        switch trend.lowercased() {
        case "improving": return .improving
        case "declining": return .declining
        case "stable": return .stable
        default: return .stable
        }
    }
}

/// Mental health alert
struct MentalHealthAlert: Codable, Identifiable {
    let id = UUID()
    let type: String
    let severity: String
    let message: String
    let score: Double

    var severityLevel: AlertSeverity {
        switch severity.lowercased() {
        case "high": return .high
        case "medium": return .medium
        case "low": return .low
        default: return .low
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, severity, message, score
    }
}

/// Alert severity levels
enum AlertSeverity: String, CaseIterable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        }
    }

    var icon: String {
        switch self {
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "info.circle.fill"
        }
    }
}

/// Data quality metrics
struct DataQualityMetrics: Codable {
    let totalIndicators: Int
    let coverageDays: Int
}

/// Subject-specific metrics
struct SubjectMetrics: Codable {
    let performance: SubjectPerformance
    let activity: SubjectActivity
}

/// Subject performance data
struct SubjectPerformance: Codable {
    let totalQuestions: Int
    let correctAnswers: Int
    let accuracy: Double
    let averageConfidence: Double

    var accuracyPercentage: String {
        return String(format: "%.1f%%", accuracy * 100)
    }
}

/// Subject activity data
struct SubjectActivity: Codable {
    let totalSessions: Int
    let totalStudyTime: Int
    let averageSessionLength: Double

    var studyTimeHours: Double {
        return Double(totalStudyTime) / 60.0
    }
}

/// Progress comparison metrics
struct ProgressMetrics: Codable {
    let comparison: String
    let improvements: [ProgressImprovement]
    let concerns: [ProgressConcern]
    let overallTrend: String
    let progressScore: Double?
    let detailedComparison: DetailedComparison?
    let recommendations: [ProgressRecommendation]?
    let previousPeriod: PreviousPeriod?

    var trendDirection: ParentReportTrendDirection {
        switch overallTrend.lowercased() {
        case "improving": return .improving
        case "excellent_progress": return .improving
        case "needs_attention": return .declining
        case "needs_immediate_attention": return .declining
        case "declining": return .declining
        case "stable": return .stable
        default: return .stable
        }
    }

    var trendColor: Color {
        switch overallTrend.lowercased() {
        case "excellent_progress": return .green
        case "improving": return .blue
        case "stable": return .gray
        case "declining": return .orange
        case "needs_attention": return .red
        case "needs_immediate_attention": return .red
        default: return .gray
        }
    }

    var trendDisplayName: String {
        switch overallTrend.lowercased() {
        case "excellent_progress": return "Excellent Progress"
        case "improving": return "Improving"
        case "stable": return "Stable"
        case "declining": return "Declining"
        case "needs_attention": return "Needs Attention"
        case "needs_immediate_attention": return "Needs Immediate Attention"
        default: return "Stable"
        }
    }
}

/// Progress improvement item
struct ProgressImprovement: Codable, Identifiable {
    let id = UUID()
    let metric: String
    let change: Double
    let message: String
    let significance: String?

    var significanceLevel: SignificanceLevel {
        switch significance?.lowercased() {
        case "major": return .major
        case "minor": return .minor
        default: return .minor
        }
    }

    enum CodingKeys: String, CodingKey {
        case metric, change, message, significance
    }
}

/// Progress concern item
struct ProgressConcern: Codable, Identifiable {
    let id = UUID()
    let metric: String
    let change: Double
    let message: String
    let significance: String?

    var significanceLevel: SignificanceLevel {
        switch significance?.lowercased() {
        case "major": return .major
        case "minor": return .minor
        default: return .minor
        }
    }

    enum CodingKeys: String, CodingKey {
        case metric, change, message, significance
    }
}

/// Detailed comparison data
struct DetailedComparison: Codable {
    let academicPerformance: AcademicComparison
    let studyHabits: StudyHabitsComparison
    let mentalWellbeing: MentalWellbeingComparison
}

/// Academic performance comparison
struct AcademicComparison: Codable {
    let accuracy: MetricComparison
    let confidence: MetricComparison
}

/// Study habits comparison
struct StudyHabitsComparison: Codable {
    let studyTime: MetricComparison
    let activeDays: MetricComparison
}

/// Mental wellbeing comparison
struct MentalWellbeingComparison: Codable {
    let engagement: MetricComparison
}

// TrendDirection enum is defined in SubjectBreakdownModels.swift to avoid conflicts

/// Individual metric comparison
struct MetricComparison: Codable {
    let current: Double
    let previous: Double
    let change: Double
    let changePercent: Double

    var changeDirection: TrendDirection {
        if change > 0.02 { return .improving }
        if change < -0.02 { return .declining }
        return .stable
    }

    var changeDisplayText: String {
        let absPercent = abs(changePercent)
        if absPercent < 1 { return "No significant change" }

        let direction = change > 0 ? "increased" : "decreased"
        return "\(direction) by \(String(format: "%.1f", absPercent))%"
    }
}

/// Progress recommendations
struct ProgressRecommendation: Codable, Identifiable {
    let id = UUID()
    let category: String
    let priority: String
    let title: String
    let description: String
    let actionItems: [String]

    var priorityLevel: RecommendationPriority {
        switch priority.lowercased() {
        case "high": return .high
        case "medium": return .medium
        case "low": return .low
        default: return .medium
        }
    }

    var categoryType: RecommendationCategory {
        switch category.lowercased() {
        case "academic": return .academic
        case "habits": return .habits
        case "motivation": return .motivation
        case "getting_started": return .gettingStarted
        default: return .academic
        }
    }

    enum CodingKeys: String, CodingKey {
        case category, priority, title, description, actionItems
    }
}

/// Previous period information
struct PreviousPeriod: Codable {
    let startDate: Date
    let endDate: Date
    let duration: Int

    var durationText: String {
        return "\(duration) day\(duration == 1 ? "" : "s")"
    }

    enum CodingKeys: String, CodingKey {
        case startDate, endDate, duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let formatter = ISO8601DateFormatter()

        let startDateString = try container.decode(String.self, forKey: .startDate)
        startDate = formatter.date(from: startDateString) ?? Date()

        let endDateString = try container.decode(String.self, forKey: .endDate)
        endDate = formatter.date(from: endDateString) ?? Date()

        duration = try container.decode(Int.self, forKey: .duration)
    }
}

/// Supporting enums
enum SignificanceLevel: String, CaseIterable {
    case major = "major"
    case minor = "minor"

    var color: Color {
        switch self {
        case .major: return .primary
        case .minor: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .major: return "exclamationmark.2"
        case .minor: return "info.circle"
        }
    }
}

enum RecommendationPriority: String, CaseIterable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    var icon: String {
        switch self {
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "info.circle.fill"
        case .low: return "lightbulb.fill"
        }
    }
}

enum RecommendationCategory: String, CaseIterable {
    case academic = "academic"
    case habits = "habits"
    case motivation = "motivation"
    case gettingStarted = "getting_started"

    var displayName: String {
        switch self {
        case .academic: return "Academic"
        case .habits: return "Study Habits"
        case .motivation: return "Motivation"
        case .gettingStarted: return "Getting Started"
        }
    }

    var icon: String {
        switch self {
        case .academic: return "graduationcap.fill"
        case .habits: return "calendar.badge.checkmark"
        case .motivation: return "heart.fill"
        case .gettingStarted: return "star.fill"
        }
    }
}

/// Mistake analysis data
struct MistakeAnalysis: Codable {
    let totalMistakes: Int
    let mistakeRate: Int
    let patterns: [MistakePattern]
    let recommendations: [String]
}

/// Mistake pattern by subject
struct MistakePattern: Codable, Identifiable {
    let id = UUID()
    let subject: String
    let count: Int
    let percentage: Int
    let averageConfidence: Double
    let commonIssues: [String]

    enum CodingKeys: String, CodingKey {
        case subject, count, percentage, averageConfidence, commonIssues
    }
}

/// Report metadata
struct ReportMetadata: Codable {
    let generationTimeMs: Int
    let dataPoints: DataPointsMetrics
}

/// Data points analyzed
struct DataPointsMetrics: Codable {
    let questions: Int
    let sessions: Int
    let conversations: Int
    let mentalHealthIndicators: Int
}

/// Trend direction enumeration
enum ParentReportTrendDirection: String, CaseIterable {
    case improving = "improving"
    case declining = "declining"
    case stable = "stable"

    var color: Color {
        switch self {
        case .improving: return .green
        case .declining: return .red
        case .stable: return .blue
        }
    }

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .declining: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var displayName: String {
        switch self {
        case .improving: return "Improving"
        case .declining: return "Declining"
        case .stable: return "Stable"
        }
    }
}

// MARK: - Narrative Report Models

/// Narrative report content structure
struct NarrativeReport: Codable, Identifiable {
    let id: String
    let content: String
    let summary: String
    let keyInsights: [String]
    let recommendations: [String]
    let wordCount: Int
    let generatedAt: Date
    let toneStyle: String?
    let language: String?
    let readingLevel: String?

    enum CodingKeys: String, CodingKey {
        case id, content, summary, keyInsights, recommendations, wordCount, generatedAt
        case toneStyle, language, readingLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        summary = try container.decode(String.self, forKey: .summary)
        keyInsights = try container.decode([String].self, forKey: .keyInsights)
        recommendations = try container.decode([String].self, forKey: .recommendations)
        wordCount = try container.decode(Int.self, forKey: .wordCount)
        toneStyle = try container.decodeIfPresent(String.self, forKey: .toneStyle)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        readingLevel = try container.decodeIfPresent(String.self, forKey: .readingLevel)

        // Handle date parsing
        let generatedAtString = try container.decode(String.self, forKey: .generatedAt)
        let formatter = ISO8601DateFormatter()
        generatedAt = formatter.date(from: generatedAtString) ?? Date()
    }
}

/// Narrative response from backend
struct NarrativeResponse: Codable {
    let success: Bool
    let narrative: NarrativeReport?
    let error: String?
}

// MARK: - API Response Models

/// Parent report generation response
struct ParentReportResponse: Codable {
    let success: Bool
    let reportId: String?
    let reportData: ReportData?
    let generationTimeMs: Int?
    let expiresAt: Date?
    let cached: Bool?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case reportId = "report_id"
        case reportData = "report_data"
        case generationTimeMs = "generation_time_ms"
        case expiresAt = "expires_at"
        case cached
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        success = try container.decode(Bool.self, forKey: .success)
        reportId = try container.decodeIfPresent(String.self, forKey: .reportId)
        reportData = try container.decodeIfPresent(ReportData.self, forKey: .reportData)
        generationTimeMs = try container.decodeIfPresent(Int.self, forKey: .generationTimeMs)
        cached = try container.decodeIfPresent(Bool.self, forKey: .cached)
        error = try container.decodeIfPresent(String.self, forKey: .error)

        // Handle date parsing
        if let expiresAtString = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
            let formatter = ISO8601DateFormatter()
            expiresAt = formatter.date(from: expiresAtString)
        } else {
            expiresAt = nil
        }
    }
}

/// Student reports list response
struct StudentReportsResponse: Codable {
    let success: Bool
    let reports: [ReportListItem]
    let pagination: PaginationInfo
    let error: String?
}

/// Report list item (summary format)
struct ReportListItem: Codable, Identifiable {
    let id: String
    let reportType: ReportType
    let startDate: Date
    let endDate: Date
    let generatedAt: Date
    let expiresAt: Date
    let aiAnalysisIncluded: Bool
    let viewedCount: Int?
    let exportedCount: Int?
    let totalGenerationTimeMs: Int?

    enum CodingKeys: String, CodingKey {
        case id, reportType = "report_type", aiAnalysisIncluded = "ai_analysis_included"
        case startDate = "start_date", endDate = "end_date"
        case generatedAt = "generated_at", expiresAt = "expires_at"
        case viewedCount = "viewed_count", exportedCount = "exported_count"
        case totalGenerationTimeMs = "total_generation_time_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        reportType = try container.decode(ReportType.self, forKey: .reportType)
        aiAnalysisIncluded = try container.decode(Bool.self, forKey: .aiAnalysisIncluded)
        viewedCount = try container.decodeIfPresent(Int.self, forKey: .viewedCount)
        exportedCount = try container.decodeIfPresent(Int.self, forKey: .exportedCount)
        totalGenerationTimeMs = try container.decodeIfPresent(Int.self, forKey: .totalGenerationTimeMs)

        // Handle date parsing
        let formatter = ISO8601DateFormatter()

        let startDateString = try container.decode(String.self, forKey: .startDate)
        startDate = formatter.date(from: startDateString) ?? Date()

        let endDateString = try container.decode(String.self, forKey: .endDate)
        endDate = formatter.date(from: endDateString) ?? Date()

        let generatedAtString = try container.decode(String.self, forKey: .generatedAt)
        generatedAt = formatter.date(from: generatedAtString) ?? Date()

        let expiresAtString = try container.decode(String.self, forKey: .expiresAt)
        expiresAt = formatter.date(from: expiresAtString) ?? Date()
    }
}

/// Pagination information
struct PaginationInfo: Codable {
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool
}

// MARK: - Report Request Models

/// Generate report request
struct GenerateReportRequest: Codable {
    let studentId: String
    let startDate: String
    let endDate: String
    let reportType: ReportType
    let includeAiAnalysis: Bool
    let compareWithPrevious: Bool

    enum CodingKeys: String, CodingKey {
        case studentId = "student_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case reportType = "report_type"
        case includeAiAnalysis = "include_ai_analysis"
        case compareWithPrevious = "compare_with_previous"
    }
}

// MARK: - Sample Data for Development

extension ParentReport {
    static let sampleReport = ParentReport(
        id: "sample-report-id",
        studentName: "Sample Student",
        reportType: .weekly,
        startDate: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
        endDate: Date(),
        reportData: ReportData.sampleData,
        generatedAt: Date(),
        expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
        aiAnalysisIncluded: true,
        viewedCount: 0,
        exportedCount: 0,
        cached: false,
        generationTimeMs: 2500
    )
}

extension ReportData {
    static let sampleData = ReportData(
        userId: "sample-user-id",
        reportPeriod: ReportPeriod(
            startDate: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
            endDate: Date()
        ),
        generatedAt: Date(),
        academic: AcademicMetrics(
            overallAccuracy: 0.85,
            averageConfidence: 0.78,
            totalQuestions: 42,
            correctAnswers: 36,
            improvementTrend: "improving",
            consistencyScore: 0.82,
            timeSpentMinutes: 240,
            questionsPerDay: 6
        ),
        activity: ActivityMetrics(
            studyTime: StudyTimeMetrics(
                totalMinutes: 240,
                averageSessionMinutes: 30,
                activeDays: 5,
                sessionsPerDay: 1.2
            ),
            engagement: EngagementMetrics(
                totalConversations: 8,
                totalMessages: 45,
                averageMessagesPerConversation: 6,
                conversationEngagementScore: 0.75
            ),
            patterns: StudyPatterns(
                preferredStudyTimes: "evening",
                sessionLengthTrend: "stable",
                subjectPreferences: ["Mathematics", "Physics", "Chemistry"]
            )
        ),
        mentalHealth: MentalHealthMetrics(
            overallWellbeing: 0.82,
            indicators: [:],
            trends: [:],
            alerts: [],
            dataQuality: DataQualityMetrics(totalIndicators: 15, coverageDays: 7)
        ),
        subjects: [:],
        progress: ProgressMetrics(
            comparison: "improving",
            improvements: [],
            concerns: [],
            overallTrend: "improving",
            progressScore: 0.85,
            detailedComparison: nil,
            recommendations: nil,
            previousPeriod: nil
        ),
        mistakes: MistakeAnalysis(
            totalMistakes: 6,
            mistakeRate: 14,
            patterns: [],
            recommendations: ["Focus on algebra practice", "Review geometry concepts"]
        ),
        metadata: ReportMetadata(
            generationTimeMs: 2500,
            dataPoints: DataPointsMetrics(
                questions: 42,
                sessions: 8,
                conversations: 8,
                mentalHealthIndicators: 15
            )
        )
    )
}