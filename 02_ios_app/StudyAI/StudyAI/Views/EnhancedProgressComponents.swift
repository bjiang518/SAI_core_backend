//
//  EnhancedProgressComponents.swift
//  StudyAI
//
//  Enhanced UI components for detailed progress comparison and recommendations
//  Displays comprehensive progress analysis with comparisons and actionable insights
//

import SwiftUI

// MARK: - Enhanced Progress Section

struct EnhancedProgressSection: View {
    let progress: ProgressMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeader(title: "Progress Analysis", icon: "chart.line.uptrend.xyaxis")

            // Overall Progress Overview
            OverallProgressCard(progress: progress)

            // Previous Period Comparison
            if let previousPeriod = progress.previousPeriod {
                PreviousPeriodCard(previousPeriod: previousPeriod)
            }

            // Detailed Metric Comparisons
            if let detailedComparison = progress.detailedComparison {
                DetailedMetricsComparison(comparison: detailedComparison)
            }

            // Improvements
            if !progress.improvements.isEmpty {
                ProgressChangesSection(
                    title: "Improvements",
                    changes: progress.improvements.map { ProgressChangeItem.improvement($0) },
                    color: .green
                )
            }

            // Concerns
            if !progress.concerns.isEmpty {
                ProgressChangesSection(
                    title: "Areas for Attention",
                    changes: progress.concerns.map { ProgressChangeItem.concern($0) },
                    color: .red
                )
            }

            // Intelligent Recommendations
            if let recommendations = progress.recommendations, !recommendations.isEmpty {
                IntelligentRecommendationsSection(recommendations: recommendations)
            }
        }
    }
}

// MARK: - Overall Progress Card

struct OverallProgressCard: View {
    let progress: ProgressMetrics

    var body: some View {
        VStack(spacing: 16) {
            // Progress Score Visualization
            HStack {
                VStack(alignment: .leading) {
                    Text("Overall Progress")
                        .font(.headline)
                        .fontWeight(.bold)

                    Text(progress.trendDisplayName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(progress.trendColor)
                }

                Spacer()

                // Progress Score Circle
                if let progressScore = progress.progressScore {
                    ProgressScoreCircle(score: progressScore, color: progress.trendColor)
                }
            }

            // Progress Description
            if progress.comparison != "no_previous_data" {
                HStack {
                    Image(systemName: progress.trendDirection.icon)
                        .foregroundColor(progress.trendColor)

                    Text("Compared to previous period")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()
                }
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)

                    Text("This is your first report - no comparison data available yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Progress Score Circle

struct ProgressScoreCircle: View {
    let score: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 6)
                .frame(width: 60, height: 60)

            Circle()
                .trim(from: 0, to: score)
                .stroke(color, lineWidth: 6)
                .frame(width: 60, height: 60)
                .rotationEffect(.degrees(-90))

            Text("\(Int(score * 100))")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
    }
}

// MARK: - Previous Period Card

struct PreviousPeriodCard: View {
    let previousPeriod: PreviousPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Previous Period")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)

                Text(formatDateRange(start: previousPeriod.startDate, end: previousPeriod.endDate))
                    .font(.subheadline)

                Spacer()

                Text(previousPeriod.durationText)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
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

    private func formatDateRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

// MARK: - Detailed Metrics Comparison

struct DetailedMetricsComparison: View {
    let comparison: DetailedComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detailed Comparison")
                .font(.headline)

            VStack(spacing: 12) {
                MetricComparisonGroup(
                    title: "Academic Performance",
                    icon: "graduationcap.fill",
                    metrics: [
                        ("Accuracy", comparison.academicPerformance.accuracy),
                        ("Confidence", comparison.academicPerformance.confidence)
                    ]
                )

                MetricComparisonGroup(
                    title: "Study Habits",
                    icon: "calendar.badge.checkmark",
                    metrics: [
                        ("Study Time", comparison.studyHabits.studyTime),
                        ("Active Days", comparison.studyHabits.activeDays)
                    ]
                )

                MetricComparisonGroup(
                    title: "Mental Wellbeing",
                    icon: "heart.fill",
                    metrics: [
                        ("Engagement", comparison.mentalWellbeing.engagement)
                    ]
                )
            }
        }
    }
}

// MARK: - Metric Comparison Group

struct MetricComparisonGroup: View {
    let title: String
    let icon: String
    let metrics: [(String, MetricComparison)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            VStack(spacing: 6) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                    MetricComparisonRow(name: metric.0, comparison: metric.1)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Metric Comparison Row

struct MetricComparisonRow: View {
    let name: String
    let comparison: MetricComparison

    var body: some View {
        HStack {
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 80, alignment: .leading)

            HStack(spacing: 8) {
                MetricValue(value: comparison.previous, label: "Previous")

                Image(systemName: comparison.changeDirection.icon)
                    .font(.system(size: 12))
                    .foregroundColor(comparison.changeDirection.color)

                MetricValue(value: comparison.current, label: "Current")
            }

            Spacer()

            Text(comparison.changeDisplayText)
                .font(.caption2)
                .foregroundColor(comparison.changeDirection.color)
                .fontWeight(.medium)
        }
    }
}

struct MetricValue: View {
    let value: Double
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f", value * 100))
                .font(.caption2)
                .fontWeight(.semibold)

            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .frame(width: 40)
    }
}

// MARK: - Progress Changes Section

enum ProgressChangeItem {
    case improvement(ProgressImprovement)
    case concern(ProgressConcern)

    var id: UUID {
        switch self {
        case .improvement(let item): return item.id
        case .concern(let item): return item.id
        }
    }

    var metric: String {
        switch self {
        case .improvement(let item): return item.metric
        case .concern(let item): return item.metric
        }
    }

    var change: Double {
        switch self {
        case .improvement(let item): return item.change
        case .concern(let item): return item.change
        }
    }

    var message: String {
        switch self {
        case .improvement(let item): return item.message
        case .concern(let item): return item.message
        }
    }

    var significance: SignificanceLevel {
        switch self {
        case .improvement(let item): return item.significanceLevel
        case .concern(let item): return item.significanceLevel
        }
    }
}

struct ProgressChangesSection: View {
    let title: String
    let changes: [ProgressChangeItem]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            LazyVStack(spacing: 12) {
                ForEach(changes, id: \.id) { change in
                    ProgressChangeCard(change: change, color: color)
                }
            }
        }
    }
}

