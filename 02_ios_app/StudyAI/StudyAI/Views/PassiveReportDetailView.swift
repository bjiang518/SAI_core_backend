//
//  PassiveReportDetailView.swift
//  StudyAI
//
//  Detailed view of all 8 reports within a batch
//  Shows full narratives with Markdown rendering
//

import SwiftUI

struct PassiveReportDetailView: View {
    let batch: PassiveReportBatch

    @StateObject private var viewModel = PassiveReportsViewModel()
    @State private var selectedReport: PassiveReport?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Batch summary header
                batchSummaryHeader

                // Loading state
                if viewModel.isLoadingDetails {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding(.top, 40)
                }

                // Report cards
                if !viewModel.detailedReports.isEmpty {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.detailedReports) { report in
                            ReportCard(report: report)
                                .onTapGesture {
                                    selectedReport = report
                                }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(periodTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadBatchDetails(batchId: batch.id)
        }
        .sheet(item: $selectedReport) { report in
            ReportDetailSheet(report: report)
        }
    }

    // MARK: - Subviews

    private var batchSummaryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date range
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.blue)
                Text(dateRangeText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Overall grade
            if let grade = batch.overallGrade {
                HStack(spacing: 8) {
                    Text("Overall Grade:")
                        .font(.headline)
                    Text(grade)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(gradeColor(grade))
                }
            }

            // Quick metrics
            HStack(spacing: 20) {
                if let accuracy = batch.overallAccuracy {
                    quickMetric(title: "Accuracy", value: "\(Int(accuracy * 100))%", color: .blue)
                }

                if let questions = batch.questionCount {
                    quickMetric(title: "Questions", value: "\(questions)", color: .green)
                }

                if let time = batch.studyTimeMinutes {
                    quickMetric(title: "Time", value: "\(time)m", color: .orange)
                }
            }

            // Summary text
            if let summary = batch.oneLineSummary {
                Text(summary)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

            Divider()
                .padding(.top, 8)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    private func quickMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
        }
    }

    // MARK: - Helpers

    private var periodTitle: String {
        "\(batch.period.capitalized) Report"
    }

    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        let start = formatter.string(from: batch.startDate)
        let end = formatter.string(from: batch.endDate)
        return "\(start) - \(end)"
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

// MARK: - Report Card Component

struct ReportCard: View {
    let report: PassiveReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and title
            HStack {
                Image(systemName: report.icon)
                    .font(.title2)
                    .foregroundColor(report.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(report.displayName)
                        .font(.headline)
                    if let wordCount = report.wordCount {
                        Text("\(wordCount) words")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }

            // Preview of narrative content (first 200 characters)
            Text(narrativePreview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(3)

            // Insights count (if available)
            if let insights = report.keyInsights {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                    Text("\(insights.count) key insights")
                        .font(.caption)
                }
                .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var narrativePreview: String {
        // Remove markdown formatting for preview
        let cleaned = report.narrativeContent
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.count > 200 {
            return String(cleaned.prefix(200)) + "..."
        }
        return cleaned
    }
}

// MARK: - Report Detail Sheet (Full Content)

struct ReportDetailSheet: View {
    let report: PassiveReport
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Report header
                    HStack(spacing: 12) {
                        Image(systemName: report.icon)
                            .font(.largeTitle)
                            .foregroundColor(report.color)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.displayName)
                                .font(.title2)
                                .fontWeight(.bold)

                            if let wordCount = report.wordCount {
                                Text("\(wordCount) words")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    Divider()

                    // Full narrative content with markdown rendering
                    MarkdownView(markdown: report.narrativeContent)
                        .padding(.horizontal)

                    // Key Insights section
                    if let insights = report.keyInsights, !insights.isEmpty {
                        insightsSection(insights: insights)
                    }

                    // Recommendations section
                    if let recommendations = report.recommendations, !recommendations.isEmpty {
                        recommendationsSection(recommendations: recommendations)
                    }

                    // Generation metadata
                    generationMetadata
                }
                .padding(.bottom, 24)
            }
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

    // MARK: - Sections

    private func insightsSection(insights: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.orange)
                Text("Key Insights")
                    .font(.headline)
            }
            .padding(.horizontal)

            ForEach(Array(insights.enumerated()), id: \.offset) { index, insight in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1).")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(insight)
                        .font(.subheadline)
                }
                .padding(.horizontal)
            }
        }
    }

    private func recommendationsSection(recommendations: [ReportRecommendation]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Recommendations")
                    .font(.headline)
            }
            .padding(.horizontal)

            ForEach(recommendations, id: \.title) { recommendation in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        priorityBadge(recommendation.priority)
                        Text(recommendation.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Text(recommendation.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
                .padding(.horizontal)
            }
        }
    }

    private var generationMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Report Details")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            VStack(spacing: 4) {
                if let aiModel = report.aiModelUsed {
                    metadataRow(label: "AI Model", value: aiModel)
                }

                if let generationTime = report.generationTimeMs {
                    metadataRow(label: "Generation Time", value: "\(generationTime)ms")
                }

                Group {
                    let formatter = DateFormatter()
                    let _ = formatter.dateStyle = .medium
                    let _ = formatter.timeStyle = .short
                    let dateStr = formatter.string(from: report.generatedAt)
                    metadataRow(label: "Generated", value: dateStr)
                }
            }
            .padding()
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }

    private func priorityBadge(_ priority: String) -> some View {
        Text(priority.uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(priorityColor(priority))
            .cornerRadius(4)
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "high": return .red
        case "medium": return .orange
        case "low": return .blue
        default: return .gray
        }
    }
}

// MARK: - Markdown Rendering

/// Simple Markdown renderer using AttributedString (iOS 15+)
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        if let attributedString = try? AttributedString(markdown: markdown) {
            Text(attributedString)
                .font(.body)
        } else {
            Text(markdown)
                .font(.body)
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
        overallGrade: "A-",
        overallAccuracy: 0.87,
        questionCount: 42,
        studyTimeMinutes: 120,
        currentStreak: 5,
        accuracyTrend: "improving",
        activityTrend: "increasing",
        oneLineSummary: "Strong performance with consistent effort",
        reportCount: 8
    )

    PassiveReportDetailView(batch: sampleBatch)
}
