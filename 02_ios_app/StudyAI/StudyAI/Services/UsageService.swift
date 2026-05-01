//
//  UsageService.swift
//  StudyAI
//

import Foundation
import Combine

/// Reads X-Usage-Remaining response headers from AI endpoints.
/// NetworkService calls update(feature:remaining:) after each AI response.
/// Views observe remainingUsage to display "X uses left" badges.
class UsageService: ObservableObject {
    static let shared = UsageService()

    @Published var remainingUsage: [String: Int] = [:]
    @Published var limitReachedFeature: String? = nil
    @Published var limitReachedCode: String? = nil
    /// Set when a free-tier feature crosses the 80%-used threshold. HomeView observes this to show the upgrade sheet.
    @Published var nudgeFeature: String? = nil

    // Free-tier monthly limits — must stay in sync with usage-tracker.js
    private let freeLimits: [String: Int] = [
        "homework_pages": 5,
        "chat_messages":  20,
        "questions":      10,
        "error_analysis": 3,
    ]

    private init() {}

    func update(feature: String, remaining: Int) {
        DispatchQueue.main.async {
            self.remainingUsage[feature] = remaining
            self.checkNudge(feature: feature, remaining: remaining)
        }
    }

    /// Called when a 429/403 with a tier error code is received.
    func flagLimitReached(feature: String, errorCode: String) {
        DispatchQueue.main.async {
            self.limitReachedFeature = feature
            self.limitReachedCode = errorCode
        }
    }

    func clearLimitReached() {
        limitReachedFeature = nil
        limitReachedCode = nil
    }

    // MARK: - 80% nudge

    private func checkNudge(feature: String, remaining: Int) {
        guard
            let limit = freeLimits[feature],
            remaining > 0,                          // hard wall (0) handled separately
            Double(remaining) / Double(limit) <= 0.20
        else { return }

        let tier = AuthenticationService.shared.currentUser?.tier ?? .free
        guard !tier.isPaid else { return }

        let monthKey = nudgeMonthKey(feature)
        guard !UserDefaults.standard.bool(forKey: monthKey) else { return }
        UserDefaults.standard.set(true, forKey: monthKey)

        nudgeFeature = feature
    }

    private func nudgeMonthKey(_ feature: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return "usage_nudge_\(feature)_\(fmt.string(from: Date()))"
    }
}
