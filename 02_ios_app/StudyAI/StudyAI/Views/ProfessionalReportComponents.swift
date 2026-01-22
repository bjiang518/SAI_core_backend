//
//  ProfessionalReportComponents.swift
//  StudyAI
//
//  Professional report UI components without emojis
//  Includes Executive Summary card, metrics cards, and charts
//

import SwiftUI
import Charts

// MARK: - Executive Summary Card (Primary Report)

struct ExecutiveSummaryCard: View {
    let batch: PassiveReportBatch

    var body: some View {
        VStack(spacing: 0) {
            // Header with grade and trend
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LEARNING PROGRESS")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    if let grade = batch.overallGrade {
                        HStack(alignment: .center, spacing: 12) {
                            Text(grade)
                                .font(.system(size: 44, weight: .bold))
                                .foregroundColor(gradeColor(grade))

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Overall Grade")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let trend = batch.accuracyTrend {
                                    trendBadge(trend)
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Mental Health Indicator (right side)
                if let score = batch.mentalHealthScore {
                    mentalHealthIndicator(score)
                }
            }
            .padding(16)

            Divider()

            // Key Metrics Grid
            VStack(spacing: 12) {
                metricsRow(
                    left: ("Accuracy", batch.overallAccuracy.map { "\(Int($0 * 100))%" } ?? "-", .blue),
                    right: ("Questions", batch.questionCount.map { "\($0)" } ?? "-", .green)
                )

                metricsRow(
                    left: ("Study Time", batch.studyTimeMinutes.map { "\($0)m" } ?? "-", .orange),
                    right: ("Streak", batch.currentStreak.map { "\($0)d" } ?? "-", .red)
                )

                if let engagement = batch.engagementLevel, let confidence = batch.confidenceLevel {
                    metricsRow(
                        left: ("Engagement", String(format: "%.1f", engagement), .purple),
                        right: ("Confidence", String(format: "%.1f", confidence), .cyan)
                    )
                }
            }
            .padding(16)

            // Summary text
            if let summary = batch.oneLineSummary {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    Text(summary)
                        .font(.subheadline)
                        .lineLimit(3)
                        .foregroundColor(.secondary)
                        .padding(16)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func metricsRow(
        left: (String, String, Color),
        right: (String, String, Color)
    ) -> some View {
        HStack(spacing: 16) {
            metricBox(label: left.0, value: left.1, color: left.2)
            metricBox(label: right.0, value: right.1, color: right.2)
        }
    }

    private func metricBox(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(color).opacity(0.1))
        .cornerRadius(8)
    }

    private func trendBadge(_ trend: String) -> some View {
        HStack(spacing: 4) {
            switch trend.lowercased() {
            case "improving":
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text("Improving")
                    .font(.caption2)
                    .foregroundColor(.green)
            case "stable":
                Image(systemName: "minus")
                    .font(.caption2)
                    .foregroundColor(.blue)
                Text("Stable")
                    .font(.caption2)
                    .foregroundColor(.blue)
            case "declining":
                Image(systemName: "arrow.down.right")
                    .font(.caption2)
                    .foregroundColor(.red)
                Text("Declining")
                    .font(.caption2)
                    .foregroundColor(.red)
            default:
                Text(trend)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(4)
    }

    private func mentalHealthIndicator(_ score: Double) -> some View {
        VStack(alignment: .center, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: min(score, 1.0))
                    .stroke(mentalHealthColor(score), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text(String(format: "%.0f", score * 100))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(mentalHealthColor(score))
                    Text("Mental")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Text(mentalHealthLabel(score))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(mentalHealthColor(score))
                .multilineTextAlignment(.center)
        }
    }

    private func mentalHealthColor(_ score: Double) -> Color {
        switch score {
        case 0.75...1.0: return .green
        case 0.5..<0.75: return .blue
        case 0.25..<0.5: return .orange
        default: return .red
        }
    }

    private func mentalHealthLabel(_ score: Double) -> String {
        switch score {
        case 0.75...1.0: return "Excellent"
        case 0.5..<0.75: return "Good"
        case 0.25..<0.5: return "Fair"
        default: return "Low"
        }
    }

    private func gradeColor(_ grade: String) -> Color {
        let firstChar = grade.first?.uppercased() ?? "C"
        switch firstChar {
        case "A": return .green
        case "B": return .blue
        case "C": return .orange
        default: return .red
        }
    }
}

// MARK: - Professional Report Card (Other Reports)

struct ProfessionalReportCard: View {
    let report: PassiveReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and title
            HStack(spacing: 12) {
                Image(systemName: report.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(report.color)
                    .frame(width: 36, height: 36)
                    .background(report.color.opacity(0.1))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(report.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let wordCount = report.wordCount {
                        Text("\(wordCount) words")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Narrative preview (clean, no formatting)
            Text(narrativePreview)
                .font(.caption)
                .lineLimit(3)
                .foregroundColor(.secondary)

            // No emoji indicators - just clean separator
            Divider()
                .opacity(0.5)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var narrativePreview: String {
        // Remove markdown formatting for preview
        let cleaned = report.narrativeContent
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count > 150 {
            return String(cleaned.prefix(150)) + "..."
        }
        return cleaned
    }
}

// MARK: - Chart Components

struct AccuracyTrendChart: View {
    let title: String
    let data: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(Int(data.last ?? 0 * 100))%")
                    .font(.headline)
                    .foregroundColor(trendColor(data))
            }

            if #available(iOS 16.0, *) {
                Chart {
                    ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                        LineMark(
                            x: .value("Day", index),
                            y: .value("Accuracy", value * 100)
                        )
                        .foregroundStyle(trendColor(data))

                        AreaMark(
                            x: .value("Day", index),
                            y: .value("Accuracy", value * 100)
                        )
                        .foregroundStyle(trendColor(data).opacity(0.1))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100])
                }
                .chartYScale(domain: 0...100)
                .frame(height: 200)
            } else {
                // Fallback for older iOS
                barChartFallback(data)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func barChartFallback(_ data: [Double]) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(data, id: \.self) { value in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(trendColor(data))
                        .frame(height: CGFloat(value * 150))

                    Text("\(Int(value * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(height: 180)
        .padding(.vertical, 8)
    }

    private func trendColor(_ data: [Double]) -> Color {
        guard let first = data.first, let last = data.last else { return .blue }
        let trend = last - first
        if trend > 0.05 {
            return .green
        } else if trend < -0.05 {
            return .red
        }
        return .blue
    }
}

struct SubjectBreakdownChart: View {
    let title: String
    let subjects: [(String, Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(subjects, id: \.0) { subject, accuracy in
                    subjectRow(subject: subject, accuracy: accuracy)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func subjectRow(subject: String, accuracy: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(subject)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(accuracy * 100))%")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(accuracyColor(accuracy))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.1))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(accuracyColor(accuracy))
                        .frame(width: geometry.size.width * accuracy)
                }
            }
            .frame(height: 8)
        }
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        switch accuracy {
        case 0.85...1.0: return .green
        case 0.75..<0.85: return .blue
        case 0.65..<0.75: return .orange
        default: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    let sampleBatch = PassiveReportBatch(
        id: "test-id",
        period: "weekly",
        startDate: Date().addingTimeInterval(-7 * 24 * 60 * 60),
        endDate: Date(),
        generatedAt: Date(),
        status: "completed",
        generationTimeMs: 5000,
        overallGrade: "B+",
        overallAccuracy: 0.82,
        questionCount: 91,
        studyTimeMinutes: 182,
        currentStreak: 6,
        accuracyTrend: "improving",
        activityTrend: "increasing",
        oneLineSummary: "Strong performance with consistent engagement patterns",
        reportCount: 8,
        mentalHealthScore: 0.77,
        engagementLevel: 0.82,
        confidenceLevel: 0.769
    )

    ScrollView {
        VStack(spacing: 16) {
            ExecutiveSummaryCard(batch: sampleBatch)
                .padding()

            let sampleReport = PassiveReport(
                id: "test",
                reportType: "academic_performance",
                narrativeContent: "Academic Performance Analysis\n\nThis week shows strong performance across mathematics and science.",
                keyInsights: nil,
                recommendations: nil,
                visualData: nil,
                wordCount: 250,
                generationTimeMs: 2000,
                aiModelUsed: "GPT-4",
                generatedAt: Date()
            )

            ProfessionalReportCard(report: sampleReport)
                .padding()

            AccuracyTrendChart(
                title: "Accuracy Trend",
                data: [0.70, 0.72, 0.75, 0.78, 0.80, 0.82, 0.81]
            )
            .padding()
        }
    }
}
