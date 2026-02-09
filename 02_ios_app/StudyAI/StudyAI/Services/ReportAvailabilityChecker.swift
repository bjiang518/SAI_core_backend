//
//  ReportAvailabilityChecker.swift
//  StudyAI
//
//  Background service to check for new parent reports and send notifications
//  Runs periodically to detect newly generated reports
//

import Foundation
import Combine
import SwiftUI

class ReportAvailabilityChecker: ObservableObject {

    static let shared = ReportAvailabilityChecker()

    // MARK: - Private Properties

    private var checkTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let notificationService = NotificationService.shared
    private let networkService = NetworkService.shared

    // Track last known batch IDs to detect new reports
    private var lastKnownBatchIds: Set<String> = []

    // Check interval (default: every 30 minutes)
    private let checkInterval: TimeInterval = 30 * 60

    // UserDefaults key for last check time
    private let lastCheckTimeKey = "com.studyai.lastReportCheckTime"

    // MARK: - Initialization

    private init() {
        loadLastKnownBatchIds()
    }

    // MARK: - Public Methods

    /// Start periodic checking for new reports
    func startPeriodicChecking() {
        print("📊 ReportAvailabilityChecker: Starting periodic checking (every \(Int(checkInterval / 60)) minutes)")

        // Check immediately on start
        Task {
            await checkForNewReports()
        }

        // Schedule periodic checks
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.checkForNewReports()
            }
        }
    }

    /// Stop periodic checking
    func stopPeriodicChecking() {
        print("📊 ReportAvailabilityChecker: Stopping periodic checking")
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Manually check for new reports (called when app comes to foreground)
    func checkForNewReports() async {
        print("📊 ReportAvailabilityChecker: Checking for new reports...")

        // Check if enough time has passed since last check (prevent spam)
        if !shouldCheckNow() {
            print("📊 ReportAvailabilityChecker: Skipping check (too soon since last check)")
            return
        }

        do {
            // Fetch latest batches
            let batches = try await fetchRecentBatches()

            // Check for new batches
            let newBatches = batches.filter { !lastKnownBatchIds.contains($0.id) }

            if !newBatches.isEmpty {
                print("📊 ReportAvailabilityChecker: Found \(newBatches.count) new report batch(es)")

                // Send notification for each new batch
                for batch in newBatches {
                    sendNotificationForBatch(batch)
                }

                // Update last known batch IDs
                lastKnownBatchIds.formUnion(batches.map { $0.id })
                saveLastKnownBatchIds()
            } else {
                print("📊 ReportAvailabilityChecker: No new reports found")
            }

            // Update last check time
            updateLastCheckTime()

        } catch {
            print("📊 ReportAvailabilityChecker: Failed to check for new reports: \(error)")
        }
    }

    // MARK: - Private Methods

    private func shouldCheckNow() -> Bool {
        guard let lastCheckTime = UserDefaults.standard.object(forKey: lastCheckTimeKey) as? Date else {
            return true // Never checked before
        }

        let timeSinceLastCheck = Date().timeIntervalSince(lastCheckTime)
        let minimumInterval: TimeInterval = 15 * 60 // Minimum 15 minutes between checks

        return timeSinceLastCheck >= minimumInterval
    }

    private func updateLastCheckTime() {
        UserDefaults.standard.set(Date(), forKey: lastCheckTimeKey)
    }

    private func fetchRecentBatches() async throws -> [ReportBatch] {
        let endpoint = "/api/reports/passive/batches?period=all&limit=5&offset=0"

        guard let url = URL(string: "\(networkService.apiBaseURL)\(endpoint)") else {
            throw NSError(domain: "ReportAvailabilityChecker", code: -1,
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

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "ReportAvailabilityChecker", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to fetch batches"])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Decode as anonymous struct matching backend response
        let batchesData = try decoder.decode(AnonymousBatchesResponse.self, from: data)
        return batchesData.batches.map { ReportBatch(passiveBatch: $0) }
    }

    private func sendNotificationForBatch(_ batch: ReportBatch) {
        print("📊 ReportAvailabilityChecker: Sending notification for \(batch.period) report")

        notificationService.sendParentReportAvailableNotification(
            period: batch.period,
            reportCount: batch.reportCount ?? 8,
            overallGrade: batch.overallGrade
        )
    }

    // MARK: - Persistence

    private func loadLastKnownBatchIds() {
        if let stored = UserDefaults.standard.stringArray(forKey: "com.studyai.lastKnownBatchIds") {
            lastKnownBatchIds = Set(stored)
            print("📊 ReportAvailabilityChecker: Loaded \(lastKnownBatchIds.count) known batch IDs")
        }
    }

    private func saveLastKnownBatchIds() {
        UserDefaults.standard.set(Array(lastKnownBatchIds), forKey: "com.studyai.lastKnownBatchIds")
        print("📊 ReportAvailabilityChecker: Saved \(lastKnownBatchIds.count) known batch IDs")
    }
}

// MARK: - Internal Models

private struct ReportBatch {
    let id: String
    let period: String
    let reportCount: Int?
    let overallGrade: String?

    init(passiveBatch: PassiveReportBatch) {
        self.id = passiveBatch.id
        self.period = passiveBatch.period
        self.reportCount = passiveBatch.reportCount
        self.overallGrade = passiveBatch.overallGrade
    }
}

// Local struct to avoid dependency on PassiveReportsViewModel
private struct AnonymousBatchesResponse: Codable {
    let success: Bool
    let batches: [PassiveReportBatch]
}
