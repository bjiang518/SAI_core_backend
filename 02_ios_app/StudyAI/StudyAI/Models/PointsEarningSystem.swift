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
    let id = UUID()
    let date: String // "2024-01-15" (server calculated date)
    let dayOfWeek: Int // 1-7, Monday=1
    var questionCount: Int
    let timezone: String
    
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
        
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
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
    let id = UUID()
    let type: LearningGoalType
    let title: String
    let description: String
    let targetValue: Int
    let basePoints: Int
    let bonusMultiplier: Double
    var currentProgress: Int = 0
    let isDaily: Bool
    let isWeekly: Bool
    
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
}

enum LearningGoalType: String, CaseIterable, Codable {
    case dailyQuestions = "daily_questions"
    case weeklyStreak = "weekly_streak"
    case accuracyGoal = "accuracy_goal"
    case studyTime = "study_time"
    case subjectMastery = "subject_mastery"
    
    var displayName: String {
        switch self {
        case .dailyQuestions: return "Daily Questions"
        case .weeklyStreak: return "Weekly Streak"
        case .accuracyGoal: return "Accuracy Goal"
        case .studyTime: return "Study Time"
        case .subjectMastery: return "Subject Mastery"
        }
    }
    
    var icon: String {
        switch self {
        case .dailyQuestions: return "questionmark.circle.fill"
        case .weeklyStreak: return "flame.fill"
        case .accuracyGoal: return "target"
        case .studyTime: return "clock.fill"
        case .subjectMastery: return "graduationcap.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .dailyQuestions: return .blue
        case .weeklyStreak: return .orange
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
    @Published var todayProgress: DailyProgress?
    
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
    
    private init() {
        print("🎯 DEBUG: PointsEarningManager instance created with ID: \(instanceId)")
        loadStoredData()
        setupDefaultGoals()
        checkDailyReset()
        checkWeeklyReset()
        handleTimezoneChange()
        
        // Load current week from server asynchronously
        Task {
            await loadCurrentWeekFromServer()
        }
    }
    
    private func loadStoredData() {
        currentPoints = userDefaults.integer(forKey: pointsKey)
        totalPointsEarned = userDefaults.integer(forKey: totalPointsKey)
        currentStreak = userDefaults.integer(forKey: streakKey)
        
        if let goalsData = userDefaults.data(forKey: goalsKey),
           let decodedGoals = try? JSONDecoder().decode([LearningGoal].self, from: goalsData) {
            learningGoals = decodedGoals
        }
        
        if let checkoutData = userDefaults.data(forKey: checkoutHistoryKey),
           let decodedCheckouts = try? JSONDecoder().decode([DailyCheckout].self, from: checkoutData) {
            dailyCheckoutHistory = decodedCheckouts
        }
        
        // Load weekly progress data
        if let weeklyData = userDefaults.data(forKey: weeklyProgressKey),
           let decodedWeekly = try? JSONDecoder().decode(WeeklyProgress.self, from: weeklyData) {
            currentWeeklyProgress = decodedWeekly
        }
        
        if let weeklyHistoryData = userDefaults.data(forKey: weeklyHistoryKey),
           let decodedHistory = try? JSONDecoder().decode([WeeklyProgress].self, from: weeklyHistoryData) {
            weeklyProgressHistory = decodedHistory
        }
        
        lastTimezoneUpdate = userDefaults.object(forKey: lastTimezoneKey) as? Date
    }
    
    private func saveData() {
        userDefaults.set(currentPoints, forKey: pointsKey)
        userDefaults.set(totalPointsEarned, forKey: totalPointsKey)
        userDefaults.set(currentStreak, forKey: streakKey)
        
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
        }
    }
    
    private func checkDailyReset() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastCheckout = dailyCheckoutHistory.last?.date ?? Date.distantPast
        let lastCheckoutDay = Calendar.current.startOfDay(for: lastCheckout)
        
        if today > lastCheckoutDay {
            resetDailyGoals()
            updateStreak()
        }
    }
    
    private func resetDailyGoals() {
        for i in 0..<learningGoals.count {
            if learningGoals[i].isDaily {
                learningGoals[i].currentProgress = 0
            }
        }
        todayProgress = DailyProgress()
        saveData()
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
        saveData()
    }
    
    private func updateWeeklyStreakGoal() {
        for i in 0..<learningGoals.count {
            if learningGoals[i].type == .weeklyStreak {
                learningGoals[i].currentProgress = currentStreak
            }
        }
    }
    
    // MARK: - Public Methods
    
