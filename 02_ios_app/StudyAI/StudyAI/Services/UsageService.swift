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

    private init() {}

    func update(feature: String, remaining: Int) {
        DispatchQueue.main.async {
            self.remainingUsage[feature] = remaining
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
}
