//
//  ReportExportService.swift
//  StudyAI
//
//  Service for handling report export and sharing functionality
//

import Foundation
import SwiftUI
import Combine
import PDFKit
import Charts

@MainActor
class ReportExportService: ObservableObject {
    @Published var isExporting = false
    @Published var isProcessing = false
    @Published var exportStatus = ""
    @Published var exportProgress: Double = 0.0
    @Published var errorMessage: String?

    private let networkService = NetworkService.shared

    // MARK: - Export Functions

    func exportReport(reportId: String, format: ReportExportView.ExportFormat) async throws -> URL {
        isExporting = true
        exportStatus = "Preparing export..."
        exportProgress = 0.1
        clearError()

        defer {
            isExporting = false
            exportProgress = 0.0
            exportStatus = ""
        }

        do {
            exportStatus = "Fetching report data..."
            exportProgress = 0.2

            // Fetch narrative content
            let narrativeResult = await ParentReportService.shared.fetchNarrative(reportId: reportId)
            let narrative: NarrativeReport?

            switch narrativeResult {
            case .success(let narrativeContent):
                narrative = narrativeContent
            case .failure(let error):
                print("⚠️ Narrative fetch failed: \(error.localizedDescription)")
                setError("Unable to load report content. Please try again.")
                throw ReportExportError.networkError("Failed to fetch narrative content")
            }

            exportStatus = "Generating PDF..."
            exportProgress = 0.5

            // Generate PDF locally with narrative content
            let fileURL = try await generateLocalPDF(reportId: reportId, narrative: narrative)

            exportProgress = 1.0
            exportStatus = "PDF generated successfully!"

            return fileURL

        } catch let error as ReportExportError {
            let userMessage = getUserFriendlyErrorMessage(for: error)
            setError(userMessage)
            print("❌ Export failed: \(error.localizedDescription)")
            throw error
        } catch {
            let userMessage = "An unexpected error occurred while exporting the report. Please try again."
            setError(userMessage)
            print("❌ Unexpected export error: \(error.localizedDescription)")
            throw ReportExportError.fileSystemError(userMessage)
        }
    }

    private func generateLocalPDF(reportId: String, narrative: NarrativeReport?) async throws -> URL {
        // Generate PDF page on main thread (UI components required), but file operations on background
        let pdfPage = try await createPDFPage(reportId: reportId, narrative: narrative)

        // Move file operations to background thread
        return try await Task.detached {
            // Create PDF document
            let pdfDocument = PDFDocument()
            pdfDocument.insert(pdfPage, at: 0)

            // Save to temporary file
            let fileName = "report_\(reportId)_enhanced.pdf"
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileURL = tempDirectory.appendingPathComponent(fileName)

            guard pdfDocument.write(to: fileURL) else {
                throw ReportExportError.fileSystemError("Failed to write PDF file")
            }

            return fileURL
        }.value
    }

    private func createPDFPage(reportId: String, narrative: NarrativeReport?) async throws -> PDFPage {
        // Create a PDF page with custom content
        let pageSize = CGSize(width: 612, height: 792) // Standard US Letter size

        let renderer = UIGraphicsImageRenderer(size: pageSize)
        let pdfImage = renderer.image { context in
            let cgContext = context.cgContext

            // White background
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: pageSize))

