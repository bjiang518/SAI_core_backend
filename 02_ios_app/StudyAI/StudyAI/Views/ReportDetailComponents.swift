//
//  ReportDetailComponents.swift
//  StudyAI
//
//  Supporting components for detailed report views
//  Provides reusable UI elements for displaying report data
//

import SwiftUI

// MARK: - Helper Functions

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

// MARK: - Performance Components

struct PerformanceMetricRow: View {
    let title: String
    let value: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }

            ProgressView(value: progress)
                .tint(.blue)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct StatisticItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
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

// MARK: - Activity Components

struct StudyTimeCard: View {
    let totalHours: Double
    let activeDays: Int
    let averageSession: Double

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                StudyTimeMetric(
                    icon: "clock.fill",
                    title: "Total Hours",
                    value: String(format: "%.1f", totalHours),
                    color: .blue
                )

                StudyTimeMetric(
                    icon: "calendar.badge.checkmark",
                    title: "Active Days",
                    value: "\(activeDays)",
                    color: .green
                )

                StudyTimeMetric(
                    icon: "timer",
                    title: "Avg Session",
                    value: String(format: "%.1fh", averageSession),
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct StudyTimeMetric: View {
    let icon: String
    let title: String
    let value: String
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
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct EngagementCard: View {
    let engagement: EngagementMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Engagement Level")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(engagement.engagementLevel)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }

                Spacer()

                Circle()
                    .fill(getEngagementColor(engagement.conversationEngagementScore))
                    .frame(width: 12, height: 12)
            }

            HStack {
                EngagementStat(
                    title: "Conversations",
                    value: "\(engagement.totalConversations)"
                )

                EngagementStat(
                    title: "Messages",
                    value: "\(engagement.totalMessages)"
                )

                EngagementStat(
                    title: "Avg per Chat",
                    value: "\(engagement.averageMessagesPerConversation)"
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func getEngagementColor(_ score: Double) -> Color {
        switch score {
        case 0.8...: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
}

struct EngagementStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StudyPatternsCard: View {
    let patterns: StudyPatterns

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PatternRow(
                title: "Preferred Study Time",
                value: patterns.preferredTimeDisplay,
                icon: "clock"
            )

            PatternRow(
                title: "Session Length Trend",
                value: patterns.sessionLengthTrend.capitalized,
                icon: "chart.line.uptrend.xyaxis"
            )

            if !patterns.subjectPreferences.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Top Subjects")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    HStack {
                        ForEach(patterns.subjectPreferences.prefix(3), id: \.self) { subject in
                            Text(subject)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct PatternRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.blue)
                .frame(width: 20)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)

            Spacer()

            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Mental Health Components

struct WellbeingOverviewCard: View {
    let mentalHealth: MentalHealthMetrics

    var body: some View {
        VStack(spacing: 16) {
            // Overall Score
            HStack {
                VStack(alignment: .leading) {
                    Text("Overall Wellbeing")
                        .font(.headline)
                        .fontWeight(.bold)

                    Text(mentalHealth.wellbeingLevel)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(mentalHealth.wellbeingColor)
                }

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color(.systemGray4), lineWidth: 8)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: mentalHealth.overallWellbeing)
                        .stroke(mentalHealth.wellbeingColor, lineWidth: 8)
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))

                    Text(mentalHealth.wellbeingPercentage)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(mentalHealth.wellbeingColor)
                }
            }

            // Indicators
            if !mentalHealth.indicators.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Indicators")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        ForEach(Array(mentalHealth.indicators.keys.prefix(4)), id: \.self) { key in
                            if let indicator = mentalHealth.indicators[key] {
                                IndicatorChip(
                                    name: key.capitalized,
                                    score: indicator.averageScore,
                                    trend: convertTrendDirection(indicator.trendDirection)
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct IndicatorChip: View {
    let name: String
    let score: Double
    let trend: TrendDirection

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.caption2)
                .fontWeight(.medium)

            Spacer()

            Image(systemName: trend.icon)
                .font(.system(size: 10))
                .foregroundColor(trend.color)

            Text(String(format: "%.1f", score * 100))
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemBackground))
        .cornerRadius(6)
    }
}

struct AlertCard: View {
    let alert: MentalHealthAlert

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alert.severityLevel.icon)
                .font(.system(size: 16))
                .foregroundColor(alert.severityLevel.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(alert.type.capitalized.replacingOccurrences(of: "_", with: " "))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(alert.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(alert.severityLevel.color.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(alert.severityLevel.color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct DataQualityCard: View {
    let dataQuality: DataQualityMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Data Coverage")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                DataQualityItem(
                    title: "Indicators",
                    value: "\(dataQuality.totalIndicators)"
                )

                DataQualityItem(
                    title: "Days Covered",
                    value: "\(dataQuality.coverageDays)"
                )

                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct DataQualityItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Subject Components

struct ReportSubjectCard: View {
    let subject: String
    let metrics: SubjectMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(subject.capitalized)
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                Text(metrics.performance.accuracyPercentage)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }

            HStack {
                SubjectMetricItem(
                    title: "Questions",
                    value: "\(metrics.performance.totalQuestions)"
                )

                SubjectMetricItem(
                    title: "Correct",
                    value: "\(metrics.performance.correctAnswers)"
                )

                SubjectMetricItem(
                    title: "Study Time",
                    value: String(format: "%.1fh", metrics.activity.studyTimeHours)
                )

                SubjectMetricItem(
                    title: "Sessions",
                    value: "\(metrics.activity.totalSessions)"
                )
            }

            ProgressView(value: metrics.performance.accuracy)
                .tint(.blue)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Enhanced Subject Visualization Components

import Charts


// MARK: - Chart Data Models

struct SubjectStudyTimeChartData {
    let subject: String
    let studyTime: Double
    let percentage: Double
    let color: Color
}

struct SubjectAccuracyData {
    let subject: String
    let accuracy: Double
    let color: Color
}

struct SubjectMetricItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Progress Components

struct ProgressOverviewCard: View {
    let progress: ProgressMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Overall Trend")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(progress.trendDirection.displayName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(progress.trendDirection.color)
                }

                Spacer()

                Image(systemName: progress.trendDirection.icon)
                    .font(.system(size: 24))
                    .foregroundColor(progress.trendDirection.color)
            }

            if let progressScore = progress.progressScore {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Progress Score")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ProgressView(value: progressScore)
                        .tint(progress.trendDirection.color)
                }
            }

            if progress.comparison != "no_previous_data" {
                Text("Compared to previous period")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ProgressItemCard: View {
    let title: String
    let message: String
    let change: Double
    let isPositive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isPositive ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(isPositive ? .green : .red)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(String(format: "%+.1f%%", change * 100))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(isPositive ? .green : .red)
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

// MARK: - Mistake Components

struct MistakesOverviewCard: View {
    let mistakes: MistakeAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Total Mistakes")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("\(mistakes.totalMistakes)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text("Mistake Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("\(mistakes.mistakeRate)%")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }

            if mistakes.totalMistakes > 0 {
                ProgressView(value: Double(mistakes.mistakeRate) / 100.0)
                    .tint(.red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct MistakePatternCard: View {
    let pattern: MistakePattern

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pattern.subject.capitalized)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(pattern.count) mistakes (\(pattern.percentage)%)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !pattern.commonIssues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Common Issues:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    ForEach(pattern.commonIssues, id: \.self) { issue in
                        Text("• \(issue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
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

struct RecommendationCard: View {
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 16))
                .foregroundColor(.orange)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - General Components

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Export Sheet

struct ReportExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let report: ParentReport

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)

                    Text("Export Report")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Choose how you'd like to share this report")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    ExportOptionButton(
                        icon: "doc.fill",
                        title: "PDF Report",
                        description: "Full detailed report as PDF"
                    ) {
                        // Export as PDF
                    }

                    ExportOptionButton(
                        icon: "photo.fill",
                        title: "Summary Image",
                        description: "Key metrics as shareable image"
                    ) {
                        // Export as image
                    }

                    ExportOptionButton(
                        icon: "envelope.fill",
                        title: "Email Report",
                        description: "Send report via email"
                    ) {
                        // Email report
                    }

                    ExportOptionButton(
                        icon: "link",
                        title: "Share Link",
                        description: "Generate shareable link"
                    ) {
                        // Generate share link
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ExportOptionButton: View {
    let icon: String
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}