//
//  PassiveReportsViewModel.swift
//  StudyAI
//
//  Passive Reports ViewModel
//  Handles API communication for scheduled weekly/monthly parent reports
//

import SwiftUI
import Combine

// MARK: - Data Models

struct PassiveReportBatch: Identifiable, Codable {
    let id: String
    let period: String // "weekly" or "monthly"
    let startDate: Date
    let endDate: Date
    let generatedAt: Date
    let status: String
    let generationTimeMs: Int?
    let overallGrade: String?
    let overallAccuracy: Double?
    let questionCount: Int?
    let studyTimeMinutes: Int?
    let currentStreak: Int?
    let accuracyTrend: String?
    let activityTrend: String?
    let oneLineSummary: String?
    let reportCount: Int?
    let mentalHealthScore: Double?
    let engagementLevel: Double?
    let confidenceLevel: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case period
        case startDate = "start_date"
        case endDate = "end_date"
        case generatedAt = "generated_at"
        case status
        case generationTimeMs = "generation_time_ms"
        case overallGrade = "overall_grade"
        case overallAccuracy = "overall_accuracy"
        case questionCount = "question_count"
        case studyTimeMinutes = "study_time_minutes"
        case currentStreak = "current_streak"
        case accuracyTrend = "accuracy_trend"
        case activityTrend = "activity_trend"
        case oneLineSummary = "one_line_summary"
        case reportCount = "report_count"
        case mentalHealthScore = "mental_health_score"
        case engagementLevel = "engagement_level"
        case confidenceLevel = "confidence_level"
    }
}

