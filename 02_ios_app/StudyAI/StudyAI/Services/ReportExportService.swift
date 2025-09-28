//
//  ReportExportService.swift
//  StudyAI
//
//  Service for handling report export and sharing functionality
//

import Foundation
import SwiftUI
import Combine

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

        defer {
            isExporting = false
            exportProgress = 0.0
            exportStatus = ""
        }

        do {
            exportStatus = "Checking narrative content..."
            exportProgress = 0.2

            // First, try to fetch narrative content to ensure it exists
            let narrativeResult = await ParentReportService.shared.fetchNarrative(reportId: reportId)
            let hasNarrative: Bool
            switch narrativeResult {
            case .success(let narrative):
                print("✅ Narrative content found - ID: \(narrative.id), Content length: \(narrative.content.count) chars")
                hasNarrative = true
            case .failure(let error):
                print("❌ No narrative content found: \(error.localizedDescription)")
                hasNarrative = false
            }

            print("📝 Narrative availability check: \(hasNarrative ? "Available" : "Not Available")")
            exportProgress = 0.3

            // Strategy 1: Try PDF export specifically designed for narrative reports
            if hasNarrative {
                exportStatus = "Generating narrative PDF..."
                let narrativeEndpoint = "\(networkService.apiBaseURL)/api/reports/\(reportId)/export/narrative?format=\(format.rawValue)"

                do {
                    return try await attemptNarrativeExport(endpoint: narrativeEndpoint, reportId: reportId, format: format)
                } catch {
                    print("⚠️ Narrative-specific export failed: \(error)")
                }
            }

            // Strategy 2: Try comprehensive export endpoint
            exportProgress = 0.4
            exportStatus = "Generating comprehensive PDF..."
            let comprehensiveEndpoint = "\(networkService.apiBaseURL)/api/reports/\(reportId)/export/comprehensive?format=\(format.rawValue)"

            do {
                return try await attemptComprehensiveExport(endpoint: comprehensiveEndpoint, reportId: reportId, format: format)
            } catch {
                print("⚠️ Comprehensive export failed: \(error)")
            }

            // Strategy 3: Standard export with explicit narrative parameters
            exportProgress = 0.5
            exportStatus = "Generating enhanced PDF..."
            let standardEndpoint = "\(networkService.apiBaseURL)/api/reports/\(reportId)/export?format=\(format.rawValue)&include_narrative=true&include_analytics=true&content_type=comprehensive&export_type=full"

            do {
                return try await attemptStandardExport(endpoint: standardEndpoint, reportId: reportId, format: format)
            } catch {
                print("⚠️ Standard export with narrative failed: \(error)")
            }

            // Strategy 4: Try POST request with narrative content body (if narrative exists)
            if hasNarrative, case .success(let narrative) = narrativeResult {
                exportProgress = 0.6
                exportStatus = "Creating custom narrative PDF..."
                do {
                    return try await attemptPostExportWithNarrative(reportId: reportId, format: format, narrative: narrative)
                } catch {
                    print("⚠️ POST export with narrative failed: \(error)")
                }
            }

            // Final fallback to basic export (warn user that narrative may not be included)
            print("⚠️ All narrative-inclusive export attempts failed, falling back to basic export")
            exportProgress = 0.7
            exportStatus = "Generating basic PDF (may not include narrative)..."
            return try await exportReportBasic(reportId: reportId, format: format)

        } catch {
            print("❌ Export error: \(error)")
            throw error
        }
    }

    // MARK: - Export Methods

    private func attemptNarrativeExport(endpoint: String, reportId: String, format: ReportExportView.ExportFormat) async throws -> URL {
        exportStatus = "Generating narrative-focused PDF..."

        guard let url = URL(string: endpoint) else {
            throw ReportExportError.networkError("Invalid narrative export URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/pdf", forHTTPHeaderField: "Accept")
        request.setValue("narrative-focus", forHTTPHeaderField: "X-Export-Type")
        request.setValue("narrative", forHTTPHeaderField: "X-Report-Content-Type")

        // Add authentication header
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        print("📤 Requesting narrative export: \(endpoint)")
        exportProgress = 0.6

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReportExportError.networkError("Invalid response")
        }

        print("📥 Narrative export response: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            throw ReportExportError.networkError("Narrative export failed with status \(httpResponse.statusCode)")
        }

        exportProgress = 0.9

        // Save the file to temporary storage
        let fileName = "report_\(reportId)_narrative.pdf"
        let fileURL = try saveToTemporaryFile(data: data, fileName: fileName)

        exportProgress = 1.0
        exportStatus = "Narrative PDF generated!"

        print("✅ Narrative PDF exported successfully")
        print("📄 File size: \(data.count) bytes")
        print("📁 File location: \(fileURL.path)")

        return fileURL
    }

    private func attemptPostExportWithNarrative(reportId: String, format: ReportExportView.ExportFormat, narrative: NarrativeReport) async throws -> URL {
        exportStatus = "Creating custom PDF with narrative..."

        let endpoint = "\(networkService.apiBaseURL)/api/reports/\(reportId)/export/custom"
        guard let url = URL(string: endpoint) else {
            throw ReportExportError.networkError("Invalid custom export URL")
        }

        // Create request body with narrative content
        let requestBody = [
            "format": format.rawValue,
            "include_narrative": true,
            "narrative_content": [
                "id": narrative.id,
                "summary": narrative.summary,
                "content": narrative.content,
                "key_insights": narrative.keyInsights,
                "recommendations": narrative.recommendations
            ],
            "export_type": "comprehensive"
        ] as [String : Any]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/pdf", forHTTPHeaderField: "Accept")
        request.setValue("custom-narrative", forHTTPHeaderField: "X-Export-Type")

        // Add authentication header
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let requestData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = requestData

        print("📤 Requesting custom POST export with narrative content")
        print("📄 Narrative content included: \(narrative.content.count) chars")
        exportProgress = 0.8

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReportExportError.networkError("Invalid response")
        }

        print("📥 Custom export response: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            throw ReportExportError.networkError("Custom export failed with status \(httpResponse.statusCode)")
        }

        exportProgress = 0.9

        // Save the file to temporary storage
        let fileName = "report_\(reportId)_custom_narrative.pdf"
        let fileURL = try saveToTemporaryFile(data: data, fileName: fileName)

        exportProgress = 1.0
        exportStatus = "Custom narrative PDF generated!"

        print("✅ Custom narrative PDF exported successfully")
        print("📄 File size: \(data.count) bytes")
        print("📁 File location: \(fileURL.path)")

        return fileURL
    }

    private func attemptComprehensiveExport(endpoint: String, reportId: String, format: ReportExportView.ExportFormat) async throws -> URL {
        exportStatus = "Generating comprehensive PDF with narrative..."

        guard let url = URL(string: endpoint) else {
            throw ReportExportError.networkError("Invalid comprehensive export URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/pdf", forHTTPHeaderField: "Accept")
        request.setValue("narrative-included", forHTTPHeaderField: "X-Export-Type")
        request.setValue("comprehensive", forHTTPHeaderField: "X-Report-Content-Type")

        // Add authentication header
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        print("📤 Requesting comprehensive export: \(endpoint)")
        exportProgress = 0.6

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReportExportError.networkError("Invalid response")
        }

        print("📥 Comprehensive export response: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            throw ReportExportError.networkError("Comprehensive export failed with status \(httpResponse.statusCode)")
        }

        exportProgress = 0.9

        // Save the file to temporary storage
        let fileName = "report_\(reportId)_comprehensive.\(format.rawValue)"
        let fileURL = try saveToTemporaryFile(data: data, fileName: fileName)

        exportProgress = 1.0
        exportStatus = "Comprehensive PDF generated!"

        print("✅ Comprehensive PDF exported successfully with narrative content")
        print("📄 File size: \(data.count) bytes")
        print("📁 File location: \(fileURL.path)")

        return fileURL
    }

    private func attemptStandardExport(endpoint: String, reportId: String, format: ReportExportView.ExportFormat) async throws -> URL {
        exportStatus = "Generating enhanced PDF..."

        guard let url = URL(string: endpoint) else {
            throw ReportExportError.networkError("Invalid standard export URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/pdf", forHTTPHeaderField: "Accept")
        request.setValue("enhanced", forHTTPHeaderField: "X-Export-Type")

        // Add authentication header
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        print("📤 Requesting enhanced export: \(endpoint)")
        exportProgress = 0.7

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReportExportError.networkError("Invalid response")
        }

        print("📥 Enhanced export response: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            throw ReportExportError.networkError("Enhanced export failed with status \(httpResponse.statusCode)")
        }

        exportProgress = 0.9

        // Save the file to temporary storage
        let fileName = "report_\(reportId)_enhanced.\(format.rawValue)"
        let fileURL = try saveToTemporaryFile(data: data, fileName: fileName)

        exportProgress = 1.0
        exportStatus = "Enhanced PDF generated!"

        print("✅ Enhanced PDF exported successfully")
        print("📄 File size: \(data.count) bytes")

        return fileURL
    }

    // MARK: - Fallback Export Method

    private func exportReportBasic(reportId: String, format: ReportExportView.ExportFormat) async throws -> URL {
        exportStatus = "Generating basic \(format.displayName.lowercased())..."
        exportProgress = 0.6

        let endpoint = "\(networkService.apiBaseURL)/api/reports/\(reportId)/export?format=\(format.rawValue)"

        guard let url = URL(string: endpoint) else {
            throw ReportExportError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Add authentication header
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        print("📤 Requesting basic export: \(endpoint)")
        print("⚠️ Note: This basic export may not include narrative content")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Basic export failed with status \(statusCode): \(errorMessage)")
            throw ReportExportError.networkError("Basic export failed: \(errorMessage)")
        }

        // Save the file to temporary storage
        let fileName = "report_\(reportId)_basic.\(format.rawValue)"
        let fileURL = try saveToTemporaryFile(data: data, fileName: fileName)

        print("✅ Basic PDF exported successfully (fallback)")
        print("📄 File size: \(data.count) bytes")
        print("⚠️ Warning: This PDF may only contain analytics data, not narrative content")

        return fileURL
    }

    // MARK: - Utility Functions

    private func saveToTemporaryFile(data: Data, fileName: String) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        try data.write(to: fileURL)
        return fileURL
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
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