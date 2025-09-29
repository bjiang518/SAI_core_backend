//
//  PointsEarningSystem.swift
//  StudyAI
//
//  Points earning system with configurable learning goals
//

import Foundation
import SwiftUI
import Combine

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
        case 1...10: return .light
        case 11...20: return .medium
        case 21...: return .high
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
        case .light: return Color.green.opacity(0.3)
        case .medium: return Color.green.opacity(0.6)
        case .high: return Color.green.opacity(0.9)
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

class PointsEarningManager: ObservableObject {
    static let shared = PointsEarningManager()
    
    private let instanceId = UUID().uuidString.prefix(8)
    
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
    
    private init() {
        loadStoredData()
        setupDefaultGoals()
        checkDailyReset()
        checkWeeklyReset()
        handleTimezoneChange()
        
        // Load current week from server asynchronously
        Task {
            await loadCurrentWeekFromServer()
        }

        // Load today's activity from server asynchronously
        Task {
            await loadTodaysActivityFromServer()
        }
    }
    
    private func loadStoredData() {
        currentPoints = userDefaults.integer(forKey: pointsKey)
        totalPointsEarned = userDefaults.integer(forKey: totalPointsKey)
        currentStreak = userDefaults.integer(forKey: streakKey)
        dailyPointsEarned = userDefaults.integer(forKey: dailyPointsEarnedKey)
        lastStreakUpdateDate = userDefaults.string(forKey: lastStreakUpdateDateKey)

        if let goalsData = userDefaults.data(forKey: goalsKey),
           let decodedGoals = try? JSONDecoder().decode([LearningGoal].self, from: goalsData) {
            learningGoals = decodedGoals
        } else {
        }

        if let checkoutData = userDefaults.data(forKey: checkoutHistoryKey),
           let decodedCheckouts = try? JSONDecoder().decode([DailyCheckout].self, from: checkoutData) {
            dailyCheckoutHistory = decodedCheckouts
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

        // MARK: - TODAY'S ACTIVITY: Load today's progress data
        print("📱 TODAY'S ACTIVITY: === LOADING TODAY'S PROGRESS FROM CACHE ===")
        if let todayData = userDefaults.data(forKey: todayProgressKey),
           let decodedTodayProgress = try? JSONDecoder().decode(DailyProgress.self, from: todayData) {
            todayProgress = decodedTodayProgress
            print("📱 TODAY'S ACTIVITY: Loaded from cache - Total: \(decodedTodayProgress.totalQuestions), Correct: \(decodedTodayProgress.correctAnswers), Accuracy: \(decodedTodayProgress.accuracy)%")
        } else {
            print("📱 TODAY'S ACTIVITY: No cached data found, creating new DailyProgress")
            todayProgress = DailyProgress()
        }
        print("📱 TODAY'S ACTIVITY: === END LOADING TODAY'S PROGRESS ===")
    }
    
    private func saveData() {
        userDefaults.set(currentPoints, forKey: pointsKey)
        userDefaults.set(totalPointsEarned, forKey: totalPointsKey)
        userDefaults.set(currentStreak, forKey: streakKey)
        userDefaults.set(dailyPointsEarned, forKey: dailyPointsEarnedKey)

        if let lastStreakDate = lastStreakUpdateDate {
            userDefaults.set(lastStreakDate, forKey: lastStreakUpdateDateKey)
        }
        
        if let goalsData = try? JSONEncoder().encode(learningGoals) {
            userDefaults.set(goalsData, forKey: goalsKey)
        }
        
        if let checkoutData = try? JSONEncoder().encode(dailyCheckoutHistory) {
            userDefaults.set(checkoutData, forKey: checkoutHistoryKey)
        }
        
        // Save weekly progress data
        if let currentWeekly = currentWeeklyProgress,
           let weeklyData = try? JSONEncoder().encode(currentWeekly) {
            userDefaults.set(weeklyData, forKey: weeklyProgressKey)
        }
        
        if let weeklyHistoryData = try? JSONEncoder().encode(weeklyProgressHistory) {
            userDefaults.set(weeklyHistoryData, forKey: weeklyHistoryKey)
        }

        if let lastUpdate = lastTimezoneUpdate {
            userDefaults.set(lastUpdate, forKey: lastTimezoneKey)
        }

        // MARK: - TODAY'S ACTIVITY: Save today's progress data
        if let currentTodayProgress = todayProgress,
           let todayData = try? JSONEncoder().encode(currentTodayProgress) {
            userDefaults.set(todayData, forKey: todayProgressKey)
            print("📱 TODAY'S ACTIVITY: Saved to cache - Total: \(currentTodayProgress.totalQuestions), Correct: \(currentTodayProgress.correctAnswers), Accuracy: \(currentTodayProgress.accuracy)%")
        } else {
            print("📱 TODAY'S ACTIVITY: Failed to save today's progress to cache")
        }
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
        print("📱 TODAY'S ACTIVITY: === CHECKING DAILY RESET ===")

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Use a more reliable method to track the last reset date
        let lastResetDateString = userDefaults.string(forKey: lastResetDateKey)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let todayString = dateFormatter.string(from: today)

        print("📱 TODAY'S ACTIVITY: Today date string: \(todayString)")
        print("📱 TODAY'S ACTIVITY: Last reset date string: \(lastResetDateString ?? "none")")

        // Only reset if we haven't reset today yet
        let shouldReset = lastResetDateString != todayString
        print("📱 TODAY'S ACTIVITY: Should reset? \(shouldReset)")

        if shouldReset {
            print("📱 TODAY'S ACTIVITY: Triggering daily reset...")
            resetDailyGoals()
            updateStreak()

            // Store today's date as the last reset date
            userDefaults.set(todayString, forKey: lastResetDateKey)
        } else {
            print("📱 TODAY'S ACTIVITY: No daily reset needed - already reset today")
        }

        print("📱 TODAY'S ACTIVITY: === END CHECKING DAILY RESET ===")
    }
    
    private func resetDailyGoals() {
        print("📱 TODAY'S ACTIVITY: === DAILY RESET TRIGGERED ===")
        print("📱 TODAY'S ACTIVITY: Resetting daily goals and today's progress")

        // Show current state before reset
        if let currentProgress = todayProgress {
            print("📱 TODAY'S ACTIVITY: BEFORE RESET - Total: \(currentProgress.totalQuestions), Correct: \(currentProgress.correctAnswers), Accuracy: \(currentProgress.accuracy)%")
        } else {
            print("📱 TODAY'S ACTIVITY: BEFORE RESET - No existing today's progress")
        }

        for i in 0..<learningGoals.count {
            if learningGoals[i].isDaily {
                let oldProgress = learningGoals[i].currentProgress
                learningGoals[i].currentProgress = 0
                print("📱 TODAY'S ACTIVITY: Reset daily goal \(learningGoals[i].type.displayName): \(oldProgress) → 0")
            }
        }

        // Reset daily checkout states
        resetDailyCheckouts()

        todayProgress = DailyProgress()
        dailyPointsEarned = 0 // Reset daily points counter for new day
        print("📱 TODAY'S ACTIVITY: Created fresh DailyProgress instance")
        print("📱 TODAY'S ACTIVITY: Reset daily points earned to 0")
        print("📱 TODAY'S ACTIVITY: AFTER RESET - Total: 0, Correct: 0, Accuracy: 0%")

        saveData()
        print("📱 TODAY'S ACTIVITY: === END DAILY RESET ===")
    }
    
    private func updateStreak() {
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        
        if let lastCheckout = dailyCheckoutHistory.last,
           Calendar.current.isDate(lastCheckout.date, inSameDayAs: yesterday) {
            // Continue streak
            currentStreak += 1
        } else if let lastCheckout = dailyCheckoutHistory.last,
                  !Calendar.current.isDate(lastCheckout.date, inSameDayAs: yesterday) {
            // Reset streak if more than one day gap
            currentStreak = 0
        }
        
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
        print("🔥 STREAK: === UPDATING ACTIVITY-BASED STREAK ===")

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        // Create today's date string for comparison
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let todayString = dateFormatter.string(from: today)

        print("🔥 STREAK: Today: \(today)")
        print("🔥 STREAK: Yesterday: \(yesterday)")
        print("🔥 STREAK: Today string: \(todayString)")
        print("🔥 STREAK: Last streak update date: \(lastStreakUpdateDate ?? "none")")
        print("🔥 STREAK: Current streak before update: \(currentStreak)")

        // Check if we've already updated the streak today
        if let lastUpdateDate = lastStreakUpdateDate, lastUpdateDate == todayString {
            print("🔥 STREAK: Streak already updated today (\(todayString)), skipping increment")
            print("🔥 STREAK: === END UPDATING ACTIVITY-BASED STREAK (NO UPDATE) ===")
            return
        }

        // Check if we had activity yesterday by looking at weekly progress
        let hadActivityYesterday = checkActivityOnDate(yesterday)
        print("🔥 STREAK: Had activity yesterday: \(hadActivityYesterday)")

        // Today we're having activity (since we're tracking a question)
        let hadActivityToday = true
        print("🔥 STREAK: Having activity today: \(hadActivityToday)")

        if hadActivityToday {
            if hadActivityYesterday {
                // Continue streak - we had activity yesterday and today
                currentStreak += 1
                print("🔥 STREAK: Continuing streak: \(currentStreak)")
            } else {
                // Check if this is the first day of activity or if we're restarting
                if currentStreak == 0 {
                    // Starting new streak
                    currentStreak = 1
                    print("🔥 STREAK: Starting new streak: \(currentStreak)")
                } else {
                    // Had a gap, reset to 1 (today's activity)
                    currentStreak = 1
                    print("🔥 STREAK: Reset streak due to gap: \(currentStreak)")
                }
            }

            // Mark that we've updated the streak for today
            lastStreakUpdateDate = todayString
            print("🔥 STREAK: Updated lastStreakUpdateDate to: \(todayString)")
        }

        // Update weekly streak goal
        updateWeeklyStreakGoal()
        updateDailyStreakGoal()

        print("🔥 STREAK: Final streak: \(currentStreak)")
        print("🔥 STREAK: === END UPDATING ACTIVITY-BASED STREAK ===")
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
                    print("🔥 STREAK: Found activity on \(dateString): \(activity.questionCount) questions")
                    return true
                }
            }
        }

        // Also check historical weekly progress
        for weekProgress in weeklyProgressHistory {
            for activity in weekProgress.dailyActivities {
                if activity.date == dateString && activity.questionCount > 0 {
                    print("🔥 STREAK: Found activity in history on \(dateString): \(activity.questionCount) questions")
                    return true
                }
            }
        }

        print("🔥 STREAK: No activity found on \(dateString)")
        return false
    }
    
    // MARK: - Public Methods
    
    func trackQuestionAnswered(subject: String, isCorrect: Bool) {
        print("📱 TODAY'S ACTIVITY: === TRACKING QUESTION ANSWERED ===")
        print("📱 TODAY'S ACTIVITY: Input - subject: \(subject), isCorrect: \(isCorrect)")

        // Show current state BEFORE tracking
        if let currentProgress = todayProgress {
            print("📱 TODAY'S ACTIVITY: BEFORE - Total: \(currentProgress.totalQuestions), Correct: \(currentProgress.correctAnswers), Accuracy: \(currentProgress.accuracy)%")
        } else {
            print("📱 TODAY'S ACTIVITY: BEFORE - No today's progress data exists")
        }

        // Update daily questions goal
        for i in 0..<learningGoals.count {
            if learningGoals[i].type == .dailyQuestions {
                let oldProgress = learningGoals[i].currentProgress
                learningGoals[i].currentProgress += 1
                let newProgress = learningGoals[i].currentProgress
                print("📱 TODAY'S ACTIVITY: Daily Questions goal updated: \(oldProgress) → \(newProgress)/\(learningGoals[i].targetValue)")
            }
        }

        // Update accuracy tracking
        if todayProgress == nil {
            todayProgress = DailyProgress()
            print("📱 TODAY'S ACTIVITY: Created new DailyProgress instance")
        }

        // Update question counts
        let oldTotalQuestions = todayProgress?.totalQuestions ?? 0
        let oldCorrectAnswers = todayProgress?.correctAnswers ?? 0

        todayProgress?.totalQuestions += 1
        if isCorrect {
            todayProgress?.correctAnswers += 1
        }

        if let progress = todayProgress {
            print("📱 TODAY'S ACTIVITY: Updated counts - Total: \(oldTotalQuestions) → \(progress.totalQuestions), Correct: \(oldCorrectAnswers) → \(progress.correctAnswers)")
            print("📱 TODAY'S ACTIVITY: Calculated accuracy: \(progress.accuracy)%")
        }

        // Update accuracy goal
        updateAccuracyGoal()

        // Update streak based on daily activity (not manual checkouts)
        updateActivityBasedStreak()

        // Update weekly progress tracking
        updateWeeklyProgress(questionCount: 1, subject: subject)

        // Save data with logging
        print("📱 TODAY'S ACTIVITY: Saving data to persistent storage...")
        saveData()

        // Refresh today's activity from server after tracking locally
        print("📱 TODAY'S ACTIVITY: Refreshing today's activity from server...")
        Task {
            await loadTodaysActivityFromServer()
        }

        // Show current state AFTER tracking and saving
        if let finalProgress = todayProgress {
            print("📱 TODAY'S ACTIVITY: AFTER - Total: \(finalProgress.totalQuestions), Correct: \(finalProgress.correctAnswers), Accuracy: \(finalProgress.accuracy)%")
        }
        print("📱 TODAY'S ACTIVITY: === END TRACKING QUESTION ANSWERED ===")
    }
    
    func trackStudyTime(_ minutes: Int) {
        for i in 0..<learningGoals.count {
            if learningGoals[i].type == .studyTime {
                learningGoals[i].currentProgress += minutes
            }
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
        if let index = learningGoals.firstIndex(where: { $0.id == goalId }) {
            learningGoals[index] = LearningGoal(
                type: learningGoals[index].type,
                title: learningGoals[index].title,
                description: learningGoals[index].description,
                targetValue: targetValue,
                basePoints: learningGoals[index].basePoints,
                bonusMultiplier: learningGoals[index].bonusMultiplier,
                currentProgress: learningGoals[index].currentProgress,
                isDaily: learningGoals[index].isDaily,
                isWeekly: learningGoals[index].isWeekly
            )
            saveData()
        }
    }

    // MARK: - Enhanced Checkout Methods

    /// Calculate available points for a specific goal with smart logic
    func calculateAvailablePoints(for goal: LearningGoal) -> Int {
        guard goal.isCompleted && !goal.isCheckedOut else { return 0 }

        switch goal.type {
        case .dailyQuestions:
            // Base points: 1 point per question (up to target)
            let basePoints = min(goal.currentProgress, goal.targetValue)

            // Check if accuracy goal is also completed for doubling
            let accuracyGoal = learningGoals.first { $0.type == .accuracyGoal }
            let hasAccuracyMultiplier = accuracyGoal?.isCompleted == true && accuracyGoal?.isCheckedOut == false

            return hasAccuracyMultiplier ? basePoints * 2 : basePoints

        case .accuracyGoal:
            // Accuracy goal provides a multiplier bonus for daily questions
            let dailyQuestionsGoal = learningGoals.first { $0.type == .dailyQuestions }
            if let dailyGoal = dailyQuestionsGoal, dailyGoal.isCompleted {
                return min(dailyGoal.currentProgress, dailyGoal.targetValue) // Equal to daily questions count
            }
            return 0

        case .dailyStreak:
            return 10 // Fixed 10 points for daily streak

        case .weeklyStreak:
            return goal.basePoints // Use configured base points

        default:
            return goal.basePoints
        }
    }

    /// Checkout points for a specific goal
    func checkoutGoal(_ goalId: UUID) -> Int {
        guard let index = learningGoals.firstIndex(where: { $0.id == goalId }) else { return 0 }

        let goal = learningGoals[index]
        let pointsToAdd = calculateAvailablePoints(for: goal)

        guard pointsToAdd > 0 else { return 0 }

        // Apply daily maximum of 100 points logic
        let remainingDailyPoints = max(0, 100 - dailyPointsEarned)
        let actualPointsToAdd = min(pointsToAdd, remainingDailyPoints)

        // If no points can be added due to daily limit, return early
        guard actualPointsToAdd > 0 else {
            return 0
        }

        // Mark goal as checked out
        learningGoals[index].isCheckedOut = true

        // Add points to total and daily counter
        currentPoints += actualPointsToAdd
        totalPointsEarned += actualPointsToAdd
        dailyPointsEarned += actualPointsToAdd

        // Apply weekend bonus if applicable
        let finalPoints = Calendar.current.isDateInWeekend(Date()) ? actualPointsToAdd * 2 : actualPointsToAdd

        // Save changes
        saveData()

        // Sync total points with backend asynchronously
        Task {
            await syncTotalPointsWithBackend()
        }


        return finalPoints
    }

    /// Reset daily checkout states
    private func resetDailyCheckouts() {
        for i in 0..<learningGoals.count {
            if learningGoals[i].isDaily {
                learningGoals[i].isCheckedOut = false
            }
        }
    }

    /// Calculate total available checkout points across all goals
    var totalAvailableCheckoutPoints: Int {
        return learningGoals.reduce(0) { total, goal in
            total + calculateAvailablePoints(for: goal)
        }
    }
    
    func resetProgress() {
        currentPoints = 0
        totalPointsEarned = 0
        currentStreak = 0
        learningGoals.forEach { goal in
            if let index = learningGoals.firstIndex(where: { $0.id == goal.id }) {
                learningGoals[index].currentProgress = 0
            }
        }
        dailyCheckoutHistory.removeAll()
        currentWeeklyProgress = nil
        weeklyProgressHistory.removeAll()
        todayProgress = DailyProgress()
        saveData()
    }
    
    // MARK: - Weekly Progress Methods
    
    /// Update daily activity and sync with server if available
    func updateWeeklyProgress(questionCount: Int, subject: String) {
        
        // Update local data structure first (for immediate UI updates)
        updateLocalWeeklyProgress(questionCount: questionCount)
        
        // Sync with server asynchronously
        Task {
            await syncWithServer(questionCount: questionCount, subject: subject)
        }
    }
    
    /// Update local weekly progress data structure
    private func updateLocalWeeklyProgress(questionCount: Int) {
        let currentDate = Date()
        let calendar = Calendar.current
        let timezone = TimeZone.current.identifier
        
        // Create or update current week progress
        if currentWeeklyProgress == nil {
            currentWeeklyProgress = createCurrentWeekProgress(timezone: timezone)
        }
        
        guard var weeklyProgress = currentWeeklyProgress else { return }
        
        // Get today's date string
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let todayString = dateFormatter.string(from: currentDate)
        
        // Find or create today's activity
        if let existingIndex = weeklyProgress.dailyActivities.firstIndex(where: { $0.date == todayString }) {
            // Update existing day
            weeklyProgress.dailyActivities[existingIndex].questionCount += questionCount
        } else {
            // Add new day activity
            let dayOfWeek = calendar.component(.weekday, from: currentDate)
            let adjustedDayOfWeek = dayOfWeek == 1 ? 7 : dayOfWeek - 1 // Convert Sunday=1 to Sunday=7, Monday=2 to Monday=1
            
            let newActivity = DailyQuestionActivity(
                date: todayString,
                dayOfWeek: adjustedDayOfWeek,
                questionCount: questionCount,
                timezone: timezone
            )
            weeklyProgress.dailyActivities.append(newActivity)
        }
        
        // Update total questions for the week
        weeklyProgress.totalQuestionsThisWeek = weeklyProgress.dailyActivities.reduce(0) { $0 + $1.questionCount }
        
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
    
    /// Sync weekly progress with server
    private func syncWithServer(questionCount: Int, subject: String) async {
        do {
            let result = await NetworkService.shared.updateUserProgress(
                questionCount: questionCount,
                subject: subject,
                currentScore: currentPoints,
                clientTimezone: TimeZone.current.identifier
            )
            
            if result.success {
                // Update local data with server response if needed
                if let serverProgress = result.progress {
                    await MainActor.run {
                        updateFromServerResponse(serverProgress)
                    }
                }
            } else {
                // Continue with local data - sync will retry later
            }
        } catch {
            // Continue with local data - sync will retry later
        }
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

    /// Load today's specific activity from server
    func loadTodaysActivityFromServer() async {
        print("📱 TODAY'S ACTIVITY: === LOADING TODAY'S ACTIVITY FROM SERVER ===")

        guard let networkService = await getNetworkService() else {
            print("📱 TODAY'S ACTIVITY: NetworkService unavailable")
            return
        }

        // Get current user info for debugging
        let authService = await MainActor.run { AuthenticationService.shared }
        let isAuthenticated = await MainActor.run { authService.isAuthenticated }
        let currentUserId = await MainActor.run { authService.currentUser?.id }
        let authToken = authService.getAuthToken()

        print("📱 TODAY'S ACTIVITY: Authentication state - isAuthenticated: \(isAuthenticated)")
        print("📱 TODAY'S ACTIVITY: Current user ID: \(currentUserId ?? "nil")")
        print("📱 TODAY'S ACTIVITY: Auth token present: \(authToken != nil)")
        if let token = authToken {
            print("📱 TODAY'S ACTIVITY: Auth token preview: \(String(token.prefix(20)))...")
        }

        do {
            let result = await networkService.getTodaysActivity(
                timezone: TimeZone.current.identifier
            )

            print("📱 TODAY'S ACTIVITY: Server response - success: \(result.success)")
            print("📱 TODAY'S ACTIVITY: Server response - message: \(result.message ?? "none")")

            if result.success, let serverTodayProgress = result.todayProgress {
                await MainActor.run {
                    // Smart merge: only update if local data doesn't exist or server has more recent data
                    if let localProgress = self.todayProgress {
                        // If local data has more questions than server, keep local data (it's more recent)
                        if localProgress.totalQuestions >= serverTodayProgress.totalQuestions {
                            print("📱 TODAY'S ACTIVITY: Keeping local data (local: \(localProgress.totalQuestions) questions >= server: \(serverTodayProgress.totalQuestions) questions)")
                            return
                        }
                    }

                    // Update with server data only if it's more complete
                    self.todayProgress = serverTodayProgress
                    print("📱 TODAY'S ACTIVITY: Updated from server - Total: \(serverTodayProgress.totalQuestions), Correct: \(serverTodayProgress.correctAnswers), Accuracy: \(serverTodayProgress.accuracy)%")

                    // Save the updated data
                    saveData()
                    print("📱 TODAY'S ACTIVITY: Server data saved to cache")
                }
            } else {
                print("📱 TODAY'S ACTIVITY: Failed to load today's activity from server: \(result.message ?? "Unknown error")")
                print("📱 TODAY'S ACTIVITY: Using local cached data")
            }
        } catch {
            print("📱 TODAY'S ACTIVITY: Error loading today's activity from server: \(error)")
            print("📱 TODAY'S ACTIVITY: Using local cached data")
        }

        print("📱 TODAY'S ACTIVITY: === END LOADING TODAY'S ACTIVITY FROM SERVER ===")
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
            return
        }

        // Parse daily activities
        var dailyActivities: [DailyQuestionActivity] = []
        for activityData in dailyActivitiesArray {
            if let date = activityData["date"] as? String,
               let dayOfWeek = activityData["dayOfWeek"] as? Int,
               let questionCount = activityData["questionCount"] as? Int,
               let activityTimezone = activityData["timezone"] as? String {

                let activity = DailyQuestionActivity(
                    date: date,
                    dayOfWeek: dayOfWeek,
                    questionCount: questionCount,
                    timezone: activityTimezone
                )
                dailyActivities.append(activity)
            }
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

        // Update local data
        currentWeeklyProgress = serverWeeklyProgress
        self.currentPoints = currentScore

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