//
//  PointsEarningSystem.swift
//  StudyAI
//
//  Points earning system with configurable learning goals
//

import Foundation
import SwiftUI
import Combine
import UIKit
import os.log


// MARK: - Weekly Progress Models

struct DailyQuestionActivity: Codable, Identifiable {
    var id: UUID
    let date: String // "2024-01-15" (server calculated date)
    let dayOfWeek: Int // 1-7, Monday=1
    var questionCount: Int
    let timezone: String

    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.date = try container.decode(String.self, forKey: .date)
        self.dayOfWeek = try container.decode(Int.self, forKey: .dayOfWeek)
        self.questionCount = try container.decode(Int.self, forKey: .questionCount)
        self.timezone = try container.decode(String.self, forKey: .timezone)
    }

    // Regular initializer for programmatic creation
    init(id: UUID = UUID(), date: String, dayOfWeek: Int, questionCount: Int, timezone: String) {
        self.id = id
        self.date = date
        self.dayOfWeek = dayOfWeek
        self.questionCount = questionCount
        self.timezone = timezone
    }

    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case date, dayOfWeek, questionCount, timezone
    }
    
    var intensityLevel: ActivityIntensity {
        switch questionCount {
        case 0: return .none
        case 1...5: return .light
        case 6...15: return .medium
        case 16...: return .high
        default: return .none
        }
    }
    
    var dayName: String {
        switch dayOfWeek {
        case 1: return "Mon"
        case 2: return "Tue"
        case 3: return "Wed"
        case 4: return "Thu"
        case 5: return "Fri"
        case 6: return "Sat"
        case 7: return "Sun"
        default: return "?"
        }
    }
}

enum ActivityIntensity: String, CaseIterable, Codable {
    case none = "none"
    case light = "light" 
    case medium = "medium"
    case high = "high"
    
    var color: Color {
        switch self {
        case .none: return Color.gray.opacity(0.1)
        case .light: return Color.green.opacity(0.4)
        case .medium: return Color.green.opacity(0.7)
        case .high: return Color.green // Solid green for maximum contrast
        }
    }
}

struct WeeklyProgress: Codable {
    let weekStart: String // "2024-01-15" (server calculated)
    let weekEnd: String   // "2024-01-21" (server calculated)
    var totalQuestionsThisWeek: Int
    var dailyActivities: [DailyQuestionActivity]
    let timezone: String
    let serverTimestamp: Date
    
    var weekDisplayString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"

        guard let startDate = dateFromString(weekStart),
              let endDate = dateFromString(weekEnd) else {
            return "Current Week"
        }

        let displayString = "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        return displayString
    }
    
    private func dateFromString(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: timezone)
        return formatter.date(from: dateString)
    }
}

struct WeeklyProgressRequest: Codable {
    let questionCount: Int
    let subject: String
    let clientTimestamp: String // ISO 8601 with timezone
    let clientTimezone: String  // IANA timezone identifier
}

struct ServerWeeklyProgressResponse: Codable {
    let currentWeek: WeeklyProgress
    let timezone: String
    let serverTimestamp: Date
    let success: Bool
    let message: String?
}

// MARK: - Learning Goals Configuration

struct LearningGoal: Codable, Identifiable {
    var id: UUID
    let type: LearningGoalType
    let title: String
    let description: String
    let targetValue: Int
    let basePoints: Int
    let bonusMultiplier: Double
    var currentProgress: Int = 0
    let isDaily: Bool
    let isWeekly: Bool

    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.type = try container.decode(LearningGoalType.self, forKey: .type)
        self.title = try container.decode(String.self, forKey: .title)
        self.description = try container.decode(String.self, forKey: .description)
        self.targetValue = try container.decode(Int.self, forKey: .targetValue)
        self.basePoints = try container.decode(Int.self, forKey: .basePoints)
        self.bonusMultiplier = try container.decode(Double.self, forKey: .bonusMultiplier)
        self.currentProgress = try container.decodeIfPresent(Int.self, forKey: .currentProgress) ?? 0
        self.isDaily = try container.decode(Bool.self, forKey: .isDaily)
        self.isWeekly = try container.decode(Bool.self, forKey: .isWeekly)
        self.isCheckedOut = try container.decodeIfPresent(Bool.self, forKey: .isCheckedOut) ?? false
    }

    // Regular initializer for programmatic creation
    init(id: UUID = UUID(), type: LearningGoalType, title: String, description: String, targetValue: Int, basePoints: Int, bonusMultiplier: Double, currentProgress: Int = 0, isDaily: Bool, isWeekly: Bool, isCheckedOut: Bool = false) {
        self.id = id
        self.type = type
        self.title = title
        self.description = description
        self.targetValue = targetValue
        self.basePoints = basePoints
        self.bonusMultiplier = bonusMultiplier
        self.currentProgress = currentProgress
        self.isDaily = isDaily
        self.isWeekly = isWeekly
        self.isCheckedOut = isCheckedOut
    }

    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case type, title, description, targetValue, basePoints, bonusMultiplier, currentProgress, isDaily, isWeekly, isCheckedOut
    }
    
    var progressPercentage: Double {
        return min(Double(currentProgress) / Double(targetValue) * 100, 100.0)
    }
    
    var isCompleted: Bool {
        return currentProgress >= targetValue
    }
    
    var pointsEarned: Int {
        if currentProgress >= targetValue {
            let bonusPoints = currentProgress > targetValue ?
                Int(Double(currentProgress - targetValue) * bonusMultiplier) : 0
            return basePoints + bonusPoints
        }
        return 0
    }

    // Track if this goal's points have been checked out
    var isCheckedOut: Bool = false

    // Calculate available points for checkout
    var availableCheckoutPoints: Int {
        if isCompleted && !isCheckedOut {
            return pointsEarned
        }
        return 0
    }
}

enum LearningGoalType: String, CaseIterable, Codable {
    case dailyQuestions = "daily_questions"
    case weeklyStreak = "weekly_streak"
    case dailyStreak = "daily_streak"
    case accuracyGoal = "accuracy_goal"
    case studyTime = "study_time"
    case subjectMastery = "subject_mastery"
    
    var displayName: String {
        switch self {
        case .dailyQuestions: return "Daily Questions"
        case .weeklyStreak: return "Weekly Streak"
        case .dailyStreak: return "Daily Streak"
        case .accuracyGoal: return "Accuracy Goal"
        case .studyTime: return "Study Time"
        case .subjectMastery: return "Subject Mastery"
        }
    }
    
    var icon: String {
        switch self {
        case .dailyQuestions: return "questionmark.circle.fill"
        case .weeklyStreak: return "flame.fill"
        case .dailyStreak: return "calendar.badge.checkmark"
        case .accuracyGoal: return "target"
        case .studyTime: return "clock.fill"
        case .subjectMastery: return "graduationcap.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .dailyQuestions: return .blue
        case .weeklyStreak: return .orange
        case .dailyStreak: return .red
        case .accuracyGoal: return .green
        case .studyTime: return .purple
        case .subjectMastery: return .indigo
        }
    }
}

// MARK: - Points System Manager

@MainActor
class PointsEarningManager: ObservableObject {
    static let shared = PointsEarningManager()

    private let instanceId = UUID().uuidString.prefix(8)
    private let logger = Logger(subsystem: "com.studyai", category: "PointsEarningManager")

    @Published var currentPoints: Int = 0
    @Published var totalPointsEarned: Int = 0
    @Published var learningGoals: [LearningGoal] = []
    @Published var dailyCheckoutHistory: [DailyCheckout] = []
    @Published var currentStreak: Int = 0
    private var lastStreakUpdateDate: String? // Track last date streak was updated (yyyy-MM-dd format)
    @Published var todayProgress: DailyProgress?
    @Published var dailyPointsEarned: Int = 0 // Track daily points to enforce 100 point maximum

    // MARK: - Weekly Progress Properties
    @Published var currentWeeklyProgress: WeeklyProgress?
    @Published var weeklyProgressHistory: [WeeklyProgress] = []
    @Published var lastTimezoneUpdate: Date?

    // MARK: - Concurrency Control
    private let syncQueue = DispatchQueue(label: "com.studyai.pointsmanager.sync", qos: .utility)

    // MARK: - Daily Reset Timer
    private var midnightTimer: Timer?
    private var dayChangeObserver: NSObjectProtocol?
    
