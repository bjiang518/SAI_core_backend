//
//  RateLimitManager.swift
//  StudyAI
//
//  Rate limit tracking and UI feedback
//

import Foundation
import Combine

/// Rate limit information for different endpoints
struct RateLimitInfo {
    let maxRequests: Int
    let remaining: Int
    let resetTime: Date?
    let endpoint: RateLimitEndpoint

    var percentageUsed: Double {
        guard maxRequests > 0 else { return 0 }
        return Double(maxRequests - remaining) / Double(maxRequests)
    }

    var isApproachingLimit: Bool {
        return remaining <= maxRequests / 4  // 75% used
    }

    var isAtLimit: Bool {
        return remaining <= 0
    }

    var timeUntilReset: TimeInterval? {
        guard let resetTime = resetTime else { return nil }
        return resetTime.timeIntervalSinceNow
    }
}

/// Supported rate-limited endpoints
enum RateLimitEndpoint: String {
    case homeworkImage = "process-homework-image"
    case batchImage = "process-homework-images-batch"
    case question = "process-question"
    case practice = "generate-practice"

    var displayName: String {
        switch self {
        case .homeworkImage:
            return "Homework Scans"
        case .batchImage:
            return "Batch Scans"
        case .question:
            return "Questions"
        case .practice:
            return "Practice Generation"
        }
    }

    var defaultLimit: Int {
        switch self {
        case .homeworkImage:
            return 10  // 10 per hour
        case .batchImage:
            return 5   // 5 per hour
        case .question:
            return 20  // 20 per hour
        case .practice:
            return 10  // 10 per hour
        }
    }
}

/// Manager for tracking and displaying rate limits
class RateLimitManager: ObservableObject {
    static let shared = RateLimitManager()

    @Published var rateLimits: [RateLimitEndpoint: RateLimitInfo] = [:]
    @Published var showWarning: Bool = false

    private let logger = AppLogger(category: "RateLimitManager")

    private init() {}

    /// Parse rate limit headers from HTTP response
    func updateFromHeaders(_ response: HTTPURLResponse, endpoint: RateLimitEndpoint) {
        let maxRequests = extractHeader(response, key: "X-RateLimit-Limit") ?? endpoint.defaultLimit
        let remaining = extractHeader(response, key: "X-RateLimit-Remaining") ?? maxRequests
        let resetTimestamp = extractHeader(response, key: "X-RateLimit-Reset")

        let resetTime: Date? = {
            if let timestamp = resetTimestamp {
                return Date(timeIntervalSince1970: TimeInterval(timestamp))
            }
            return nil
        }()

        let info = RateLimitInfo(
            maxRequests: maxRequests,
            remaining: remaining,
            resetTime: resetTime,
            endpoint: endpoint
        )

        DispatchQueue.main.async {
            self.rateLimits[endpoint] = info

            // Show warning if approaching limit
            if info.isApproachingLimit {
                self.showWarning = true
                self.logger.warning("Approaching rate limit for \(endpoint.displayName): \(info.remaining)/\(info.maxRequests) remaining")
            }

            // Log if at limit
            if info.isAtLimit {
                self.logger.error("Rate limit reached for \(endpoint.displayName)")
            }
        }
    }

    /// Get rate limit info for an endpoint
    func getLimit(for endpoint: RateLimitEndpoint) -> RateLimitInfo? {
        return rateLimits[endpoint]
    }

    /// Check if can make request (returns false if at limit)
    func canMakeRequest(to endpoint: RateLimitEndpoint) -> Bool {
        guard let info = rateLimits[endpoint] else {
            return true  // No limit info = assume can make request
        }
        return !info.isAtLimit
    }

    private func extractHeader(_ response: HTTPURLResponse, key: String) -> Int? {
        guard let value = response.value(forHTTPHeaderField: key) else {
            return nil
        }
        return Int(value)
    }

    /// Reset tracking (for testing or manual reset)
    func reset() {
        DispatchQueue.main.async {
            self.rateLimits.removeAll()
            self.showWarning = false
        }
    }
}

/// SwiftUI view for displaying rate limit status
import SwiftUI

struct RateLimitBadge: View {
    let info: RateLimitInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .font(.caption)
                .foregroundColor(badgeColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(info.remaining) left")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(badgeColor)

                if let timeUntil = info.timeUntilReset, timeUntil > 0 {
                    Text("Resets in \(formatTimeInterval(timeUntil))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(badgeColor.opacity(0.1))
        .cornerRadius(8)
    }

    private var badgeColor: Color {
        if info.isAtLimit {
            return .red
        } else if info.isApproachingLimit {
            return .orange
        } else {
            return .green
        }
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

/// Full rate limit warning banner
struct RateLimitWarningBanner: View {
    let info: RateLimitInfo
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Approaching usage limit")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("You have \(info.remaining) \(info.endpoint.displayName.lowercased()) remaining this hour")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let timeUntil = info.timeUntilReset, timeUntil > 0 {
                        Text("Limit resets in \(formatTimeInterval(timeUntil))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)

                    Rectangle()
                        .fill(progressColor)
                        .frame(width: geometry.size.width * CGFloat(info.percentageUsed), height: 6)
                        .cornerRadius(3)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var progressColor: Color {
        if info.isAtLimit {
            return .red
        } else if info.isApproachingLimit {
            return .orange
        } else {
            return .green
        }
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let remainingMinutes = Int(interval) % 60
        return "\(minutes):\(String(format: "%02d", remainingMinutes))"
    }
}

// MARK: - Usage Examples
/*
 // In DirectAIHomeworkView or similar:
 @StateObject private var rateLimitManager = RateLimitManager.shared

 var body: some View {
     VStack {
         // Show rate limit badge
         if let info = rateLimitManager.getLimit(for: .homeworkImage) {
             RateLimitBadge(info: info)
                 .padding()
         }

         // Show warning banner when approaching limit
         if rateLimitManager.showWarning,
            let info = rateLimitManager.getLimit(for: .homeworkImage) {
             RateLimitWarningBanner(info: info) {
                 rateLimitManager.showWarning = false
             }
             .padding()
         }

         // Your content here
     }
 }

 // In NetworkService, after receiving response:
 if let httpResponse = response as? HTTPURLResponse {
     RateLimitManager.shared.updateFromHeaders(httpResponse, endpoint: .homeworkImage)
 }
 */
