//
//  ReportGenerator.swift
//  StudyAI
//
//  Service focused on report generation functionality
//  Handles API communication for creating new reports
//

import Foundation
import Combine

/// Service responsible for generating new parent reports
class ReportGenerator: ObservableObject {
    @Published var isGeneratingReport = false
    @Published var reportGenerationProgress: Double = 0.0
    @Published var lastError: ParentReportError?

    private let baseURL = "https://sai-backend-production.up.railway.app"
    private let localStorage = LocalReportStorage.shared
    private let localAggregator = LocalReportDataAggregator.shared

    /// Generate a new parent report using LOCAL data aggregation
    func generateReport(
        studentId: String,
        startDate: Date,
        endDate: Date,
        reportType: ReportType,
        includeAIAnalysis: Bool = true,
        compareWithPrevious: Bool = true
    ) async -> Result<ParentReport, ParentReportError> {

        print("📊 Starting LOCAL-FIRST report generation")

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
            return .failure(error)
        }

        await MainActor.run { reportGenerationProgress = 0.1 }

        // ✅ NEW: Aggregate data from LOCAL storage (replaces backend database queries)
        print("📱 Aggregating data from local storage...")
        let aggregatedData = await localAggregator.aggregateReportData(
            userId: studentId,
            startDate: startDate,
            endDate: endDate,
            options: ReportAggregationOptions(includeAIInsights: includeAIAnalysis)
        )

        await MainActor.run { reportGenerationProgress = 0.4 }

        print("✅ Local aggregation complete:")
        print("   • Questions: \(aggregatedData.academic?.totalQuestions ?? 0)")
        print("   • Accuracy: \(String(format: "%.1f%%", (aggregatedData.academic?.overallAccuracy ?? 0) * 100))")
        print("   • Subjects: \(aggregatedData.subjects?.keys.joined(separator: ", ") ?? "none")")

        // Prepare request with LOCAL aggregated data
        let generateURL = "\(baseURL)/api/reports/generate"
        guard let url = URL(string: generateURL) else {
            let error = ParentReportError.invalidURL
            await MainActor.run { lastError = error }
            return .failure(error)
        }

        // Format dates for API
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // ✅ NEW: Send pre-aggregated local data to backend
        let requestBody = GenerateReportRequestWithData(
            studentId: studentId,
            startDate: dateFormatter.string(from: startDate),
            endDate: dateFormatter.string(from: endDate),
            reportType: reportType,
            includeAiAnalysis: includeAIAnalysis,
            compareWithPrevious: compareWithPrevious,
            aggregatedData: aggregatedData  // ✅ Include local data
        )

        await MainActor.run { reportGenerationProgress = 0.5 }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("StudyAI-iOS/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120.0

        do {
            let requestData = try JSONEncoder().encode(requestBody)
            request.httpBody = requestData

            await MainActor.run { reportGenerationProgress = 0.3 }

            let (data, response) = try await URLSession.shared.data(for: request)

            await MainActor.run { reportGenerationProgress = 0.8 }

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = ParentReportError.invalidResponse
                await MainActor.run { lastError = error }
                return .failure(error)
            }

            switch httpResponse.statusCode {
            case 200:
                let result = try await processGenerationResponse(data: data,
                                                               studentId: studentId,
                                                               startDate: startDate,
                                                               endDate: endDate,
                                                               reportType: reportType,
                                                               includeAIAnalysis: includeAIAnalysis)
                await MainActor.run { reportGenerationProgress = 1.0 }
                return result

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
            let reportError = ParentReportError.networkError(error.localizedDescription)
            await MainActor.run { lastError = reportError }
            return .failure(reportError)
        }
    }

