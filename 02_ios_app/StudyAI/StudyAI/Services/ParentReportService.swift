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

            // Debug: Print raw response data
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 RAW RESPONSE DATA (first 2000 chars):")
                print(String(responseString.prefix(2000)))
                if responseString.count > 2000 {
                    print("... (truncated, total length: \(responseString.count) characters)")
                }
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let reportResponse: ParentReportResponse
                do {
                    reportResponse = try decoder.decode(ParentReportResponse.self, from: data)
                    print("✅ Successfully decoded ParentReportResponse")
                    print("📊 Report Response Debug:")
                    print("   - Success: \(reportResponse.success)")
                    print("   - Report ID: \(reportResponse.reportId ?? "nil")")
                    print("   - Cached: \(reportResponse.cached ?? false)")
                    print("   - Generation Time: \(reportResponse.generationTimeMs ?? 0)ms")
                    print("   - Report Data Type: \(reportResponse.reportData?.type ?? "nil")")
                    print("   - Narrative Available: \(reportResponse.reportData?.narrativeAvailable ?? false)")
                    print("   - Narrative ID: \(reportResponse.reportData?.narrativeId ?? "nil")")
                    print("   - Narrative URL: \(reportResponse.reportData?.narrativeURL ?? "nil")")
                } catch {
                    print("❌ Failed to decode ParentReportResponse: \(error)")
                    print("❌ Decoder error details: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        print("❌ Decoding error context: \(decodingError)")
                    }
                    throw error
                }

                if reportResponse.success,
                   let reportId = reportResponse.reportId {

                    // Handle the new narrative-based response format
                    if let reportData = reportResponse.reportData, reportData.isNarrativeReport {
                        print("📝 New narrative-based report format detected")
                        print("📊 Narrative Report Data Debug:")
                        print("   - Is Narrative Report: \(reportData.isNarrativeReport)")
                        print("   - Type: \(reportData.type ?? "nil")")
                        print("   - Narrative Available: \(reportData.narrativeAvailable ?? false)")
                        print("   - Narrative ID: \(reportData.narrativeId ?? "nil")")
                        print("   - URL: \(reportData.url ?? "nil")")
                        print("   - Fetch Narrative URL: \(reportData.fetchNarrativeUrl ?? "nil")")
                        print("   - Final Narrative URL: \(reportData.narrativeURL ?? "nil")")

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
                        print("📊 Legacy Report Data Debug:")
                        print("   - User ID: \(reportData.userId ?? "nil")")
                        print("   - Has Academic Data: \(reportData.academic != nil)")
                        print("   - Has Activity Data: \(reportData.activity != nil)")
                        print("   - Has Progress Data: \(reportData.progress != nil)")
                        print("   - Has Subjects Data: \(reportData.subjects != nil)")
                        print("   - Report Period: \(reportData.reportPeriod != nil)")
                        print("   - Generated At: \(reportData.generatedAt ?? Date())")

                        // Check if this legacy report actually has narrative data in it
                        if reportData.narrativeURL != nil || reportData.narrativeId != nil {
                            print("🔍 Legacy report contains narrative data!")
                            print("   - Narrative URL in legacy: \(reportData.narrativeURL ?? "nil")")
                            print("   - Narrative ID in legacy: \(reportData.narrativeId ?? "nil")")
                        }

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
        print("📝 === FETCHING NARRATIVE CONTENT ===")
        print("📝 Report ID: \(reportId)")

        guard let authToken = AuthenticationService.shared.getAuthToken() else {
            let error = ParentReportError.notAuthenticated
            await MainActor.run { lastError = error }
            print("❌ No auth token available for narrative fetch")
            return .failure(error)
        }

        print("🔑 Auth token available: \(String(authToken.prefix(20)))...")

        let narrativeURL = "\(baseURL)/api/reports/\(reportId)/narrative"
        print("🔗 Narrative URL: \(narrativeURL)")

        guard let url = URL(string: narrativeURL) else {
            let error = ParentReportError.invalidURL
            await MainActor.run { lastError = error }
            print("❌ Invalid narrative URL: \(narrativeURL)")
            return .failure(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0

        print("📤 Sending narrative fetch request...")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = ParentReportError.invalidResponse
                await MainActor.run { lastError = error }
                print("❌ Invalid HTTP response for narrative fetch")
                return .failure(error)
            }

            print("📥 Narrative fetch response status: \(httpResponse.statusCode)")

            // Debug: Print raw narrative response data
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 NARRATIVE RAW RESPONSE DATA (first 2000 chars):")
                print(String(responseString.prefix(2000)))
                if responseString.count > 2000 {
                    print("... (truncated, total length: \(responseString.count) characters)")
                }
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                do {
                    let narrativeResponse = try decoder.decode(NarrativeResponse.self, from: data)
                    print("✅ Successfully decoded NarrativeResponse")
                    print("📝 Narrative Response Debug:")
                    print("   - Success: \(narrativeResponse.success)")
                    print("   - Has Narrative: \(narrativeResponse.narrative != nil)")

                    if let narrative = narrativeResponse.narrative {
                        print("📝 Narrative Content Debug:")
                        print("   - ID: \(narrative.id)")
                        print("   - Content Length: \(narrative.content.count) characters")
                        print("   - Summary Length: \(narrative.summary.count) characters")
                        print("   - Key Insights Count: \(narrative.keyInsights.count)")
                        print("   - Recommendations Count: \(narrative.recommendations.count)")
                        print("   - Word Count: \(narrative.wordCount)")
                        print("   - Generated At: \(narrative.generatedAt)")
                        print("   - Tone Style: \(narrative.toneStyle ?? "nil")")
                        print("   - Language: \(narrative.language ?? "nil")")
                        print("   - Reading Level: \(narrative.readingLevel ?? "nil")")

                        // Show first 200 characters of content
                        print("📝 Content Preview (first 200 chars):")
                        print(String(narrative.content.prefix(200)))
                        if narrative.content.count > 200 {
                            print("... (content continues)")
                        }
                    }

                    if let error = narrativeResponse.error {
                        print("⚠️ Narrative response contains error: \(error)")
                    }
                } catch {
                    print("❌ Failed to decode NarrativeResponse: \(error)")
                    print("❌ Decoder error details: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        print("❌ Decoding error context: \(decodingError)")
                    }
                    throw error
                }

                let narrativeResponse = try decoder.decode(NarrativeResponse.self, from: data)

                if narrativeResponse.success, let narrative = narrativeResponse.narrative {
                    print("✅ Narrative fetched successfully!")
                    print("📝 Final narrative ID: \(narrative.id)")
                    return .success(narrative)
                } else {
                    let errorMessage = narrativeResponse.error ?? "Failed to fetch narrative"
                    print("❌ Narrative fetch failed: \(errorMessage)")
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
        print("📄 === FETCHING SPECIFIC REPORT ===")
        print("📄 Report ID: \(reportId)")

        guard let authToken = AuthenticationService.shared.getAuthToken() else {
            let error = ParentReportError.notAuthenticated
            await MainActor.run { lastError = error }
            print("❌ No auth token available for report fetch")
            return .failure(error)
        }

        print("🔑 Auth token available: \(String(authToken.prefix(20)))...")

        let fetchURL = "\(baseURL)/api/reports/\(reportId)"
        print("🔗 Fetch URL: \(fetchURL)")

        guard let url = URL(string: fetchURL) else {
            let error = ParentReportError.invalidURL
            await MainActor.run { lastError = error }
            print("❌ Invalid fetch URL: \(fetchURL)")
            return .failure(error)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        print("📤 Sending report fetch request...")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = ParentReportError.invalidResponse
                await MainActor.run { lastError = error }
                print("❌ Invalid HTTP response for report fetch")
                return .failure(error)
            }

            print("📥 Report fetch response status: \(httpResponse.statusCode)")

            // Debug: Print raw report fetch response data
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 REPORT FETCH RAW RESPONSE DATA (first 2000 chars):")
                print(String(responseString.prefix(2000)))
                if responseString.count > 2000 {
                    print("... (truncated, total length: \(responseString.count) characters)")
                }
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                do {
                    // Parse the nested response structure
                    let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    print("📄 Report fetch response structure parsed")
                    print("📄 Response keys: \(response?.keys.joined(separator: ", ") ?? "nil")")

                    guard let success = response?["success"] as? Bool, success,
                          let reportDict = response?["report"] as? [String: Any] else {
                        print("❌ Invalid response structure or not successful")
                        print("   - Success: \(response?["success"] ?? "nil")")
                        print("   - Has report: \(response?["report"] != nil)")
                        let error = ParentReportError.parsingError("Invalid response structure")
                        await MainActor.run { lastError = error }
                        return .failure(error)
                    }

                    print("📄 Report dictionary keys: \(reportDict.keys.joined(separator: ", "))")

                    // Convert back to JSON data for decoding
                    let reportData = try JSONSerialization.data(withJSONObject: reportDict)

                    // Debug: Print exactly what we're trying to decode
                    if let debugString = String(data: reportData, encoding: .utf8) {
                        print("🔍 EXACT DATA BEING DECODED (first 1000 chars):")
                        print(String(debugString.prefix(1000)))
                        if debugString.count > 1000 {
                            print("... (truncated, total length: \(debugString.count) characters)")
                        }
                    }

                    print("🔍 About to decode ParentReport.self from extracted report data...")
                    let report = try decoder.decode(ParentReport.self, from: reportData)

                    print("✅ Report fetched successfully: \(reportId)")
                    print("📄 Fetched report data type: \(report.reportData.type ?? "nil")")
                    print("📄 Is narrative report: \(report.reportData.isNarrativeReport)")
                    print("📄 Narrative available: \(report.reportData.narrativeAvailable ?? false)")
                    print("📄 Narrative URL: \(report.reportData.narrativeURL ?? "nil")")

                    return .success(report)
                } catch {
                    print("❌ Failed to decode report response: \(error)")
                    print("❌ Decoder error details: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        print("❌ Decoding error context: \(decodingError)")
                    }
                    throw error
                }

            case 401:
                let error = ParentReportError.notAuthenticated
                await MainActor.run { lastError = error }
                print("❌ Authentication failed for report fetch")
                return .failure(error)

            case 403:
                let error = ParentReportError.accessDenied
                await MainActor.run { lastError = error }
                print("❌ Access denied for report fetch")
                return .failure(error)

            case 404:
                let error = ParentReportError.reportNotFound
                await MainActor.run { lastError = error }
                print("❌ Report not found: \(reportId)")
                return .failure(error)

            default:
                let error = ParentReportError.serverError(httpResponse.statusCode)
                await MainActor.run { lastError = error }
                print("❌ Server error for report fetch: \(httpResponse.statusCode)")
                return .failure(error)
            }

        } catch {
            print("❌ Report fetch request failed: \(error)")
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

        print("📋 === FETCHING STUDENT REPORTS ===")
        print("📋 Student ID: \(studentId)")
        print("📋 Limit: \(limit), Offset: \(offset)")
        print("📋 Report Type Filter: \(reportType?.rawValue ?? "nil")")

        guard let authToken = AuthenticationService.shared.getAuthToken() else {
            let error = ParentReportError.notAuthenticated
            await MainActor.run { lastError = error }
            print("❌ No auth token available for reports fetch")
            return .failure(error)
        }

        print("🔑 Auth token available: \(String(authToken.prefix(20)))...")

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
            print("❌ Invalid reports URL: \(urlComponents.string ?? "nil")")
            return .failure(error)
        }

        print("🔗 Reports URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        print("📤 Sending reports fetch request...")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                let error = ParentReportError.invalidResponse
                await MainActor.run { lastError = error }
                print("❌ Invalid HTTP response for reports fetch")
                return .failure(error)
            }

            print("📥 Reports fetch response status: \(httpResponse.statusCode)")

            // Debug: Print raw reports response data
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 REPORTS RAW RESPONSE DATA (first 2000 chars):")
                print(String(responseString.prefix(2000)))
                if responseString.count > 2000 {
                    print("... (truncated, total length: \(responseString.count) characters)")
                }
            }

            switch httpResponse.statusCode {
            case 200:
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                do {
                    let reportsResponse = try decoder.decode(StudentReportsResponse.self, from: data)
                    print("✅ Successfully decoded StudentReportsResponse")
                    print("📋 Reports Response Debug:")
                    print("   - Success: \(reportsResponse.success)")
                    print("   - Reports Count: \(reportsResponse.reports.count)")
                    print("   - Total: \(reportsResponse.pagination.total)")
                    print("   - Has More: \(reportsResponse.pagination.hasMore)")

                    // Debug each report
                    for (index, report) in reportsResponse.reports.enumerated() {
                        print("📋 Report \(index + 1):")
                        print("   - ID: \(report.id)")
                        print("   - Type: \(report.reportType.rawValue)")
                        print("   - Date Range: \(report.startDate) to \(report.endDate)")
                        print("   - Generated At: \(report.generatedAt)")
                        print("   - AI Analysis: \(report.aiAnalysisIncluded)")
                        print("   - Views: \(report.viewedCount ?? 0)")
                        print("   - Exports: \(report.exportedCount ?? 0)")
                    }

                    if let error = reportsResponse.error {
                        print("⚠️ Reports response contains error: \(error)")
                    }
                } catch {
                    print("❌ Failed to decode StudentReportsResponse: \(error)")
                    print("❌ Decoder error details: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        print("❌ Decoding error context: \(decodingError)")
                    }
                    throw error
                }

                let reportsResponse = try decoder.decode(StudentReportsResponse.self, from: data)

                if reportsResponse.success {
                    await MainActor.run {
                        availableReports = reportsResponse.reports
                    }

                    print("✅ Fetched \(reportsResponse.reports.count) reports for student (IOS)")
                    return .success(reportsResponse)
                } else {
                    let errorMessage = reportsResponse.error ?? "Failed to fetch reports"
                    print("❌ Reports fetch failed: \(errorMessage)")
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