    private let userDefaults = UserDefaults.standard
    private let pointsKey = "studyai_current_points"
    private let totalPointsKey = "studyai_total_points"
    private let goalsKey = "studyai_learning_goals"
    private let checkoutHistoryKey = "studyai_checkout_history"
    private let streakKey = "studyai_current_streak"
    private let weeklyProgressKey = "studyai_current_weekly_progress"
    private let weeklyHistoryKey = "studyai_weekly_progress_history"
    private let lastTimezoneKey = "studyai_last_timezone"
    private let todayProgressKey = "studyai_today_progress"
    private let lastResetDateKey = "studyai_last_reset_date"
    private let dailyPointsEarnedKey = "studyai_daily_points_earned"
    private let lastStreakUpdateDateKey = "studyai_last_streak_update_date"

    deinit {
        // Clean up timer and observers
        midnightTimer?.invalidate()
        if let observer = dayChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private init() {

        loadStoredData()
        setupDefaultGoals()

        // CRITICAL: Check daily reset BEFORE any server communication
        checkDailyReset()

        checkWeeklyReset()
        handleTimezoneChange()

        // Setup app termination handling for batched saves
        setupAppTerminationHandling()

        // Setup midnight reset timer
        setupMidnightResetTimer()

        // Setup day change notifications
        setupDayChangeNotifications()


        // Load current week from server asynchronously (AFTER daily reset check)
        Task {
            await loadCurrentWeekFromServer()
        }

        // CRITICAL: Load today's activity from server to sync with backend
        // This implements cache-first with server fallback strategy
        Task {
            await loadTodaysActivityWithCacheStrategy()
        }
    }

    /// Setup app termination handling to ensure data is saved
    private func setupAppTerminationHandling() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.forceSave()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.forceSave()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Check if we need to perform daily reset when app comes to foreground
            Task { @MainActor in
                self?.checkDailyResetOnForeground()
            }
        }