    private func processGenerationResponse(
        data: Data,
        studentId: String,
        startDate: Date,
        endDate: Date,
        reportType: ReportType,
        includeAIAnalysis: Bool
    ) async throws -> Result<ParentReport, ParentReportError> {

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let reportResponse = try decoder.decode(ParentReportResponse.self, from: data)

        guard reportResponse.success, let reportId = reportResponse.reportId else {
            let errorMessage = reportResponse.error ?? "Unknown error occurred"
            let error = ParentReportError.generationFailed(errorMessage)
            await MainActor.run { lastError = error }
            return .failure(error)
        }

        // Handle new narrative-based response format
        if let reportData = reportResponse.reportData, reportData.isNarrativeReport {
            let report = try createNarrativeReport(
                reportId: reportId,
                reportData: reportData,
                studentId: studentId,
                startDate: startDate,
                endDate: endDate,
                reportType: reportType,
                includeAIAnalysis: includeAIAnalysis,
                reportResponse: reportResponse
            )

            // Cache the generated report
            await localStorage.cacheReport(report)
            print("✅ Narrative-based report created and cached successfully")
            return .success(report)

        } else if let reportData = reportResponse.reportData {
            // Handle legacy full analytics format
            let report = try createLegacyReport(
                reportId: reportId,
                reportData: reportData,
                studentId: studentId,
                startDate: startDate,
                endDate: endDate,
                reportType: reportType,
                includeAIAnalysis: includeAIAnalysis,
                reportResponse: reportResponse
            )

            // Cache the generated report
            await localStorage.cacheReport(report)
            print("✅ Legacy analytics report generated and cached successfully")
            return .success(report)

        } else {
            let error = ParentReportError.parsingError("No report data found in response")
            await MainActor.run { lastError = error }
            return .failure(error)
        }
    }

    private func createNarrativeReport(
        reportId: String,
        reportData: ReportData,
        studentId: String,
        startDate: Date,
        endDate: Date,
        reportType: ReportType,
        includeAIAnalysis: Bool,
        reportResponse: ParentReportResponse
    ) throws -> ParentReport {

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")

        let reportDict: [String: Any] = [
            "id": reportId,
            "userId": studentId,
            "report_type": reportType.rawValue,
            "start_date": dateFormatter.string(from: startDate),
            "end_date": dateFormatter.string(from: endDate),
            "report_data": [
                "type": reportData.type ?? "narrative_report",
                "narrative_available": reportData.narrativeAvailable ?? false,
                "url": reportData.narrativeURL ?? "",
                "userId": studentId
            ],
            "generated_at": dateFormatter.string(from: Date().addingTimeInterval(-30)),
            "expires_at": dateFormatter.string(from: reportResponse.expiresAt ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()),
            "ai_analysis_included": includeAIAnalysis,
            "cached": reportResponse.cached ?? false,
            "generation_time_ms": reportResponse.generationTimeMs ?? 0
        ]

        let reportJsonData = try JSONSerialization.data(withJSONObject: reportDict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ParentReport.self, from: reportJsonData)
    }

    private func createLegacyReport(
        reportId: String,
        reportData: ReportData,
        studentId: String,
        startDate: Date,
        endDate: Date,
        reportType: ReportType,
        includeAIAnalysis: Bool,
        reportResponse: ParentReportResponse
    ) throws -> ParentReport {

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")

        // Convert reportData to dictionary
        let reportDataDict: [String: Any]
        do {
            let reportDataJson = try JSONEncoder().encode(reportData)
            reportDataDict = try JSONSerialization.jsonObject(with: reportDataJson) as? [String: Any] ?? [:]
        } catch {
            reportDataDict = [:]
        }

        let reportDict: [String: Any] = [
            "id": reportId,
            "userId": studentId,
            "report_type": reportType.rawValue,
            "start_date": dateFormatter.string(from: startDate),
            "end_date": dateFormatter.string(from: endDate),
            "report_data": reportDataDict,
            "generated_at": dateFormatter.string(from: reportData.generatedAt ?? Date()),
            "expires_at": dateFormatter.string(from: reportResponse.expiresAt ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()),
            "ai_analysis_included": includeAIAnalysis,
            "cached": reportResponse.cached ?? false,
            "generation_time_ms": reportResponse.generationTimeMs ?? 0
        ]

        let reportJsonData = try JSONSerialization.data(withJSONObject: reportDict)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ParentReport.self, from: reportJsonData)
    }
}

// MARK: - Request Models for Local-First Report Generation

/// Request body for generating report with pre-aggregated local data
struct GenerateReportRequestWithData: Codable {
    let studentId: String
    let startDate: String
    let endDate: String
    let reportType: ReportType
    let includeAiAnalysis: Bool
    let compareWithPrevious: Bool
    let aggregatedData: ReportData  // ✅ LOCAL aggregated data

    enum CodingKeys: String, CodingKey {
        case studentId = "student_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case reportType = "report_type"
        case includeAiAnalysis = "include_ai_analysis"
        case compareWithPrevious = "compare_with_previous"
        case aggregatedData = "aggregated_data"
    }
}

