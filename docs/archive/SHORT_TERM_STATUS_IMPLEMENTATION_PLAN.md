# Short-Term Status Architecture - Implementation Plan

**Version**: 1.1
**Last Updated**: 2025-01-25
**Status**: Ready for Implementation

This document outlines the step-by-step implementation of the Short-Term Status Architecture with fixes for the 8 critical issues identified during architecture review.

---

## Critical Fixes Summary

All 8 issues from the architecture review have been addressed:

1. **FIX #1**: Concept extraction via AI (added `primary_concept` to ErrorAnalysisResponse)
2. **FIX #2**: Weighted decrement matching error severity (60% of average error weight)
3. **FIX #3**: Honest storage narrative (better UX trade-off, not space savings)
4. **FIX #4**: AI fallback descriptions (always generate readable fallback first)
5. **FIX #5**: Separate progress indicators (3 bars, not weighted average)
6. **FIX #6**: Consecutive correct tracking (with reset on wrong answer)
7. **FIX #7**: Triple-layered migration (app launch + midnight timer + background task)
8. **FIX #8**: Practice integration (extend QuestionGenerationService with weakness targeting)

**Key Enhancements**:
- Hybrid retry detection (explicit practice button + auto-detection)
- Triple-layered migration triggers for reliability
- Weakness-targeted question generation

---

## Pre-Implementation Requirements

### ✅ Prerequisites Checklist

- [ ] Two-Pass Grading System is functional (Pass 1 + Pass 2 error analysis)
- [ ] Error analysis successfully saves to local storage
- [ ] Question archiving captures `isCorrect` field accurately
- [ ] QuestionGenerationService exists and can generate targeted questions

**Current Status**: ✅ All prerequisites met (as of 2025-01-25)

---

## Phase 1: Data Model Foundation (Days 1-2)

### 1.1 Enhance Error Analysis Response

**File**: `02_ios_app/StudyAI/StudyAI/Services/ErrorAnalysisQueueService.swift`

**Changes**:
```swift
// BEFORE
struct ErrorAnalysisResponse: Codable {
    let error_type: String?
    let evidence: String?
    let confidence: Double
    let learning_suggestion: String?
    let analysis_failed: Bool
}

// AFTER
struct ErrorAnalysisResponse: Codable {
    let error_type: String?
    let evidence: String?
    let confidence: Double
    let learning_suggestion: String?
    let analysis_failed: Bool

    // ✅ FIX #1: Add concept extraction
    let primary_concept: String?    // e.g., "quadratic_equations"
    let secondary_concept: String?  // e.g., "factoring" (optional)
}
```

**Testing**:
```swift
// Archive a question with error analysis and verify concepts are extracted
let response = ErrorAnalysisResponse(
    error_type: "procedural_error",
    evidence: "Student incorrectly factored quadratic equation",
    confidence: 0.85,
    learning_suggestion: "Review factoring techniques",
    analysis_failed: false,
    primary_concept: "quadratic_equations",
    secondary_concept: "factoring"
)
```

### 1.2 Create Core Data Models

**File**: `02_ios_app/StudyAI/StudyAI/Models/ShortTermStatusModels.swift` (NEW)

```swift
//
//  ShortTermStatusModels.swift
//  StudyAI
//
//  Short-term status tracking with time-based weakness migration
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

// MARK: - Storage Keys

enum ShortTermStatusStorageKeys {
    static let shortTermStatus = "shortTermStatus_v1"
    static let weaknessPointFolder = "weaknessPointFolder_v1"
    static let lastMigrationDate = "lastWeaknessMigrationDate"
}
```

**Testing**:
- Build and verify all types compile
- Test Codable encoding/decoding
- Verify computed properties work correctly

---

## Phase 2: Core Service Implementation (Days 3-5)

### 2.1 Create ShortTermStatusService

**File**: `02_ios_app/StudyAI/StudyAI/Services/ShortTermStatusService.swift` (NEW)

