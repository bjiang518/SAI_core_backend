//
//  ShortTermStatusService.swift
//  StudyAI
//
//  Manages active weaknesses and persistent weakness points
//  Created by Claude Code on 1/25/25.
//

import Foundation
import Combine
import UIKit  // Required for UIApplication lifecycle notifications
#if canImport(BackgroundTasks)
import BackgroundTasks  // ✅ Required for Layer 3 background migration (iOS only)
#endif

@MainActor
class ShortTermStatusService: ObservableObject {
    static let shared = ShortTermStatusService()

    @Published var status: ShortTermStatus
    @Published var weaknessFolder: WeaknessPointFolder

    // ✅ NEW: Track recently mastered weaknesses for UI celebration
    @Published var recentMasteries: [(key: String, timestamp: Date)] = []

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

        // Layer 3: Background task registration moved to StudyAIApp.swift
        // (Must be registered before application:didFinishLaunchingWithOptions: completes)

        // BATTERY OPTIMIZATION: Stop timer when app goes to background
        setupLifecycleObservers()
    }

    private func setupLifecycleObservers() {
        // Stop midnight timer when app enters background (saves battery)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.midnightCheckTimer?.invalidate()
            self?.midnightCheckTimer = nil
        }

        // Restart midnight timer when app returns to foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleMidnightCheck()
        }
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

    // ✅ NEW: Clear recent masteries (called after UI celebration is shown)
    func clearRecentMasteries() {
        recentMasteries.removeAll()
        logger.debug("Cleared recent masteries")
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

        print("🎯 [WeaknessTracking] recordMistake called:")
        print("   Key: \(key)")
        print("   Error Type: \(errorType) (weight: \(increment))")

        if var weakness = status.activeWeaknesses[key] {
            // Update existing weakness
            let oldValue = weakness.value

            // ✅ NEW: Check if transitioning from mastery (negative) to weakness (positive)
            let wasNegative = oldValue < 0
            weakness.value += increment
            let isNowPositive = weakness.value > 0

            if wasNegative && isNowPositive {
                // Transitioning from mastery to weakness: clear mastery data, start fresh tracking
                weakness.masteryQuestions = []
                weakness.recentErrorTypes = [errorType]
                weakness.recentQuestionIds = questionId.map { [$0] } ?? []
                print("   ⚠️ TRANSITION: Mastery → Weakness (cleared mastery data)")
            } else {
                // Track recent error types (keep last 3)
                weakness.recentErrorTypes.append(errorType)
                if weakness.recentErrorTypes.count > 3 {
                    weakness.recentErrorTypes.removeFirst()
                }

                // ✅ FIX: Track recent question IDs (keep last 5, prevent duplicates)
                if let qId = questionId {
                    // Only append if not already in the array (prevent duplicates)
                    if !weakness.recentQuestionIds.contains(qId) {
                        weakness.recentQuestionIds.append(qId)
                        if weakness.recentQuestionIds.count > 5 {
                            weakness.recentQuestionIds.removeFirst()
                        }
                    } else {
                        print("   ℹ️ Question ID \(qId) already tracked (duplicate prevented)")
                    }
                }
            }

            weakness.lastAttempt = Date()
            weakness.totalAttempts += 1

            status.activeWeaknesses[key] = weakness

            print("   ✅ UPDATED existing weakness: \(oldValue) → \(weakness.value) (attempts: \(weakness.totalAttempts))")
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
            if let qId = questionId {
                newWeakness.recentQuestionIds = [qId]
            }

            status.activeWeaknesses[key] = newWeakness

            print("   ✅ CREATED new weakness with value: \(increment)")
            logger.info("Created new weakness '\(key)' with value \(increment)")
        }

        print("   📊 Total active weaknesses: \(status.activeWeaknesses.count)")

        // ✅ NEW: Enforce memory limit (20 keys per subject)
        enforceMemoryLimit()

        save()
    }

    // ✅ Error type weights (updated for hierarchical error analysis)
    func errorTypeWeight(_ type: String) -> Double {
        switch type {
        // NEW hierarchical error types (3 types)
        case "conceptual_gap": return 3.0        // High severity - conceptual misunderstanding
        case "execution_error": return 1.5       // Medium severity - procedural/calculation errors
        case "needs_refinement": return 0.5      // Low severity - careless mistakes

        // OLD error types (backward compatibility)
        case "conceptual_misunderstanding": return 3.0
        case "procedural_error": return 2.0
        case "calculation_mistake": return 1.0
        case "careless_mistake": return 0.5

        default: return 1.5
        }
    }

    // MARK: - Record Correct Attempt

    // ✅ HYBRID RETRY DETECTION: Explicit practice + auto-detection
    func recordCorrectAttempt(key: String, retryType: RetryType = .firstTime, questionId: String? = nil) {
        guard var weakness = status.activeWeaknesses[key] else {
            // ✅ NEW: If key doesn't exist, create mastery entry with negative value
            logger.info("Creating new mastery entry for: \(key)")
            var newMastery = WeaknessValue(
                value: -0.5,  // Start with small mastery bonus
                firstDetected: Date(),
                lastAttempt: Date(),
                totalAttempts: 1,
                correctAttempts: 1
            )
            if let qId = questionId {
                newMastery.masteryQuestions = [qId]
            }
            status.activeWeaknesses[key] = newMastery

            // ✅ NEW: Enforce memory limit
            enforceMemoryLimit()
            save()
            return
        }

        let oldValue = weakness.value

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

        // ✅ NEW: Allow negative values (remove clamp at 0)
        weakness.value -= decrement

        // ✅ NEW: Check if transitioning from weakness (positive) to mastery (negative)
        let wasPositive = oldValue > 0
        let isNowNegative = weakness.value < 0

        if wasPositive && isNowNegative {
            // Transitioning from weakness to mastery: clear weakness tracking, start mastery tracking
            weakness.recentErrorTypes = []
            weakness.recentQuestionIds = []
            weakness.masteryQuestions = questionId.map { [$0] } ?? []
            logger.info("🎉 TRANSITION: Weakness → Mastery for '\(key)' (value: \(weakness.value))")
            print("   🎉 TRANSITION: Weakness → Mastery (cleared error data, starting mastery tracking)")

            // ✅ NEW: Add to recentMasteries for UI celebration
            recentMasteries.append((key: key, timestamp: Date()))
            print("   🎊 Added to recentMasteries for UI celebration!")
        } else if isNowNegative {
            // Already in mastery: track mastery questions (keep last 5, prevent duplicates)
            if let qId = questionId {
                // Only append if not already in the array (prevent duplicates)
                if !weakness.masteryQuestions.contains(qId) {
                    weakness.masteryQuestions.append(qId)
                    if weakness.masteryQuestions.count > 5 {
                        weakness.masteryQuestions.removeFirst()
                    }
                } else {
                    print("   ℹ️ Question ID \(qId) already tracked in mastery (duplicate prevented)")
                }
            }
        }

        weakness.correctAttempts += 1
        weakness.totalAttempts += 1
        weakness.lastAttempt = Date()

        logger.debug("Correct attempt on '\(key)': value \(oldValue) → \(weakness.value) (decrement: \(decrement), retry: \(retryType))")

        status.activeWeaknesses[key] = weakness

        // ✅ NEW: Enforce memory limit
        enforceMemoryLimit()

        save()
    }

    // ✅ NEW: Memory management - keep only 20 most recent keys per subject
    private func enforceMemoryLimit() {
        let maxKeysPerSubject = 20

        // Group by subject (extract subject from key "Mathematics/branch/topic")
        var keysBySubject: [String: [String]] = [:]

        for key in status.activeWeaknesses.keys {
            let components = key.split(separator: "/").map(String.init)
            guard let subject = components.first else { continue }

            if keysBySubject[subject] == nil {
                keysBySubject[subject] = []
            }
            keysBySubject[subject]?.append(key)
        }

        // For each subject, keep only the 20 most recent
        for (subject, keys) in keysBySubject {
            if keys.count > maxKeysPerSubject {
                // Sort by lastAttempt (most recent first)
                let sortedKeys = keys.sorted { key1, key2 in
                    let date1 = status.activeWeaknesses[key1]?.lastAttempt ?? Date.distantPast
                    let date2 = status.activeWeaknesses[key2]?.lastAttempt ?? Date.distantPast
                    return date1 > date2
                }

                // Remove oldest keys (beyond the limit)
                let keysToRemove = sortedKeys.suffix(keys.count - maxKeysPerSubject)

                for key in keysToRemove {
                    status.activeWeaknesses.removeValue(forKey: key)
                    logger.info("🗑️ Removed old weakness key (memory limit): \(key)")
                }

                logger.info("📊 Memory cleanup for \(subject): Removed \(keysToRemove.count) old keys, kept \(maxKeysPerSubject)")
            }
        }
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

    // ✅ FIX #7: LAYER 3 - Background task scheduling (registration moved to StudyAIApp.swift)

    /// Schedule next background migration task
    /// Called from StudyAIApp.swift after task completion
    func scheduleNextBackgroundMigration() {
        #if canImport(BackgroundTasks) && !targetEnvironment(simulator)
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
        let allQuestions = QuestionLocalStorage.shared.getLocalQuestions()

        return allQuestions
            .filter { question in
                guard let weaknessKey = question["weaknessKey"] as? String,
                      weaknessKey == key else {
                    return false
                }
                return true
            }
            .prefix(limit)
            .compactMap { question -> [String: Any]? in
                guard let errorType = question["errorType"] as? String,
                      let evidence = question["errorEvidence"] as? String else {
                    return nil
                }
                return [
                    "errorType": errorType,
                    "evidence": evidence,
                    "questionText": question["questionText"] as? String ?? ""
                ]
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
        let localStorage = QuestionLocalStorage.shared
        let allQuestions = localStorage.getLocalQuestions()

        // ✅ Filter out weaknesses that have no associated questions
        let weaknessesWithQuestions = status.activeWeaknesses.filter { (key, value) in
            let hasQuestions = allQuestions.contains { question in
                guard let weaknessKey = question["weaknessKey"] as? String else {
                    return false
                }
                return weaknessKey == key
            }

            if !hasQuestions {
                logger.debug("⚠️ Filtering out weakness '\(key)' - no questions found")
            }

            return hasQuestions
        }

        return weaknessesWithQuestions
            .sorted { $0.value.value > $1.value.value }
            .prefix(limit)
            .map { (key: $0.key, value: $0.value) }
    }

    // MARK: - Manual Removal

    /// Manually remove a weakness from active tracking
    /// Called when user taps the X button on a weakness card
    func removeWeakness(key: String) {
        guard status.activeWeaknesses[key] != nil else {
            logger.warning("Attempted to remove non-existent weakness: \(key)")
            return
        }

        status.activeWeaknesses.removeValue(forKey: key)
        save()

        logger.info("🗑️ Manually removed weakness: '\(key)'")
    }

    /// Remove a question's contribution to weakness tracking
    /// Called when user deletes a mistake question from Library
    /// - Parameters:
    ///   - questionId: The ID of the deleted question
    ///   - weaknessKey: The weakness key associated with this question
    ///   - errorType: The error type that contributed to the weakness (optional)
    func removeQuestionFromWeakness(questionId: String, weaknessKey: String?, errorType: String?) {
        print("🗑️ [WeaknessTracking] removeQuestionFromWeakness called:")
        print("   Question ID: \(questionId)")
        print("   Weakness Key: \(weaknessKey ?? "NONE")")
        print("   Error Type: \(errorType ?? "NONE")")

        // If we have a weakness key, update that specific weakness
        if let key = weaknessKey, var weakness = status.activeWeaknesses[key] {
            print("   📊 Found weakness for key: \(key)")
            print("      Current value: \(weakness.value)")
            print("      Question IDs before: \(weakness.recentQuestionIds)")

            // Remove question ID from recentQuestionIds
            let oldCount = weakness.recentQuestionIds.count
            weakness.recentQuestionIds.removeAll { $0 == questionId }
            let removed = oldCount - weakness.recentQuestionIds.count

            print("      Removed \(removed) occurrence(s) of question ID")
            print("      Question IDs after: \(weakness.recentQuestionIds)")

            // ✅ CONSERVATIVE: Decrement weakness value by error type weight
            // This prevents inflated weakness scores when questions are deleted
            if let errorType = errorType {
                let decrement = errorTypeWeight(errorType)
                let oldValue = weakness.value
                weakness.value = max(0, weakness.value - decrement)  // Never go below 0

                print("      Decrementing value by \(decrement) (error type: \(errorType))")
                print("      Value changed: \(oldValue) → \(weakness.value)")
            }

            // If weakness is now empty (no recent questions) and value is small, remove it
            if weakness.recentQuestionIds.isEmpty && weakness.value < 1.0 {
                status.activeWeaknesses.removeValue(forKey: key)
                print("      ✅ Removed weakness key (empty + low value)")
            } else {
                status.activeWeaknesses[key] = weakness
                print("      ✅ Updated weakness key")
            }

            save()
        } else if let key = weaknessKey {
            // Weakness key provided but not found (already migrated or removed)
            print("   ⚠️ Weakness key '\(key)' not found in active weaknesses (possibly migrated)")
        } else {
            // No weakness key - scan all weaknesses to remove question ID
            print("   🔍 No weakness key provided - scanning all weaknesses")
            var updated = false

            for (key, var weakness) in status.activeWeaknesses {
                if weakness.recentQuestionIds.contains(questionId) {
                    print("      Found question ID in key: \(key)")
                    weakness.recentQuestionIds.removeAll { $0 == questionId }

                    // Same cleanup logic
                    if weakness.recentQuestionIds.isEmpty && weakness.value < 1.0 {
                        status.activeWeaknesses.removeValue(forKey: key)
                        print("      ✅ Removed weakness key (empty + low value)")
                    } else {
                        status.activeWeaknesses[key] = weakness
                        print("      ✅ Updated weakness key")
                    }
                    updated = true
                }
            }

            if updated {
                save()
                print("   ✅ Completed scan and update")
            } else {
                print("   ℹ️ Question ID not found in any weakness")
            }
        }

        print("   📊 Final state: \(status.activeWeaknesses.count) active weaknesses")
    }

    // MARK: - Handwriting Recording (for report generation)

    /// Record handwriting score (updates short-term + appends to long-term)
    func recordHandwritingScore(
        score: Float,
        feedback: String?,
        subject: String?,
        questionCount: Int
    ) {
        // Update short-term (recent)
        status.recentHandwritingScore = score
        status.recentHandwritingFeedback = feedback
        status.recentHandwritingDate = Date()

        // Append to long-term history
        var history = loadHandwritingHistory()

        let snapshot = HandwritingSnapshot(
            score: score,
            date: Date(),
            subject: subject,
            questionCount: questionCount
        )

        history.records.append(snapshot)

        // Keep last 100 records only (limit storage)
        if history.records.count > 100 {
            history.records = Array(history.records.suffix(100))
        }

        saveHandwritingHistory(history)
        save() // Save ShortTermStatus

        logger.info("✅ Recorded handwriting: \(score)/10 (total records: \(history.records.count))")
    }

    // MARK: - Handwriting History Storage

    private func loadHandwritingHistory() -> HandwritingHistory {
        if let data = UserDefaults.standard.data(forKey: ShortTermStatusStorageKeys.handwritingHistory),
           let decoded = try? JSONDecoder().decode(HandwritingHistory.self, from: data) {
            return decoded
        }
        return HandwritingHistory()
    }

    private func saveHandwritingHistory(_ history: HandwritingHistory) {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: ShortTermStatusStorageKeys.handwritingHistory)
        }
    }

    /// Get handwriting history (for report generation)
    func getHandwritingHistory() -> HandwritingHistory {
        return loadHandwritingHistory()
    }
}