        // Setup periodic data integrity checks
        setupPeriodicIntegrityChecks()
    }

    /// Setup midnight reset timer to trigger daily resets at midnight
    private func setupMidnightResetTimer() {
        // Cancel existing timer if any
        midnightTimer?.invalidate()

        let calendar = Calendar.current
        let now = Date()

        // Calculate next midnight
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let nextMidnight = calendar.dateInterval(of: .day, for: tomorrow)?.start else {
            return
        }

        let timeUntilMidnight = nextMidnight.timeIntervalSince(now)

        // Create timer for midnight
        midnightTimer = Timer.scheduledTimer(withTimeInterval: timeUntilMidnight, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.performMidnightReset()
            }
        }
    }

    /// Setup day change notifications (fallback mechanism)
    private func setupDayChangeNotifications() {
        // Remove existing observer
        if let observer = dayChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        // Listen for day change notifications
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.performMidnightReset()
            }
        }
    }

    /// Perform midnight reset - triggered at midnight or day change
    private func performMidnightReset() {

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)

        let lastResetDateString = userDefaults.string(forKey: lastResetDateKey)


        // Only reset if we haven't reset today yet
        if lastResetDateString != todayString {

            // Calculate streak before resetting daily data
            updateStreakForNewDay()

            // Reset daily goals and checkout states
            resetDailyGoals()

            // Store today's date as the last reset date
            userDefaults.set(todayString, forKey: lastResetDateKey)

        } else {
        }

        // Setup next midnight timer
        setupMidnightResetTimer()

    }

    /// Check for daily reset when app comes to foreground
    private func checkDailyResetOnForeground() {

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)

        let lastResetDateString = userDefaults.string(forKey: lastResetDateKey)


        // Only reset if we haven't reset today yet
        if lastResetDateString != todayString {
            performMidnightReset()
        } else {
        }

    }

    /// Setup periodic data integrity checks and retry failed syncs
    private func setupPeriodicIntegrityChecks() {
        Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.performPeriodicMaintenance()
            }
        }
    }

    /// Perform periodic maintenance tasks
    private func performPeriodicMaintenance() async {
        // Check data integrity
        if !validateDataIntegrity() {
            // Check data integrity
        }

        // Force save to ensure data persistence
        await MainActor.run {
            self.forceSave()
        }
    }
    
    private func loadStoredData() {

        currentPoints = max(0, userDefaults.integer(forKey: pointsKey))
        totalPointsEarned = max(0, userDefaults.integer(forKey: totalPointsKey))
        currentStreak = max(0, userDefaults.integer(forKey: streakKey))
        dailyPointsEarned = max(0, userDefaults.integer(forKey: dailyPointsEarnedKey))
        lastStreakUpdateDate = userDefaults.string(forKey: lastStreakUpdateDateKey)


        // Load goals with validation
        if let goalsData = userDefaults.data(forKey: goalsKey),
           let decodedGoals = try? JSONDecoder().decode([LearningGoal].self, from: goalsData) {
            // Validate loaded goals
            learningGoals = decodedGoals.filter { goal in
                goal.targetValue > 0 && goal.basePoints >= 0 && goal.currentProgress >= 0
            }
            if learningGoals.count != decodedGoals.count {
            }
        } else {
        }

        // Load checkout history with size limits
        if let checkoutData = userDefaults.data(forKey: checkoutHistoryKey),
           let decodedCheckouts = try? JSONDecoder().decode([DailyCheckout].self, from: checkoutData) {
            // Keep only last 30 days to prevent unbounded growth
            dailyCheckoutHistory = Array(decodedCheckouts.suffix(30))
            if dailyCheckoutHistory.count != decodedCheckouts.count {
            }
        }

        // Load weekly progress data with validation
        if let weeklyData = userDefaults.data(forKey: weeklyProgressKey),
           let decodedWeekly = try? JSONDecoder().decode(WeeklyProgress.self, from: weeklyData) {

            // Validate that the decoded weekly progress has proper date format
            if validateWeeklyProgressData(decodedWeekly) {
                currentWeeklyProgress = decodedWeekly
            } else {
                userDefaults.removeObject(forKey: weeklyProgressKey)
                currentWeeklyProgress = nil
            }
        }
        
        if let weeklyHistoryData = userDefaults.data(forKey: weeklyHistoryKey),
           let decodedHistory = try? JSONDecoder().decode([WeeklyProgress].self, from: weeklyHistoryData) {
            weeklyProgressHistory = decodedHistory
        }

        lastTimezoneUpdate = userDefaults.object(forKey: lastTimezoneKey) as? Date

        // ✅ CRITICAL FIX: Never load todayProgress from disk in loadStoredData()
        // This prevents loading stale data from previous days or earlier launches today.
        // The proper data will be loaded by either:
        // 1. checkDailyReset() if we haven't reset yet today
        // 2. loadTodaysActivityWithCacheStrategy() from server
        // 3. trackQuestionAnswered() when user answers questions
        todayProgress = DailyProgress()
        logger.info("📊 [loadStoredData] Initialized todayProgress as empty (will be populated by cache strategy or question tracking)")
    }
    
    // MARK: - Batched UserDefaults Operations

    private let saveQueue = DispatchQueue(label: "com.studyai.pointsmanager.save", qos: .utility)
    private var pendingSaveTask: DispatchWorkItem?
    private let saveBatchDelay: TimeInterval = 0.5 // 500ms delay to batch saves

    /// Schedule a batched save operation to reduce I/O frequency
    private func scheduleBatchedSave() {
        saveQueue.async { [weak self] in
            guard let self = self else { return }

            // Cancel any pending save task
            self.pendingSaveTask?.cancel()

            // Create new save task with delay
            self.pendingSaveTask = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.performBatchedSave()
            }

            // Execute after delay
            self.saveQueue.asyncAfter(deadline: .now() + self.saveBatchDelay, execute: self.pendingSaveTask!)
        }
    }

    /// Perform the actual batched save operation
    private func performBatchedSave() {
        // Perform all UserDefaults operations in a single batch
        let updates: [String: Any?] = [
            pointsKey: currentPoints,
            totalPointsKey: totalPointsEarned,
            streakKey: currentStreak,
            dailyPointsEarnedKey: dailyPointsEarned,
            lastStreakUpdateDateKey: lastStreakUpdateDate,
            goalsKey: try? JSONEncoder().encode(learningGoals),
            checkoutHistoryKey: try? JSONEncoder().encode(dailyCheckoutHistory),
            weeklyProgressKey: currentWeeklyProgress.flatMap { try? JSONEncoder().encode($0) },
            weeklyHistoryKey: try? JSONEncoder().encode(weeklyProgressHistory),
            lastTimezoneKey: lastTimezoneUpdate,
            todayProgressKey: todayProgress.flatMap { try? JSONEncoder().encode($0) }
        ]

        // Apply all updates in batch
        for (key, value) in updates {
            if let value = value {
                userDefaults.set(value, forKey: key)
            } else {
                userDefaults.removeObject(forKey: key)
            }
        }

    }

    /// Legacy saveData method - now uses batched saving
    private func saveData() {
        scheduleBatchedSave()
    }

    /// Force immediate save (for critical operations like app termination)
    func forceSave() {
        pendingSaveTask?.cancel()
        performBatchedSave()
    }
    
    private func setupDefaultGoals() {

        if learningGoals.isEmpty {
            learningGoals = [
                LearningGoal(
                    type: .dailyQuestions,
                    title: "Daily Questions",
                    description: "Answer questions every day to build consistent learning habits",
                    targetValue: 5,
                    basePoints: 50,
                    bonusMultiplier: 10.0,
                    isDaily: true,
                    isWeekly: false
                ),
                LearningGoal(
                    type: .weeklyStreak,
                    title: "Weekly Streak",
                    description: "Maintain a 7-day learning streak to earn big bonus points",
                    targetValue: 7,
                    basePoints: 200,
                    bonusMultiplier: 50.0,
                    isDaily: false,
                    isWeekly: true
                ),
                LearningGoal(
                    type: .dailyStreak,
                    title: "Daily Streak",
                    description: "Keep your learning momentum going with daily activity",
                    targetValue: 1,
                    basePoints: 25,
                    bonusMultiplier: 5.0,
                    isDaily: true,
                    isWeekly: false
                ),
                LearningGoal(
                    type: .accuracyGoal,
                    title: "Accuracy Goal",
                    description: "Achieve high accuracy in your answers to maximize your score",
                    targetValue: 80,
                    basePoints: 100,
                    bonusMultiplier: 5.0,
                    isDaily: true,
                    isWeekly: false
                )
            ]
            saveData()
        } else {

            // Migration: Add Daily Streak goal if it doesn't exist (for existing users)
            let hasDailyStreak = learningGoals.contains { $0.type == .dailyStreak }

            if !hasDailyStreak {
                let dailyStreakGoal = LearningGoal(
                    type: .dailyStreak,
                    title: "Daily Streak",
                    description: "Keep your learning momentum going with daily activity",
                    targetValue: 1,
                    basePoints: 25,
                    bonusMultiplier: 5.0,
                    isDaily: true,
                    isWeekly: false
                )
                learningGoals.append(dailyStreakGoal)
                saveData()
            } else {
            }
        }

    }
    
    private func checkDailyReset() {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Use a more reliable method to track the last reset date
        let lastResetDateString = userDefaults.string(forKey: lastResetDateKey)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let todayString = dateFormatter.string(from: today)

        logger.info("🔄 [checkDailyReset] InstanceID: \(self.instanceId) - Checking daily reset")
        logger.info("🔄 [checkDailyReset] Today: \(todayString), Last Reset: \(lastResetDateString ?? "nil")")

        // ✅ FIX: Only reset on date change, never mid-day
        // Previous logic incorrectly reset when question count > 10, causing data loss
        logger.info("🔄 [checkDailyReset] Current todayProgress: \(self.todayProgress?.totalQuestions ?? 0) questions, \(self.todayProgress?.correctAnswers ?? 0) correct")

        // Reset ONLY if we haven't reset today yet (different date)
        let shouldReset = (lastResetDateString != todayString)

        if shouldReset {
            logger.info("🔄 [checkDailyReset] ⚠️ PERFORMING DAILY RESET - Reason: New day (was: \(lastResetDateString ?? "never"), now: \(todayString))")

            // Calculate streak before resetting daily data
            updateStreakForNewDay()

            // Reset daily goals and checkout states
            resetDailyGoals()

            // Store today's date as the last reset date
            userDefaults.set(todayString, forKey: lastResetDateKey)

            // Force save the changes
            forceSave()

            logger.info("🔄 [checkDailyReset] ✅ Daily reset completed - Date saved: \(todayString)")
        } else {
            logger.info("🔄 [checkDailyReset] ✅ No reset needed - Already reset today")
        }

    }
    
    private func resetDailyGoals() {

        // Show current state before reset
        if let currentProgress = todayProgress {
        } else {
        }


        // Reset all daily goal progress and checkout states
        for i in 0..<learningGoals.count {
            if learningGoals[i].isDaily {
                let oldProgress = learningGoals[i].currentProgress
                let wasCheckedOut = learningGoals[i].isCheckedOut

                learningGoals[i].currentProgress = 0
                learningGoals[i].isCheckedOut = false

            }
        }

        // Reset today's progress to zero
        todayProgress = DailyProgress()

        // CRITICAL: Reset daily points earned to 0 for new day
        dailyPointsEarned = 0

        // ✅ FIX: Do NOT reset lastStreakUpdateDate here!
        // It's managed by updateStreakForNewDay() and updateActivityBasedStreak()
        // to prevent multiple streak updates on the same day


        // Final state verification
        if let finalProgress = todayProgress {
        }

        saveData()
    }
    
    /// Update streak for new day based on actual user activity
    private func updateStreakForNewDay() {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let todayString = dateFormatter.string(from: today)
        let yesterdayString = dateFormatter.string(from: yesterday)

        // ✅ FIX: Prevent multiple streak updates on same day
        // Check if we've already updated the streak for this transition
        if let lastUpdate = lastStreakUpdateDate, lastUpdate == todayString {
            logger.info("🔥 [STREAK] Already updated streak for today (\(todayString)), skipping")
            return
        }

        // Check if user had any activity yesterday
        let hadActivityYesterday = checkActivityOnDate(yesterday)

        if hadActivityYesterday {
            // User was active yesterday, continue/increment streak
            currentStreak += 1
            logger.info("🔥 [STREAK] User was active yesterday (\(yesterdayString)), incrementing streak to \(self.currentStreak)")
        } else {
            // User was not active yesterday, reset streak to 0
            // Streak will be set to 1 when user becomes active today
            currentStreak = 0
            logger.info("🔥 [STREAK] User was NOT active yesterday (\(yesterdayString)), resetting streak to 0")
        }

        // Mark that we've updated the streak for today's transition
        lastStreakUpdateDate = todayString
        logger.info("🔥 [STREAK] Set lastStreakUpdateDate to \(todayString)")

        // Update streak-related goals
        updateWeeklyStreakGoal()
        updateDailyStreakGoal()

    }

    private func updateStreak() {
        // This method is kept for compatibility but simplified
        // Real streak logic is now handled by updateStreakForNewDay() and updateActivityBasedStreak()
        // This method is kept for compatibility but simplified
        updateWeeklyStreakGoal()
        updateDailyStreakGoal()
        saveData()
    }
    
    private func updateWeeklyStreakGoal() {
        for i in 0..<learningGoals.count {
            if learningGoals[i].type == .weeklyStreak {
                learningGoals[i].currentProgress = currentStreak
            }
        }
    }

    private func updateDailyStreakGoal() {
        for i in 0..<learningGoals.count {
            if learningGoals[i].type == .dailyStreak {
                // For daily streak, we just need 1 day (target is 1), so set to 1 if we have any activity today
                learningGoals[i].currentProgress = min(currentStreak, 1)
            }
        }
    }

    /// Update streak based on daily activity rather than manual checkouts
    private func updateActivityBasedStreak() {

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        // Create today's date string for comparison
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let todayString = dateFormatter.string(from: today)


        // Check if we've already updated the streak today
        if let lastUpdateDate = lastStreakUpdateDate, lastUpdateDate == todayString {
            return
        }

        // Check if we had activity yesterday by looking at weekly progress
        let hadActivityYesterday = checkActivityOnDate(yesterday)

        // Today we're having activity (since we're tracking a question)
        let hadActivityToday = true

        if hadActivityToday {
            if hadActivityYesterday {
                // Continue streak - we had activity yesterday and today
                currentStreak += 1
            } else {
                // Check if this is the first day of activity or if we're restarting
                if currentStreak == 0 {
                    // Starting new streak
                    currentStreak = 1
                } else {
                    // Had a gap, reset to 1 (today's activity)
                    currentStreak = 1
                }
            }

            // Mark that we've updated the streak for today
            lastStreakUpdateDate = todayString
        }

        // Update weekly streak goal
        updateWeeklyStreakGoal()
        updateDailyStreakGoal()

    }

    /// Check if there was any question activity on a specific date
    private func checkActivityOnDate(_ date: Date) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let dateString = dateFormatter.string(from: date)

        // Check in weekly progress activities
        if let weeklyProgress = currentWeeklyProgress {
            for activity in weeklyProgress.dailyActivities {
                if activity.date == dateString && activity.questionCount > 0 {
                    return true
                }
            }
        }

        // Also check historical weekly progress
        for weekProgress in weeklyProgressHistory {
            for activity in weekProgress.dailyActivities {
                if activity.date == dateString && activity.questionCount > 0 {
                    return true
                }
            }
        }

        return false
    }
    
    // MARK: - Public Methods

    /// Force check for daily reset (for debugging/testing purposes)
    func forceCheckDailyReset() {
        performMidnightReset()
    }

    /// Clear last reset date (for testing purposes)
    func clearLastResetDate() {
        userDefaults.removeObject(forKey: lastResetDateKey)
    }
    
    func trackQuestionAnswered(subject: String, isCorrect: Bool) {
        // Log user context for multi-device debugging
        logger.info("📊 [trackQuestionAnswered] InstanceID: \(self.instanceId) - Tracking question for subject: \(subject), isCorrect: \(isCorrect)")

        // Create data backup before critical operation
        let backup = createDataBackup()

        // Validate data integrity before proceeding
        guard validateDataIntegrity() else {
            // Data integrity check failed, restoring from backup
            restoreFromBackup(backup)
            return
        }

        // Ensure todayProgress exists
        if todayProgress == nil {
            todayProgress = DailyProgress()
        }

        guard var currentProgress = todayProgress else {
            return
        }

        // Update daily questions goal with bounds checking
        for i in 0..<learningGoals.count {
            if learningGoals[i].type == .dailyQuestions {
                learningGoals[i].currentProgress = max(0, learningGoals[i].currentProgress + 1)
            }
        }

        // Update question counts with safe access
        currentProgress.totalQuestions = max(0, currentProgress.totalQuestions + 1)
        if isCorrect {
            currentProgress.correctAnswers = max(0, currentProgress.correctAnswers + 1)
        }

        // Update the published property
        todayProgress = currentProgress

        // Update accuracy goal
        updateAccuracyGoal()

        // Update streak based on daily activity (not manual checkouts)
        updateActivityBasedStreak()

        // Update weekly progress tracking
        updateWeeklyProgress(questionCount: 1, subject: subject)

        // Validate consistency between today's progress and weekly grid
        validateTodayConsistency()

        // Save data with logging
        saveData()

        // Sync to server immediately to update subject breakdown
        Task {
            await NetworkService.shared.trackQuestionAnswered(
                subject: subject,
                isCorrect: isCorrect,
                studyTimeSeconds: 0
            )

            // Invalidate subject breakdown cache after successful sync
            // This ensures next progress view load fetches fresh data
            SubjectBreakdownCache.shared.invalidateCache(timeframe: "today")
            SubjectBreakdownCache.shared.invalidateCache(timeframe: "week")
            SubjectBreakdownCache.shared.invalidateCache(timeframe: "month")
        }
    }
    
    func trackStudyTime(_ minutes: Int) {
        guard minutes > 0 else {
            return
        }

        for i in 0..<learningGoals.count {
            if learningGoals[i].type == .studyTime {
                let oldProgress = learningGoals[i].currentProgress
                learningGoals[i].currentProgress = max(0, learningGoals[i].currentProgress + minutes)
            }
        }

        // Update today's progress with study time
        if var currentProgress = todayProgress {
            currentProgress.studyTimeMinutes = max(0, currentProgress.studyTimeMinutes + minutes)
            todayProgress = currentProgress
        } else {
            var newProgress = DailyProgress()
            newProgress.studyTimeMinutes = minutes
            todayProgress = newProgress
        }

        saveData()
    }
    
    private func updateAccuracyGoal() {
        guard let progress = todayProgress, progress.totalQuestions > 0 else { return }
        
        let accuracy = Int((Double(progress.correctAnswers) / Double(progress.totalQuestions)) * 100)
        
        for i in 0..<learningGoals.count {
            if learningGoals[i].type == .accuracyGoal {
                learningGoals[i].currentProgress = accuracy
            }
        }
    }
    
    func performDailyCheckout() -> DailyCheckout {
        let checkout = DailyCheckout(
            date: Date(),
            pointsEarned: calculateDailyPoints(),
            goalsCompleted: learningGoals.filter { $0.isCompleted }.count,
            streak: currentStreak,
            isWeekend: Calendar.current.isDateInWeekend(Date())
        )
        
        // Apply weekend bonus if applicable
        let finalPoints = checkout.isWeekend ? checkout.pointsEarned * 2 : checkout.pointsEarned
        
        currentPoints += finalPoints
        totalPointsEarned += finalPoints
        dailyCheckoutHistory.append(checkout)
        
        // Keep only last 30 days of checkout history
        if dailyCheckoutHistory.count > 30 {
            dailyCheckoutHistory.removeFirst(dailyCheckoutHistory.count - 30)
        }
        
        saveData()
        return checkout
    }
    
    private func calculateDailyPoints() -> Int {
        var totalPoints = 0
        
        for goal in learningGoals {
            if goal.isDaily {
                totalPoints += goal.pointsEarned
            }
        }
        
        // Add weekly streak bonus if applicable
        let weeklyGoal = learningGoals.first { $0.type == .weeklyStreak }
        if let weeklyGoal = weeklyGoal, weeklyGoal.isCompleted {
            totalPoints += weeklyGoal.pointsEarned
        }
        
        return totalPoints
    }
    
    func updateLearningGoal(_ goalId: UUID, targetValue: Int) {
        guard targetValue > 0 else {
            return
        }

        guard let index = learningGoals.firstIndex(where: { $0.id == goalId }) else {
            return
        }

        guard index >= 0 && index < learningGoals.count else {
            return
        }

        let currentGoal = learningGoals[index]
        learningGoals[index] = LearningGoal(
            type: currentGoal.type,
            title: currentGoal.title,
            description: currentGoal.description,
            targetValue: max(1, targetValue), // Ensure minimum target value of 1
            basePoints: max(0, currentGoal.basePoints),
            bonusMultiplier: max(0.0, currentGoal.bonusMultiplier),
            currentProgress: max(0, currentGoal.currentProgress),
            isDaily: currentGoal.isDaily,
            isWeekly: currentGoal.isWeekly
        )

        saveData()
    }

    // MARK: - Enhanced Checkout Methods

    /// Calculate available points for a specific goal with smart logic
    func calculateAvailablePoints(for goal: LearningGoal) -> Int {
        guard goal.isCompleted && !goal.isCheckedOut else {
            return 0
        }

        // Ensure goal progress and target values are valid
        guard goal.currentProgress >= 0,
              goal.targetValue > 0,
              goal.basePoints >= 0 else {
            return 0
        }

        switch goal.type {
        case .dailyQuestions:
            // Base points: 1 point per question (up to target)
            let basePoints = min(max(0, goal.currentProgress), max(1, goal.targetValue))

            // Check if accuracy goal is also completed for doubling
            let accuracyGoal = learningGoals.first { $0.type == .accuracyGoal }
            let hasAccuracyMultiplier = accuracyGoal?.isCompleted == true && accuracyGoal?.isCheckedOut == false

            return hasAccuracyMultiplier ? max(0, basePoints * 2) : max(0, basePoints)

        case .accuracyGoal:
            // Accuracy goal provides a multiplier bonus for daily questions
            let dailyQuestionsGoal = learningGoals.first { $0.type == .dailyQuestions }
            if let dailyGoal = dailyQuestionsGoal,
               dailyGoal.isCompleted,
               dailyGoal.currentProgress > 0,
               dailyGoal.targetValue > 0 {
                return max(0, min(dailyGoal.currentProgress, dailyGoal.targetValue))
            }
            return 0

        case .dailyStreak:
            return 10 // Fixed 10 points for daily streak

        case .weeklyStreak:
            return max(0, goal.basePoints) // Use configured base points with bounds checking

        default:
            return max(0, goal.basePoints)
        }
    }

    /// Checkout points for a specific goal
    func checkoutGoal(_ goalId: UUID) -> Int {
        logger.info("[CHECKOUT] === CHECKING OUT GOAL ===")

        guard let index = learningGoals.firstIndex(where: { $0.id == goalId }) else {
            logger.info("[CHECKOUT] ❌ Goal not found")
            return 0
        }

        let goal = learningGoals[index]
        logger.info("[CHECKOUT] Goal: \(goal.title), Type: \(goal.type.rawValue)")
        logger.info("[CHECKOUT] Progress: \(goal.currentProgress)/\(goal.targetValue), Completed: \(goal.isCompleted), CheckedOut: \(goal.isCheckedOut)")

        let pointsToAdd = calculateAvailablePoints(for: goal)
        logger.info("[CHECKOUT] Available points: \(pointsToAdd)")

        guard pointsToAdd > 0 else {
            logger.info("[CHECKOUT] ❌ No points available")
            return 0
        }

        // Apply daily maximum of 100 points logic
        let remainingDailyPoints = max(0, 100 - dailyPointsEarned)
        let actualPointsToAdd = min(pointsToAdd, remainingDailyPoints)
        logger.info("[CHECKOUT] Daily points earned: \(self.dailyPointsEarned)/100, Remaining: \(remainingDailyPoints)")
        logger.info("[CHECKOUT] Actual points to add: \(actualPointsToAdd)")

        // If no points can be added due to daily limit, return early
        guard actualPointsToAdd > 0 else {
            logger.info("[CHECKOUT] ❌ Daily limit reached")
            return 0
        }

        // Mark goal as checked out
        learningGoals[index].isCheckedOut = true

        // Add points to total and daily counter with bounds checking
        let oldCurrentPoints = currentPoints
        let oldTotalPoints = totalPointsEarned
        currentPoints = max(0, currentPoints + actualPointsToAdd)
        totalPointsEarned = max(0, totalPointsEarned + actualPointsToAdd)
        dailyPointsEarned = max(0, dailyPointsEarned + actualPointsToAdd)

        logger.info("[CHECKOUT] Points updated: current \(oldCurrentPoints) → \(self.currentPoints), total \(oldTotalPoints) → \(self.totalPointsEarned)")

        // Apply weekend bonus if applicable
        let finalPoints = Calendar.current.isDateInWeekend(Date()) ? actualPointsToAdd * 2 : actualPointsToAdd
        logger.info("[CHECKOUT] Final points (with weekend bonus if applicable): \(finalPoints)")

        // Save changes
        saveData()

        // Sync total points with backend asynchronously
        Task {
            await syncTotalPointsWithBackend()
        }

        logger.info("[CHECKOUT] ✅ Checkout complete")
        logger.info("[CHECKOUT] === END CHECKOUT ===")

        return finalPoints
    }

    /// Reset daily checkout states
    private func resetDailyCheckouts() {
        guard !learningGoals.isEmpty else {
            return
        }

        for i in 0..<learningGoals.count {
            guard i >= 0 && i < learningGoals.count else {
                continue
            }

            if learningGoals[i].isDaily {
                learningGoals[i].isCheckedOut = false
            }
        }

    }

    /// Calculate total available checkout points across all goals
    var totalAvailableCheckoutPoints: Int {
        guard !learningGoals.isEmpty else {
            return 0
        }

        let total = learningGoals.reduce(0) { total, goal in
            let points = calculateAvailablePoints(for: goal)
            return total + max(0, points) // Ensure no negative points are added
        }

        return max(0, total) // Ensure total is never negative
    }
    
    func resetProgress() {

        // Reset point counters with bounds checking
        currentPoints = 0
        totalPointsEarned = 0
        currentStreak = 0
        dailyPointsEarned = 0
        lastStreakUpdateDate = nil

        // Reset learning goals progress with validation
        if learningGoals.isEmpty {
        }

        for i in 0..<learningGoals.count {
            guard i >= 0 && i < learningGoals.count else {
                continue
            }

            learningGoals[i].currentProgress = 0
            learningGoals[i].isCheckedOut = false
        }

        // Clear history arrays
        dailyCheckoutHistory.removeAll()
        weeklyProgressHistory.removeAll()

        // Reset progress data
        currentWeeklyProgress = nil
        todayProgress = DailyProgress()

        // ✅ FIX: Completely remove all UserDefaults keys instead of saving empty values
        // This ensures storage is truly cleared (0 KB instead of 1 KB)
        userDefaults.removeObject(forKey: pointsKey)
        userDefaults.removeObject(forKey: totalPointsKey)
        userDefaults.removeObject(forKey: streakKey)
        userDefaults.removeObject(forKey: dailyPointsEarnedKey)
        userDefaults.removeObject(forKey: lastStreakUpdateDateKey)
        userDefaults.removeObject(forKey: goalsKey)
        userDefaults.removeObject(forKey: checkoutHistoryKey)
        userDefaults.removeObject(forKey: weeklyProgressKey)
        userDefaults.removeObject(forKey: weeklyHistoryKey)
        userDefaults.removeObject(forKey: lastTimezoneKey)
        userDefaults.removeObject(forKey: todayProgressKey)
        userDefaults.removeObject(forKey: lastResetDateKey)

        print("✅ [resetProgress] Completely removed all progress data from UserDefaults")

    }
    
    // MARK: - Weekly Progress Methods
    
    /// Update daily activity in local data structure (for UI display)
    /// Server sync is handled separately by trackQuestionAnswered()
    func updateWeeklyProgress(questionCount: Int, subject: String) {
        guard questionCount > 0 else {
            return
        }

        // Update local data structure for immediate UI updates
        // This maintains currentWeeklyProgress which is displayed in WeeklyProgressGrid
        updateLocalWeeklyProgress(questionCount: questionCount)

        // Note: Server sync is now handled by trackQuestionAnswered() API call
        // No need for duplicate syncWithServer() call here
    }
    
    /// Update local weekly progress data structure
    private func updateLocalWeeklyProgress(questionCount: Int) {
        guard questionCount > 0 else {
            return
        }

        let currentDate = Date()
        let calendar = Calendar.current
        let timezone = TimeZone.current.identifier

        // Create or update current week progress
        if currentWeeklyProgress == nil {
            print("📊 [updateLocalWeeklyProgress] Creating new currentWeeklyProgress")
            currentWeeklyProgress = createCurrentWeekProgress(timezone: timezone)
        }

        guard var weeklyProgress = currentWeeklyProgress else {
            print("❌ [updateLocalWeeklyProgress] Failed to get weeklyProgress")
            return
        }

        print("📊 [updateLocalWeeklyProgress] Current weeklyProgress has \(weeklyProgress.dailyActivities.count) activities")

        // Get today's date string
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let todayString = dateFormatter.string(from: currentDate)

        print("📊 [updateLocalWeeklyProgress] Today's date: \(todayString), adding \(questionCount) questions")

        // Find or create today's activity
        if let existingIndex = weeklyProgress.dailyActivities.firstIndex(where: { $0.date == todayString }) {
            // Update existing day with bounds checking
            let currentCount = weeklyProgress.dailyActivities[existingIndex].questionCount
            weeklyProgress.dailyActivities[existingIndex].questionCount = max(0, currentCount + questionCount)
            print("📊 [updateLocalWeeklyProgress] ✅ Updated existing activity at index \(existingIndex): \(currentCount) → \(weeklyProgress.dailyActivities[existingIndex].questionCount)")
        } else {
            // Add new day activity
            let dayOfWeek = calendar.component(.weekday, from: currentDate)
            let adjustedDayOfWeek = dayOfWeek == 1 ? 7 : dayOfWeek - 1 // Convert Sunday=1 to Sunday=7, Monday=2 to Monday=1

            guard adjustedDayOfWeek >= 1 && adjustedDayOfWeek <= 7 else {
                print("❌ [updateLocalWeeklyProgress] Invalid dayOfWeek: \(adjustedDayOfWeek)")
                return
            }

            let newActivity = DailyQuestionActivity(
                date: todayString,
                dayOfWeek: adjustedDayOfWeek,
                questionCount: max(0, questionCount),
                timezone: timezone
            )
            weeklyProgress.dailyActivities.append(newActivity)
            print("📊 [updateLocalWeeklyProgress] ✅ Created new activity: date=\(todayString), dayOfWeek=\(adjustedDayOfWeek), count=\(questionCount)")
        }

        // Update total questions for the week with bounds checking
        weeklyProgress.totalQuestionsThisWeek = max(0, weeklyProgress.dailyActivities.reduce(0) { $0 + $1.questionCount })

        print("📊 [updateLocalWeeklyProgress] Total questions this week: \(weeklyProgress.totalQuestionsThisWeek)")
        print("📊 [updateLocalWeeklyProgress] Final dailyActivities count: \(weeklyProgress.dailyActivities.count)")

        // Save updated progress
        currentWeeklyProgress = weeklyProgress
        saveData()
    }
    
    /// Create a new week progress structure for the current week
    private func createCurrentWeekProgress(timezone: String) -> WeeklyProgress {
        let calendar = Calendar.current
        let now = Date()
        
        // Find the start of the current week (Monday)
        let weekday = calendar.component(.weekday, from: now)
        let daysFromMonday = (weekday == 1) ? 6 : weekday - 2 // Sunday=1, so 6 days back to Monday
        
        guard let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: now),
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            // Fallback to current date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone.current
            let todayString = dateFormatter.string(from: now)
            
            return WeeklyProgress(
                weekStart: todayString,
                weekEnd: todayString,
                totalQuestionsThisWeek: 0,
                dailyActivities: [],
                timezone: timezone,
                serverTimestamp: now
            )
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        
        let weekStartString = dateFormatter.string(from: weekStart)
        let weekEndString = dateFormatter.string(from: weekEnd)
        
        // Create empty daily activities for the week
        var dailyActivities: [DailyQuestionActivity] = []
        for i in 0..<7 {
            if let dayDate = calendar.date(byAdding: .day, value: i, to: weekStart) {
                let dayString = dateFormatter.string(from: dayDate)
                let dayOfWeek = i + 1 // Monday = 1, Sunday = 7
                
                let activity = DailyQuestionActivity(
                    date: dayString,
                    dayOfWeek: dayOfWeek,
                    questionCount: 0,
                    timezone: timezone
                )
                dailyActivities.append(activity)
            }
        }
        
        
        return WeeklyProgress(
            weekStart: weekStartString,
            weekEnd: weekEndString,
            totalQuestionsThisWeek: 0,
            dailyActivities: dailyActivities,
            timezone: timezone,
            serverTimestamp: now
        )
    }
    
    /// Validate that weekly progress data has proper date format
    private func validateWeeklyProgressData(_ weeklyProgress: WeeklyProgress) -> Bool {
        // Check if dates are in proper format (yyyy-MM-dd)
        let dateRegex = "^\\d{4}-\\d{2}-\\d{2}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", dateRegex)

        let weekStartValid = predicate.evaluate(with: weeklyProgress.weekStart)
        let weekEndValid = predicate.evaluate(with: weeklyProgress.weekEnd)

        if !weekStartValid || !weekEndValid {
            return false
        }

        // Check if weekDisplayString works (doesn't return fallback text)
        let displayString = weeklyProgress.weekDisplayString
        if displayString == "Current Week" {
            return false
        }

        return true
    }

    /// Clear cached weekly progress data and force fresh creation
    func clearWeeklyProgressCache() {
        userDefaults.removeObject(forKey: weeklyProgressKey)
        userDefaults.removeObject(forKey: weeklyHistoryKey)
        currentWeeklyProgress = nil
        weeklyProgressHistory = []

        // Force create fresh weekly progress
        checkWeeklyReset()
    }

    /// Validate consistency between todayProgress and weekly grid today
    private func validateTodayConsistency() {
        guard let todayProgress = todayProgress,
              let weeklyProgress = currentWeeklyProgress else {
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let today = dateFormatter.string(from: Date())

        // Find today's activity in weekly progress
        guard let weeklyToday = weeklyProgress.dailyActivities.first(where: { $0.date == today }) else {
            logger.warning("[CONSISTENCY] Today (\(today)) not found in weekly progress")
            return
        }

        // Check if counts match
        if todayProgress.totalQuestions != weeklyToday.questionCount {
            logger.warning("[CONSISTENCY] ⚠️ MISMATCH DETECTED:")
            logger.warning("[CONSISTENCY]   todayProgress.totalQuestions = \(todayProgress.totalQuestions)")
            logger.warning("[CONSISTENCY]   weeklyProgress today = \(weeklyToday.questionCount)")
            logger.warning("[CONSISTENCY] ✅ Auto-fixing: Using weekly progress as source of truth")

            // Auto-fix: Use weekly progress as source of truth
            self.todayProgress = DailyProgress(
                totalQuestions: weeklyToday.questionCount,
                correctAnswers: todayProgress.correctAnswers, // Keep original correct count
                studyTimeMinutes: todayProgress.studyTimeMinutes,
                subjectsStudied: todayProgress.subjectsStudied
            )

            saveData()
            logger.info("[CONSISTENCY] ✅ Fixed todayProgress to match weekly grid")
        } else {
            logger.debug("[CONSISTENCY] ✅ todayProgress and weekly grid are consistent: \(todayProgress.totalQuestions) questions")
        }
    }

    /// Check if we need to start a new week (called on app launch)
    func checkWeeklyReset() {

        guard let currentWeekly = currentWeeklyProgress else {
            // No current week data, create new week
            currentWeeklyProgress = createCurrentWeekProgress(timezone: TimeZone.current.identifier)
            saveData()
            return
        }


        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current

        let today = dateFormatter.string(from: Date())

        // Check if today is within the current week range
        if today < currentWeekly.weekStart || today > currentWeekly.weekEnd {

            // Archive current week if it has data
            if currentWeekly.totalQuestionsThisWeek > 0 {
                weeklyProgressHistory.append(currentWeekly)

                // Keep only last 12 weeks of history
                if weeklyProgressHistory.count > 12 {
                    weeklyProgressHistory.removeFirst(weeklyProgressHistory.count - 12)
                }
            }

            // Start new week
            currentWeeklyProgress = createCurrentWeekProgress(timezone: TimeZone.current.identifier)
            saveData()
        } else {
        }

    }
    
    /// Get activity for a specific date
    func getActivityForDate(_ dateString: String) -> DailyQuestionActivity? {
        return currentWeeklyProgress?.dailyActivities.first { $0.date == dateString }
    }
    
    /// Handle timezone changes (for traveling users)
    func handleTimezoneChange() {
        let currentTimezone = TimeZone.current.identifier
        let storedTimezone = userDefaults.string(forKey: "lastUserTimezone")
        
        if currentTimezone != storedTimezone {
            
            // Update stored timezone
            userDefaults.set(currentTimezone, forKey: "lastUserTimezone")
            lastTimezoneUpdate = Date()
            
            // For now, just update the timezone in current progress
            // In production, this would trigger server sync
            if var weeklyProgress = currentWeeklyProgress {
                // Update timezone but keep existing data
                weeklyProgress = WeeklyProgress(
                    weekStart: weeklyProgress.weekStart,
                    weekEnd: weeklyProgress.weekEnd,
                    totalQuestionsThisWeek: weeklyProgress.totalQuestionsThisWeek,
                    dailyActivities: weeklyProgress.dailyActivities.map { activity in
                        DailyQuestionActivity(
                            date: activity.date,
                            dayOfWeek: activity.dayOfWeek,
                            questionCount: activity.questionCount,
                            timezone: currentTimezone
                        )
                    },
                    timezone: currentTimezone,
                    serverTimestamp: Date()
                )
                currentWeeklyProgress = weeklyProgress
            }
            
            saveData()
        }
    }

    // MARK: - Server Sync Methods

    /// Load today's activity from server only if we haven't reset today
    func loadTodaysActivityFromServerIfNotReset() async {
        logger.info("[SERVER_LOAD] === CHECKING IF SHOULD LOAD TODAY'S ACTIVITY FROM SERVER ===")

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)
        let lastResetDateString = userDefaults.string(forKey: lastResetDateKey)

        logger.info("[SERVER_LOAD] Today: \(todayString), Last reset: \(lastResetDateString ?? "none")")

        // Check if we have any local activity today (indicating we shouldn't load from server)
        let hasLocalActivityToday = todayProgress?.totalQuestions ?? 0 > 0

        logger.info("[SERVER_LOAD] Has local activity today: \(hasLocalActivityToday) (\(self.todayProgress?.totalQuestions ?? 0) questions)")

        // Only load from server if:
        // 1. We have reset today (lastResetDateString == todayString) AND
        // 2. We don't have any local activity yet (fresh reset state)
        if lastResetDateString == todayString && !hasLocalActivityToday {
            logger.info("[SERVER_LOAD] Loading from server is safe - we've reset today and have no local activity")
            await loadTodaysActivityFromServerWithConflictResolution()
        } else {
            logger.info("[SERVER_LOAD] NOT loading from server - either haven't reset today OR have local activity to preserve")
        }

        logger.info("[SERVER_LOAD] === END CHECKING IF SHOULD LOAD TODAY'S ACTIVITY FROM SERVER ===")
    }

    /// NEW: Load today's activity with cache-first strategy
    /// This implements: 1) Use local if available, 2) Otherwise load from server
    private func loadTodaysActivityWithCacheStrategy() async {
        // Get user ID for diagnostic logging
        let authService = await MainActor.run { AuthenticationService.shared }
        let currentUserId = await MainActor.run { authService.currentUser?.id }
        let currentUserEmail = await MainActor.run { authService.currentUser?.email }

        // Check if we have valid local data
        let hasValidLocalData = todayProgress?.totalQuestions ?? 0 > 0

        // Get last reset date for context
        let lastResetDateString = userDefaults.string(forKey: lastResetDateKey)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)

        if hasValidLocalData {
            // Local cache is available and valid, use it
            return
        }

        // No local data or local data is empty - load from server
        guard let networkService = await getNetworkService() else {
            return
        }

        let result = await networkService.getTodaysActivity(
            timezone: TimeZone.current.identifier
        )

        if result.success, let serverTodayProgress = result.todayProgress {
            await MainActor.run {
                // ✅ SAFETY: Validate server data before using it
                guard serverTodayProgress.totalQuestions >= 0,
                      serverTodayProgress.correctAnswers >= 0,
                      serverTodayProgress.correctAnswers <= serverTodayProgress.totalQuestions else {
                    return
                }

                // ✅ CRITICAL: Cross-reference with weekly progress to detect stale data
                // The "today" endpoint sometimes returns stale data from previous days
                // If today's date doesn't appear in weekly progress, use 0 instead
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone.current
                let todayString = dateFormatter.string(from: today)

                // Check if today exists in weekly progress data
                var todayActivityFromWeekly: DailyQuestionActivity? = nil
                if let weeklyProgress = self.currentWeeklyProgress {
                    todayActivityFromWeekly = weeklyProgress.dailyActivities.first { $0.date == todayString }
                }

                if let weeklyActivity = todayActivityFromWeekly {
                    // Today's date exists in weekly progress - use that as the source of truth
                    let weeklyQuestions = weeklyActivity.questionCount

                    if weeklyQuestions != serverTodayProgress.totalQuestions {
                        // Use weekly progress data (more reliable)
                        self.todayProgress = DailyProgress(
                            totalQuestions: weeklyQuestions,
                            correctAnswers: weeklyQuestions, // Assume all correct if we don't have breakdown
                            studyTimeMinutes: serverTodayProgress.studyTimeMinutes,
                            subjectsStudied: serverTodayProgress.subjectsStudied
                        )
                    } else {
                        // Data matches, use server data
                        self.todayProgress = serverTodayProgress
                    }
                } else {
                    // Today doesn't exist in weekly progress - this means NO activity today
                    // Override with empty progress (no activity today)
                    self.todayProgress = DailyProgress()
                }

                saveData()
            }
        } else {
            // Server has no data - keep empty local state
        }
    }

    /// Load today's activity with proper conflict resolution
    private func loadTodaysActivityFromServerWithConflictResolution() async {
        logger.info("[TODAY'S ACTIVITY] === LOADING TODAY'S ACTIVITY FROM SERVER (WITH CONFLICT RESOLUTION) ===")

        guard let networkService = await getNetworkService() else {
            logger.info("[TODAY'S ACTIVITY] NetworkService unavailable")
            return
        }

        let result = await networkService.getTodaysActivity(
            timezone: TimeZone.current.identifier
        )

        logger.info("[TODAY'S ACTIVITY] Server response - success: \(result.success)")

        if result.success, let serverTodayProgress = result.todayProgress {
            await MainActor.run {
                // ✅ SAFETY: Validate server data before using it
                guard serverTodayProgress.totalQuestions >= 0,
                      serverTodayProgress.correctAnswers >= 0,
                      serverTodayProgress.correctAnswers <= serverTodayProgress.totalQuestions else {
                    logger.info("[TODAY'S ACTIVITY] ⚠️ Server data is invalid, rejecting")
                    return
                }

                // Smart merge with timestamp consideration
                if let localProgress = self.todayProgress {
                    // Only update if server data is significantly more complete
                    // (more than 1 question difference to account for sync delays)
                    if localProgress.totalQuestions > serverTodayProgress.totalQuestions + 1 {
                        logger.info("[TODAY'S ACTIVITY] Keeping local data (local: \(localProgress.totalQuestions) >> server: \(serverTodayProgress.totalQuestions))")
                        return
                    }

                    // If counts are similar, merge the data
                    if abs(localProgress.totalQuestions - serverTodayProgress.totalQuestions) <= 1 {
                        let mergedProgress = DailyProgress(
                            totalQuestions: max(localProgress.totalQuestions, serverTodayProgress.totalQuestions),
                            correctAnswers: max(localProgress.correctAnswers, serverTodayProgress.correctAnswers),
                            studyTimeMinutes: max(localProgress.studyTimeMinutes, serverTodayProgress.studyTimeMinutes),
                            subjectsStudied: localProgress.subjectsStudied.union(serverTodayProgress.subjectsStudied)
                        )
                        self.todayProgress = mergedProgress
                        logger.info("[TODAY'S ACTIVITY] Merged local and server data - Total: \(mergedProgress.totalQuestions), Correct: \(mergedProgress.correctAnswers)")
                        saveData()
                        return
                    }
                }

                // Use server data if local doesn't exist or server is significantly more complete
                self.todayProgress = serverTodayProgress
                logger.info("[TODAY'S ACTIVITY] Updated from server - Total: \(serverTodayProgress.totalQuestions), Correct: \(serverTodayProgress.correctAnswers)")
                saveData()
            }
        } else {
            logger.info("[TODAY'S ACTIVITY] Failed to load today's activity from server: \(result.message ?? "Unknown error")")
        }


        logger.info("[TODAY'S ACTIVITY] === END LOADING TODAY'S ACTIVITY FROM SERVER (WITH CONFLICT RESOLUTION) ===")
    }

    // Data integrity validation
    private func validateDataIntegrity() -> Bool {
        // Check for negative values that shouldn't exist
        guard currentPoints >= 0,
              totalPointsEarned >= 0,
              currentStreak >= 0,
              dailyPointsEarned >= 0 else {
            logger.info("[DATA_INTEGRITY] Data integrity check failed: negative values detected")
            logger.info("[DATA_INTEGRITY] currentPoints: \(self.currentPoints), totalPointsEarned: \(self.totalPointsEarned), currentStreak: \(self.currentStreak), dailyPointsEarned: \(self.dailyPointsEarned)")
            return false
        }

        // RELAXED: Allow currentPoints to be greater than totalPointsEarned
        // This can happen if user received bonus points, imported data, or had data migration
        // We only fail if currentPoints is negative or totalPointsEarned is negative (checked above)
        if totalPointsEarned < currentPoints {
            logger.info("[DATA_INTEGRITY] Note: totalPointsEarned (\(self.totalPointsEarned)) < currentPoints (\(self.currentPoints)) - this is allowed")
        }

        // Validate goal data
        for goal in learningGoals {
            guard goal.currentProgress >= 0,
                  goal.targetValue > 0,
                  goal.basePoints >= 0 else {
                logger.info("[DATA_INTEGRITY] Data integrity check failed: invalid goal data for \(goal.title)")
                return false
            }
        }

        return true
    }

    /// Create data backup before critical operations
    private func createDataBackup() -> [String: Any] {
        return [
            "currentPoints": currentPoints,
            "totalPointsEarned": totalPointsEarned,
            "currentStreak": currentStreak,
            "dailyPointsEarned": dailyPointsEarned,
            "lastStreakUpdateDate": lastStreakUpdateDate as Any,
            "learningGoals": (try? JSONEncoder().encode(learningGoals)) as Any,
            "todayProgress": (try? JSONEncoder().encode(todayProgress)) as Any,
            "timestamp": Date()
        ]
    }

    /// Restore data from backup if corruption is detected
    private func restoreFromBackup(_ backup: [String: Any]) {
        logger.info("[DATA_RECOVERY] Restoring data from backup")

        if let points = backup["currentPoints"] as? Int {
            currentPoints = max(0, points)
        }
        if let totalPoints = backup["totalPointsEarned"] as? Int {
            totalPointsEarned = max(0, totalPoints)
        }
        if let streak = backup["currentStreak"] as? Int {
            currentStreak = max(0, streak)
        }
        if let dailyPoints = backup["dailyPointsEarned"] as? Int {
            dailyPointsEarned = max(0, dailyPoints)
        }
        if let streakDate = backup["lastStreakUpdateDate"] as? String {
            lastStreakUpdateDate = streakDate
        }
        if let goalsData = backup["learningGoals"] as? Data,
           let goals = try? JSONDecoder().decode([LearningGoal].self, from: goalsData) {
            learningGoals = goals
        }
        if let progressData = backup["todayProgress"] as? Data,
           let progress = try? JSONDecoder().decode(DailyProgress.self, from: progressData) {
            todayProgress = progress
        }

        forceSave()
        logger.info("[DATA_RECOVERY] Data restoration completed")
    }
    
    /// Load current week progress from server on app start
    func loadCurrentWeekFromServer() async {

        guard let networkService = await getNetworkService() else {
            return
        }

        // Get current user info for debugging
        let authService = await MainActor.run { AuthenticationService.shared }
        let isAuthenticated = await MainActor.run { authService.isAuthenticated }
        let currentUserId = await MainActor.run { authService.currentUser?.id }
        let authToken = authService.getAuthToken()

        if let token = authToken {
        }

        do {
            let result = await networkService.getCurrentWeekProgress(
                timezone: TimeZone.current.identifier
            )


            if result.success, let serverProgress = result.progress {
                await MainActor.run {
                    updateFromServerResponse(serverProgress)
                    saveData()
                }
            } else {
            }
        } catch {
        }

    }

    /// Load today's specific activity from server (legacy method - redirects to conflict resolution version)
    func loadTodaysActivityFromServer() async {
        await loadTodaysActivityFromServerWithConflictResolution()
    }
    
    /// Update local data structure with server response
    private func updateFromServerResponse(_ serverProgress: [String: Any]) {
        guard let weekStart = serverProgress["week_start"] as? String,
              let weekEnd = serverProgress["week_end"] as? String,
              let totalQuestions = serverProgress["total_questions_this_week"] as? Int,
              let currentScore = serverProgress["current_score"] as? Int,
              let dailyActivitiesArray = serverProgress["daily_activities"] as? [[String: Any]],
              let timezone = serverProgress["timezone"] as? String,
              let serverTimestamp = serverProgress["updated_at"] as? String else {
            logger.info("[SERVER_SYNC] Invalid server response format for weekly progress")
            return
        }

        // Validate server data bounds
        guard totalQuestions >= 0,
              currentScore >= 0,
              !weekStart.isEmpty,
              !weekEnd.isEmpty,
              !timezone.isEmpty else {
            logger.info("[SERVER_SYNC] Server response contains invalid data values")
            return
        }

        // Parse daily activities with validation
        var dailyActivities: [DailyQuestionActivity] = []
        for activityData in dailyActivitiesArray {
            guard let date = activityData["date"] as? String,
                  let dayOfWeek = activityData["dayOfWeek"] as? Int,
                  let questionCount = activityData["questionCount"] as? Int,
                  let activityTimezone = activityData["timezone"] as? String else {
                logger.info("[SERVER_SYNC] Skipping invalid daily activity data from server")
                continue
            }

            // Validate activity data bounds
            guard !date.isEmpty,
                  dayOfWeek >= 1 && dayOfWeek <= 7,
                  questionCount >= 0,
                  !activityTimezone.isEmpty else {
                logger.info("[SERVER_SYNC] Skipping daily activity with invalid values: date=\(date), dayOfWeek=\(dayOfWeek), count=\(questionCount)")
                continue
            }

            let activity = DailyQuestionActivity(
                date: date,
                dayOfWeek: dayOfWeek,
                questionCount: max(0, questionCount),
                timezone: activityTimezone
            )
            dailyActivities.append(activity)
        }

        // Parse server timestamp
        let dateFormatter = ISO8601DateFormatter()
        let parsedServerTimestamp = dateFormatter.date(from: serverTimestamp) ?? Date()

        // Create WeeklyProgress from server data
        let serverWeeklyProgress = WeeklyProgress(
            weekStart: weekStart,
            weekEnd: weekEnd,
            totalQuestionsThisWeek: totalQuestions,
            dailyActivities: dailyActivities,
            timezone: timezone,
            serverTimestamp: parsedServerTimestamp
        )

        // Update local data with bounds checking
        currentWeeklyProgress = serverWeeklyProgress
        self.currentPoints = max(0, currentScore)

        logger.info("[SERVER_SYNC] Updated from server: \(dailyActivities.count) activities, \(totalQuestions) total questions, \(currentScore) points")

    }

    // MARK: - Total Points Backend Sync

    /// Sync total points with backend after checkout
    private func syncTotalPointsWithBackend() async {

        guard let networkService = await getNetworkService() else {
            return
        }

        // Get current user info
        let authService = await MainActor.run { AuthenticationService.shared }
        let isAuthenticated = await MainActor.run { authService.isAuthenticated }
        let currentUserId = await MainActor.run { authService.currentUser?.id }

        guard isAuthenticated, let userId = currentUserId else {
            return
        }

        let currentTotalPoints = await MainActor.run { self.totalPointsEarned }

        do {
            let result = await networkService.syncTotalPoints(
                userId: userId,
                totalPoints: currentTotalPoints
            )


            if result.success {
                if let levelData = result.updatedLevel {
                    await MainActor.run {
                        // Update local data with backend level information if needed
                        // Could update UI or local state here based on level changes
                    }
                }
            } else {
            }
        } catch {
        }

    }

    /// Get NetworkService reference safely
    private func getNetworkService() async -> NetworkService? {
        return await MainActor.run {
            NetworkService.shared
        }
    }
}