```swift
//
//  ShortTermStatusService.swift
//  StudyAI
//
//  Manages active weaknesses and persistent weakness points
//

import Foundation
import Combine
import BackgroundTasks  // ✅ Required for Layer 3 background migration

@MainActor
class ShortTermStatusService: ObservableObject {
    static let shared = ShortTermStatusService()

    @Published var status: ShortTermStatus
    @Published var weaknessFolder: WeaknessPointFolder

    private let logger = AppLogger.forFeature("ShortTermStatus")
    private var midnightCheckTimer: Timer?

    private init() {
        // Load from UserDefaults
        if let data = UserDefaults.standard.data(forKey: ShortTermStatusStorageKeys.shortTermStatus),
           let decoded = try? JSONDecoder().decode(ShortTermStatus.self, from: data) {
            self.status = decoded
            logger.info("Loaded short-term status: \(decoded.activeWeaknesses.count) active weaknesses")
        } else {
            self.status = ShortTermStatus()
            logger.info("Initialized new short-term status")
        }

        if let data = UserDefaults.standard.data(forKey: ShortTermStatusStorageKeys.weaknessPointFolder),
           let decoded = try? JSONDecoder().decode(WeaknessPointFolder.self, from: data) {
            self.weaknessFolder = decoded
            logger.info("Loaded weakness point folder: \(decoded.weaknessPoints.count) points")
        } else {
            self.weaknessFolder = WeaknessPointFolder()
            logger.info("Initialized new weakness point folder")
        }

        // ✅ FIX #7: Triple-layered migration triggers
        // Layer 1: Check on app launch (ALWAYS runs)
        checkAndRunMigrationIfNeeded()

        // Layer 2: Schedule midnight check if app is running
        scheduleMidnightCheck()

        // Layer 3: Register background task for when app is closed
        registerBackgroundMigrationTask()
    }

    // MARK: - Save

    func save() {
        status.lastUpdated = Date()

        if let encoded = try? JSONEncoder().encode(status) {
            UserDefaults.standard.set(encoded, forKey: ShortTermStatusStorageKeys.shortTermStatus)
        }
        if let encoded = try? JSONEncoder().encode(weaknessFolder) {
            UserDefaults.standard.set(encoded, forKey: ShortTermStatusStorageKeys.weaknessPointFolder)
        }

        logger.debug("Saved status: \(status.activeWeaknesses.count) active, \(weaknessFolder.weaknessPoints.count) points")
    }

    // MARK: - Key Generation

    func generateKey(subject: String, concept: String, questionType: String) -> String {
        let normalizedSubject = subject.trimmingCharacters(in: .whitespaces)
        let normalizedConcept = concept.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "_")
        let normalizedType = questionType.trimmingCharacters(in: .whitespaces).lowercased()

        return "\(normalizedSubject)/\(normalizedConcept)/\(normalizedType)"
    }

    // MARK: - Record Mistake

    func recordMistake(key: String, errorType: String, questionId: String? = nil) {
        let increment = errorTypeWeight(errorType)

        if var weakness = status.activeWeaknesses[key] {
            // Update existing weakness
            weakness.value += increment
            weakness.lastAttempt = Date()
            weakness.totalAttempts += 1

            // ✅ FIX #2: Track recent error types (keep last 3)
            weakness.recentErrorTypes.append(errorType)
            if weakness.recentErrorTypes.count > 3 {
                weakness.recentErrorTypes.removeFirst()
            }

            status.activeWeaknesses[key] = weakness

            logger.debug("Updated weakness '\(key)': value=\(weakness.value), attempts=\(weakness.totalAttempts)")
        } else {
            // Create new weakness
            var newWeakness = WeaknessValue(
                value: increment,
                firstDetected: Date(),
                lastAttempt: Date(),
                totalAttempts: 1,
                correctAttempts: 0
            )
            newWeakness.recentErrorTypes = [errorType]

            status.activeWeaknesses[key] = newWeakness

            logger.info("Created new weakness '\(key)' with value \(increment)")
        }

        save()
    }

    // ✅ FIX #2: Error type weights
    private func errorTypeWeight(_ type: String) -> Double {
        switch type {
        case "conceptual_misunderstanding": return 3.0
        case "procedural_error": return 2.0
        case "calculation_mistake": return 1.0
        case "careless_mistake": return 0.5
        default: return 1.5
        }
    }

    // MARK: - Record Correct Attempt

    // ✅ HYBRID RETRY DETECTION: Explicit practice + auto-detection
    enum RetryType {
        case explicitPractice   // User clicked "Practice" button → 1.5x bonus
        case autoDetected       // Same weakness within 24h → 1.2x bonus
        case firstTime          // Regular attempt → 1.0x decrement
    }

    func recordCorrectAttempt(key: String, retryType: RetryType = .firstTime, questionId: String? = nil) {
        guard var weakness = status.activeWeaknesses[key] else {
            logger.warning("Attempted to record correct for non-existent weakness: \(key)")
            return
        }

        // ✅ FIX #2: Calculate weighted decrement based on error history
        let avgErrorWeight = weakness.recentErrorTypes.isEmpty ? 1.5 :
            weakness.recentErrorTypes.map { errorTypeWeight($0) }.reduce(0, +) / Double(weakness.recentErrorTypes.count)

        // Apply retry bonus
        let bonusMultiplier: Double = {
            switch retryType {
            case .explicitPractice: return 1.5  // User-driven, full bonus
            case .autoDetected: return 1.2      // Serendipitous retry, partial bonus
            case .firstTime: return 1.0         // No bonus
            }
        }()

        let baseDecrement = 1.0
        let decrement = baseDecrement * avgErrorWeight * 0.6 * bonusMultiplier

        weakness.value = max(0.0, weakness.value - decrement)
        weakness.correctAttempts += 1
        weakness.totalAttempts += 1
        weakness.lastAttempt = Date()

        logger.debug("Correct attempt on '\(key)': value \(weakness.value + decrement) → \(weakness.value) (decrement: \(decrement), retry: \(retryType))")

        // Check for mastery
        if weakness.value == 0.0 {
            status.activeWeaknesses.removeValue(forKey: key)
            logger.info("✅ Weakness mastered and removed: \(key)")

            // TODO: Show celebration UI
            // TODO: Record in trajectory
        } else {
            status.activeWeaknesses[key] = weakness
        }

        save()
    }

    // Helper: Auto-detect retry
    func recordCorrectAttemptWithAutoDetection(key: String, questionId: String) {
        // Check if this question was recently attempted (last 24h)
        let recentAttempts = getRecentAttempts(key: key, hours: 24)

        let retryType: RetryType = recentAttempts.contains(questionId) ?
            .autoDetected : .firstTime

        recordCorrectAttempt(key: key, retryType: retryType, questionId: questionId)
    }

    private func getRecentAttempts(key: String, hours: Int) -> Set<String> {
        // Get questions from local storage that match this weakness key in the last N hours
        let allQuestions = QuestionLocalStorage.shared.getLocalQuestions()
        let cutoffDate = Date().addingTimeInterval(-Double(hours * 3600))

        let recentQuestionIds = allQuestions
            .filter { question in
                guard let weaknessKey = question["weaknessKey"] as? String,
                      weaknessKey == key,
                      let archivedAtString = question["archivedAt"] as? String,
                      let archivedAt = ISO8601DateFormatter().date(from: archivedAtString) else {
                    return false
                }
                return archivedAt >= cutoffDate
            }
            .compactMap { $0["id"] as? String }

        return Set(recentQuestionIds)
    }

    // MARK: - Migration Check

    // ✅ FIX #7: LAYER 1 - Check on app launch
    func checkAndRunMigrationIfNeeded() {
        let lastMigration = UserDefaults.standard.object(forKey: ShortTermStatusStorageKeys.lastMigrationDate) as? Date
        let now = Date()

        // Check if it's been >24 hours since last migration
        let shouldMigrate: Bool
        if let last = lastMigration {
            shouldMigrate = now.timeIntervalSince(last) >= 24 * 60 * 60
        } else {
            shouldMigrate = true  // Never run before
        }

        if shouldMigrate {
            logger.info("Migration check triggered (Layer 1: App Launch)")
            Task {
                await performDailyWeaknessMigration()
            }
        } else {
            logger.debug("Migration not needed (last run: \(lastMigration?.description ?? "never"))")
        }
    }

    // ✅ FIX #7: LAYER 2 - Midnight check when app is running
    private func scheduleMidnightCheck() {
        // Calculate seconds until next midnight
        let now = Date()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let nextMidnight = calendar.startOfDay(for: tomorrow)
        let timeUntilMidnight = nextMidnight.timeIntervalSince(now)

        logger.debug("Scheduling midnight migration check in \(Int(timeUntilMidnight/3600))h")

        // Schedule timer for midnight
        midnightCheckTimer?.invalidate()
        midnightCheckTimer = Timer.scheduledTimer(withTimeInterval: timeUntilMidnight, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.logger.info("Migration check triggered (Layer 2: Midnight)")
                await self?.performDailyWeaknessMigration()
                self?.scheduleMidnightCheck()  // Reschedule for next midnight
            }
        }
    }

    // ✅ FIX #7: LAYER 3 - Background task when app is closed
    private func registerBackgroundMigrationTask() {
        #if !targetEnvironment(simulator)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.studyai.weaknessmigration",
            using: nil
        ) { [weak self] task in
            Task {
                self?.logger.info("Migration check triggered (Layer 3: Background Task)")
                await self?.performDailyWeaknessMigration()
                task.setTaskCompleted(success: true)
            }

            // Schedule next background migration
            self?.scheduleBackgroundMigration()
        }

        scheduleBackgroundMigration()
        #else
        logger.debug("Background tasks disabled in simulator")
        #endif
    }

    private func scheduleBackgroundMigration() {
        #if !targetEnvironment(simulator)
        let request = BGAppRefreshTaskRequest(identifier: "com.studyai.weaknessmigration")
        request.earliestBeginDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("Scheduled background migration for tomorrow")
        } catch {
            logger.error("Failed to schedule background migration: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Daily Migration

    func performDailyWeaknessMigration() async {
        logger.info("🔄 Starting daily weakness migration...")

        let now = Date()
        let migrationThreshold: TimeInterval = 21 * 24 * 60 * 60  // 21 days

        var keysToMigrate: [(key: String, weakness: WeaknessValue)] = []

        for (key, weakness) in status.activeWeaknesses {
            let age = now.timeIntervalSince(weakness.firstDetected)
            let accuracy = weakness.accuracy

            // Migration criteria: ALL must be true
            let meetsAgeCriteria = age >= migrationThreshold
            let meetsValueCriteria = weakness.value > 0.0
            let meetsAttemptCriteria = weakness.totalAttempts >= 5
            let meetsAccuracyCriteria = accuracy < 0.6

            if meetsAgeCriteria && meetsValueCriteria && meetsAttemptCriteria && meetsAccuracyCriteria {
                keysToMigrate.append((key: key, weakness: weakness))
                logger.info("  📦 Migrating '\(key)': age=\(Int(age/86400))d, value=\(weakness.value), accuracy=\(Int(accuracy*100))%")
            }
        }

        if keysToMigrate.isEmpty {
            logger.info("✅ No weaknesses eligible for migration")
            UserDefaults.standard.set(now, forKey: ShortTermStatusStorageKeys.lastMigrationDate)
            return
        }

        logger.info("Found \(keysToMigrate.count) weaknesses to migrate")

        // Migrate each weakness
        for (key, weakness) in keysToMigrate {
            await migrateToWeaknessPoint(key: key, weakness: weakness)
            status.activeWeaknesses.removeValue(forKey: key)
        }

        save()
        UserDefaults.standard.set(now, forKey: ShortTermStatusStorageKeys.lastMigrationDate)

        logger.info("✅ Migration complete: \(keysToMigrate.count) weaknesses migrated")

        // Queue AI generation for new weakness points
        if !keysToMigrate.isEmpty {
            await queueAIDescriptionGeneration()
        }
    }

    // MARK: - Migrate to Weakness Point

    private func migrateToWeaknessPoint(key: String, weakness: WeaknessValue) async {
        logger.debug("Creating weakness point for '\(key)'")

        // ✅ FIX #4: Generate fallback description immediately (not placeholder)
        let fallbackDescription = generateFallbackDescription(key: key)

        let severity = determineSeverity(weakness)

        let point = WeaknessPoint(
            id: UUID(),
            originalKey: key,
            naturalLanguageDescription: fallbackDescription,
            severity: severity,
            isAIGenerated: false,  // Fallback used initially
            firstDetected: weakness.firstDetected,
            migratedAt: Date(),
            finalValue: weakness.value,
            attemptCount: weakness.totalAttempts,
            accuracyAtMigration: weakness.accuracy,
            removalCriteria: RemovalCriteria.default(for: severity)
        )

        weaknessFolder.weaknessPoints.append(point)

        logger.info("Created weakness point: '\(fallbackDescription)' (severity: \(severity))")
    }

    // ✅ FIX #4: Fallback description generator
    private func generateFallbackDescription(key: String) -> String {
        let parts = key.split(separator: "/")
        guard parts.count == 3 else {
            return "General weakness in \(parts.first ?? "this area")"
        }

        let concept = parts[1].replacingOccurrences(of: "_", with: " ")
        let type = parts[2].replacingOccurrences(of: "_", with: " ")

        return "Difficulty with \(concept) \(type)s"
    }

    private func determineSeverity(_ weakness: WeaknessValue) -> WeaknessSeverity {
        if weakness.value >= 5.0 {
            return .high
        } else if weakness.value >= 2.0 {
            return .medium
        } else {
            return .low
        }
    }

    // MARK: - AI Description Generation

    private func queueAIDescriptionGeneration() async {
        // Get all weakness points that don't have AI descriptions
        let pendingPoints = weaknessFolder.weaknessPoints.filter {
            !$0.isAIGenerated && !$0.aiGenerationFailedPermanently && $0.aiGenerationAttempts < 3
        }

        guard !pendingPoints.isEmpty else { return }

        logger.info("Queuing \(pendingPoints.count) weakness points for AI description generation")

        // TODO: Implement batch AI generation (Phase 3)
        // For now, just log that we would generate
        for point in pendingPoints {
            logger.debug("  Would generate AI description for: \(point.originalKey)")
        }
    }

    // MARK: - Weakness Point Management

    func recordWeaknessPointAttempt(pointId: UUID, isCorrect: Bool) {
        guard let index = weaknessFolder.weaknessPoints.firstIndex(where: { $0.id == pointId }) else {
            logger.warning("Weakness point not found: \(pointId)")
            return
        }

        var point = weaknessFolder.weaknessPoints[index]
        point.postMigrationAttempts += 1
        point.lastAttemptDate = Date()

        if isCorrect {
            point.postMigrationCorrect += 1
            // ✅ FIX #6: Track consecutive correct
            point.currentConsecutiveCorrect += 1
            point.bestConsecutiveStreak = max(point.bestConsecutiveStreak, point.currentConsecutiveCorrect)
        } else {
            // ✅ FIX #6: Reset on wrong
            point.currentConsecutiveCorrect = 0
        }

        weaknessFolder.weaknessPoints[index] = point

        // Check for removal
        let criteria = point.removalCriteria
        let meetsConsecutive = point.currentConsecutiveCorrect >= criteria.requiredConsecutiveCorrect
        let meetsAccuracy = point.postMigrationAccuracy >= criteria.minimumAccuracy
        let meetsAttempts = point.postMigrationAttempts >= criteria.minimumAttempts

        logger.debug("Weakness point attempt: consecutive=\(point.currentConsecutiveCorrect)/\(criteria.requiredConsecutiveCorrect), accuracy=\(Int(point.postMigrationAccuracy*100))%/\(Int(criteria.minimumAccuracy*100))%, attempts=\(point.postMigrationAttempts)/\(criteria.minimumAttempts)")

        if meetsConsecutive && meetsAccuracy && meetsAttempts {
            weaknessFolder.weaknessPoints.remove(at: index)
            logger.info("🎉 Weakness point mastered and removed: \(point.naturalLanguageDescription)")

            // TODO: Show mastery celebration
        }

        save()
    }

    // ✅ FIX #5: Calculate separate progress components
    func getProgress(for pointId: UUID) -> WeaknessPointProgress? {
        guard let point = weaknessFolder.weaknessPoints.first(where: { $0.id == pointId }) else {
            return nil
        }

        let criteria = point.removalCriteria

        let consecutiveProgress = min(1.0, Double(point.currentConsecutiveCorrect) / Double(criteria.requiredConsecutiveCorrect))
        let consecutiveMet = point.currentConsecutiveCorrect >= criteria.requiredConsecutiveCorrect

        let accuracyProgress: Double
        let accuracyMet: Bool
        if point.postMigrationAttempts >= criteria.minimumAttempts {
            accuracyProgress = min(1.0, point.postMigrationAccuracy / criteria.minimumAccuracy)
            accuracyMet = point.postMigrationAccuracy >= criteria.minimumAccuracy
        } else {
            accuracyProgress = 0.0
            accuracyMet = false
        }

        let attemptsProgress = min(1.0, Double(point.postMigrationAttempts) / Double(criteria.minimumAttempts))
        let attemptsMet = point.postMigrationAttempts >= criteria.minimumAttempts

        return WeaknessPointProgress(
            consecutiveMet: consecutiveMet,
            accuracyMet: accuracyMet,
            attemptsMet: attemptsMet,
            consecutiveProgress: consecutiveProgress,
            accuracyProgress: accuracyProgress,
            attemptsProgress: attemptsProgress
        )
    }

    // MARK: - Top Weaknesses

    func getTopActiveWeaknesses(limit: Int = 5) -> [(key: String, value: WeaknessValue)] {
        return status.activeWeaknesses
            .sorted { $0.value.value > $1.value.value }
            .prefix(limit)
            .map { (key: $0.key, value: $0.value) }
    }
}
```

