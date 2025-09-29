//
//  ParentReportService.swift
//  StudyAI
//
//  Service coordinator for parent reports functionality
//  Acts as a façade over specialized report services
//

import Foundation
import Combine

/// Service class for coordinating parent reports functionality
/// Acts as a facade over specialized report services
class ParentReportService: ObservableObject {
    static let shared = ParentReportService()

    // Specialized services
    private let reportGenerator = ReportGenerator()
    private let reportFetcher = ReportFetcher()
    private let localStorage = LocalReportStorage.shared

    // Published properties for UI updates - delegated from specialized services
    @Published var isGeneratingReport = false
    @Published var reportGenerationProgress: Double = 0.0
    @Published var lastGeneratedReport: ParentReport?
    @Published var availableReports: [ReportListItem] = []
    @Published var lastError: ParentReportError?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        print("📊 ParentReportService initialized")
        setupBindings()
    }

    private func setupBindings() {
        // Bind generator properties
        reportGenerator.$isGeneratingReport
            .assign(to: &$isGeneratingReport)

        reportGenerator.$reportGenerationProgress
            .assign(to: &$reportGenerationProgress)

        reportGenerator.$lastError
            .compactMap { $0 }
            .assign(to: &$lastError)

        // Bind fetcher errors
        reportFetcher.$lastError
            .compactMap { $0 }
            .assign(to: &$lastError)
    }

    // MARK: - Report Generation (Delegated to ReportGenerator)

    /// Generate a new parent report
    func generateReport(
        studentId: String,
        startDate: Date,
        endDate: Date,
        reportType: ReportType,
        includeAIAnalysis: Bool = true,
        compareWithPrevious: Bool = true
    ) async -> Result<ParentReport, ParentReportError> {

        let result = await reportGenerator.generateReport(
            studentId: studentId,
            startDate: startDate,
            endDate: endDate,
            reportType: reportType,
            includeAIAnalysis: includeAIAnalysis,
            compareWithPrevious: compareWithPrevious
        )

        // Update our state based on the result
        if case .success(let report) = result {
            await MainActor.run {
                lastGeneratedReport = report
            }

            // Refresh available reports list
            Task {
                _ = await fetchStudentReports(studentId: studentId)
            }
        }

        return result
    }

    // MARK: - Report Retrieval (Delegated to ReportFetcher)

    /// Fetch narrative content for a report
    func fetchNarrative(reportId: String) async -> Result<NarrativeReport, ParentReportError> {
        return await reportFetcher.fetchNarrative(reportId: reportId)
    }

    /// Fetch a specific report by ID
    func fetchReport(reportId: String) async -> Result<ParentReport, ParentReportError> {
        return await reportFetcher.fetchReport(reportId: reportId)
    }

    /// Fetch list of reports for a student
    func fetchStudentReports(
        studentId: String,
        limit: Int = 20,
        offset: Int = 0,
        reportType: ReportType? = nil
    ) async -> Result<StudentReportsResponse, ParentReportError> {

        let result = await reportFetcher.fetchStudentReports(
            studentId: studentId,
            limit: limit,
            offset: offset,
            reportType: reportType
        )

        // Update our state based on the result
        if case .success(let reportsResponse) = result {
            await MainActor.run {
                availableReports = reportsResponse.reports
            }
        }

        return result
    }

    /// Get the generation status of a report
    func getReportStatus(reportId: String) async -> Result<ReportStatus, ParentReportError> {
        return await reportFetcher.getReportStatus(reportId: reportId)
    }

    // MARK: - Utility Methods

    /// Clear all cached report data
    func clearCache() {
        Task { @MainActor in
            availableReports.removeAll()
            lastGeneratedReport = nil
            lastError = nil
        }

        // Clear local storage cache
        Task {
            await localStorage.clearAllCache()
        }

        print("🗑️ ParentReportService cache cleared")
    }

    /// Get cache information
    func getCacheInfo() async -> (size: Int64, isEnabled: Bool) {
        let size = await localStorage.getCacheSize()
        return (size: size, isEnabled: true)
    }
}

// MARK: - Supporting Models

/// Report generation status
struct ReportStatus: Codable {
    let success: Bool
    let status: String
    let generatedAt: Date?
    let expiresAt: Date?
    let generationTimeMs: Int?

    enum CodingKeys: String, CodingKey {
        case success, status
        case generatedAt = "generated_at"
        case expiresAt = "expires_at"
        case generationTimeMs = "generation_time_ms"
    }
}

/// Parent report service errors
enum ParentReportError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidRequest(String)
    case invalidResponse
    case networkError(String)
    case parsingError(String)
    case generationFailed(String)
    case fetchFailed(String)
    case reportNotFound
    case accessDenied
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to access your reports."
        case .invalidURL:
            return "There's a configuration issue. Please restart the app and try again."
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .invalidResponse:
            return "We're having trouble communicating with our servers. Please try again."
        case .networkError(_):
            return "Network connection problem. Please check your internet and try again."
        case .parsingError(_):
            return "We encountered an issue processing your report data. Please try again."
        case .generationFailed(_):
            return "Report generation failed. Please try again in a few moments."
        case .fetchFailed(_):
            return "Unable to load your reports. Please check your connection and try again."
        case .reportNotFound:
            return "This report is no longer available. It may have expired."
        case .accessDenied:
            return "You don't have permission to access this report."
        case .serverError(_):
            return "Our servers are experiencing issues. Please try again in a few minutes."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notAuthenticated:
            return "Please log in to your account and try again."
        case .networkError:
            return "Check your internet connection and try again."
        case .serverError:
            return "The server is experiencing issues. Please try again in a few minutes."
        case .reportNotFound:
            return "The report may have expired. Try generating a new report."
        case .accessDenied:
            return "Ensure you have permission to view this student's reports."
        default:
            return "Please try again or contact support if the problem persists."
        }
    }
}