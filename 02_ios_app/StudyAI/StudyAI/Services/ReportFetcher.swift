//
//  ReportFetcher.swift
//  StudyAI
//
//  Service focused on fetching existing reports and narrative content
//  Handles retrieval operations with caching support
//

import Foundation
import Combine

/// Service responsible for fetching existing reports and their content
class ReportFetcher: ObservableObject {
    @Published var lastError: ParentReportError?

    private let baseURL = "https://sai-backend-production.up.railway.app"
    private let localStorage = LocalReportStorage.shared

    /// Fetch narrative content for a report
    func fetchNarrative(reportId: String) async -> Result<NarrativeReport, ParentReportError> {
        print("📝 Fetching narrative content for report: \(reportId)")

        // Try to load from cache first
        if let cachedNarrative = await localStorage.getCachedNarrative(reportId: reportId) {
            print("📝 Narrative loaded from cache: \(reportId)")
            return .success(cachedNarrative)
        }

        // If not in cache, fetch from network
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

                if narrativeResponse.success {
                    if let narrative = narrativeResponse.narrative {
                        // Cache the narrative for future use
                        await localStorage.cacheNarrative(narrative, reportId: reportId)

                        print("✅ Narrative fetched and cached successfully: \(reportId)")
                        return .success(narrative)
                    } else {
                        let error = ParentReportError.fetchFailed("No narrative content available")
                        await MainActor.run { lastError = error }
                        return .failure(error)
                    }
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
            let reportError = ParentReportError.networkError(error.localizedDescription)
            await MainActor.run { lastError = reportError }
            return .failure(reportError)
        }
    }

    /// Fetch a specific report by ID
    func fetchReport(reportId: String) async -> Result<ParentReport, ParentReportError> {
        print("📄 Fetching report: \(reportId)")

        // Try to load from cache first
        if let cachedReport = await localStorage.getCachedReport(reportId: reportId) {
            print("📄 Report loaded from cache: \(reportId)")
            return .success(cachedReport)
        }

        // If not in cache, fetch from network
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

                do {
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

                    // Cache the fetched report
                    await localStorage.cacheReport(report)

                    print("✅ Report fetched and cached successfully: \(reportId)")

                    return .success(report)
                } catch {
                    throw error
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
            let reportError = ParentReportError.networkError(error.localizedDescription)
            await MainActor.run { lastError = reportError }
            return .failure(reportError)
        }
    }

    /// Fetch list of reports for a student
    func fetchStudentReports(
        studentId: String,
        limit: Int = 20,
        offset: Int = 0,
        reportType: ReportType? = nil
    ) async -> Result<StudentReportsResponse, ParentReportError> {

        print("📋 Fetching student reports for: \(studentId)")

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

    /// Get the generation status of a report
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
}