**Testing**:
```swift
// Test error recording
let service = ShortTermStatusService.shared
service.recordMistake(key: "Math/algebra/calculation", errorType: "procedural_error")
// Verify: activeWeaknesses has 1 entry

// Test correct attempt
service.recordCorrectAttempt(key: "Math/algebra/calculation")
// Verify: value decreased

// Test migration (simulate 21 days)
// Modify firstDetected date manually in UserDefaults
// Call performDailyWeaknessMigration()
// Verify: weakness moved to weaknessPoints
```

---

## Phase 3: Backend AI Integration (Days 6-7)

### 3.1 Update Backend Error Analysis Endpoint

**File**: `01_core_backend/src/gateway/routes/ai/modules/question-processing.js`

Add concept extraction to existing error analysis prompt:

```javascript
// Find the error analysis prompt
const errorAnalysisPrompt = `Analyze this student's wrong answer...

Return JSON with:
{
    "error_type": "...",
    "evidence": "...",
    "confidence": 0.85,
    "learning_suggestion": "...",
    "analysis_failed": false,

    // ✅ NEW: Add concept extraction
    "primary_concept": "quadratic_equations",  // Main concept (required)
    "secondary_concept": "factoring"  // Sub-concept (optional)
}

Concept guidelines:
- primary_concept: Core topic (e.g., "quadratic_equations", "stoichiometry", "kinematics")
- secondary_concept: Specific sub-skill (e.g., "factoring", "balancing_equations", "force_diagrams")
- Use snake_case format
- Be specific but consistent (same concept for similar questions)
`;
```

