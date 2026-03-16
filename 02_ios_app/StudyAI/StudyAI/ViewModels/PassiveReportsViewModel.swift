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

    // Computed property for display name (4 report types)
    var displayName: String {
        switch reportType {
        case "activity":
            return NSLocalizedString("reports.passive.activity", value: "Activity Report", comment: "")
        case "areas_of_improvement":
            return NSLocalizedString("reports.passive.areas_of_improvement", value: "Areas for Improvement", comment: "")
        case "mental_health":
            return NSLocalizedString("reports.passive.mental_health", value: "Mental Health & Wellbeing", comment: "")
        case "summary":
            return NSLocalizedString("reports.passive.summary", value: "Weekly/Monthly Summary", comment: "")
        default:
            return reportType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // Icon for report type (4 report types)
    var icon: String {
        switch reportType {
        case "activity": return "chart.bar.fill"
        case "areas_of_improvement": return "exclamationmark.triangle.fill"
        case "mental_health": return "heart.fill"
        case "summary": return "doc.text.fill"
        default: return "doc.fill"
        }
    }

    // Color for report type (4 report types)
    var color: Color {
        switch reportType {
        case "activity": return .blue
        case "areas_of_improvement": return .orange
        case "mental_health": return .pink
        case "summary": return .green
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

/// Refresh Coordinator to prevent race conditions
@MainActor
class RefreshCoordinator {
    private var lastRefreshTime: Date?
    private var isRefreshing = false
    private let minimumRefreshInterval: TimeInterval = 2.0 // Don't refresh more than once per 2 seconds

    func shouldRefresh() -> Bool {
        // Don't start new refresh if one is in progress
        guard !isRefreshing else {
            debugPrint("⚠️ [RefreshCoordinator] Already refreshing, skipping")
            return false
        }

        // Debounce: Don't refresh if we just refreshed recently
        if let lastRefresh = lastRefreshTime {
            let timeSinceLastRefresh = Date().timeIntervalSince(lastRefresh)
            if timeSinceLastRefresh < minimumRefreshInterval {
                debugPrint("⚠️ [RefreshCoordinator] Debouncing: \(String(format: "%.1f", timeSinceLastRefresh))s since last refresh (min: \(minimumRefreshInterval)s)")
                debugPrint("   Last refresh was at: \(lastRefresh)")
                debugPrint("   Current time: \(Date())")
                return false
            }
        }

        return true
    }

    func startRefresh() {
        isRefreshing = true
        lastRefreshTime = Date()
        debugPrint("🔄 [RefreshCoordinator] Refresh started at: \(Date())")
    }

    func endRefresh() {
        isRefreshing = false
        debugPrint("✅ [RefreshCoordinator] Refresh completed at: \(Date())")
    }

    func forceRefresh() {
        // Reset state to allow immediate refresh
        debugPrint("🔓 [RefreshCoordinator] Force refresh - resetting state")
        debugPrint("   Previous lastRefreshTime: \(lastRefreshTime?.description ?? "nil")")
        debugPrint("   Previous isRefreshing: \(isRefreshing)")
        isRefreshing = false
        lastRefreshTime = nil
        debugPrint("   State reset complete - next refresh will proceed immediately")
    }
}

@MainActor
class PassiveReportsViewModel: ObservableObject {
    // MARK: - Published Properties

    @AppStorage("appLanguage") private var appLanguage: String = "en"

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
    private let notificationService = NotificationService.shared
    private let reportChecker = ReportAvailabilityChecker.shared
    private var cancellables = Set<AnyCancellable>()
    private let refreshCoordinator = RefreshCoordinator() // Prevent race conditions

    // Request deduplication: Cache in-flight requests to prevent duplicate network calls
    private var inFlightRequests: [String: Task<[PassiveReportBatch], Error>] = [:]

    // MARK: - Public Methods

    /// Start background report checking (call when user logs in or app starts)
    func startReportMonitoring() {
        debugPrint("📊 [PassiveReports] Starting report monitoring")
        reportChecker.startPeriodicChecking()
    }

    /// Stop background report checking (call when user logs out)
    func stopReportMonitoring() {
        debugPrint("📊 [PassiveReports] Stopping report monitoring")
        reportChecker.stopPeriodicChecking()
    }

    /// Check for new reports immediately (call when app comes to foreground)
    func checkForNewReportsNow() async {
        await reportChecker.checkForNewReports()
    }

    /// Load all report batches (both weekly and monthly) with race condition prevention
    func loadAllBatches() async {
        // Check if we should refresh (debouncing + in-progress check)
        guard refreshCoordinator.shouldRefresh() else {
            debugPrint("⚠️ [PassiveReports] Skipping loadAllBatches - already in progress or too soon")
            return
        }

        debugPrint("🔄 [PassiveReports] loadAllBatches() called - fetching weekly and monthly batches")
        debugPrint("   Current state: weeklyBatches=\(weeklyBatches.count), monthlyBatches=\(monthlyBatches.count)")

        refreshCoordinator.startRefresh()
        isLoadingBatches = true
        errorMessage = nil

        do {
            // Load weekly and monthly in parallel
            async let weekly = loadBatches(period: "weekly")
            async let monthly = loadBatches(period: "monthly")

            let (weeklyResult, monthlyResult) = try await (weekly, monthly)

            debugPrint("✅ [PassiveReports] Fetch complete:")
            debugPrint("   Weekly batches fetched: \(weeklyResult.count)")
            if !weeklyResult.isEmpty {
                debugPrint("   Most recent weekly: \(weeklyResult[0].startDate) to \(weeklyResult[0].endDate)")
            }
            debugPrint("   Monthly batches fetched: \(monthlyResult.count)")
            if !monthlyResult.isEmpty {
                debugPrint("   Most recent monthly: \(monthlyResult[0].startDate) to \(monthlyResult[0].endDate)")
            }

            weeklyBatches = weeklyResult
            monthlyBatches = monthlyResult

            isLoadingBatches = false
            refreshCoordinator.endRefresh()

            debugPrint("✅ [PassiveReports] State updated: weeklyBatches=\(weeklyBatches.count), monthlyBatches=\(monthlyBatches.count)")

        } catch {
            // Ignore cancellation errors from pull-to-refresh
            if (error as NSError).code == NSURLErrorCancelled {
                debugPrint("ℹ️ [PassiveReports] Request cancelled (likely pull-to-refresh)")
                isLoadingBatches = false
                refreshCoordinator.endRefresh()
                return
            }
            isLoadingBatches = false
            refreshCoordinator.endRefresh()
            errorMessage = error.localizedDescription
            showError = true
            debugPrint("❌ [PassiveReports] Failed to load batches: \(error)")
        }
    }

    /// Load batches for a specific period with request deduplication
    private func loadBatches(period: String) async throws -> [PassiveReportBatch] {
        debugPrint("📥 [LOAD-BATCHES] ===== STARTING BATCH LOAD =====")
        debugPrint("   Period: \(period)")
        debugPrint("   Timestamp: \(Date())")

        // Check if there's already a request in flight for this period
        if let existingTask = inFlightRequests[period] {
            debugPrint("♻️ [LOAD-BATCHES] Reusing in-flight request for period: \(period)")
            return try await existingTask.value
        }

        // Create new task
        let task = Task<[PassiveReportBatch], Error> {
            let endpoint = "/api/reports/passive/batches?period=\(period)&limit=10&offset=0"
            debugPrint("🌐 [LOAD-BATCHES] Building request:")
            debugPrint("   Endpoint: \(endpoint)")

            guard let url = URL(string: "\(networkService.apiBaseURL)\(endpoint)") else {
                debugPrint("❌ [LOAD-BATCHES] Invalid URL")
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            debugPrint("   Full URL: \(url.absoluteString)")

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15.0 // 15 second timeout

            // Add authentication
            let token = AuthenticationService.shared.getAuthToken()
            if let authToken = token {
                request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
                debugPrint("   Auth: ✅ Token present (length: \(authToken.count))")
            } else {
                debugPrint("   Auth: ❌ No token found")
            }

            debugPrint("🚀 [LOAD-BATCHES] Sending request...")
            let requestStartTime = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            let requestDuration = Date().timeIntervalSince(requestStartTime)
            debugPrint("📦 [LOAD-BATCHES] Response received in \(String(format: "%.2f", requestDuration))s")

            guard let httpResponse = response as? HTTPURLResponse else {
                debugPrint("❌ [LOAD-BATCHES] Invalid response type")
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            debugPrint("📊 [LOAD-BATCHES] HTTP Response:")
            debugPrint("   Status Code: \(httpResponse.statusCode)")
            debugPrint("   Data size: \(data.count) bytes")

            guard httpResponse.statusCode == 200 else {
                // Enhanced error handling for 401 (authentication issues)
                if httpResponse.statusCode == 401 {
                    debugPrint("❌ [LOAD-BATCHES] Authentication failed (401)")
                    debugPrint("   Token present: \(token != nil)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        debugPrint("   Server response: \(responseString)")
                    }
                    throw NSError(domain: "PassiveReportsViewModel", code: 401,
                                 userInfo: [NSLocalizedDescriptionKey: "Authentication failed. Please log in again."])
                }

                debugPrint("❌ [LOAD-BATCHES] Server error: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    debugPrint("   Response body: \(responseString.prefix(200))...")
                }
                throw NSError(domain: "PassiveReportsViewModel", code: httpResponse.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"])
            }

            debugPrint("🔍 [LOAD-BATCHES] Decoding JSON response...")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let batchesResponse = try decoder.decode(BatchesResponse.self, from: data)
            debugPrint("✅ [LOAD-BATCHES] Successfully decoded \(batchesResponse.batches.count) batches")

            // Log each batch
            for (index, batch) in batchesResponse.batches.enumerated() {
                debugPrint("   [\(index + 1)] ID: \(batch.id.prefix(13))...")
                debugPrint("       Period: \(batch.period)")
                debugPrint("       Dates: \(batch.startDate) to \(batch.endDate)")
                debugPrint("       Status: \(batch.status)")
                debugPrint("       Reports: \(batch.reportCount ?? 0)")
            }

            debugPrint("✅ [LOAD-BATCHES] ===== BATCH LOAD COMPLETE =====")
            return batchesResponse.batches
        }

        // Store task in in-flight dictionary
        inFlightRequests[period] = task

        // Clean up after completion
        defer {
            inFlightRequests.removeValue(forKey: period)
            debugPrint("🧹 [PassiveReports] Cleaned up in-flight request for period: \(period)")
        }

        return try await task.value
    }

    /// Load detailed reports for a specific batch
    func loadBatchDetails(batchId: String) async {
        debugPrint("📖 [BATCH-DETAIL] ===== LOADING BATCH DETAILS =====")
        debugPrint("   Batch ID: \(batchId)")
        debugPrint("   Timestamp: \(Date())")

        isLoadingDetails = true
        errorMessage = nil

        do {
            let endpoint = "/api/reports/passive/batches/\(batchId)"
            debugPrint("🌐 [BATCH-DETAIL] Building request:")
            debugPrint("   Endpoint: \(endpoint)")

            guard let url = URL(string: "\(networkService.apiBaseURL)\(endpoint)") else {
                debugPrint("❌ [BATCH-DETAIL] Invalid URL")
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            debugPrint("   Full URL: \(url.absoluteString)")

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Add authentication
            let token = AuthenticationService.shared.getAuthToken()
            if let authToken = token {
                request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
                debugPrint("   Auth: ✅ Token present (length: \(authToken.count))")
            } else {
                debugPrint("   Auth: ❌ No token found")
            }

            debugPrint("🚀 [BATCH-DETAIL] Sending request...")
            let requestStartTime = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            let requestDuration = Date().timeIntervalSince(requestStartTime)
            debugPrint("📦 [BATCH-DETAIL] Response received in \(String(format: "%.2f", requestDuration))s")

            guard let httpResponse = response as? HTTPURLResponse else {
                debugPrint("❌ [BATCH-DETAIL] Invalid response type")
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            debugPrint("📊 [BATCH-DETAIL] HTTP Response:")
            debugPrint("   Status Code: \(httpResponse.statusCode)")
            debugPrint("   Data size: \(data.count) bytes")

            guard httpResponse.statusCode == 200 else {
                debugPrint("❌ [BATCH-DETAIL] Server error: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    debugPrint("   Response body: \(responseString.prefix(200))...")
                }
                throw NSError(domain: "PassiveReportsViewModel", code: httpResponse.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"])
            }

            debugPrint("🔍 [BATCH-DETAIL] Decoding JSON response...")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let detailResponse = try decoder.decode(BatchDetailResponse.self, from: data)
            debugPrint("✅ [BATCH-DETAIL] Successfully decoded response")
            debugPrint("   Batch Period: \(detailResponse.batch.period)")
            debugPrint("   Batch Dates: \(detailResponse.batch.startDate) to \(detailResponse.batch.endDate)")
            debugPrint("   Reports Count: \(detailResponse.reports.count)")

            // Log each report
            for (index, report) in detailResponse.reports.enumerated() {
                debugPrint("   [\(index + 1)] Type: \(report.reportType)")
                debugPrint("       Content length: \(report.narrativeContent.count) chars")
                debugPrint("       Word count: \(report.wordCount ?? 0)")
            }

            selectedBatch = detailResponse.batch
            detailedReports = detailResponse.reports

            isLoadingDetails = false
            debugPrint("✅ [BATCH-DETAIL] ===== BATCH DETAILS LOADED =====")

        } catch {
            isLoadingDetails = false
            errorMessage = error.localizedDescription
            showError = true
            debugPrint("❌ [BATCH-DETAIL] Failed to load batch details: \(error)")
            debugPrint("   Error type: \(type(of: error))")
            debugPrint("   Localized description: \(error.localizedDescription)")
        }
    }

    /// Manually trigger report generation (TESTING ONLY - will be removed)
    func triggerManualGeneration(period: String) async {
        isGenerating = true
        errorMessage = nil

        // CRITICAL: Validate token before starting
        debugPrint("🔐 [PassiveReports] Validating authentication token...")
        if !AuthenticationService.shared.isTokenValid() {
            debugPrint("❌ [PassiveReports] Token validation FAILED - cannot generate report")
            debugPrint("   Token is either missing, corrupted, or expired")
            isGenerating = false
            errorMessage = "Your session is invalid. Please log in again."
            showError = true
            return
        }
        debugPrint("✅ [PassiveReports] Token validation passed")

        // CRITICAL: Sync local data to server BEFORE generating report
        // This ensures all locally-stored questions and conversations are uploaded
        // User has agreed to this sync requirement during onboarding
        debugPrint("🔄 [PassiveReports] ===== SYNCING LOCAL DATA TO SERVER =====")
        debugPrint("   Syncing questions, conversations, and progress data...")
        do {
            let syncResult = try await StorageSyncService.shared.syncAllToServer()
            debugPrint("✅ [PassiveReports] Sync completed successfully")
            debugPrint("   Questions: \(syncResult.questionsSynced) synced, \(syncResult.questionsDuplicates) duplicates")
            debugPrint("   Conversations: \(syncResult.conversationsSynced) synced, \(syncResult.conversationsDuplicates) duplicates")
            debugPrint("   Progress: \(syncResult.progressSynced ? "synced" : "skipped")")
            debugPrint("   Total synced: \(syncResult.totalSynced) items")

            if !syncResult.isSuccess {
                debugPrint("⚠️ [PassiveReports] Sync completed with errors:")
                syncResult.errors.forEach { debugPrint("   - \($0)") }
            }
        } catch {
            debugPrint("❌ [PassiveReports] Sync failed: \(error.localizedDescription)")
            debugPrint("   Proceeding with report generation using existing server data")
            // Don't block report generation - user might have already synced manually
        }
        debugPrint("🔄 [PassiveReports] ===== SYNC COMPLETE ======")

        // IMPORTANT: Ensure token is fresh before long operation (can take 100+ seconds)
        await AuthenticationService.shared.ensureTokenFreshForLongOperation(
            operationName: "report generation (\(period))",
            minimumRemainingTime: 300 // 5 minutes
        )

        // Re-validate after refresh attempt (in case refresh failed or cleared token)
        debugPrint("🔐 [PassiveReports] Re-validating token after refresh check...")
        if !AuthenticationService.shared.isTokenValid() {
            debugPrint("❌ [PassiveReports] Token still invalid after refresh attempt")
            debugPrint("   User may have been logged out due to corrupted token")
            isGenerating = false
            errorMessage = "Unable to refresh your session. Please log in again."
            showError = true
            return
        }
        debugPrint("✅ [PassiveReports] Token still valid after refresh check")

        do {
            let endpoint = "/api/reports/passive/generate-now"

            guard let url = URL(string: "\(networkService.apiBaseURL)\(endpoint)") else {
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Add authentication (token should now be fresh)
            let token = AuthenticationService.shared.getAuthToken()
            if let authToken = token {
                request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            }

            let requestBody: [String: Any] = [
                "period": period,
                "language": appLanguage
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            // Extended timeout for report generation (can take 100+ seconds)
            request.timeoutInterval = 180.0  // 3 minutes

            debugPrint("🧪 [PassiveReports] Triggering report generation for period: \(period)")
            debugPrint("🧪 [PassiveReports] Endpoint: \(endpoint)")
            debugPrint("🧪 [PassiveReports] Auth token: \(token != nil ? "✅ Present (refreshed if needed)" : "❌ Missing")")
            debugPrint("🧪 [PassiveReports] Timeout: 180 seconds")

            // CRITICAL: Ensure refresh happens even if there are errors
            var shouldRefresh = false
            defer {
                if shouldRefresh {
                    debugPrint("🔄 [PassiveReports] DEFER: Triggering refresh after generation attempt")
                    Task {
                        debugPrint("🔄 [PassiveReports] DEFER: Forcing refresh coordinator to bypass debounce...")
                        refreshCoordinator.forceRefresh()
                        debugPrint("🔄 [PassiveReports] DEFER: Loading all batches...")
                        await loadAllBatches()
                        debugPrint("✅ [PassiveReports] DEFER: Post-generation refresh complete")
                        debugPrint("   Weekly batches: \(weeklyBatches.count)")
                        debugPrint("   Monthly batches: \(monthlyBatches.count)")
                    }
                }
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            debugPrint("📥 [PassiveReports] Response received from server")
            debugPrint("   Response time: ~\((Date().timeIntervalSince1970 * 1000).rounded())ms since request")

            // CRITICAL: Set flag to trigger refresh in defer block
            // This ensures refresh happens even if JSON parsing fails
            shouldRefresh = true
            debugPrint("✅ [PassiveReports] Refresh flag set - defer block will execute refresh")

            guard let httpResponse = response as? HTTPURLResponse else {
                debugPrint("❌ [PassiveReports] Invalid response type")
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            debugPrint("🧪 [PassiveReports] Response status: \(httpResponse.statusCode)")

            // Print full response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                debugPrint("🧪 [PassiveReports] Response body: \(responseString.prefix(500))...")
            }

            guard httpResponse.statusCode == 200 else {
                debugPrint("❌ [PassiveReports] Generation failed with status \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    debugPrint("❌ [PassiveReports] Error details: \(responseString)")
                }
                throw NSError(domain: "PassiveReportsViewModel", code: httpResponse.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"])
            }

            debugPrint("🔍 [PassiveReports] Parsing JSON response...")
            let result = try JSONDecoder().decode(GenerationResponse.self, from: data)
            debugPrint("✅ [PassiveReports] JSON decoded successfully")
            debugPrint("   Batch ID: \(result.batchId)")
            debugPrint("   Report count: \(result.reportCount)")
            debugPrint("   Generation time: \(result.generationTimeMs)ms")

            isGenerating = false

            debugPrint("✅ [PassiveReports] Manual generation complete: \(result.reportCount) reports in \(result.generationTimeMs)ms")
            debugPrint("✅ [PassiveReports] Batch ID: \(result.batchId)")
            debugPrint("🔄 [PassiveReports] EXPLICIT refresh (defer will be skipped)...")

            // Disable defer refresh since we're doing explicit refresh
            shouldRefresh = false

            // CRITICAL FIX: Force refresh BEFORE sending notification
            // The notification will trigger another loadAllBatches() call from the View
            // We need to ensure the debounce timer is reset so both calls succeed
            debugPrint("🔄 [PassiveReports] Forcing refresh coordinator to bypass debounce...")
            refreshCoordinator.forceRefresh() // Reset lastRefreshTime and isRefreshing flag

            // Send notification for new report (this may trigger view to call loadAllBatches)
            notificationService.sendParentReportAvailableNotification(
                period: period,
                reportCount: result.reportCount,
                overallGrade: nil
            )

            // Reload batches to show new report
            debugPrint("🔄 [PassiveReports] Loading all batches...")
            await loadAllBatches()

            debugPrint("✅ [PassiveReports] Explicit refresh complete")
            debugPrint("   Weekly batches: \(weeklyBatches.count)")
            debugPrint("   Monthly batches: \(monthlyBatches.count)")

            if weeklyBatches.isEmpty && monthlyBatches.isEmpty {
                debugPrint("⚠️ [PassiveReports] WARNING: No batches loaded after generation!")
                debugPrint("   Expected at least 1 batch for period: \(period)")
                debugPrint("   This might indicate a backend issue or query cache problem")
            }

        } catch {
            isGenerating = false
            errorMessage = error.localizedDescription
            showError = true
            debugPrint("❌ [PassiveReports] Manual generation failed: \(error)")
            debugPrint("❌ [PassiveReports] Error details: \(error.localizedDescription)")
        }
    }

    /// Delete a report batch with optimistic updates and rollback on failure
    func deleteBatch(_ batch: PassiveReportBatch) async {
        debugPrint("🗑️ [DELETE] ===== DELETE BATCH START =====")
        debugPrint("   Timestamp: \(Date())")
        debugPrint("   Batch ID: \(batch.id)")
        debugPrint("   Period: \(batch.period)")
        debugPrint("   Date Range: \(batch.startDate) to \(batch.endDate)")
        debugPrint("   Current weekly batches: \(weeklyBatches.count)")
        debugPrint("   Current monthly batches: \(monthlyBatches.count)")

        // CRITICAL: Stop background checker to prevent false "new report" notifications
        debugPrint("🛑 [DELETE] Stopping background report checker...")
        reportChecker.stopPeriodicChecking()
        debugPrint("   ✅ Report checker stopped")

        // OPTIMISTIC UPDATE: Save original state for rollback
        let originalWeeklyBatches = weeklyBatches
        let originalMonthlyBatches = monthlyBatches
        debugPrint("💾 [DELETE] Saved original state for rollback:")
        debugPrint("   Original weekly: \(originalWeeklyBatches.count)")
        debugPrint("   Original monthly: \(originalMonthlyBatches.count)")

        // Normalize period (case-insensitive comparison)
        let normalizedPeriod = batch.period.lowercased()
        let isWeekly = normalizedPeriod == "weekly"
        debugPrint("📊 [DELETE] Batch classification:")
        debugPrint("   Normalized period: \(normalizedPeriod)")
        debugPrint("   Is weekly: \(isWeekly)")

        // Remove from local arrays immediately (optimistic)
        debugPrint("🔄 [DELETE] Performing optimistic update...")
        if isWeekly {
            let beforeCount = weeklyBatches.count
            weeklyBatches.removeAll { $0.id == batch.id }
            debugPrint("   Weekly batches: \(beforeCount) → \(weeklyBatches.count)")
        } else {
            let beforeCount = monthlyBatches.count
            monthlyBatches.removeAll { $0.id == batch.id }
            debugPrint("   Monthly batches: \(beforeCount) → \(monthlyBatches.count)")
        }
        debugPrint("   ✅ Local state updated optimistically")

        do {
            let endpoint = "/api/reports/passive/batches/\(batch.id)"
            debugPrint("🌐 [DELETE] Building DELETE request:")
            debugPrint("   Endpoint: \(endpoint)")

            guard let url = URL(string: "\(networkService.apiBaseURL)\(endpoint)") else {
                debugPrint("❌ [DELETE] Invalid URL")
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
            }
            debugPrint("   Full URL: \(url.absoluteString)")

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.timeoutInterval = 10.0 // 10 second timeout for delete

            // Add authentication
            let token = AuthenticationService.shared.getAuthToken()
            if let authToken = token {
                request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
                debugPrint("   Auth: ✅ Token present (length: \(authToken.count))")
            } else {
                debugPrint("   Auth: ❌ No token - request will fail")
                throw NSError(domain: "PassiveReportsViewModel", code: 401,
                             userInfo: [NSLocalizedDescriptionKey: "No authentication token available"])
            }

            debugPrint("🚀 [DELETE] Sending DELETE request...")
            let requestStartTime = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            let requestDuration = Date().timeIntervalSince(requestStartTime)
            debugPrint("📦 [DELETE] Response received in \(String(format: "%.2f", requestDuration))s")

            guard let httpResponse = response as? HTTPURLResponse else {
                debugPrint("❌ [DELETE] Invalid response type")
                throw NSError(domain: "PassiveReportsViewModel", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }

            debugPrint("📊 [DELETE] HTTP Response:")
            debugPrint("   Status Code: \(httpResponse.statusCode)")
            debugPrint("   Data size: \(data.count) bytes")

            // Print response body for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                debugPrint("   Response body: \(responseString.prefix(200))")
            }

            guard httpResponse.statusCode == 200 else {
                debugPrint("❌ [DELETE] Server error: \(httpResponse.statusCode)")
                throw NSError(domain: "PassiveReportsViewModel", code: httpResponse.statusCode,
                             userInfo: [NSLocalizedDescriptionKey: "Server returned status \(httpResponse.statusCode)"])
            }

            debugPrint("✅ [DELETE] Successfully deleted batch from server")
            debugPrint("   Batch ID: \(batch.id)")
            debugPrint("   Local state already updated (optimistic)")

            // CRITICAL FIX: Wait 2 seconds before restarting checker
            // This prevents immediate "new report" notification if regeneration was triggered
            debugPrint("⏳ [DELETE] Waiting 2 seconds before restarting checker...")
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            debugPrint("   ✅ Wait complete")

            // CRITICAL FIX: Force refresh from server to get latest state
            // This ensures we have correct batch IDs if backend regenerated
            debugPrint("🔄 [DELETE] Force refreshing from server to sync state...")
            debugPrint("   Resetting debounce timer...")
            refreshCoordinator.forceRefresh() // Reset debounce timer
            debugPrint("   ✅ Debounce timer reset")
            debugPrint("   Loading all batches...")
            await loadAllBatches()
            debugPrint("   ✅ Batches reloaded")

            // Restart checker after refresh completes
            debugPrint("▶️ [DELETE] Restarting report checker...")
            reportChecker.startPeriodicChecking()
            debugPrint("   ✅ Report checker restarted")
            debugPrint("🗑️ [DELETE] ===== DELETE BATCH END (SUCCESS) =====")

        } catch {
            // ROLLBACK: Restore original state on failure
            debugPrint("❌ [DELETE] ===== DELETE BATCH FAILED - ROLLING BACK =====")
            debugPrint("   Error type: \(type(of: error))")
            debugPrint("   Error: \(error)")
            debugPrint("   Localized: \(error.localizedDescription)")

            debugPrint("🔄 [DELETE] Rolling back state...")
            weeklyBatches = originalWeeklyBatches
            monthlyBatches = originalMonthlyBatches

            debugPrint("   ✅ Rollback complete:")
            debugPrint("      Weekly batches restored: \(weeklyBatches.count)")
            debugPrint("      Monthly batches restored: \(monthlyBatches.count)")

            // Restart checker even after failure
            debugPrint("▶️ [DELETE] Restarting report checker after failure...")
            reportChecker.startPeriodicChecking()
            debugPrint("   ✅ Report checker restarted")

            errorMessage = "Failed to delete report: \(error.localizedDescription)"
            showError = true
            debugPrint("🗑️ [DELETE] ===== DELETE BATCH END (FAILED) =====")
        }
    }

    /// Delete multiple batches atomically
    func deleteBatches(_ batches: [PassiveReportBatch]) async -> (succeeded: Int, failed: Int) {
        debugPrint("🗑️ [PassiveReports] ===== BATCH DELETE START =====")
        debugPrint("   Batches to delete: \(batches.count)")

        var succeeded = 0
        var failed = 0

        // OPTIMISTIC UPDATE: Save original state
        let originalWeeklyBatches = weeklyBatches
        let originalMonthlyBatches = monthlyBatches

        // Remove all batches optimistically
        let batchIds = Set(batches.map { $0.id })
        weeklyBatches.removeAll { batchIds.contains($0.id) }
        monthlyBatches.removeAll { batchIds.contains($0.id) }

        debugPrint("🗑️ [PassiveReports] Optimistically removed \(batches.count) batches")

        // Attempt to delete each batch
        for batch in batches {
            do {
                try await performSingleDelete(batch.id)
                succeeded += 1
                debugPrint("✅ [PassiveReports] Deleted batch \(batch.id.prefix(8))...")
            } catch {
                failed += 1
                debugPrint("❌ [PassiveReports] Failed to delete batch \(batch.id.prefix(8))...: \(error.localizedDescription)")
            }
        }

        if failed > 0 {
            // PARTIAL ROLLBACK: Reload from server to get correct state
            debugPrint("⚠️ [PassiveReports] \(failed) deletions failed - reloading from server")
            errorMessage = "Deleted \(succeeded) reports, but \(failed) failed. Refreshing..."
            showError = true

            // Reload to ensure consistency
            await loadAllBatches()
        } else {
            debugPrint("✅ [PassiveReports] All \(succeeded) batches deleted successfully")
        }

        debugPrint("🗑️ [PassiveReports] ===== BATCH DELETE END =====")
        return (succeeded, failed)
    }

    /// Perform single DELETE request without state management
    private func performSingleDelete(_ batchId: String) async throws {
        let endpoint = "/api/reports/passive/batches/\(batchId)"

        guard let url = URL(string: "\(networkService.apiBaseURL)\(endpoint)") else {
            throw NSError(domain: "PassiveReportsViewModel", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 10.0

        if let authToken = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        } else {
            throw NSError(domain: "PassiveReportsViewModel", code: 401,
                         userInfo: [NSLocalizedDescriptionKey: "No authentication token"])
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "PassiveReportsViewModel", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        // Success case
        if httpResponse.statusCode == 200 {
            return
        }

        // Error case - parse error response for better messages
        var errorMessage = "Server returned status \(httpResponse.statusCode)"
        var errorCode = "UNKNOWN_ERROR"

        if let responseString = String(data: data, encoding: .utf8) {
            debugPrint("❌ [DELETE] Server error response: \(responseString)")

            // Try to parse JSON error response
            if let jsonData = responseString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                errorCode = json["code"] as? String ?? "UNKNOWN_ERROR"
                let serverMessage = json["error"] as? String ?? errorMessage

                // Provide user-friendly messages based on error code
                switch errorCode {
                case "BATCH_NOT_FOUND":
                    errorMessage = "This report was already deleted or doesn't exist."
                case "ACCESS_DENIED":
                    errorMessage = "You don't have permission to delete this report. It may belong to a different account."
                case "LOCK_CONFLICT":
                    errorMessage = "This report is being modified. Please try again in a moment."
                default:
                    errorMessage = serverMessage
                }

                debugPrint("❌ [DELETE] Error code: \(errorCode)")
                debugPrint("❌ [DELETE] User-friendly message: \(errorMessage)")
            }
        }

        throw NSError(
            domain: "PassiveReportsViewModel",
            code: httpResponse.statusCode,
            userInfo: [
                NSLocalizedDescriptionKey: errorMessage,
                "errorCode": errorCode
            ]
        )
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
