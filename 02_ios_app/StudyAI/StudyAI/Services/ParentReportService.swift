//
//  ParentReportService.swift
//  StudyAI
//
//  Service for generating and managing parent reports
//  Handles API communication with the backend parent reports system
//

import Foundation
import Combine

/// Service class for managing parent reports API calls
class ParentReportService: ObservableObject {
    static let shared = ParentReportService()

    // Use existing NetworkService infrastructure
    private let baseURL = "https://sai-backend-production.up.railway.app"

    // Published properties for UI updates
    @Published var isGeneratingReport = false
    @Published var reportGenerationProgress: Double = 0.0
    @Published var lastGeneratedReport: ParentReport?
    @Published var availableReports: [ReportListItem] = []

    // Error handling
    @Published var lastError: ParentReportError?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        print("📊 ParentReportService initialized")
    }

    // MARK: - Report Generation

    /// Generate a new parent report
    /// - Parameters:
    ///   - studentId: The student's user ID
    ///   - startDate: Report start date
    ///   - endDate: Report end date
    ///   - reportType: Type of report to generate
    ///   - includeAIAnalysis: Whether to include AI-powered insights
    ///   - compareWithPrevious: Whether to compare with previous reports
    /// - Returns: Generated report or error
    func generateReport(
        studentId: String,
        startDate: Date,
        endDate: Date,
        reportType: ReportType,
        includeAIAnalysis: Bool = true,
        compareWithPrevious: Bool = true
    ) async -> Result<ParentReport, ParentReportError> {

        print("📊 === PARENT REPORT GENERATION STARTED ===")
        print("👤 Student ID: \(studentId)")
        print("📅 Date Range: \(startDate) to \(endDate)")
        print("📋 Report Type: \(reportType.rawValue)")
        print("🤖 AI Analysis: \(includeAIAnalysis)")
        print("📈 Compare Previous: \(compareWithPrevious)")

        await MainActor.run {
            isGeneratingReport = true
            reportGenerationProgress = 0.0
            lastError = nil
        }

        defer {
            Task { @MainActor in
                isGeneratingReport = false
                reportGenerationProgress = 0.0
            }
        }

        // Check authentication
        guard let authToken = AuthenticationService.shared.getAuthToken() else {
            let error = ParentReportError.notAuthenticated
            await MainActor.run { lastError = error }
            print("❌ Authentication required for report generation")
            return .failure(error)
        }

        print("🔑 Auth token found: \(String(authToken.prefix(20)))...")
        print("🔍 Token length: \(authToken.count) characters")

        await MainActor.run { reportGenerationProgress = 0.1 }

        // Prepare request
        let generateURL = "\(baseURL)/api/reports/generate"
        guard let url = URL(string: generateURL) else {
            let error = ParentReportError.invalidURL
            await MainActor.run { lastError = error }
            return .failure(error)
        }

        // Format dates for API
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let requestBody = GenerateReportRequest(
            studentId: studentId,
            startDate: dateFormatter.string(from: startDate),
            endDate: dateFormatter.string(from: endDate),
            reportType: reportType,
            includeAiAnalysis: includeAIAnalysis,
            compareWithPrevious: compareWithPrevious
        )

        await MainActor.run { reportGenerationProgress = 0.2 }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("StudyAI-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120.0 // Extended timeout for report generation

        do {
            let requestData = try JSONEncoder().encode(requestBody)
            request.httpBody = requestData

            // Debug: Print the exact JSON being sent
            if let jsonString = String(data: requestData, encoding: .utf8) {
                print("📤 Request JSON: \(jsonString)")
            }

            print("📤 Sending report generation request...")
            await MainActor.run { reportGenerationProgress = 0.3 }

            let (data, response) = try await URLSession.shared.data(for: request)

            await MainActor.run { reportGenerationProgress = 0.8 }

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = ParentReportError.invalidResponse
                await MainActor.run { lastError = error }
                return .failure(error)
            }

            print("📥 Report generation response status: \(httpResponse.statusCode)")

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let reportResponse: ParentReportResponse
                do {
                    reportResponse = try decoder.decode(ParentReportResponse.self, from: data)
                } catch {
                    print("❌ Failed to decode ParentReportResponse: \(error)")
                    throw error
                }

                if reportResponse.success,
                   let reportId = reportResponse.reportId {

                    // Handle the new narrative-based response format
                    if let reportData = reportResponse.reportData, reportData.isNarrativeReport {
                        print("📝 New narrative-based report format detected")

                        // Create a lightweight ParentReport for narrative-based reports
                        let dateFormatter = ISO8601DateFormatter()

                        let reportDict: [String: Any] = [
                            "report_id": reportId,  // Use correct key that matches ParentReport model
                            "userId": studentId,
                            "report_type": reportType.rawValue,
                            "start_date": dateFormatter.string(from: startDate),
                            "end_date": dateFormatter.string(from: endDate),
                            "report_data": [
                                "type": reportData.type ?? "narrative_report",
                                "narrative_available": reportData.narrativeAvailable ?? false,
                                "url": reportData.narrativeURL ?? "",
                                "userId": studentId // Add minimal backward compatibility
                            ],
                            "generated_at": dateFormatter.string(from: Date()),
                            "expires_at": dateFormatter.string(from: reportResponse.expiresAt ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()),
                            "ai_analysis_included": includeAIAnalysis,
                            "cached": reportResponse.cached ?? false,
                            "generation_time_ms": reportResponse.generationTimeMs ?? 0
                        ]

                        let reportJsonData = try JSONSerialization.data(withJSONObject: reportDict)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let report = try decoder.decode(ParentReport.self, from: reportJsonData)

                        await MainActor.run {
                            lastGeneratedReport = report
                            reportGenerationProgress = 1.0
                        }

                        print("✅ Narrative-based report created successfully!")
                        print("🆔 Report ID: \(reportId)")

                        // Refresh available reports list
                        Task {
                            _ = await fetchStudentReports(studentId: studentId)
                        }

                        return .success(report)

                    } else if let reportData = reportResponse.reportData {
                        // Handle legacy full analytics format for backward compatibility
                        print("📊 Legacy analytics report format detected")

                        // Create full ParentReport object using JSON encoding/decoding
                        let dateFormatter = ISO8601DateFormatter()

                        // Convert reportData to dictionary directly without double encoding/decoding
                        let reportDataDict: [String: Any]
                        do {
                            let reportDataJson = try JSONEncoder().encode(reportData)
                            reportDataDict = try JSONSerialization.jsonObject(with: reportDataJson) as? [String: Any] ?? [:]
                        } catch {
                            print("❌ Failed to convert reportData to dictionary: \(error)")
                            reportDataDict = [:]
                        }

                        let reportDict: [String: Any] = [
                            "report_id": reportId,  // Use correct key that matches ParentReport model
                            "userId": studentId,
                            "report_type": reportType.rawValue,
                            "start_date": dateFormatter.string(from: startDate),
                            "end_date": dateFormatter.string(from: endDate),
                            "report_data": reportDataDict,  // Use the properly converted dictionary
                            "generated_at": dateFormatter.string(from: reportData.generatedAt ?? Date()),
                            "expires_at": dateFormatter.string(from: reportResponse.expiresAt ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()),
                            "ai_analysis_included": includeAIAnalysis,
                            "cached": reportResponse.cached ?? false,
                            "generation_time_ms": reportResponse.generationTimeMs ?? 0
                        ]

                        let reportJsonData = try JSONSerialization.data(withJSONObject: reportDict)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let report = try decoder.decode(ParentReport.self, from: reportJsonData)

                        await MainActor.run {
                            lastGeneratedReport = report
                            reportGenerationProgress = 1.0
                        }

                        print("✅ Legacy analytics report generated successfully!")

                        // Refresh available reports list
                        Task {
                            _ = await fetchStudentReports(studentId: studentId)
                        }

                        return .success(report)
                    } else {
                        // Handle case where reportData is nil
                        let error = ParentReportError.parsingError("No report data found in response")
                        await MainActor.run { lastError = error }
                        return .failure(error)
                    }
                } else {
                    let errorMessage = reportResponse.error ?? "Unknown error occurred"
                    let error = ParentReportError.generationFailed(errorMessage)
                    await MainActor.run { lastError = error }
                    return .failure(error)
                }

            case 401:
                let error = ParentReportError.notAuthenticated
                await MainActor.run { lastError = error }
                return .failure(error)

            case 403:
                let error = ParentReportError.accessDenied
                await MainActor.run { lastError = error }
                return .failure(error)

            case 400:
                let error = ParentReportError.invalidRequest("Invalid request parameters")
                await MainActor.run { lastError = error }
                return .failure(error)

            default:
                let error = ParentReportError.serverError(httpResponse.statusCode)
                await MainActor.run { lastError = error }
                return .failure(error)
            }

        } catch {
            print("❌ Report generation request failed: \(error)")
            let reportError = ParentReportError.networkError(error.localizedDescription)
            await MainActor.run { lastError = reportError }
            return .failure(reportError)
        }
    }

    // MARK: - Narrative Content Fetching

    /// Fetch narrative content for a report
    /// - Parameter reportId: The report ID to fetch narrative for
    /// - Returns: Narrative content or error
    func fetchNarrative(reportId: String) async -> Result<NarrativeReport, ParentReportError> {
        print("📝 Fetching narrative for report: \(reportId)")

        guard let authToken = AuthenticationService.shared.getAuthToken() else {
            let error = ParentReportError.notAuthenticated
            await MainActor.run { lastError = error }
            return .failure(error)
        }

        let narrativeURL = "\(baseURL)/api/reports/\(reportId)/narrative"
        guard let url = URL(string: narrativeURL) else {
            let error = ParentReportError.invalidURL
            await MainActor.run { lastError = error }
            return .failure(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = ParentReportError.invalidResponse
                await MainActor.run { lastError = error }
                return .failure(error)
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let narrativeResponse = try decoder.decode(NarrativeResponse.self, from: data)

                if narrativeResponse.success, let narrative = narrativeResponse.narrative {
                    print("✅ Narrative fetched successfully!")
                    return .success(narrative)
                } else {
                    let errorMessage = narrativeResponse.error ?? "Failed to fetch narrative"
                    let error = ParentReportError.fetchFailed(errorMessage)
                    await MainActor.run { lastError = error }
                    return .failure(error)
                }

            case 401:
                let error = ParentReportError.notAuthenticated
                await MainActor.run { lastError = error }
                return .failure(error)

            case 403:
                let error = ParentReportError.accessDenied
                await MainActor.run { lastError = error }
                return .failure(error)

            case 404:
                let error = ParentReportError.reportNotFound
                await MainActor.run { lastError = error }
                return .failure(error)

            default:
                let error = ParentReportError.serverError(httpResponse.statusCode)
                await MainActor.run { lastError = error }
                return .failure(error)
            }

        } catch {
            print("❌ Narrative fetch failed: \(error)")
            let reportError = ParentReportError.networkError(error.localizedDescription)
            await MainActor.run { lastError = reportError }
            return .failure(reportError)
        }
    }

    // MARK: - Report Retrieval

    /// Fetch a specific report by ID
    /// - Parameter reportId: The report ID to fetch
    /// - Returns: Retrieved report or error
    func fetchReport(reportId: String) async -> Result<ParentReport, ParentReportError> {
        print("📄 Fetching report: \(reportId)")

        guard let authToken = AuthenticationService.shared.getAuthToken() else {
            let error = ParentReportError.notAuthenticated
            await MainActor.run { lastError = error }
            return .failure(error)
        }

        let fetchURL = "\(baseURL)/api/reports/\(reportId)"
        guard let url = URL(string: fetchURL) else {
            let error = ParentReportError.invalidURL
            await MainActor.run { lastError = error }
            return .failure(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = ParentReportError.invalidResponse
                await MainActor.run { lastError = error }
                return .failure(error)
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                // Parse the nested response structure
                let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let success = response?["success"] as? Bool, success,
                      let reportDict = response?["report"] as? [String: Any] else {
                    let error = ParentReportError.parsingError("Invalid response structure")
                    await MainActor.run { lastError = error }
                    return .failure(error)
                }

                // Convert back to JSON data for decoding
                let reportData = try JSONSerialization.data(withJSONObject: reportDict)
                let report = try decoder.decode(ParentReport.self, from: reportData)

                print("✅ Report fetched successfully: \(reportId)")
                return .success(report)

            case 401:
                let error = ParentReportError.notAuthenticated
                await MainActor.run { lastError = error }
                return .failure(error)

            case 403:
                let error = ParentReportError.accessDenied
                await MainActor.run { lastError = error }
                return .failure(error)

            case 404:
                let error = ParentReportError.reportNotFound
                await MainActor.run { lastError = error }
                return .failure(error)

            default:
                let error = ParentReportError.serverError(httpResponse.statusCode)
                await MainActor.run { lastError = error }
                return .failure(error)
            }

        } catch {
            let reportError = ParentReportError.networkError(error.localizedDescription)
            await MainActor.run { lastError = reportError }
            return .failure(reportError)
        }
    }

    /// Fetch list of reports for a student
    /// - Parameters:
    ///   - studentId: Student's user ID
    ///   - limit: Maximum number of reports to fetch
    ///   - offset: Offset for pagination
    ///   - reportType: Optional filter by report type
    /// - Returns: List of reports or error
    func fetchStudentReports(
        studentId: String,
        limit: Int = 20,
        offset: Int = 0,
        reportType: ReportType? = nil
    ) async -> Result<StudentReportsResponse, ParentReportError> {

        print("📋 Fetching reports for student: \(studentId)")

        guard let authToken = AuthenticationService.shared.getAuthToken() else {
            let error = ParentReportError.notAuthenticated
            await MainActor.run { lastError = error }
            return .failure(error)
        }

        var urlComponents = URLComponents(string: "\(baseURL)/api/reports/student/\(studentId)")!
        var queryItems: [URLQueryItem] = []

        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        queryItems.append(URLQueryItem(name: "offset", value: String(offset)))

        if let reportType = reportType {
            queryItems.append(URLQueryItem(name: "report_type", value: reportType.rawValue))
        }

        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            let error = ParentReportError.invalidURL
            await MainActor.run { lastError = error }
            return .failure(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = ParentReportError.invalidResponse
                await MainActor.run { lastError = error }
                return .failure(error)
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let reportsResponse = try decoder.decode(StudentReportsResponse.self, from: data)

                if reportsResponse.success {
                    await MainActor.run {
                        availableReports = reportsResponse.reports
                    }

                    print("✅ Fetched \(reportsResponse.reports.count) reports for student")
                    return .success(reportsResponse)
                } else {
                    let errorMessage = reportsResponse.error ?? "Failed to fetch reports"
                    let error = ParentReportError.fetchFailed(errorMessage)
                    await MainActor.run { lastError = error }
                    return .failure(error)
                }

            case 401:
                let error = ParentReportError.notAuthenticated
                await MainActor.run { lastError = error }
                return .failure(error)

            case 403:
                let error = ParentReportError.accessDenied
                await MainActor.run { lastError = error }
                return .failure(error)

            default:
                let error = ParentReportError.serverError(httpResponse.statusCode)
                await MainActor.run { lastError = error }
                return .failure(error)
            }

        } catch {
            let reportError = ParentReportError.networkError(error.localizedDescription)
            await MainActor.run { lastError = reportError }
            return .failure(reportError)
        }
    }

    // MARK: - Report Status

    /// Get the generation status of a report
    /// - Parameter reportId: The report ID to check
    /// - Returns: Report status information
    func getReportStatus(reportId: String) async -> Result<ReportStatus, ParentReportError> {
        guard let authToken = AuthenticationService.shared.getAuthToken() else {
            return .failure(.notAuthenticated)
        }

        let statusURL = "\(baseURL)/api/reports/\(reportId)/status"
        guard let url = URL(string: statusURL) else {
            return .failure(.invalidURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .failure(.serverError((response as? HTTPURLResponse)?.statusCode ?? 500))
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let status = try decoder.decode(ReportStatus.self, from: data)

            return .success(status)

        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }

    // MARK: - Utility Methods

    /// Clear all cached report data
    func clearCache() {
        Task { @MainActor in
            availableReports.removeAll()
            lastGeneratedReport = nil
            lastError = nil
        }
        print("🗑️ ParentReportService cache cleared")
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
            return "Authentication required. Please log in to generate reports."
        case .invalidURL:
            return "Invalid API URL configuration."
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .invalidResponse:
            return "Invalid server response format."
        case .networkError(let message):
            return "Network error: \(message)"
        case .parsingError(let message):
            return "Failed to parse response: \(message)"
        case .generationFailed(let message):
            return "Report generation failed: \(message)"
        case .fetchFailed(let message):
            return "Failed to fetch reports: \(message)"
        case .reportNotFound:
            return "Report not found or has expired."
        case .accessDenied:
            return "Access denied to this student's data."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
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