### 3.2 Create Weakness Description Generation Endpoint

**File**: `01_core_backend/src/gateway/routes/ai/modules/weakness-description.js` (NEW)

```javascript
module.exports = async function (fastify, opts) {
  const { getUserId } = require('../utils/auth-helper');

  fastify.post('/api/ai/generate-weakness-descriptions', async (request, reply) => {
    const userId = getUserId(request);

    const { weaknesses } = request.body;

    if (!Array.isArray(weaknesses) || weaknesses.length === 0) {
      return reply.code(400).send({ error: 'Invalid weaknesses array' });
    }

    fastify.log.info(`[WeaknessAI] Generating descriptions for ${weaknesses.count} weaknesses`);

    try {
      const descriptions = [];

      for (const weakness of weaknesses) {
        const prompt = generateWeaknessPrompt(weakness);

        const completion = await openai.chat.completions.create({
          model: 'gpt-4o-mini',
          messages: [
            { role: 'system', content: 'You are an educational AI that analyzes student learning patterns.' },
            { role: 'user', content: prompt }
          ],
          temperature: 0.3,
          max_tokens: 100
        });

        const responseText = completion.choices[0].message.content.trim();
        const parsed = JSON.parse(responseText);

        descriptions.push({
          key: weakness.key,
          description: parsed.description,
          severity: parsed.severity,
          confidence: parsed.confidence
        });
      }

      return { descriptions };

    } catch (error) {
      fastify.log.error('[WeaknessAI] Generation failed:', error);
      return reply.code(500).send({ error: 'AI generation failed' });
    }
  });
};

function generateWeaknessPrompt(weakness) {
  const errorHistory = weakness.errorHistory.map((e, i) =>
    `${i+1}. ${e.errorType}: ${e.evidence}`
  ).join('\n');

  return `Analyze this student's persistent learning struggle and generate a concise, actionable description.

**Weakness Key**: ${weakness.key}
**Attempts**: ${weakness.attemptCount} (Accuracy: ${(weakness.accuracy*100).toFixed(0)}%)

**Error History** (most recent):
${errorHistory}

## Task

Generate a **single sentence** (max 20 words) that:
1. Describes the CORE concept/skill the student struggles with
2. Is specific enough to guide targeted practice
3. Uses student-friendly language (no jargon)
4. Focuses on WHAT they struggle with, not WHY

## Examples

Input: "Physics/mechanics/force_diagrams" + 8 attempts with "procedural_error"
Output: "Has difficulty drawing accurate force diagrams with correct arrow directions and magnitudes"

Input: "Math/fractions/word_problem" + 12 attempts with "reading_comprehension"
Output: "Struggles to identify which operation to use when solving fraction word problems"

## Output Format

Return JSON:
{
    "description": "<20-word sentence>",
    "severity": "<high|medium|low>",
    "confidence": <0.0-1.0>
}

Severity guidelines:
- **high**: Accuracy < 30% AND 10+ attempts
- **medium**: Accuracy 30-50% AND 7+ attempts
- **low**: Accuracy 50-60% AND 5+ attempts`;
}
```

Register in `01_core_backend/src/gateway/routes/ai/index.js`:

```javascript
// Add to module registration
await fastify.register(require('./modules/weakness-description'));
```

**Testing**:
```bash
curl -X POST http://localhost:3000/api/ai/generate-weakness-descriptions \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "weaknesses": [{
      "key": "Math/algebra/calculation",
      "errorHistory": [
        {
          "errorType": "procedural_error",
          "evidence": "Incorrectly distributed negative sign"
        }
      ],
      "attemptCount": 12,
      "accuracy": 0.33
    }]
  }'
```

### 3.3 Connect iOS to Backend

**File**: `02_ios_app/StudyAI/StudyAI/NetworkService.swift`

Add new method:

```swift
// MARK: - Weakness Description Generation

func generateWeaknessDescriptions(_ weaknesses: [[String: Any]]) async throws -> [WeaknessDescriptionResponse] {
    guard let url = URL(string: "\(baseURL)/api/ai/generate-weakness-descriptions") else {
        throw NetworkError.invalidURL
    }

    let requestBody: [String: Any] = [
        "weaknesses": weaknesses
    ]

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(authToken ?? "")", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw NetworkError.serverError
    }

    let responseData = try JSONDecoder().decode(WeaknessDescriptionsResponse.self, from: data)
    return responseData.descriptions
}

struct WeaknessDescriptionsResponse: Codable {
    let descriptions: [WeaknessDescriptionResponse]
}

struct WeaknessDescriptionResponse: Codable {
    let key: String
    let description: String
    let severity: String
    let confidence: Double
}
```

Update ShortTermStatusService to use it:

