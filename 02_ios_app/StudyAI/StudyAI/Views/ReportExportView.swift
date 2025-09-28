//
//  ReportExportView.swift
//  StudyAI
//
//  Advanced export and sharing functionality for parent reports
//

import SwiftUI

struct ReportExportView: View {
    let report: ParentReport
    @StateObject private var exportService = ReportExportService()
    @Environment(\.dismiss) private var dismiss

    @State private var showingShareSheet = false
    @State private var selectedExportFormat: ExportFormat = .pdf
    @State private var exportedFileURL: URL?

    enum ExportFormat: String, CaseIterable {
        case pdf = "pdf"

        var displayName: String {
            switch self {
            case .pdf: return "PDF Document"
            }
        }

        var icon: String {
            switch self {
            case .pdf: return "doc.fill"
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    ReportHeaderCard(report: report)

                    // PDF Preview
                    PDFPreviewSection(
                        report: report,
                        isExporting: exportService.isExporting,
                        onExport: handleExport
                    )

                    // Success Actions
                    if let fileURL = exportedFileURL {
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)

                                Text("PDF Generated Successfully")
                                    .font(.headline)
                                    .fontWeight(.medium)

                                Spacer()
                            }

                            Button(action: { showingShareSheet = true }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Share File")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Export & Share")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let fileURL = exportedFileURL {
                ActivityViewController(activityItems: [fileURL])
            }
        }
        .alert("Export Error", isPresented: .constant(exportService.errorMessage != nil)) {
            Button("OK") {
                exportService.clearError()
            }
        } message: {
            Text(exportService.errorMessage ?? "")
        }
    }

    private func handleExport() {
        Task {
            do {
                let fileURL = try await exportService.exportReport(
                    reportId: report.id,
                    format: selectedExportFormat
                )
                await MainActor.run {
                    exportedFileURL = fileURL
                }
            } catch {
                await MainActor.run {
                    exportService.setError(error.localizedDescription)
                }
            }
        }
    }

    private func handleDirectShare() {
        handleExport()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if exportedFileURL != nil {
                showingShareSheet = true
            }
        }
    }
}

// MARK: - Supporting Views

struct ReportHeaderCard: View {
    let report: ParentReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.reportTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(formatDate(report.startDate)) - \(formatDate(report.endDate))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Label(report.reportType.rawValue.capitalized, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundColor(.blue)

                    Text("Generated \(formatDate(report.generatedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct PDFPreviewSection: View {
    let report: ParentReport
    let isExporting: Bool
    let onExport: () -> Void
    @StateObject private var reportService = ParentReportService.shared
    @State private var narrativeContent: NarrativeReport?
    @State private var isLoadingPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PDF Preview")
                .font(.headline)

            // PDF Preview with actual content
            VStack(spacing: 12) {
                // Preview content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Report Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text(report.reportTitle)
                                .font(.title3)
                                .fontWeight(.bold)

                            Text("Period: \(report.dateRange)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("Generated: \(formatDate(report.generatedAt))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                        // Content Preview
                        if isLoadingPreview {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading preview...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else if let narrative = narrativeContent {
                            // Show narrative preview
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Summary")
                                    .font(.headline)
                                    .foregroundColor(.blue)

                                Text(narrative.summary)
                                    .font(.body)
                                    .lineLimit(3)

                                if !narrative.keyInsights.isEmpty {
                                    Text("Key Insights")
                                        .font(.headline)
                                        .foregroundColor(.orange)

                                    ForEach(Array(narrative.keyInsights.prefix(2).enumerated()), id: \.offset) { index, insight in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("•")
                                                .foregroundColor(.orange)
                                            Text(insight)
                                                .font(.body)
                                                .lineLimit(2)
                                        }
                                    }

                                    if narrative.keyInsights.count > 2 {
                                        Text("... and \(narrative.keyInsights.count - 2) more insights")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
                                    }
                                }

                                if !narrative.recommendations.isEmpty {
                                    Text("Recommendations")
                                        .font(.headline)
                                        .foregroundColor(.green)

                                    ForEach(Array(narrative.recommendations.prefix(2).enumerated()), id: \.offset) { index, recommendation in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("•")
                                                .foregroundColor(.green)
                                            Text(recommendation)
                                                .font(.body)
                                                .lineLimit(2)
                                        }
                                    }

                                    if narrative.recommendations.count > 2 {
                                        Text("... and \(narrative.recommendations.count - 2) more recommendations")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .italic()
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
                        } else {
                            // Fallback to basic analytics preview
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Academic Performance")
                                    .font(.headline)
                                    .foregroundColor(.blue)

                                if let academic = report.reportData.academic {
                                    HStack {
                                        Text("Overall Accuracy:")
                                        Spacer()
                                        Text(academic.accuracyPercentage)
                                            .fontWeight(.medium)
                                    }

                                    HStack {
                                        Text("Questions Answered:")
                                        Spacer()
                                        Text("\(academic.totalQuestions)")
                                            .fontWeight(.medium)
                                    }

                                    HStack {
                                        Text("Study Time:")
                                        Spacer()
                                        Text("\(academic.timeSpentMinutes) minutes")
                                            .fontWeight(.medium)
                                    }
                                }

                                Text("...and more detailed analytics")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
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
                    .padding()
                }
                .frame(height: 250)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Export button
                Button(action: onExport) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(isExporting ? "Generating PDF..." : "Generate & Export PDF")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isExporting)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onAppear {
            loadPreviewContent()
        }
    }

    private func loadPreviewContent() {
        guard narrativeContent == nil && !isLoadingPreview else { return }

        isLoadingPreview = true

        Task {
            let result = await reportService.fetchNarrative(reportId: report.id)

            await MainActor.run {
                isLoadingPreview = false

                switch result {
                case .success(let narrative):
                    narrativeContent = narrative
                case .failure(_):
                    // If narrative fetch fails, we'll show the analytics fallback
                    narrativeContent = nil
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Data Models - removed unused sharing structures

#Preview {
    ReportExportView(report: ParentReport.sampleReport)
}