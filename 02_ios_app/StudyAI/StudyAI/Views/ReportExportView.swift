//
//  ReportExportView.swift
//  StudyAI
//
//  Advanced export and sharing functionality for parent reports
//

import SwiftUI
import PDFKit
import Charts

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

                    // Step 1: Generate PDF Button (if no PDF generated yet)
                    if exportedFileURL == nil {
                        GeneratePDFSection(
                            isExporting: exportService.isExporting,
                            exportProgress: exportService.exportProgress,
                            exportStatus: exportService.exportStatus,
                            onExport: handleExport
                        )
                    }

                    // Step 2: PDF Preview (only after PDF is generated)
                    if let fileURL = exportedFileURL {
                        PDFPreviewSection(
                            report: report,
                            fileURL: fileURL,
                            showPreview: true
                        )
                    }

                    // Step 3: Share Actions (only after PDF is generated)
                    if let fileURL = exportedFileURL {
                        ShareActionsSection(onShare: { showingShareSheet = true })
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

// MARK: - New Supporting Views

struct GeneratePDFSection: View {
    let isExporting: Bool
    let exportProgress: Double
    let exportStatus: String
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate PDF Report")
                .font(.headline)

            Text("Create a comprehensive PDF document with narrative insights and analytics.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Export Progress (if exporting)
            if isExporting {
                VStack(spacing: 12) {
                    ProgressView(value: exportProgress)
                        .frame(height: 8)
                        .tint(.blue)

                    HStack {
                        Text(exportStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(Int(exportProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            // Generate Button
            Button(action: onExport) {
                HStack {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "doc.badge.plus")
                    }
                    Text(isExporting ? "Generating PDF..." : "Generate PDF")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isExporting ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isExporting)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct PDFPreviewSection: View {
    let report: ParentReport
    let fileURL: URL
    let showPreview: Bool
    @State private var pdfDocument: PDFDocument?
    @State private var pdfImage: UIImage?
    @State private var isLoadingPDF = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)

                Text("PDF Generated Successfully")
                    .font(.headline)
                    .fontWeight(.medium)

                Spacer()
            }

            Text("PDF Preview")
                .font(.headline)

            // PDF Document Preview
            VStack(spacing: 12) {
                if isLoadingPDF {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading PDF preview...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                } else if let pdfImage = pdfImage {
                    // PDF thumbnail preview
                    VStack(spacing: 8) {
                        Image(uiImage: pdfImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 400)
                            .background(Color.white)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                        Text("First page preview")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                } else {
                    // Fallback state
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)

                        Text("PDF Ready")
                            .font(.headline)

                        Text("Unable to generate preview")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }

            // File info
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileURL.lastPathComponent)
                        .font(.caption)
                        .fontWeight(.medium)

                    Text("Ready to share")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // File size if available
                if let fileSize = getFileSize(url: fileURL) {
                    Text(fileSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onAppear {
            if showPreview {
                loadPDFPreview()
            }
        }
    }

    private func loadPDFPreview() {
        guard pdfDocument == nil && !isLoadingPDF else { return }

        isLoadingPDF = true

        Task {
            await MainActor.run {
                // Load PDF document from file URL
                if let document = PDFDocument(url: fileURL) {
                    self.pdfDocument = document

                    // Generate thumbnail from first page
                    if let firstPage = document.page(at: 0) {
                        let pageRect = firstPage.bounds(for: .mediaBox)
                        let renderer = UIGraphicsImageRenderer(size: pageRect.size)

                        let thumbnailImage = renderer.image { context in
                            UIColor.white.setFill()
                            context.fill(pageRect)

                            context.cgContext.translateBy(x: 0, y: pageRect.size.height)
                            context.cgContext.scaleBy(x: 1.0, y: -1.0)

                            firstPage.draw(with: .mediaBox, to: context.cgContext)
                        }

                        self.pdfImage = thumbnailImage
                    }
                }

                self.isLoadingPDF = false
            }
        }
    }

    private func getFileSize(url: URL) -> String? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[FileAttributeKey.size] as? NSNumber {
                let sizeInBytes = size.intValue
                if sizeInBytes < 1024 {
                    return "\(sizeInBytes) B"
                } else if sizeInBytes < 1024 * 1024 {
                    return "\(sizeInBytes / 1024) KB"
                } else {
                    return String(format: "%.1f MB", Double(sizeInBytes) / (1024 * 1024))
                }
            }
        } catch {
            print("Error getting file size: \(error)")
        }
        return nil
    }
}

struct ShareActionsSection: View {
    let onShare: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Button(action: onShare) {
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

// MARK: - Supporting Data Models - removed unused sharing structures

#Preview {
    ReportExportView(report: ParentReport.sampleReport)
}