```swift
private func queueAIDescriptionGeneration() async {
    let pendingPoints = weaknessFolder.weaknessPoints.filter {
        !$0.isAIGenerated && !$0.aiGenerationFailedPermanently && $0.aiGenerationAttempts < 3
    }

    guard !pendingPoints.isEmpty else { return }

    logger.info("Generating AI descriptions for \(pendingPoints.count) weakness points")

    // Build request data
    let requestData = pendingPoints.map { point -> [String: Any] in
        // Get error history from local storage
        let errorHistory = getErrorHistoryForKey(point.originalKey, limit: 5)

        return [
            "key": point.originalKey,
            "errorHistory": errorHistory,
            "attemptCount": point.attemptCount,
            "accuracy": point.accuracyAtMigration
        ]
    }

    do {
        let descriptions = try await NetworkService.shared.generateWeaknessDescriptions(requestData)

        // Update weakness points with AI descriptions
        for description in descriptions {
            if let index = weaknessFolder.weaknessPoints.firstIndex(where: { $0.originalKey == description.key }) {
                weaknessFolder.weaknessPoints[index].naturalLanguageDescription = description.description
                weaknessFolder.weaknessPoints[index].isAIGenerated = true
                weaknessFolder.weaknessPoints[index].aiGenerationAttempts += 1

                logger.info("✅ AI description generated for '\(description.key)': \(description.description)")
            }
        }

        save()

    } catch {
        logger.error("Failed to generate AI descriptions: \(error.localizedDescription)")

        // Mark failed attempts
        for point in pendingPoints {
            if let index = weaknessFolder.weaknessPoints.firstIndex(where: { $0.id == point.id }) {
                weaknessFolder.weaknessPoints[index].aiGenerationAttempts += 1
                if weaknessFolder.weaknessPoints[index].aiGenerationAttempts >= 3 {
                    weaknessFolder.weaknessPoints[index].aiGenerationFailedPermanently = true
                    logger.warning("AI generation permanently failed for '\(point.originalKey)' - using fallback")
                }
            }
        }
        save()
    }
}

private func getErrorHistoryForKey(_ key: String, limit: Int) -> [[String: Any]] {
    // Get questions from local storage that match this weakness key
    let allQuestions = QuestionLocalStorage.shared.getLocalQuestions()

    // Filter questions matching this weakness (would need weaknessKey field added to storage)
    // For now, return empty array (will use fallback description)
    return []
}
```

---

## Phase 4: Integration with Error Analysis (Days 8-9)

### 4.1 Update Question Archiving

**File**: `02_ios_app/StudyAI/StudyAI/Services/LibraryDataService.swift`

Add weakness key field to saved questions:

```swift
func saveQuestions(_ questions: [[String: Any]]) -> [(originalId: String, savedId: String)] {
    // ... existing code ...

    for var question in questions {
        // ... existing normalization ...

        // ✅ NEW: Extract and save weakness key if question is wrong
        if let isCorrect = question["isCorrect"] as? Bool, !isCorrect {
            // Extract concept from error analysis
            let primaryConcept = question["errorAnalysisPrimaryConcept"] as? String ?? "general"
            let subject = question["subject"] as? String ?? "Unknown"
            let questionType = question["questionType"] as? String ?? "general"

            // Generate weakness key
            let weaknessKey = "\(subject)/\(primaryConcept)/\(questionType)"
            question["weaknessKey"] = weaknessKey

            print("   🔑 [Storage] Assigned weakness key: \(weaknessKey)")
        }

        // ... rest of existing code ...
    }

    // ... existing code ...
}
```

### 4.2 Update Error Analysis to Include Concepts

**File**: `02_ios_app/StudyAI/StudyAI/Services/ErrorAnalysisQueueService.swift`

Update to save concepts:

```swift
private func updateLocalQuestionWithAnalysis(questionId: String, analysis: ErrorAnalysisResponse) {
    var allQuestions = localStorage.getLocalQuestions()

    guard let index = allQuestions.firstIndex(where: { ($0["id"] as? String) == questionId }) else {
        print("⚠️ [ErrorAnalysis] Question \(questionId) not found in local storage")
        return
    }

    // Update with analysis results
    allQuestions[index]["errorType"] = analysis.error_type ?? ""
    allQuestions[index]["errorEvidence"] = analysis.evidence ?? ""
    allQuestions[index]["errorConfidence"] = analysis.confidence
    allQuestions[index]["learningSuggestion"] = analysis.learning_suggestion ?? ""
    allQuestions[index]["errorAnalysisStatus"] = analysis.analysis_failed ? "failed" : "completed"
    allQuestions[index]["errorAnalyzedAt"] = ISO8601DateFormatter().string(from: Date())

    // ✅ NEW: Save concept data for weakness tracking
    allQuestions[index]["errorAnalysisPrimaryConcept"] = analysis.primary_concept ?? "general"
    if let secondary = analysis.secondary_concept {
        allQuestions[index]["errorAnalysisSecondaryConcept"] = secondary
    }

    // Save back to local storage
    _ = localStorage.saveQuestions([allQuestions[index]])

    print("✅ [ErrorAnalysis] Updated question \(questionId): \(analysis.error_type ?? "unknown") (concept: \(analysis.primary_concept ?? "N/A"))")

    // ✅ NEW: Update short-term status
    if !analysis.analysis_failed,
       let errorType = analysis.error_type,
       let primaryConcept = analysis.primary_concept {

        let subject = allQuestions[index]["subject"] as? String ?? "Unknown"
        let questionType = allQuestions[index]["questionType"] as? String ?? "general"

        Task { @MainActor in
            let key = ShortTermStatusService.shared.generateKey(
                subject: subject,
                concept: primaryConcept,
                questionType: questionType
            )

            ShortTermStatusService.shared.recordMistake(
                key: key,
                errorType: errorType,
                questionId: questionId
            )
        }
    }
}
```

---

## Phase 5: UI Implementation (Days 10-12)

### 5.1 Create Recent Mistakes Section

**File**: `02_ios_app/StudyAI/StudyAI/Views/MistakeReviewView.swift`

Add to existing view:

```swift
// Add at the top of ScrollView
VStack(spacing: 24) {
    // ✅ NEW: Recent Mistakes Section
    RecentMistakesSection()

    // Existing time range selection...
    // Existing subject selection...
}
```

### 5.2 Create RecentMistakesSection View

**File**: `02_ios_app/StudyAI/StudyAI/Views/RecentMistakesSection.swift` (NEW)

