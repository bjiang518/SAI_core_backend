//
//  ShortTermStatusModels.swift
//  StudyAI
//
//  Short-term status tracking with time-based weakness migration
//  Created by Claude Code on 1/25/25.
//

import Foundation
import SwiftUI

// MARK: - Short-Term Status (Active Weaknesses)

struct ShortTermStatus: Codable {
    var activeWeaknesses: [String: WeaknessValue] = [:]
    var lastUpdated: Date = Date()
}

struct WeaknessValue: Codable {
    var value: Double              // Current weakness intensity (0.0 = mastered)
    var firstDetected: Date        // When this key was first created
    var lastAttempt: Date          // Most recent attempt on this weakness
    var totalAttempts: Int         // Number of times attempted
    var correctAttempts: Int       // Number of correct attempts

    // ✅ FIX #2: Track recent error types for weighted decrement
    var recentErrorTypes: [String] = []  // Last 3 error types

    // Computed properties
    var accuracy: Double {
        guard totalAttempts > 0 else { return 0.0 }
        return Double(correctAttempts) / Double(totalAttempts)
    }

    var daysActive: Int {
        return Calendar.current.dateComponents([.day], from: firstDetected, to: Date()).day ?? 0
    }
}

// MARK: - Weakness Point Folder (Persistent Weaknesses)

struct WeaknessPointFolder: Codable {
    var weaknessPoints: [WeaknessPoint] = []
    var lastGenerationDate: Date?
}

struct WeaknessPoint: Codable, Identifiable {
    let id: UUID
    let originalKey: String                // "Math/algebra/calculation"
    var naturalLanguageDescription: String // AI-generated or fallback
    let severity: WeaknessSeverity

    // ✅ FIX #4: Track AI generation status
    var isAIGenerated: Bool = false
    var aiGenerationAttempts: Int = 0
    var aiGenerationFailedPermanently: Bool = false

    // Migration metadata
    let firstDetected: Date
    let migratedAt: Date
    let finalValue: Double                 // Value when migrated
    let attemptCount: Int
    let accuracyAtMigration: Double

    // Post-migration tracking
    var postMigrationAttempts: Int = 0
    var postMigrationCorrect: Int = 0
    var lastAttemptDate: Date?

    // ✅ FIX #6: Add consecutive tracking
    var currentConsecutiveCorrect: Int = 0
    var bestConsecutiveStreak: Int = 0

    // Removal tracking
    var removalCriteria: RemovalCriteria

    // Computed properties
    var postMigrationAccuracy: Double {
        guard postMigrationAttempts > 0 else { return 0.0 }
        return Double(postMigrationCorrect) / Double(postMigrationAttempts)
    }
}

enum WeaknessSeverity: String, Codable {
    case high    // finalValue >= 5.0
    case medium  // finalValue 2.0-4.9
    case low     // finalValue < 2.0

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        }
    }
}

struct RemovalCriteria: Codable {
    let requiredConsecutiveCorrect: Int  // Default: 5
    let minimumAccuracy: Double          // Default: 0.8 (80%)
    let minimumAttempts: Int             // Default: 10

    static func `default`(for severity: WeaknessSeverity) -> RemovalCriteria {
        switch severity {
        case .high:
            return RemovalCriteria(
                requiredConsecutiveCorrect: 7,
                minimumAccuracy: 0.85,
                minimumAttempts: 15
            )
        case .medium:
            return RemovalCriteria(
                requiredConsecutiveCorrect: 5,
                minimumAccuracy: 0.80,
                minimumAttempts: 10
            )
        case .low:
            return RemovalCriteria(
                requiredConsecutiveCorrect: 3,
                minimumAccuracy: 0.75,
                minimumAttempts: 7
            )
        }
    }
}

// MARK: - Progress Tracking

// ✅ FIX #5: Separate progress indicators (not weighted average)
struct WeaknessPointProgress {
    let consecutiveMet: Bool
    let accuracyMet: Bool
    let attemptsMet: Bool

    let consecutiveProgress: Double  // 0.0 to 1.0
    let accuracyProgress: Double
    let attemptsProgress: Double

    var allMet: Bool {
        consecutiveMet && accuracyMet && attemptsMet
    }

    var overallProgress: Double {
        (consecutiveProgress + accuracyProgress + attemptsProgress) / 3.0
    }
}

// MARK: - Retry Types

// ✅ HYBRID RETRY DETECTION
enum RetryType {
    case explicitPractice   // User clicked "Practice" button → 1.5x bonus
    case autoDetected       // Same weakness within 24h → 1.2x bonus
    case firstTime          // Regular attempt → 1.0x decrement
}

// MARK: - Storage Keys

enum ShortTermStatusStorageKeys {
    static let shortTermStatus = "shortTermStatus_v1"
    static let weaknessPointFolder = "weaknessPointFolder_v1"
    static let lastMigrationDate = "lastWeaknessMigrationDate"
}