// MARK: - Supporting Models

struct DailyCheckout: Codable, Identifiable {
    var id: UUID
    let date: Date
    let pointsEarned: Int
    let goalsCompleted: Int
    let streak: Int
    let isWeekend: Bool

    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate UUID for id since it's not in JSON
        self.id = UUID()

        // Handle date parsing
        let dateString = try container.decode(String.self, forKey: .date)
        let formatter = ISO8601DateFormatter()
        self.date = formatter.date(from: dateString) ?? Date()

        self.pointsEarned = try container.decode(Int.self, forKey: .pointsEarned)
        self.goalsCompleted = try container.decode(Int.self, forKey: .goalsCompleted)
        self.streak = try container.decode(Int.self, forKey: .streak)
        self.isWeekend = try container.decode(Bool.self, forKey: .isWeekend)
    }

    // Regular initializer for programmatic creation
    init(id: UUID = UUID(), date: Date, pointsEarned: Int, goalsCompleted: Int, streak: Int, isWeekend: Bool) {
        self.id = id
        self.date = date
        self.pointsEarned = pointsEarned
        self.goalsCompleted = goalsCompleted
        self.streak = streak
        self.isWeekend = isWeekend
    }

    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case date, pointsEarned, goalsCompleted, streak, isWeekend
    }
    
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    var finalPoints: Int {
        return isWeekend ? pointsEarned * 2 : pointsEarned
    }
}