```swift
//
//  RecentMistakesSection.swift
//  StudyAI
//
//  Recent mistakes with "Do it again" functionality
//

import SwiftUI

struct RecentMistakesSection: View {
    @ObservedObject private var statusService = ShortTermStatusService.shared
    @State private var selectedWeaknessForPractice: (key: String, value: WeaknessValue)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Active Weaknesses")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if !statusService.status.activeWeaknesses.isEmpty {
                    Text("\(statusService.status.activeWeaknesses.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
            }

            if statusService.status.activeWeaknesses.isEmpty {
                EmptyWeaknessView()
            } else {
                ForEach(topWeaknesses, id: \.key) { weakness in
                    ActiveWeaknessCard(
                        key: weakness.key,
                        value: weakness.value,
                        onPractice: {
                            selectedWeaknessForPractice = weakness
                        }
                    )
                }
            }

            // Weakness Points (if any)
            if !statusService.weaknessFolder.weaknessPoints.isEmpty {
                Divider()
                    .padding(.vertical, 8)

                HStack {
                    Text("Persistent Weaknesses")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Spacer()

                    Text("\(statusService.weaknessFolder.weaknessPoints.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }

                ForEach(statusService.weaknessFolder.weaknessPoints) { point in
                    WeaknessPointCard(point: point)
                }
            }
        }
        .padding()
        .sheet(item: $selectedWeaknessForPractice) { weakness in
            WeaknessPracticeView(weaknessKey: weakness.key, weaknessValue: weakness.value)
        }
    }

    private var topWeaknesses: [(key: String, value: WeaknessValue)] {
        statusService.getTopActiveWeaknesses(limit: 5)
    }
}

// MARK: - Active Weakness Card

struct ActiveWeaknessCard: View {
    let key: String
    let value: WeaknessValue
    let onPractice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(formatKey(key))
                        .font(.headline)

                    HStack(spacing: 12) {
                        Label("\(String(format: "%.1f", value.value))", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(severityColor(value.value))

                        Label("\(value.correctAttempts)/\(value.totalAttempts)", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Label("\(value.daysActive)d", systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    onPractice()
                } label: {
                    Text("Practice")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(severityColor(value.value))
                        .cornerRadius(8)
                }
            }

            // Progress bar
            ProgressView(value: value.accuracy) {
                Text("Accuracy: \(Int(value.accuracy * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .tint(value.accuracy >= 0.6 ? .green : .orange)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func formatKey(_ key: String) -> String {
        let parts = key.split(separator: "/")
        if parts.count >= 2 {
            let concept = parts[1].replacingOccurrences(of: "_", with: " ").capitalized
            let type = parts.count >= 3 ? parts[2].replacingOccurrences(of: "_", with: " ") : ""
            return "\(concept) \(type)".trimmingCharacters(in: .whitespaces)
        }
        return key
    }

    private func severityColor(_ value: Double) -> Color {
        if value >= 5.0 { return .red }
        else if value >= 2.0 { return .orange }
        else { return .yellow }
    }
}

// MARK: - Empty State

struct EmptyWeaknessView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("No Active Weaknesses")
                .font(.headline)

            Text("Great work! Keep practicing to maintain your skills.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Weakness Point Card

struct WeaknessPointCard: View {
    let point: WeaknessPoint
    @ObservedObject private var statusService = ShortTermStatusService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Description
            HStack {
                Image(systemName: point.isAIGenerated ? "sparkles" : "text.bubble")
                    .font(.caption)
                    .foregroundColor(point.isAIGenerated ? .blue : .gray)

                Text(point.naturalLanguageDescription)
                    .font(.body)

                Spacer()

                // Severity badge
                Text(point.severity.rawValue.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(point.severity.color)
                    .cornerRadius(4)
            }

            // Progress tracking (if has attempts)
            if point.postMigrationAttempts > 0, let progress = statusService.getProgress(for: point.id) {
                Divider()

                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        // ✅ FIX #5: Show separate progress indicators
                        ProgressMetric(
                            icon: "arrow.right.circle.fill",
                            label: "Consecutive",
                            value: "\(point.currentConsecutiveCorrect)/\(point.removalCriteria.requiredConsecutiveCorrect)",
                            progress: progress.consecutiveProgress,
                            isMet: progress.consecutiveMet,
                            color: .green
                        )

                        ProgressMetric(
                            icon: "percent",
                            label: "Accuracy",
                            value: "\(Int(point.postMigrationAccuracy*100))%",
                            progress: progress.accuracyProgress,
                            isMet: progress.accuracyMet,
                            color: .blue
                        )

                        ProgressMetric(
                            icon: "number",
                            label: "Attempts",
                            value: "\(point.postMigrationAttempts)/\(point.removalCriteria.minimumAttempts)",
                            progress: progress.attemptsProgress,
                            isMet: progress.attemptsMet,
                            color: .orange
                        )
                    }
                    .font(.caption)

                    if progress.allMet {
                        Text("🎉 Ready to remove - one more correct answer!")
                            .font(.caption)
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(point.severity.color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(point.severity.color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct ProgressMetric: View {
    let icon: String
    let label: String
    let value: String
    let progress: Double
    let isMet: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: isMet ? "checkmark.circle.fill" : icon)
                    .foregroundColor(isMet ? .green : color)
                Text(label)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(isMet ? .green : .primary)

            ProgressView(value: progress)
                .tint(isMet ? .green : color)
        }
        .frame(maxWidth: .infinity)
    }
}
```

### 5.3 Create Weakness Practice View

**File**: `02_ios_app/StudyAI/StudyAI/Views/WeaknessPracticeView.swift` (NEW)