    func trackQuestionAnswered(subject: String, isCorrect: Bool) {
        print("🎯 DEBUG: [Instance \(instanceId)] trackQuestionAnswered called - subject: \(subject), isCorrect: \(isCorrect)")
        
        // Show current state BEFORE tracking
        print("🎯 DEBUG: [Instance \(instanceId)] BEFORE tracking - Current learning goals state:")
        for (index, goal) in learningGoals.enumerated() {
            print("🎯 DEBUG: [Instance \(instanceId)]   Goal \(index): \(goal.type.displayName) - Progress: \(goal.currentProgress)/\(goal.targetValue)")
        }
        
        // Update daily questions goal
        for i in 0..<learningGoals.count {
            if learningGoals[i].type == .dailyQuestions {
                let oldProgress = learningGoals[i].currentProgress
                learningGoals[i].currentProgress += 1
                let newProgress = learningGoals[i].currentProgress
                print("🎯 DEBUG: [Instance \(instanceId)] Daily Questions progress updated: \(oldProgress) → \(newProgress)/\(learningGoals[i].targetValue)")
            }
        }
        
        // Update accuracy tracking
        if todayProgress == nil {
            todayProgress = DailyProgress()
            print("🎯 DEBUG: Created new DailyProgress")
        }
        todayProgress?.totalQuestions += 1
        if isCorrect {
            todayProgress?.correctAnswers += 1
        }
        
        if let progress = todayProgress {
            print("🎯 DEBUG: Today's progress - Total: \(progress.totalQuestions), Correct: \(progress.correctAnswers), Accuracy: \(progress.accuracy)%")
        }
        
        // Update accuracy goal
        updateAccuracyGoal()
        
        // MARK: - NEW: Update weekly progress tracking
        updateWeeklyProgress(questionCount: 1, subject: subject)
        
        saveData()
        
        // Show current state AFTER tracking and saving
        print("🎯 DEBUG: [Instance \(instanceId)] AFTER tracking - Current learning goals state:")
        for (index, goal) in learningGoals.enumerated() {
            print("🎯 DEBUG: [Instance \(instanceId)]   Goal \(index): \(goal.type.displayName) - Progress: \(goal.currentProgress)/\(goal.targetValue)")
        }
        print("🎯 DEBUG: [Instance \(instanceId)] Data saved and accuracy goal updated")
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
    
    func addCustomLearningGoal(_ goal: LearningGoal) {
        learningGoals.append(goal)
        saveData()
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
        print("📊 DEBUG: updateWeeklyProgress called - questionCount: \(questionCount), subject: \(subject)")
        
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
            print("📊 DEBUG: Updated existing day \(todayString): \(weeklyProgress.dailyActivities[existingIndex].questionCount) questions")
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
            print("📊 DEBUG: Added new day activity for \(todayString): \(questionCount) questions")
        }
        
        // Update total questions for the week
        weeklyProgress.totalQuestionsThisWeek = weeklyProgress.dailyActivities.reduce(0) { $0 + $1.questionCount }
        
        // Save updated progress
        currentWeeklyProgress = weeklyProgress
        saveData()
        
        print("📊 DEBUG: Weekly total updated: \(weeklyProgress.totalQuestionsThisWeek) questions")
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
        
        print("📊 DEBUG: Created new week progress: \(weekStartString) - \(weekEndString)")
        
        return WeeklyProgress(
            weekStart: weekStartString,
            weekEnd: weekEndString,
            totalQuestionsThisWeek: 0,
            dailyActivities: dailyActivities,
            timezone: timezone,
            serverTimestamp: now
        )
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
            print("📊 DEBUG: Week boundary crossed, archiving current week and starting new")
            
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
            print("📊 DEBUG: Timezone changed from \(storedTimezone ?? "unknown") to \(currentTimezone)")
            
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
                print("📊 DEBUG: Server sync successful")
                // Update local data with server response if needed
                if let serverProgress = result.progress {
                    await MainActor.run {
                        updateFromServerResponse(serverProgress)
                    }
                }
            } else {
                print("📊 DEBUG: Server sync failed: \(result.message ?? "Unknown error")")
                // Continue with local data - sync will retry later
            }
        } catch {
            print("📊 DEBUG: Server sync error: \(error)")
            // Continue with local data - sync will retry later
        }
    }
    
    /// Load current week progress from server on app start
    func loadCurrentWeekFromServer() async {
        guard let networkService = await getNetworkService() else { return }
        
        do {
            let result = await networkService.getCurrentWeekProgress(
                timezone: TimeZone.current.identifier
            )
            
            if result.success, let serverProgress = result.progress {
                await MainActor.run {
                    updateFromServerResponse(serverProgress)
                    saveData()
                    print("📊 DEBUG: Loaded current week from server successfully")
                }
            } else {
                print("📊 DEBUG: Failed to load current week from server: \(result.message ?? "Unknown error")")
            }
        } catch {
            print("📊 DEBUG: Error loading current week from server: \(error)")
        }
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
            print("📊 DEBUG: Invalid server response format")
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
        
        print("📊 DEBUG: Updated local data from server - Total questions: \(totalQuestions), Score: \(currentScore)")
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
    let id = UUID()
    let date: Date
    let pointsEarned: Int
    let goalsCompleted: Int
    let streak: Int
    let isWeekend: Bool
    
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