struct PassiveReport: Identifiable, Codable {
    let id: String
    let reportType: String
    let narrativeContent: String
    let keyInsights: [String]?
    let recommendations: [ReportRecommendation]?
    let visualData: VisualData?
    let wordCount: Int?
    let generationTimeMs: Int?
    let aiModelUsed: String?
    let generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case reportType = "report_type"
        case narrativeContent = "narrative_content"
        case keyInsights = "key_insights"
        case recommendations
        case visualData = "visual_data"
        case wordCount = "word_count"
        case generationTimeMs = "generation_time_ms"
        case aiModelUsed = "ai_model_used"
        case generatedAt = "generated_at"
    }

    // Computed property for display name
    var displayName: String {
        switch reportType {
        case "executive_summary":
            return NSLocalizedString("reports.passive.executive_summary", value: "Executive Summary", comment: "")
        case "academic_performance":
            return NSLocalizedString("reports.passive.academic_performance", value: "Academic Performance", comment: "")
        case "learning_behavior":
            return NSLocalizedString("reports.passive.learning_behavior", value: "Learning Behavior", comment: "")
        case "motivation_emotional":
            return NSLocalizedString("reports.passive.motivation_emotional", value: "Motivation & Engagement", comment: "")
        case "progress_trajectory":
            return NSLocalizedString("reports.passive.progress_trajectory", value: "Progress Trajectory", comment: "")
        case "social_learning":
            return NSLocalizedString("reports.passive.social_learning", value: "Social Learning", comment: "")
        case "risk_opportunity":
            return NSLocalizedString("reports.passive.risk_opportunity", value: "Risk & Opportunity", comment: "")
        case "action_plan":
            return NSLocalizedString("reports.passive.action_plan", value: "Action Plan", comment: "")
        default:
            return reportType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // Icon for report type
    var icon: String {
        switch reportType {
        case "executive_summary": return "doc.text.fill"
        case "academic_performance": return "graduationcap.fill"
        case "learning_behavior": return "chart.bar.fill"
        case "motivation_emotional": return "heart.fill"
        case "progress_trajectory": return "arrow.up.right"
        case "social_learning": return "person.3.fill"
        case "risk_opportunity": return "exclamationmark.triangle.fill"
        case "action_plan": return "list.bullet.clipboard.fill"
        default: return "doc.fill"
        }
    }

    // Color for report type
    var color: Color {
        switch reportType {
        case "executive_summary": return .blue
        case "academic_performance": return .purple
        case "learning_behavior": return .green
        case "motivation_emotional": return .pink
        case "progress_trajectory": return .orange
        case "social_learning": return .cyan
        case "risk_opportunity": return .red
        case "action_plan": return .indigo
        default: return .gray
        }
    }
}

struct ReportRecommendation: Codable {
    let priority: String
    let category: String
    let title: String
    let description: String
}

struct VisualData: Codable {
    let accuracyTrend: [Double]?
    let subjectBreakdown: [String: PassiveSubjectMetrics]?
    let weeklyActivity: [Int]?
}

struct PassiveSubjectMetrics: Codable {
    let totalQuestions: Int
    let correctAnswers: Int
    let accuracy: Double
}

struct BatchDetailResponse: Codable {
    let success: Bool
    let batch: PassiveReportBatch
    let reports: [PassiveReport]
}

// MARK: - ViewModel

@MainActor
class PassiveReportsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var weeklyBatches: [PassiveReportBatch] = []
    @Published var monthlyBatches: [PassiveReportBatch] = []
    @Published var selectedBatch: PassiveReportBatch?
    @Published var detailedReports: [PassiveReport] = []

    @Published var isLoadingBatches = false
    @Published var isLoadingDetails = false
    @Published var isGenerating = false

    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: - Private Properties

    private let networkService = NetworkService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Public Methods

    /// Load all report batches (both weekly and monthly)
    func loadAllBatches() async {
        // Skip if already loading to prevent cancellation errors on pull-to-refresh
        guard !isLoadingBatches else {
            print("⚠️ [PassiveReports] Already loading batches, skipping duplicate request")
            return
        }

        isLoadingBatches = true
        errorMessage = nil

        do {
            // Load weekly and monthly in parallel
            async let weekly = loadBatches(period: "weekly")
            async let monthly = loadBatches(period: "monthly")

            let (weeklyResult, monthlyResult) = try await (weekly, monthly)

            weeklyBatches = weeklyResult
            monthlyBatches = monthlyResult

            isLoadingBatches = false

        } catch {
            // Ignore cancellation errors from pull-to-refresh
            if (error as NSError).code == NSURLErrorCancelled {
                print("ℹ️ [PassiveReports] Request cancelled (likely pull-to-refresh)")
                isLoadingBatches = false
                return
            }
            isLoadingBatches = false
            errorMessage = error.localizedDescription
            showError = true
            print("❌ [PassiveReports] Failed to load batches: \(error)")
        }
    }

    /// Load batches for a specific period
    private func loadBatches(period: String) async throws -> [PassiveReportBatch] {
        let endpoint = "/api/reports/passive/batches?period=\(period)&limit=10&offset=0"

        guard let url = URL(string: "\(networkService.apiBaseURL)\(endpoint)") else {
            throw NSError(domain: "PassiveReportsViewModel", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add authentication
        let token = AuthenticationService.shared.getAuthToken()
        if let authToken = token {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "PassiveReportsViewModel", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            // Enhanced error handling for 401 (authentication issues)
            if httpResponse.statusCode == 401 {
                print("❌ [PassiveReports] Authentication failed (401)")
                print("   Token present: \(token != nil)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("   Server response: \(responseString)")
                }
                throw NSError(domain: "PassiveReportsViewModel", code: 401,
                             userInfo: [NSLocalizedDescriptionKey: "Authentication failed. Please log in again."])
            }

            throw NSError(domain: "PassiveReportsViewModel", code: httpResponse.statusCode,
                         userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let batchesResponse = try decoder.decode(BatchesResponse.self, from: data)
        return batchesResponse.batches
    }

    /// Load detailed reports for a specific batch
    func loadBatchDetails(batchId: String) async {
        isLoadingDetails = true
        errorMessage = nil

        do {
            let endpoint = "/api/reports/passive/batches/\(batchId)"

            guard let url = URL(string: "\(networkService.apiBaseURL)\(endpoint)") else {
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Add authentication
            if let token = AuthenticationService.shared.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "PassiveReportsViewModel", code: httpResponse.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"])
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let detailResponse = try decoder.decode(BatchDetailResponse.self, from: data)

            selectedBatch = detailResponse.batch
            detailedReports = detailResponse.reports

            isLoadingDetails = false

        } catch {
            isLoadingDetails = false
            errorMessage = error.localizedDescription
            showError = true
            print("❌ [PassiveReports] Failed to load batch details: \(error)")
        }
    }

    /// Manually trigger report generation (TESTING ONLY - will be removed)
    func triggerManualGeneration(period: String) async {
        isGenerating = true
        errorMessage = nil

        do {
            let endpoint = "/api/reports/passive/generate-now"

            guard let url = URL(string: "\(networkService.apiBaseURL)\(endpoint)") else {
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Add authentication
            let token = AuthenticationService.shared.getAuthToken()
            if let authToken = token {
                request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            }

            let requestBody: [String: Any] = [
                "period": period
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            // Extended timeout for report generation (can take 100+ seconds)
            request.timeoutInterval = 180.0  // 3 minutes

            print("🧪 [PassiveReports] Triggering report generation for period: \(period)")
            print("🧪 [PassiveReports] Endpoint: \(endpoint)")
            print("🧪 [PassiveReports] Auth token: \(token != nil ? "✅ Present" : "❌ Missing")")
            print("🧪 [PassiveReports] Timeout: 180 seconds")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            print("🧪 [PassiveReports] Response status: \(httpResponse.statusCode)")

            // Print full response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("🧪 [PassiveReports] Response body: \(responseString.prefix(500))...")
            }

            guard httpResponse.statusCode == 200 else {
                print("❌ [PassiveReports] Generation failed with status \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("❌ [PassiveReports] Error details: \(responseString)")
                }
                throw NSError(domain: "PassiveReportsViewModel", code: httpResponse.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"])
            }

            let result = try JSONDecoder().decode(GenerationResponse.self, from: data)

            isGenerating = false

            print("✅ [PassiveReports] Manual generation complete: \(result.reportCount) reports in \(result.generationTimeMs)ms")
            print("✅ [PassiveReports] Batch ID: \(result.batchId)")
            print("🔄 [PassiveReports] Reloading batches to show new report...")

            // Reload batches to show new report
            await loadAllBatches()

        } catch {
            isGenerating = false
            errorMessage = error.localizedDescription
            showError = true
            print("❌ [PassiveReports] Manual generation failed: \(error)")
            print("❌ [PassiveReports] Error details: \(error.localizedDescription)")
        }
    }

    /// Delete a report batch
    func deleteBatch(_ batch: PassiveReportBatch) async {
        do {
            let endpoint = "/api/reports/passive/batches/\(batch.id)"

            guard let url = URL(string: "\(networkService.apiBaseURL)\(endpoint)") else {
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Add authentication
            if let token = AuthenticationService.shared.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "PassiveReportsViewModel", code: httpResponse.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: "Failed to delete report"])
            }

            // Remove from local arrays
            if batch.period.lowercased() == "weekly" {
                weeklyBatches.removeAll { $0.id == batch.id }
            } else {
                monthlyBatches.removeAll { $0.id == batch.id }
            }

            print("✅ [PassiveReports] Successfully deleted batch \(batch.id)")

        } catch {
            errorMessage = "Failed to delete report: \(error.localizedDescription)"
            showError = true
            print("❌ [PassiveReports] Failed to delete batch: \(error)")
        }
    }
}

// MARK: - Response Models

struct BatchesResponse: Codable {
    let success: Bool
    let batches: [PassiveReportBatch]
    let pagination: Pagination
}

struct Pagination: Codable {
    let total: Int
    let limit: Int
    let offset: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case total
        case limit
        case offset
        case hasMore = "has_more"
    }
}

struct GenerationResponse: Codable {
    let success: Bool
    let message: String
    let batchId: String
    let reportCount: Int
    let generationTimeMs: Int
    let period: String

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case batchId = "batch_id"
        case reportCount = "report_count"
        case generationTimeMs = "generation_time_ms"
        case period
    }
}