struct DailyProgress: Codable {
    var totalQuestions: Int = 0
    var correctAnswers: Int = 0
    var studyTimeMinutes: Int = 0
    var subjectsStudied: Set<String> = []

    // Custom initializer for server data
    init(totalQuestions: Int = 0, correctAnswers: Int = 0, studyTimeMinutes: Int = 0, subjectsStudied: Set<String> = []) {
        self.totalQuestions = totalQuestions
        self.correctAnswers = correctAnswers
        self.studyTimeMinutes = studyTimeMinutes
        self.subjectsStudied = subjectsStudied
    }

    var accuracy: Double {
        guard totalQuestions > 0 else { return 0.0 }
        return Double(correctAnswers) / Double(totalQuestions) * 100
    }
}

// MARK: - Extensions for Enhanced Server Sync

extension Array where Element: Hashable {
    /// Find the most frequent element in the array
    var most: Element? {
        guard !isEmpty else { return nil }

        let frequencyMap = Dictionary(grouping: self, by: { $0 }).mapValues { $0.count }
        return frequencyMap.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - Points Earning Events

struct PointsEarningEvent {
    let type: LearningGoalType
    let points: Int
    let description: String
    let timestamp: Date
    let isBonus: Bool
    
    static func questionAnswered(correct: Bool) -> PointsEarningEvent {
        return PointsEarningEvent(
            type: .dailyQuestions,
            points: correct ? 10 : 5,
            description: correct ? "Correct answer" : "Question attempted",
            timestamp: Date(),
            isBonus: false
        )
    }
    
    static func goalCompleted(_ goal: LearningGoal) -> PointsEarningEvent {
        return PointsEarningEvent(
            type: goal.type,
            points: goal.pointsEarned,
            description: "\(goal.title) completed",
            timestamp: Date(),
            isBonus: goal.currentProgress > goal.targetValue
        )
    }
    
    static func weekendBonus(_ points: Int) -> PointsEarningEvent {
        return PointsEarningEvent(
            type: .weeklyStreak,
            points: points,
            description: "Weekend checkout bonus",
            timestamp: Date(),
            isBonus: true
        )
    }
}