            // Draw content
            drawPDFContent(context: cgContext, pageSize: pageSize, reportId: reportId, narrative: narrative)
        }

        // Convert UIImage to PDFPage
        guard let pdfPage = PDFPage(image: pdfImage) else {
            throw ReportExportError.fileSystemError("Failed to create PDF page")
        }

        return pdfPage
    }

    private func drawPDFContent(context: CGContext, pageSize: CGSize, reportId: String, narrative: NarrativeReport?) {
        // Save graphics state
        context.saveGState()

        let margin: CGFloat = 40
        let contentWidth = pageSize.width - (margin * 2)
        let currentY = margin

        var yPosition = currentY

        // Title
        yPosition += drawTitle(context: context, rect: CGRect(x: margin, y: yPosition, width: contentWidth, height: 50))
        yPosition += 30

        // Narrative Section (use full remaining space)
        let remainingHeight = pageSize.height - yPosition - margin
        drawNarrativeSection(context: context, rect: CGRect(x: margin, y: yPosition, width: contentWidth, height: remainingHeight), narrative: narrative)

        context.restoreGState()
    }

    private func drawTitle(context: CGContext, rect: CGRect) -> CGFloat {
        let title = "Study Progress Report"
        let subtitle = Date().formatted(date: .abbreviated, time: .omitted)

        // Main title
        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]

        let titleString = NSAttributedString(string: title, attributes: titleAttributes)
        let titleSize = titleString.size()
        titleString.draw(at: CGPoint(x: rect.minX, y: rect.minY))

        // Subtitle
        let subtitleFont = UIFont.systemFont(ofSize: 12)
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: UIColor.gray
        ]

        let subtitleString = NSAttributedString(string: subtitle, attributes: subtitleAttributes)
        subtitleString.draw(at: CGPoint(x: rect.minX, y: rect.minY + titleSize.height + 3))

        return titleSize.height + 15
    }


    private func drawNarrativeSection(context: CGContext, rect: CGRect, narrative: NarrativeReport?) {
        guard let narrative = narrative else {
            // Draw placeholder text if no narrative
            let placeholderFont = UIFont.systemFont(ofSize: 14)
            let placeholderText = "Narrative content is not available for this report."
            let placeholderString = NSAttributedString(string: placeholderText, attributes: [.font: placeholderFont, .foregroundColor: UIColor.gray])
            placeholderString.draw(in: rect)
            return
        }

        var yPosition = rect.minY

        // Key Insights Section
        if !narrative.keyInsights.isEmpty {
            let insightsText = narrative.keyInsights.enumerated().map { index, insight in
                "• \(insight)"
            }.joined(separator: "\n\n")

            yPosition += drawNarrativeBlock(
                context: context,
                title: "Key Insights",
                content: insightsText,
                rect: CGRect(x: rect.minX, y: yPosition, width: rect.width, height: rect.height - (yPosition - rect.minY)),
                fontSize: 9
            )
            yPosition += 10
        }

        // Recommendations Section
        if !narrative.recommendations.isEmpty {
            let recommendationsText = narrative.recommendations.enumerated().map { index, recommendation in
                "• \(recommendation)"
            }.joined(separator: "\n\n")

            yPosition += drawNarrativeBlock(
                context: context,
                title: "Recommendations",
                content: recommendationsText,
                rect: CGRect(x: rect.minX, y: yPosition, width: rect.width, height: rect.height - (yPosition - rect.minY)),
                fontSize: 9
            )
            yPosition += 10
        }

        // Full Report Content Section
        let remainingHeight = rect.height - (yPosition - rect.minY)
        if remainingHeight > 80 { // Only show if there's enough space
            _ = drawNarrativeBlock(
                context: context,
                title: "Detailed Analysis",
                content: narrative.content,
                rect: CGRect(x: rect.minX, y: yPosition, width: rect.width, height: remainingHeight),
                fontSize: 8
            )
        }
    }

    private func drawNarrativeBlock(context: CGContext, title: String, content: String, rect: CGRect, fontSize: CGFloat = 9) -> CGFloat {
        var yPosition = rect.minY

        // Title
        let titleFont = UIFont.boldSystemFont(ofSize: 12)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.systemBlue
        ]

        let titleString = NSAttributedString(string: title, attributes: titleAttributes)
        titleString.draw(at: CGPoint(x: rect.minX, y: yPosition))
        yPosition += 15

        // Content
        let contentFont = UIFont.systemFont(ofSize: fontSize)
        let contentAttributes: [NSAttributedString.Key: Any] = [
            .font: contentFont,
            .foregroundColor: UIColor.black
        ]

        let contentString = NSAttributedString(string: content, attributes: contentAttributes)
        let contentRect = CGRect(x: rect.minX, y: yPosition, width: rect.width, height: rect.height - (yPosition - rect.minY))
        contentString.draw(in: contentRect)

        // Calculate actual height used
        let boundingRect = contentString.boundingRect(
            with: CGSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        )

        return 15 + boundingRect.height + 10 // title height + content height + spacing
    }


    // MARK: - Utility Functions

    private func saveToTemporaryFile(data: Data, fileName: String) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        try data.write(to: fileURL)
        return fileURL
    }

    func setError(_ message: String) {
        Task { @MainActor in
            errorMessage = message
        }
    }

    func clearError() {
        Task { @MainActor in
            errorMessage = nil
        }
    }

    private func getUserFriendlyErrorMessage(for error: ReportExportError) -> String {
        switch error {
        case .invalidResponse:
            return "There was a problem communicating with the server. Please check your connection and try again."
        case .networkError(_):
            return "Network connection problem. Please check your internet connection and try again."
        case .fileSystemError(_):
            return "Unable to save the PDF file. Please ensure you have enough storage space and try again."
        }
    }
}

// MARK: - Error Types

enum ReportExportError: LocalizedError {
    case invalidResponse
    case networkError(String)
    case fileSystemError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let message):
            return "Network error: \(message)"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        }
    }
}

// MARK: - Activity View Controller for System Share Sheet

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}