```swift
//
//  WeaknessPracticeView.swift
//  StudyAI
//
//  "Do it again" practice view for weaknesses
//

import SwiftUI

struct WeaknessPracticeView: View {
    let weaknessKey: String
    let weaknessValue: WeaknessValue

    @StateObject private var viewModel: WeaknessPracticeViewModel
    @Environment(\.dismiss) private var dismiss

    init(weaknessKey: String, weaknessValue: WeaknessValue) {
        self.weaknessKey = weaknessKey
        self.weaknessValue = weaknessValue
        self._viewModel = StateObject(wrappedValue: WeaknessPracticeViewModel(weaknessKey: weaknessKey))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Weakness info header
                    WeaknessInfoHeader(key: weaknessKey, value: weaknessValue)

                    // Practice questions
                    if viewModel.isLoading {
                        ProgressView("Generating practice questions...")
                            .padding()
                    } else if let error = viewModel.error {
                        ErrorView(message: error, onRetry: {
                            Task { await viewModel.loadPracticeQuestions() }
                        })
                    } else if viewModel.questions.isEmpty {
                        Text("No questions available")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(viewModel.questions.enumerated()), id: \.offset) { index, question in
                            PracticeQuestionCard(
                                question: question,
                                questionNumber: index + 1,
                                onSubmit: { answer in
                                    await viewModel.submitAnswer(questionIndex: index, answer: answer)
                                }
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.loadPracticeQuestions()
        }
    }
}

// MARK: - Weakness Info Header

struct WeaknessInfoHeader: View {
    let key: String
    let value: WeaknessValue

    var body: some View {
        VStack(spacing: 12) {
            Text(formatKey(key))
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 20) {
                StatBadge(icon: "exclamationmark.triangle.fill", label: "Weakness", value: String(format: "%.1f", value.value), color: .orange)
                StatBadge(icon: "percent", label: "Accuracy", value: "\(Int(value.accuracy * 100))%", color: .blue)
                StatBadge(icon: "number", label: "Attempts", value: "\(value.totalAttempts)", color: .purple)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func formatKey(_ key: String) -> String {
        let parts = key.split(separator: "/")
        if parts.count >= 2 {
            return parts[1].replacingOccurrences(of: "_", with: " ").capitalized
        }
        return key
    }
}

struct StatBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
    }
}

// MARK: - Practice Question Card

struct PracticeQuestionCard: View {
    let question: PracticeQuestion
    let questionNumber: Int
    let onSubmit: (String) async -> Void

    @State private var userAnswer: String = ""
    @State private var isSubmitting = false
    @State private var showResult = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Question number
            Text("Question \(questionNumber)")
                .font(.caption)
                .foregroundColor(.secondary)

            // Question text
            Text(question.questionText)
                .font(.body)

            // Answer input (based on question type)
            if !showResult {
                Group {
                    switch question.questionType {
                    case "multiple_choice":
                        MultipleChoiceInput(options: question.options ?? [], selectedOption: $userAnswer)
                    case "true_false":
                        TrueFalseInput(selectedOption: $userAnswer)
                    default:
                        TextEditor(text: $userAnswer)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                }

                // Submit button
                Button {
                    Task {
                        isSubmitting = true
                        await onSubmit(userAnswer)
                        showResult = true
                        isSubmitting = false
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Submit Answer")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(userAnswer.isEmpty || isSubmitting)
            } else {
                // Show result
                ResultView(result: question.result)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(radius: 2)
        )
    }
}

// MARK: - Weakness Practice ViewModel

@MainActor
class WeaknessPracticeViewModel: ObservableObject {
    let weaknessKey: String

    @Published var questions: [PracticeQuestion] = []
    @Published var isLoading = false
    @Published var error: String?

    private let logger = AppLogger.forFeature("WeaknessPractice")

    init(weaknessKey: String) {
        self.weaknessKey = weaknessKey
    }

    // ✅ FIX #8: Enhanced question generation with weakness targeting
    func loadPracticeQuestions() async {
        isLoading = true
        error = nil

        do {
            // Parse weakness key: "Math/algebra/calculation"
            let parts = weaknessKey.split(separator: "/")
            guard parts.count >= 2 else {
                throw PracticeError.invalidWeaknessKey
            }

            let subject = String(parts[0])
            let concept = String(parts[1]).replacingOccurrences(of: "_", with: " ")

            // Get weakness value for difficulty calculation
            guard let weaknessValue = ShortTermStatusService.shared.status.activeWeaknesses[weaknessKey] else {
                throw PracticeError.weaknessNotFound
            }

            // Get recent mistakes for this weakness
            let recentMistakes = getRecentMistakes(for: weaknessKey)

            // Build weakness context for targeted generation
            let weaknessContext = WeaknessContext(
                weaknessKey: weaknessKey,
                errorTypes: weaknessValue.recentErrorTypes,
                recentMistakeExamples: recentMistakes.map { $0.questionText },
                targetAccuracy: min(0.9, weaknessValue.accuracy + 0.1)  // Slightly harder
            )

            // Generate targeted questions
            let generatedQuestions = try await QuestionGenerationService.shared.generateQuestions(
                subject: subject,
                topic: concept,
                count: 3,
                difficulty: determineDifficulty(weaknessValue.value),
                weaknessContext: weaknessContext  // ✅ NEW: Weakness targeting
            )

            // Convert to PracticeQuestion
            questions = generatedQuestions.map { q in
                PracticeQuestion(
                    id: UUID(),
                    questionText: q.questionText,
                    questionType: q.questionType,
                    options: q.options,
                    correctAnswer: q.correctAnswer
                )
            }

            logger.info("Generated \(questions.count) practice questions for '\(weaknessKey)'")

        } catch {
            self.error = error.localizedDescription
            logger.error("Failed to generate practice questions: \(error)")
        }

        isLoading = false
    }

    private func determineDifficulty(_ weaknessValue: Double) -> String {
        // High weakness = start easy to build confidence
        if weaknessValue >= 5.0 { return "easy" }
        else if weaknessValue >= 2.0 { return "medium" }
        else { return "hard" }  // Nearly mastered = challenge them
    }

    private func getRecentMistakes(for key: String) -> [(questionText: String, studentAnswer: String)] {
        let allQuestions = QuestionLocalStorage.shared.getLocalQuestions()

        return allQuestions
            .filter { question in
                guard let weaknessKey = question["weaknessKey"] as? String,
                      weaknessKey == key,
                      let isCorrect = question["isCorrect"] as? Bool,
                      !isCorrect else {
                    return false
                }
                return true
            }
            .prefix(5)  // Last 5 mistakes
            .compactMap { question in
                guard let questionText = question["questionText"] as? String,
                      let studentAnswer = question["studentAnswer"] as? String else {
                    return nil
                }
                return (questionText: questionText, studentAnswer: studentAnswer)
            }
    }

    func submitAnswer(questionIndex: Int, answer: String) async {
        guard questionIndex < questions.count else { return }

        var question = questions[questionIndex]

        // Grade the answer
        let isCorrect = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == question.correctAnswer.lowercased()

        question.result = PracticeQuestionResult(
            isCorrect: isCorrect,
            userAnswer: answer,
            correctAnswer: question.correctAnswer,
            feedback: generateFeedback(isCorrect: isCorrect, questionType: question.questionType)
        )

        questions[questionIndex] = question

        // Update short-term status
        if isCorrect {
            ShortTermStatusService.shared.recordCorrectAttempt(
                key: weaknessKey,
                retryType: .explicitPractice,  // ✅ Full bonus for practice button
                questionId: question.id.uuidString
            )
            logger.info("Correct practice answer for '\(weaknessKey)'")
        } else {
            ShortTermStatusService.shared.recordMistake(
                key: weaknessKey,
                errorType: "practice_error",
                questionId: question.id.uuidString
            )
            logger.info("Incorrect practice answer for '\(weaknessKey)'")
        }
    }

    private func generateFeedback(isCorrect: Bool, questionType: String) -> String {
        if isCorrect {
            return "Great job! Keep practicing to master this weakness."
        } else {
            return "Not quite. Review the correct answer and try similar questions."
        }
    }
}

// MARK: - Practice Question Models

struct PracticeQuestion: Identifiable {
    let id: UUID
    let questionText: String
    let questionType: String
    let options: [String]?
    let correctAnswer: String
    var result: PracticeQuestionResult?
}

struct PracticeQuestionResult {
    let isCorrect: Bool
    let userAnswer: String
    let correctAnswer: String
    let feedback: String
}

enum PracticeError: LocalizedError {
    case invalidWeaknessKey
    case weaknessNotFound
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .invalidWeaknessKey: return "Invalid weakness key format"
        case .weaknessNotFound: return "Weakness not found in active weaknesses"
        case .generationFailed: return "Failed to generate practice questions"
        }
    }
}

// MARK: - Enhanced QuestionGenerationService

// ✅ FIX #8: Add weakness context to existing service
extension QuestionGenerationService {
    func generateQuestions(
        subject: String,
        topic: String,
        count: Int,
        difficulty: String,
        weaknessContext: WeaknessContext? = nil  // ✅ NEW parameter
    ) async throws -> [GeneratedQuestion] {

        // Build prompt with weakness targeting if context provided
        var prompt = buildBasePrompt(subject: subject, topic: topic, count: count, difficulty: difficulty)

        if let context = weaknessContext {
            prompt += """


            WEAKNESS TARGETING:
            This student struggles with: \(context.weaknessKey)
            Common errors: \(context.errorTypes.joined(separator: ", "))

            Generate questions that:
            1. Target this specific weakness pattern
            2. Start at \(Int(context.targetAccuracy * 100))% difficulty (student's current level + 10%)
            3. Gradually increase difficulty across the \(count) questions
            4. Use similar patterns to recent mistakes (but don't copy exactly)
            5. Focus on areas where errors occurred

            Recent mistake examples (for pattern reference only):
            \(context.recentMistakeExamples.prefix(3).enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n"))
            """
        }

        // Call existing generation logic with enhanced prompt
        return try await generateWithPrompt(prompt)
    }
}

struct WeaknessContext {
    let weaknessKey: String
    let errorTypes: [String]
    let recentMistakeExamples: [String]
    let targetAccuracy: Double  // 0.0 to 1.0
}
```

