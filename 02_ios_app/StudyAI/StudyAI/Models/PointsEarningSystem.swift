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
        case .dailyQuestions: return NSLocalizedString("goals.dailyQuestions", comment: "")
        case .weeklyStreak: return NSLocalizedString("goals.weeklyStreak", comment: "")
        case .dailyStreak: return NSLocalizedString("goals.dailyStreak", comment: "")
        case .accuracyGoal: return NSLocalizedString("goals.accuracyGoal", comment: "")
        case .studyTime: return NSLocalizedString("goals.studyTime", comment: "")
        case .subjectMastery: return NSLocalizedString("goals.subjectMastery", comment: "")
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
    @Published var todayProgress: DailyProgress? // TODAY's counters (reset at midnight)
    @Published var thisWeekProgress: [DailyProgress] = [] // This week's daily progress (7 days max)
    @Published var thisMonthProgress: [DailyProgress] = [] // This month's daily progress (31 days max)
    @Published var dailyPointsEarned: Int = 0 // Track daily points to enforce 100 point maximum
    private var updatedToday: Bool = false // Track if today's progress has been calculated from local storage
    private var lastLoginDate: String? // Track last login date to reset updatedToday flag

    // MARK: - Weekly Progress Properties (Legacy - for grid display)
    @Published var currentWeeklyProgress: WeeklyProgress?
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
    private let lastTimezoneKey = "studyai_last_timezone"
    private let todayProgressKey = "studyai_today_progress"
    private let thisWeekProgressKey = "studyai_this_week_progress"
    private let thisMonthProgressKey = "studyai_this_month_progress"
    private let lastResetDateKey = "studyai_last_reset_date"
    private let dailyPointsEarnedKey = "studyai_daily_points_earned"
    private let lastStreakUpdateDateKey = "studyai_last_streak_update_date"
    private let updatedTodayKey = "studyai_updated_today"
    private let lastLoginDateKey = "studyai_last_login_date"

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

        // ✅ LOCAL-ONLY: Removed server loads from init
        // All progress data is now loaded from local storage only
        // Use StorageSyncService to sync progress with server
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
        updatedToday = userDefaults.bool(forKey: updatedTodayKey)
        lastLoginDate = userDefaults.string(forKey: lastLoginDateKey)

        // Load goals with validation
        if let goalsData = userDefaults.data(forKey: goalsKey),
           let decodedGoals = try? JSONDecoder().decode([LearningGoal].self, from: goalsData) {
            // Validate loaded goals
            learningGoals = decodedGoals.filter { goal in
                goal.targetValue > 0 && goal.basePoints >= 0 && goal.currentProgress >= 0
            }
        }

        // Load checkout history with size limits
        if let checkoutData = userDefaults.data(forKey: checkoutHistoryKey),
           let decodedCheckouts = try? JSONDecoder().decode([DailyCheckout].self, from: checkoutData) {
            // Keep only last 30 days to prevent unbounded growth
            dailyCheckoutHistory = Array(decodedCheckouts.suffix(30))
        }

        // Load legacy weekly progress data (for grid display)
        if let weeklyData = userDefaults.data(forKey: weeklyProgressKey),
           let decodedWeekly = try? JSONDecoder().decode(WeeklyProgress.self, from: weeklyData) {
            if validateWeeklyProgressData(decodedWeekly) {
                currentWeeklyProgress = decodedWeekly
            }
        }

        // Load today's progress (counter-based)
        if let todayData = userDefaults.data(forKey: todayProgressKey),
           let decodedToday = try? JSONDecoder().decode(DailyProgress.self, from: todayData) {
            // Validate date - only load if it's for today
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let todayString = dateFormatter.string(from: Date())

            if decodedToday.date == todayString {
                todayProgress = decodedToday
                print("📊 [loadStoredData] Loaded today's progress: \(decodedToday.totalQuestions) questions, \(decodedToday.correctAnswers) correct")
            } else {
                // Stale data from previous day, initialize empty
                todayProgress = DailyProgress(date: todayString)
                print("📊 [loadStoredData] Stale progress data detected, initialized empty for \(todayString)")
            }
        } else {
            // No saved data, initialize empty
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let todayString = dateFormatter.string(from: Date())
            todayProgress = DailyProgress(date: todayString)
            print("📊 [loadStoredData] No saved progress, initialized empty for \(todayString)")
        }

        // Load this week's progress history (counter-based)
        if let weekData = userDefaults.data(forKey: thisWeekProgressKey),
           let decodedWeek = try? JSONDecoder().decode([DailyProgress].self, from: weekData) {
            thisWeekProgress = decodedWeek
            print("📊 [loadStoredData] Loaded \(decodedWeek.count) days of weekly progress")
        }

        // Load this month's progress history (counter-based)
        if let monthData = userDefaults.data(forKey: thisMonthProgressKey),
           let decodedMonth = try? JSONDecoder().decode([DailyProgress].self, from: monthData) {
            thisMonthProgress = decodedMonth
            print("📊 [loadStoredData] Loaded \(decodedMonth.count) days of monthly progress")
        }

        lastTimezoneUpdate = userDefaults.object(forKey: lastTimezoneKey) as? Date
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
            updatedTodayKey: updatedToday,
            lastLoginDateKey: lastLoginDate,
            goalsKey: try? JSONEncoder().encode(learningGoals),
            checkoutHistoryKey: try? JSONEncoder().encode(dailyCheckoutHistory),
            weeklyProgressKey: currentWeeklyProgress.flatMap { try? JSONEncoder().encode($0) },
            todayProgressKey: todayProgress.flatMap { try? JSONEncoder().encode($0) },
            thisWeekProgressKey: try? JSONEncoder().encode(thisWeekProgress),
            thisMonthProgressKey: try? JSONEncoder().encode(thisMonthProgress),
            lastTimezoneKey: lastTimezoneUpdate
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
                    title: NSLocalizedString("goals.dailyQuestions", comment: ""),
                    description: NSLocalizedString("goals.dailyQuestionsDescription", comment: ""),
                    targetValue: 5,
                    basePoints: 50,
                    bonusMultiplier: 10.0,
                    isDaily: true,
                    isWeekly: false
                ),
                LearningGoal(
                    type: .weeklyStreak,
                    title: NSLocalizedString("goals.weeklyStreak", comment: ""),
                    description: NSLocalizedString("goals.weeklyStreakDescription", comment: ""),
                    targetValue: 7,
                    basePoints: 200,
                    bonusMultiplier: 50.0,
                    isDaily: false,
                    isWeekly: true
                ),
                LearningGoal(
                    type: .dailyStreak,
                    title: NSLocalizedString("goals.dailyStreak", comment: ""),
                    description: NSLocalizedString("goals.dailyStreakDescription", comment: ""),
                    targetValue: 1,
                    basePoints: 25,
                    bonusMultiplier: 5.0,
                    isDaily: true,
                    isWeekly: false
                ),
                LearningGoal(
                    type: .accuracyGoal,
                    title: NSLocalizedString("goals.accuracyGoal", comment: ""),
                    description: NSLocalizedString("goals.accuracyGoalDescription", comment: ""),
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
                    title: NSLocalizedString("goals.dailyStreak", comment: ""),
                    description: NSLocalizedString("goals.dailyStreakDescription", comment: ""),
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
        print("\n📊 ========================================")
        print("📊 [RESET] Resetting daily progress and goals")
        print("📊 ========================================")

        // Get today's date string
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())

        // Reset all daily goal progress and checkout states
        for i in 0..<learningGoals.count {
            if learningGoals[i].isDaily {
                let oldProgress = learningGoals[i].currentProgress
                learningGoals[i].currentProgress = 0
                learningGoals[i].isCheckedOut = false
                print("📊 [RESET] Goal '\(learningGoals[i].title)': \(oldProgress) → 0")
            }
        }

            // Reset today's progress counters (create new empty progress for today)
        todayProgress = DailyProgress(date: todayString)
        print("📊 [RESET] Created new daily progress for \(todayString)")

        // CRITICAL: Reset daily-reset points to 0 for new day
        currentPoints = 0
        print("📊 [RESET] Reset currentPoints (daily-reset points) to 0")

        // CRITICAL: Reset daily points earned to 0 for new day
        dailyPointsEarned = 0
        print("📊 [RESET] Reset dailyPointsEarned to 0")

        // NOTE: totalPointsEarned is NEVER reset - it's the lifetime total
        print("📊 [RESET] totalPointsEarned unchanged: \(totalPointsEarned) (lifetime total)")

        // Reset updatedToday flag so streak can be updated when user marks progress
        updatedToday = false
        userDefaults.set(false, forKey: updatedTodayKey)
        print("📊 [RESET] Reset updatedToday flag")

        print("📊 ========================================")
        print("📊 [RESET] Daily reset complete")
        print("📊 ========================================\n")

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

        // Check in this week's counter-based progress
        for dayProgress in thisWeekProgress {
            if dayProgress.date == dateString && dayProgress.totalQuestions > 0 {
                return true
            }
        }

        // Check in this month's counter-based progress
        for dayProgress in thisMonthProgress {
            if dayProgress.date == dateString && dayProgress.totalQuestions > 0 {
                return true
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

    // MARK: - Mark Progress (Called when user grades homework and clicks "Mark Progress")

    /// Update progress counters when user marks homework progress
    /// This is the ONLY way to update daily counters (not automatic on archive)
    func markHomeworkProgress(subject: String, numberOfQuestions: Int, numberOfCorrectQuestions: Int) {
        print("\n📊 ========================================")
        print("📊 [MARK PROGRESS] User marking progress for homework")
        print("📊 ========================================")
        print("📊 Subject: \(subject)")
        print("📊 Questions: \(numberOfQuestions)")
        print("📊 Correct: \(numberOfCorrectQuestions)")

        let calendar = Calendar.current
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: now)

        // Initialize today's progress if needed
        if todayProgress == nil || todayProgress?.date != todayString {
            print("📊 [MARK PROGRESS] Initializing new daily progress for \(todayString)")
            todayProgress = DailyProgress(date: todayString)
        }

        // Update subject counters for today
        var currentSubjectProgress = todayProgress?.subjectProgress[subject] ?? SubjectDailyProgress(subject: subject)
        currentSubjectProgress.numberOfQuestions += numberOfQuestions
        currentSubjectProgress.numberOfCorrectQuestions += numberOfCorrectQuestions
        todayProgress?.subjectProgress[subject] = currentSubjectProgress

        print("📊 [MARK PROGRESS] Updated \(subject): \(currentSubjectProgress.numberOfQuestions) questions, \(currentSubjectProgress.numberOfCorrectQuestions) correct")
        print("📊 [MARK PROGRESS] Today's total: \(todayProgress?.totalQuestions ?? 0) questions, \(todayProgress?.correctAnswers ?? 0) correct")
        print("📊 [MARK PROGRESS] Today's accuracy: \(String(format: "%.1f%%", todayProgress?.accuracy ?? 0.0))")

        // Update weekly progress
        updateWeeklyProgressCounters(todayProgress: todayProgress!)

        // Update monthly progress
        updateMonthlyProgressCounters(todayProgress: todayProgress!)

        // Update streak if this is first progress today
        if !updatedToday && todayProgress!.totalQuestions > 0 {
            print("📊 [MARK PROGRESS] First progress today - updating streak")
            updateStreakForToday(todayString: todayString)
            updatedToday = true
            userDefaults.set(true, forKey: updatedTodayKey)
        }

        // Update learning goals
        updateLearningGoalsFromProgress()

        // Save data locally
        saveData()

        // ✅ LOCAL-FIRST: Progress is saved locally only
        // Sync will only happen when user explicitly chooses "Sync with Server" in Settings
        // No automatic backend sync on marking progress

        print("📊 ========================================")
        print("📊 [MARK PROGRESS] COMPLETE (LOCAL ONLY)")
        print("📊 ========================================\n")
    }

    /// Update weekly progress history with today's progress
    private func updateWeeklyProgressCounters(todayProgress: DailyProgress) {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return }

        // Remove any progress from previous weeks
        thisWeekProgress.removeAll { progress in
            guard let progressDate = dateFromString(progress.date) else { return true }
            return progressDate < weekStart
        }

        // Update or add today's progress
        if let index = thisWeekProgress.firstIndex(where: { $0.date == todayProgress.date }) {
            thisWeekProgress[index] = todayProgress
            print("📊 [WEEKLY] Updated progress for \(todayProgress.date)")
        } else {
            thisWeekProgress.append(todayProgress)
            print("📊 [WEEKLY] Added progress for \(todayProgress.date)")
        }

        print("📊 [WEEKLY] Total days this week: \(thisWeekProgress.count)")
        let weekTotal = thisWeekProgress.reduce(0) { $0 + $1.totalQuestions }
        let weekCorrect = thisWeekProgress.reduce(0) { $0 + $1.correctAnswers }
        print("📊 [WEEKLY] Week total: \(weekTotal) questions, \(weekCorrect) correct")
    }

    /// Update monthly progress history with today's progress
    private func updateMonthlyProgressCounters(todayProgress: DailyProgress) {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.dateInterval(of: .month, for: now)?.start else { return }

        // Remove any progress from previous months
        thisMonthProgress.removeAll { progress in
            guard let progressDate = dateFromString(progress.date) else { return true }
            return progressDate < monthStart
        }

        // Update or add today's progress
        if let index = thisMonthProgress.firstIndex(where: { $0.date == todayProgress.date }) {
            thisMonthProgress[index] = todayProgress
            print("📊 [MONTHLY] Updated progress for \(todayProgress.date)")
        } else {
            thisMonthProgress.append(todayProgress)
            print("📊 [MONTHLY] Added progress for \(todayProgress.date)")
        }

        print("📊 [MONTHLY] Total days this month: \(thisMonthProgress.count)")
        let monthTotal = thisMonthProgress.reduce(0) { $0 + $1.totalQuestions }
        let monthCorrect = thisMonthProgress.reduce(0) { $0 + $1.correctAnswers }
        print("📊 [MONTHLY] Month total: \(monthTotal) questions, \(monthCorrect) correct")
    }

    /// Update streak for today
    private func updateStreakForToday(todayString: String) {
        // Check if we've already updated streak for today
        if lastStreakUpdateDate == todayString {
            print("🔥 [STREAK] Already updated for today")
            return
        }

        // If we had activity, increment streak
        if todayProgress?.totalQuestions ?? 0 > 0 {
            currentStreak += 1
            print("🔥 [STREAK] Incremented to \(currentStreak)")
        }

        lastStreakUpdateDate = todayString
        userDefaults.set(todayString, forKey: lastStreakUpdateDateKey)
    }

    /// Update learning goals based on progress
    private func updateLearningGoalsFromProgress() {
        guard let progress = todayProgress else { return }

        // Update daily questions goal
        for i in 0..<learningGoals.count {
            if learningGoals[i].type == .dailyQuestions {
                learningGoals[i].currentProgress = progress.totalQuestions
            }
        }

        // Update accuracy goal
        if progress.totalQuestions > 0 {
            let accuracy = Int(progress.accuracy)
            for i in 0..<learningGoals.count {
                if learningGoals[i].type == .accuracyGoal {
                    learningGoals[i].currentProgress = accuracy
                }
            }
        }

        // Update streak goals
        updateWeeklyStreakGoal()
        updateDailyStreakGoal()
    }

    private func dateFromString(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    func trackQuestionAnswered(subject: String, isCorrect: Bool) {
        // ⚠️ DEPRECATED: Progress is now counter-based via markHomeworkProgress()
        // This method is kept for compatibility but does nothing
        // When user clicks "Mark Progress" after grading, use markHomeworkProgress() instead
        logger.info("⚠️ [trackQuestionAnswered] DEPRECATED - Use markHomeworkProgress() instead")
    }

    func trackStudyTime(_ minutes: Int) {
        // ⚠️ DEPRECATED: Study time tracking removed from counter-based approach
        // This method is kept for compatibility but does nothing
        logger.info("⚠️ [trackStudyTime] DEPRECATED - Study time tracking removed")
    }

    /// Track focus session completion and award points
    /// Awards 1 point per 5 minutes of focus time
    func trackFocusSession(durationMinutes: Int, pointsEarned: Int) {
        print("\n🧘 ========================================")
        print("🧘 [FOCUS SESSION] Tracking completed session")
        print("🧘 ========================================")
        print("🧘 Duration: \(durationMinutes) minutes")
        print("🧘 Points Earned: \(pointsEarned)")

        // Award points immediately
        currentPoints += pointsEarned
        totalPointsEarned += pointsEarned

        print("🧘 [FOCUS SESSION] ✅ Awarded \(pointsEarned) points")
        print("🧘 [FOCUS SESSION] Current Total: \(currentPoints) points")

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
        userDefaults.removeObject(forKey: lastTimezoneKey)
        userDefaults.removeObject(forKey: todayProgressKey)
        userDefaults.removeObject(forKey: thisWeekProgressKey)
        userDefaults.removeObject(forKey: thisMonthProgressKey)
        userDefaults.removeObject(forKey: lastResetDateKey)

        print("✅ [resetProgress] Completely removed all progress data from UserDefaults")

    }
    
    // MARK: - Weekly Progress Methods
    
    /// Update daily activity in local data structure (for UI display)
    /// Server sync is handled separately by markHomeworkProgress()
    func updateWeeklyProgress(questionCount: Int, subject: String) {
        guard questionCount > 0 else {
            return
        }

        // Update local data structure for immediate UI updates
        // This maintains currentWeeklyProgress which is displayed in WeeklyProgressGrid
        updateLocalWeeklyProgress(questionCount: questionCount)

        // Note: Server sync is now handled by markHomeworkProgress() method
        // which syncs daily progress counters with backend
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
        currentWeeklyProgress = nil

        // Force create fresh weekly progress
        checkWeeklyReset()
    }

    /// Validate consistency between todayProgress and weekly grid today
    /// (Disabled for counter-based approach - no longer needed)
    private func validateTodayConsistency() {
        // Counter-based approach ensures consistency by design
        // No validation needed
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
            // (No history storage needed for counter-based approach)

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

    /// Sync daily progress data with backend
    /// Called after marking homework progress to sync today's counters with server
    private func syncDailyProgressWithBackend() async {
        logger.info("[DAILY_PROGRESS_SYNC] === SYNCING DAILY PROGRESS WITH BACKEND ===")

        guard let networkService = await getNetworkService() else {
            logger.info("[DAILY_PROGRESS_SYNC] ❌ NetworkService not available")
            return
        }

        // Get current user info
        let authService = await MainActor.run { AuthenticationService.shared }
        let isAuthenticated = await MainActor.run { authService.isAuthenticated }
        let currentUserId = await MainActor.run { authService.currentUser?.id }

        guard isAuthenticated, let userId = currentUserId else {
            logger.info("[DAILY_PROGRESS_SYNC] ❌ User not authenticated")
            return
        }

        // Get today's progress
        let progress = await MainActor.run { self.todayProgress }

        guard let progress = progress else {
            logger.info("[DAILY_PROGRESS_SYNC] ❌ No progress data to sync")
            return
        }

        logger.info("[DAILY_PROGRESS_SYNC] Syncing progress for date: \(progress.date)")
        logger.info("[DAILY_PROGRESS_SYNC] Total questions: \(progress.totalQuestions), Correct: \(progress.correctAnswers)")

        do {
            let result = await networkService.syncDailyProgress(
                userId: userId,
                dailyProgress: progress
            )

            if result.success {
                logger.info("[DAILY_PROGRESS_SYNC] ✅ Daily progress synced successfully")
                if let message = result.message {
                    logger.info("[DAILY_PROGRESS_SYNC] Server message: \(message)")
                }
            } else {
                logger.info("[DAILY_PROGRESS_SYNC] ❌ Sync failed: \(result.message ?? "Unknown error")")
            }
        } catch {
            logger.info("[DAILY_PROGRESS_SYNC] ❌ Sync error: \(error.localizedDescription)")
        }

        logger.info("[DAILY_PROGRESS_SYNC] === SYNC COMPLETE ===")
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

// MARK: - Subject Daily Progress (Counter-Based)

/// Daily progress counter for a single subject
/// Resets at midnight, updated when user marks progress
struct SubjectDailyProgress: Codable {
    let subject: String
    var numberOfQuestions: Int = 0
    var numberOfCorrectQuestions: Int = 0

    var accuracy: Double {
        guard numberOfQuestions > 0 else { return 0.0 }
        return Double(numberOfCorrectQuestions) / Double(numberOfQuestions) * 100
    }
}

/// Daily progress aggregated across all subjects
struct DailyProgress: Codable {
    var subjectProgress: [String: SubjectDailyProgress] = [:] // key: subject name
    var date: String // yyyy-MM-dd format

    init(date: String = "") {
        self.subjectProgress = [:]
        self.date = date
    }

    // Computed properties for aggregated values
    var totalQuestions: Int {
        return subjectProgress.values.reduce(0) { $0 + $1.numberOfQuestions }
    }

    var correctAnswers: Int {
        return subjectProgress.values.reduce(0) { $0 + $1.numberOfCorrectQuestions }
    }

    var accuracy: Double {
        guard totalQuestions > 0 else { return 0.0 }
        return Double(correctAnswers) / Double(totalQuestions) * 100
    }

    var subjectsStudied: Set<String> {
        return Set(subjectProgress.keys)
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