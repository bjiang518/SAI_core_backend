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
    @State private var executiveSummaryHeight: CGFloat = 200

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

                                HTMLView(htmlContent: executiveSummary.narrativeContent, contentHeight: $executiveSummaryHeight)
                                    .frame(height: max(executiveSummaryHeight, 200))
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
            await viewModel.loadBatchDetails(batchId: batch.id)
        }
        .fullScreenCover(item: $selectedReport) { report in
            ReportDetailSheet(report: report)
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
    @State private var htmlContentHeight: CGFloat = 600

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Full narrative content with HTML rendering - dynamic height
                        HTMLView(htmlContent: report.narrativeContent, contentHeight: $htmlContentHeight)
                            .frame(height: max(htmlContentHeight, 400))

                        // Key Insights section
                        if let insights = report.keyInsights, !insights.isEmpty {
                            insightsSection(insights: insights)
                        }

                        // Recommendations section
                        if let recommendations = report.recommendations, !recommendations.isEmpty {
                            recommendationsSection(recommendations: recommendations)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
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
    @Binding var contentHeight: CGFloat

    init(htmlContent: String, contentHeight: Binding<CGFloat> = .constant(0)) {
        self.htmlContent = htmlContent
        self._contentHeight = contentHeight
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false // Disable internal scrolling
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear

        // Add message handler ONCE in makeUIView
        config.userContentController.add(context.coordinator, name: "heightChanged")

        // Store reference
        context.coordinator.webView = webView

        // Load HTML with proper viewport settings for mobile
        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
                    background-color: transparent;
                    width: 100%;
                    overflow-x: hidden;
                }
                * {
                    box-sizing: border-box;
                    max-width: 100%;
                }
                /* Override any container max-widths from backend HTML */
                .container, div[style*="max-width"] {
                    max-width: 100% !important;
                    width: 100% !important;
                    margin-left: 0 !important;
                    margin-right: 0 !important;
                }
                /* Ensure all content scales properly */
                img, table, pre, code {
                    max-width: 100%;
                    width: auto;
                    height: auto;
                }
            </style>
        </head>
        <body>
            \(htmlContent)
            <script>
                // Send content height to Swift
                function updateHeight() {
                    const height = document.body.scrollHeight;
                    window.webkit.messageHandlers.heightChanged.postMessage(height);
                }

                // Update height when content loads and when images load
                window.addEventListener('load', updateHeight);
                document.addEventListener('DOMContentLoaded', updateHeight);

                // Observe image loading
                const images = document.querySelectorAll('img');
                images.forEach(img => {
                    img.addEventListener('load', updateHeight);
                });

                // Initial update
                setTimeout(updateHeight, 100);
                setTimeout(updateHeight, 500);
                setTimeout(updateHeight, 1000);
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(htmlString, baseURL: nil)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if content actually changed
        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
                    background-color: transparent;
                    width: 100%;
                    overflow-x: hidden;
                }
                * {
                    box-sizing: border-box;
                    max-width: 100%;
                }
                /* Override any container max-widths from backend HTML */
                .container, div[style*="max-width"] {
                    max-width: 100% !important;
                    width: 100% !important;
                    margin-left: 0 !important;
                    margin-right: 0 !important;
                }
                /* Ensure all content scales properly */
                img, table, pre, code {
                    max-width: 100%;
                    width: auto;
                    height: auto;
                }
            </style>
        </head>
        <body>
            \(htmlContent)
            <script>
                // Send content height to Swift
                function updateHeight() {
                    const height = document.body.scrollHeight;
                    window.webkit.messageHandlers.heightChanged.postMessage(height);
                }

                // Update height when content loads and when images load
                window.addEventListener('load', updateHeight);
                document.addEventListener('DOMContentLoaded', updateHeight);

                // Observe image loading
                const images = document.querySelectorAll('img');
                images.forEach(img => {
                    img.addEventListener('load', updateHeight);
                });

                // Initial update
                setTimeout(updateHeight, 100);
                setTimeout(updateHeight, 500);
                setTimeout(updateHeight, 1000);
            </script>
        </body>
        </html>
        """

        webView.loadHTMLString(htmlString, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(contentHeight: $contentHeight)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var contentHeight: Binding<CGFloat>
        weak var webView: WKWebView?

        init(contentHeight: Binding<CGFloat>) {
            self.contentHeight = contentHeight
            super.init()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Message handler is already registered in makeUIView - just measure height
            webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, error in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async {
                        self?.contentHeight.wrappedValue = height
                        print("🌐 [WKWebView] Content height updated: \(height)")
                    }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "heightChanged", let height = message.body as? CGFloat {
                DispatchQueue.main.async {
                    self.contentHeight.wrappedValue = height
                    print("🌐 [WKWebView] Content height from JS: \(height)")
                }
            }
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
        HStack(spacing: 12) {
            // Small icon
            Image(systemName: report.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(report.color)
                .frame(width: 32, height: 32)
                .background(report.color.opacity(0.1))
                .cornerRadius(8)

            // Report name only
            Text(report.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Spacer()

            // Chevron indicator
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