**Required Info.plist configuration for background tasks**:

Add to `02_ios_app/StudyAI/StudyAI/Info.plist`:
```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.studyai.weaknessmigration</string>
</array>
```

---

## Phase 6: Testing & Deployment (Days 13-14)

### 6.1 Testing Checklist

- [ ] Unit tests for ShortTermStatusService
  - [ ] Record mistake increments value correctly
  - [ ] Record correct decrements value (weighted)
  - [ ] Migration triggers after 21 days
  - [ ] Weakness point removal works with all criteria
- [ ] Integration tests
  - [ ] Error analysis saves concepts
  - [ ] Questions get assigned weakness keys
  - [ ] AI description generation succeeds
  - [ ] Fallback descriptions work when AI fails
- [ ] UI tests
  - [ ] Recent mistakes section displays correctly
  - [ ] Practice view renders question types
  - [ ] Progress indicators update in real-time
- [ ] End-to-end test
  - [ ] Archive wrong question → Error analysis → Weakness created → Practice → Mastery → Removal

### 6.2 Deployment Steps

1. Deploy backend changes
   ```bash
   cd 01_core_backend
   git add src/gateway/routes/ai/modules/weakness-description.js
   git commit -m "feat: Add weakness description generation endpoint"
   git push origin main  # Auto-deploys to Railway
   ```

2. Deploy iOS app
   - Build and test on simulator
   - Create TestFlight build
   - Submit for review

---

## Phase 7: Monitoring & Iteration (Ongoing)

### 7.1 Metrics to Track

- Active weakness count per user
- Migration rate (weaknesses → points per day)
- AI description quality (manual review sample)
- Mastery rate (weaknesses reaching 0)
- Practice engagement (clicks on "Practice" button)

### 7.2 Optimization Opportunities

- Adjust 21-day threshold based on data
- Tune error type weights
- Improve concept extraction accuracy
- A/B test removal criteria strictness

---

## Summary: Implementation Order

1. ✅ **Phase 1** (Days 1-2): Data models + error analysis enhancement
2. ✅ **Phase 2** (Days 3-5): Core service implementation
3. ✅ **Phase 3** (Days 6-7): Backend AI integration
4. ✅ **Phase 4** (Days 8-9): Error analysis integration
5. ✅ **Phase 5** (Days 10-12): UI implementation
6. ✅ **Phase 6** (Days 13-14): Testing & deployment
7. ✅ **Phase 7** (Ongoing): Monitoring & iteration

**Total Timeline**: 14 days (2 weeks)

---

## Critical Success Factors

1. **Concept extraction quality**: If concepts are generic, weakness tracking fails
2. **AI fallback reliability**: Users must never see "Generating..." forever
3. **Migration timing**: 21 days must be validated with real usage data
4. **Progress clarity**: Users must understand removal criteria clearly
5. **Practice engagement**: "Do it again" must be compelling and easy

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Poor concept extraction | Use fallback + iterative prompt tuning |
| AI generation failures | Always generate fallback description first |
| Storage overflow | Monitor UserDefaults size, add cleanup if needed |
| User confusion on progress | Show 3 separate progress bars, not weighted average |
| Low practice engagement | Integrate with QuestionGenerationService for quality |

---

**Next Steps**: Begin Phase 1 implementation after stakeholder approval.

---

## Appendix: Design Decisions Q&A

### Q1: What were FIX #3 and FIX #8?

**FIX #3: Honest Storage Narrative**
- **Original claim**: "37% reduction in storage"
- **Math reality**: 255 bytes > 160 bytes = 59% INCREASE
- **Fix**: Rewrote narrative to be honest about trade-offs:
  - Weakness points provide better UX (readable descriptions vs. cryptic keys)
  - Total storage ~16KB is acceptable for UserDefaults
  - Focus on user experience, not misleading storage "savings"

**FIX #8: Practice Integration**
- **Original**: Placeholder comment `// Generate targeted practice questions`
- **Fix**: Full implementation connecting to QuestionGenerationService:
  - Extended service with `weaknessContext` parameter
  - Weakness-targeted question generation
  - Integrated in WeaknessPracticeViewModel
  - Backend prompt enhancement for targeting

### Q2: Retry Detection - Automatic or Manual?

**Decision: Hybrid approach (both)**

Implemented three retry types:
1. **Explicit Practice** (1.5x bonus): User clicks "Practice" button → full bonus for intentional practice
2. **Auto-Detected** (1.2x bonus): Same weakness within 24h → partial bonus for serendipitous retry
3. **First Time** (1.0x): No bonus for new attempts

**Benefits**:
- Rewards user-driven practice (explicit)
- Credits organic improvement (auto-detect)
- Prevents gaming system (24h window limit)
- Flexible for different learning patterns

### Q3: Question Generation - Existing vs. New Service?

**Decision: Extend existing QuestionGenerationService**

Added `weaknessContext` parameter to existing service:

```swift
func generateQuestions(
    subject: String,
    topic: String,
    count: Int,
    difficulty: String,
    weaknessContext: WeaknessContext? = nil  // ✅ NEW
) async throws -> [GeneratedQuestion]
```

**Benefits**:
- Reuses existing AI infrastructure
- Maintains consistency in question format
- Less code to maintain
- Backward compatible (optional parameter)
- Can still use regular generation when context is nil

**Backend integration**: Enhanced AI prompt with weakness patterns, error types, and recent mistakes for targeted generation.

### Q4: Migration Trigger - Launch Only or Periodic?

**Decision: Triple-layered approach (maximum reliability)**

Implemented three independent migration triggers:

| Layer | Trigger | Coverage | Reliability |
|-------|---------|----------|-------------|
| **Layer 1** | App launch check | Daily users ✅ | High ✅ |
| **Layer 2** | Midnight timer (when app running) | Heavy users ✅ | Medium (requires app open) |
| **Layer 3** | Background task (iOS-scheduled) | Infrequent users ✅ | iOS-dependent |

**How they work together**:
- Layer 1 catches up on missed migrations at next app launch (failsafe)
- Layer 2 runs precisely at midnight for active users
- Layer 3 handles users who rarely open the app

**Configuration required**:
```xml
<!-- Info.plist -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.studyai.weaknessmigration</string>
</array>
```

**Result**: Nearly 100% coverage across all user patterns with minimal overhead.

---

**Document Version History**:
- v1.0 (2025-01-25): Initial implementation plan with 8 critical fixes
- v1.1 (2025-01-25): Enhanced with hybrid retry detection, triple-layered migration, weakness-targeted generation, and Q&A appendix