// MARK: - Progress Change Card

struct ProgressChangeCard: View {
    let change: ProgressChangeItem
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            // Significance Indicator
            Image(systemName: change.significance.icon)
                .font(.system(size: 16))
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(change.metric.capitalized)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Text(String(format: "%+.1f%%", change.change * 100))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                }

                Text(change.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Intelligent Recommendations Section

struct IntelligentRecommendationsSection: View {
    let recommendations: [ProgressRecommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personalized Recommendations")
                .font(.headline)

            LazyVStack(spacing: 12) {
                ForEach(recommendations) { recommendation in
                    RecommendationCard(recommendation: recommendation)
                }
            }
        }
    }
}

// MARK: - Enhanced Recommendation Card

struct RecommendationCard: View {
    let recommendation: ProgressRecommendation
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: recommendation.priorityLevel.icon)
                    .font(.system(size: 18))
                    .foregroundColor(recommendation.priorityLevel.color)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(recommendation.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Spacer()

                        // Category Badge
                        Text(recommendation.categoryType.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(recommendation.priorityLevel.color.opacity(0.1))
                            .foregroundColor(recommendation.priorityLevel.color)
                            .cornerRadius(4)

                        // Priority Badge
                        Text(recommendation.priority.capitalized)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(recommendation.priorityLevel.color)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }

                    Text(recommendation.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Action Items (Expandable)
            if !recommendation.actionItems.isEmpty {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack {
                        Text(isExpanded ? "Hide Action Items" : "Show Action Items (\(recommendation.actionItems.count))")
                            .font(.caption)
                            .fontWeight(.medium)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())

                if isExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(recommendation.actionItems.enumerated()), id: \.offset) { index, actionItem in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)

                                Text(actionItem)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(recommendation.priorityLevel.color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            EnhancedProgressSection(progress: ProgressMetrics(
                comparison: "has_previous_data",
                improvements: [
                    ProgressImprovement(
                        metric: "accuracy",
                        change: 0.08,
                        message: "Excellent improvement in accuracy! Keep up the great work.",
                        significance: "major"
                    )
                ],
                concerns: [
                    ProgressConcern(
                        metric: "study_time",
                        change: -0.15,
                        message: "Study time has decreased. Try to maintain regular schedule.",
                        significance: "minor"
                    )
                ],
                overallTrend: "improving",
                progressScore: 0.72,
                detailedComparison: nil,
                recommendations: [
                    ProgressRecommendation(
                        category: "motivation",
                        priority: "low",
                        title: "Maintain Momentum",
                        description: "You're making excellent progress! Keep up the current approach.",
                        actionItems: [
                            "Continue current study methods",
                            "Gradually increase challenge level",
                            "Share progress with family or friends"
                        ]
                    )
                ],
                previousPeriod: PreviousPeriod(
                    startDate: Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date(),
                    endDate: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
                    duration: 7
                )
            ))
        }
        .padding()
    }
}