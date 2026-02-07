//
//  PassiveReportDetailView.swift
//  StudyAI
//
//  Detailed view of all 8 reports within a batch
//  Shows full narratives with Markdown rendering
//

import SwiftUI
import Charts
import WebKit

struct PassiveReportDetailView: View {
    let batch: PassiveReportBatch

    @StateObject private var viewModel = PassiveReportsViewModel()
    @State private var selectedReport: PassiveReport?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Loading state
                if viewModel.isLoadingDetails {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding(.top, 40)
                } else {
                    // Executive Summary (Primary - shown first)
                    if let executiveSummary = viewModel.detailedReports.first(where: { $0.reportType == "executive_summary" }) {
                        VStack(spacing: 16) {
                            ExecutiveSummaryCard(batch: batch)

                            // Executive Summary Narrative
                            VStack(alignment: .leading, spacing: 12) {
                                Text("PROFESSIONAL ASSESSMENT")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)

                                HTMLView(htmlContent: executiveSummary.narrativeContent)
                                    .frame(minHeight: 200)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)

                            Divider()
                                .padding(.vertical, 8)
                        }
                    }

                    // Other Report Cards (Secondary)
                    if viewModel.detailedReports.count > 1 {
                        VStack(spacing: 8) {
                            Text("DETAILED REPORTS")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(viewModel.detailedReports.filter { $0.reportType != "executive_summary" }) { report in
                                ProfessionalReportCard(report: report)
                                    .onTapGesture {
                                        selectedReport = report
                                    }
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
            print("📖 [PassiveReportDetail] Opening batch details")
            print("   Batch ID: \(batch.id)")
            print("   Period: \(batch.period)")
            print("   Date Range: \(batch.startDate) to \(batch.endDate)")
            print("   Expected Report Count: \(batch.reportCount ?? 0)")

            await viewModel.loadBatchDetails(batchId: batch.id)

            print("📖 [PassiveReportDetail] Batch details loaded")
            print("   Actual Reports Loaded: \(viewModel.detailedReports.count)")
        }
        .fullScreenCover(item: $selectedReport) { report in
            ReportDetailSheet(report: report)
                .onAppear {
                    print("📄 [PassiveReportDetail] Opening individual report")
                    print("   Report Type: \(report.reportType)")
                    print("   Display Name: \(report.displayName)")
                    print("   Word Count: \(report.wordCount ?? 0)")
                }
        }
    }

    // MARK: - Helpers

    private var periodTitle: String {
        "\(batch.period.capitalized) Report"
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

                    // Full narrative content with HTML rendering
                    HTMLView(htmlContent: report.narrativeContent)
                        .frame(minHeight: 400)
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
            .onAppear {
                print("\n========================================")
                print("📄 [ReportDetailSheet] DISPLAYING FULL REPORT")
                print("========================================")
                print("Report Type: \(report.reportType)")
                print("Display Name: \(report.displayName)")
                print("Generated At: \(report.generatedAt)")
                print("AI Model: \(report.aiModelUsed ?? "N/A")")
                print("\n--- NARRATIVE CONTENT (FULL) ---")
                print(report.narrativeContent)
                print("--- END NARRATIVE CONTENT ---\n")

                if let insights = report.keyInsights, !insights.isEmpty {
                    print("--- KEY INSIGHTS ---")
                    for (index, insight) in insights.enumerated() {
                        print("\(index + 1). \(insight)")
                    }
                    print("--- END KEY INSIGHTS ---\n")
                }

                if let recommendations = report.recommendations, !recommendations.isEmpty {
                    print("--- RECOMMENDATIONS ---")
                    for rec in recommendations {
                        print("[\(rec.priority)] \(rec.title)")
                        print("   \(rec.description)")
                    }
                    print("--- END RECOMMENDATIONS ---\n")
                }
                print("========================================\n")
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

// MARK: - HTML Rendering

/// WebView renderer for HTML content (reports from backend)
struct HTMLView: UIViewRepresentable {
    let htmlContent: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator

        // Load HTML with proper viewport settings for mobile
        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 16px;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
                    background-color: #f5f5f5;
                }
                * {
                    box-sizing: border-box;
                }
            </style>
        </head>
        <body>
            \(htmlContent)
        </body>
        </html>
        """

        webView.loadHTMLString(htmlString, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Update HTML content when it changes
        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 16px;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
                    background-color: #f5f5f5;
                }
                * {
                    box-sizing: border-box;
                }
            </style>
        </head>
        <body>
            \(htmlContent)
        </body>
        </html>
        """

        webView.loadHTMLString(htmlString, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        // Handle any web view navigation if needed
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
        reportCount: 8,
        mentalHealthScore: 0.82,
        engagementLevel: 0.85,
        confidenceLevel: 0.87
    )

    PassiveReportDetailView(batch: sampleBatch)
}

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
                // Icon with colored background
                ZStack {
                    Circle()
                        .fill(report.color.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: report.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(report.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Report title
                    Text(report.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    // Metadata row
                    HStack(spacing: 8) {
                        if let wordCount = report.wordCount {
                            Label("\(wordCount) words", systemImage: "doc.text")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if let generationTime = report.generationTimeMs {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(generationTime)ms")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Chevron indicator
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }

            // Content preview with better formatting
            Text(narrativePreview)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundColor(.secondary)
                .lineSpacing(4)

            // Show insight count if available
            if let insights = report.keyInsights, !insights.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("\(insights.count) key insight\(insights.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Show recommendation count
                    if let recs = report.recommendations, !recs.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text("\(recs.count) recommendation\(recs.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(report.color.opacity(0.2), lineWidth: 1)
        )
    }

    private var narrativePreview: String {
        // Extract text from HTML content
        let cleaned = stripHTMLTags(from: report.narrativeContent)
            .replacingOccurrences(of: "\n\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Get first 150 characters of actual text content
        if cleaned.count > 150 {
            return String(cleaned.prefix(150)) + "..."
        }
        return cleaned.isEmpty ? "Tap to view full report" : cleaned
    }

    /// Strip HTML tags and extract plain text content
    private func stripHTMLTags(from html: String) -> String {
        // Remove <!DOCTYPE>, <html>, <head>, <style>, <script> sections
        var text = html

        // Remove everything in <head>...</head>
        if let headRange = text.range(of: "<head[^>]*>.*?</head>", options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(headRange)
        }

        // Remove <style>...</style> blocks
        while let styleRange = text.range(of: "<style[^>]*>.*?</style>", options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(styleRange)
        }

        // Remove <script>...</script> blocks
        while let scriptRange = text.range(of: "<script[^>]*>.*?</script>", options: [.regularExpression, .caseInsensitive]) {
            text.removeSubrange(scriptRange)
        }

        // Replace common block-level tags with spaces/newlines
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</h1>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</h2>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</h3>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)

        // Remove all remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        // Clean up excessive whitespace
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n\\s*\\n\\s*\\n+", with: "\n\n", options: .regularExpression)

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
