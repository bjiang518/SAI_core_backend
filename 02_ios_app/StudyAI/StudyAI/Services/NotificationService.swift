//
//  NotificationService.swift
//  StudyAI
//
//  Handles all local notification logic including permissions and scheduling
//

import Foundation
import UserNotifications
import Combine
import UIKit

class NotificationService: NSObject, ObservableObject {

    static let shared = NotificationService()

    // MARK: - Published Properties

    @Published var isAuthorized = false
    @Published var settings = NotificationSettings()
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Constants

    private let notificationCenter = UNUserNotificationCenter.current()
    private let studyReminderIdentifierPrefix = "com.studyai.studyReminder"
    private let dailyChallengeIdentifierPrefix = "com.studyai.dailyChallenge"

    // MARK: - Initialization

    override init() {
        super.init()
        notificationCenter.delegate = self
        loadSettings()
        Task {
            await checkAuthorizationStatus()
            // Auto-request permission and schedule reminders on first launch
            if authorizationStatus == .notDetermined {
                let granted = await requestAuthorization()
                if granted {
                    scheduleStudyReminders()
                    scheduleDailyChallengeReminder()
                }
            } else if isAuthorized {
                scheduleStudyReminders()
                scheduleDailyChallengeReminder()
            }
        }
    }

    // MARK: - Settings Management

    func loadSettings() {
        settings = NotificationSettings.load()
        debugPrint("📱 NotificationService: Settings loaded")
    }

    func saveSettings() {
        settings.save()
        debugPrint("📱 NotificationService: Settings saved")
    }

    // MARK: - Permission Management

    @MainActor
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            await checkAuthorizationStatus()

            if granted {
                debugPrint("📱 NotificationService: Authorization granted")
                // Register for remote (APNs) notifications so server can push reports
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                debugPrint("📱 NotificationService: Authorization denied")
            }

            return granted
        } catch {
            debugPrint("📱 NotificationService: Authorization error: \(error)")
            return false
        }
    }

    @MainActor
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = (settings.authorizationStatus == .authorized)

        // Register for remote (APNs) notifications whenever permission is granted,
        // even if it was granted in a previous session (no dialog shown then).
        if settings.authorizationStatus == .authorized {
            UIApplication.shared.registerForRemoteNotifications()
        }

        debugPrint("📱 NotificationService: Authorization status: \(authorizationStatus.rawValue)")
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Study Reminder Scheduling

    func scheduleStudyReminders() {
        guard settings.isEnabled && settings.studyReminders.isEnabled else {
            debugPrint("📱 NotificationService: Study reminders disabled, skipping scheduling")
            return
        }

        // Cancel existing reminders first
        cancelStudyReminders()

        let config = settings.studyReminders
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: config.time)

        guard let hour = timeComponents.hour, let minute = timeComponents.minute else {
            debugPrint("📱 NotificationService: Invalid time components")
            return
        }

        // Collect signals and schedule non-repeating personalized notifications for next 7 days
        Task {
            let signals = await collectStudySignals()

            let now = Date()
            var scheduledCount = 0

            for dayOffset in 0..<7 {
                guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }

                // Determine weekday and check if it's in the user's selected days
                let weekdayIndex = calendar.component(.weekday, from: targetDate)
                guard let weekday = Weekday.allCases.first(where: { $0.calendarWeekday == weekdayIndex }),
                      config.days.contains(weekday) else { continue }

                // Build exact fire date components
                var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
                dateComponents.hour = hour
                dateComponents.minute = minute

                // Skip if fire time is already past today
                if let fireDate = calendar.date(from: dateComponents), fireDate <= now {
                    continue
                }

                // Date-based identifier (compatible with cancelStudyReminders prefix filter)
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd"
                let dateString = dateFormatter.string(from: targetDate)
                let identifier = "\(studyReminderIdentifierPrefix).\(dateString)"

                // Select personalized message
                let dayOfYear = calendar.ordinality(of: .day, in: .year, for: targetDate) ?? dayOffset
                let message = PersonalizedMessageEngine.selectMessage(for: signals, dayOfYear: dayOfYear)

                let content = UNMutableNotificationContent()
                content.title = message.title
                content.body = message.body
                content.sound = .default
                content.badge = 1
                content.categoryIdentifier = "STUDY_REMINDER"

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                notificationCenter.add(request) { error in
                    if let error = error {
                        debugPrint("📱 NotificationService: Failed to schedule \(dateString) reminder: \(error)")
                    }
                }
                scheduledCount += 1
            }

            debugPrint("📱 NotificationService: Scheduled \(scheduledCount) personalized study reminders")
        }
    }

    /// Refresh study reminders with fresh personalized content, at most once per calendar day.
    func refreshStudyRemindersIfNeeded() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        guard settings.lastReminderRefreshDate != today else { return }

        settings.lastReminderRefreshDate = today
        saveSettings()
        scheduleStudyReminders()
        scheduleDailyChallengeReminder()
        debugPrint("📱 NotificationService: Daily reminder refresh triggered")
    }

    // MARK: - Personalized Signal Collection

    private func collectStudySignals() async -> StudySignals {
        return await MainActor.run {
            let profile = ProfileService.shared.currentProfile
            let userName = AuthenticationService.shared.currentUser?.name
            let points = PointsEarningManager.shared

            // Display name: prefer profile firstName, fall back to first word of user name
            let displayName = profile?.firstName ?? userName?.components(separatedBy: " ").first

            // Top weakness: highest value > 0, parse key "Subject/baseBranch/detailedBranch"
            let topWeakness: (subject: String, concept: String)? = {
                let weaknesses = ShortTermStatusService.shared.status.activeWeaknesses
                    .filter { $0.value.value > 0 }
                    .sorted { $0.value.value > $1.value.value }
                guard let top = weaknesses.first else { return nil }
                let parts = top.key.components(separatedBy: "/")
                let subject = parts.first ?? top.key
                let concept = (parts.count >= 3 ? parts[2] : parts.count >= 2 ? parts[1] : subject)
                    .replacingOccurrences(of: "_", with: " ")
                return (subject: subject, concept: concept)
            }()

            // Incomplete practice session subject
            let incompleteSubject = PracticeSessionManager.shared.incompleteSessions.first?.subject

            // Daily goal progress (first incomplete daily goal)
            let goalProgress: Double? = {
                guard let goal = points.learningGoals.first(where: { $0.isDaily && !$0.isCompleted && $0.targetValue > 0 }) else { return nil }
                return Double(goal.currentProgress) / Double(goal.targetValue)
            }()

            return StudySignals(
                displayName: displayName,
                currentStreak: points.currentStreak,
                hasActivityToday: (points.todayProgress?.totalQuestions ?? 0) > 0,
                topWeakness: topWeakness,
                favoriteSubject: profile?.favoriteSubjects.first,
                incompleteSessionSubject: incompleteSubject,
                goalProgressPercent: goalProgress
            )
        }
    }

    // MARK: - Daily Challenge Reminder (4pm, every day)

    func scheduleDailyChallengeReminder() {
        guard settings.isEnabled else { return }

        cancelDailyChallengeReminders()

        let calendar = Calendar.current
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let todayKey = { () -> String in
            var f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: now)
        }()
        let alreadyDoneToday = UserDefaults.standard.string(forKey: "daily_challenge_last_completed") == todayKey

        for dayOffset in 0..<7 {
            guard let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }

            if dayOffset == 0 && alreadyDoneToday { continue }

            var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.hour = 16
            dateComponents.minute = 0

            if let fireDate = calendar.date(from: dateComponents), fireDate <= now { continue }

            let dateString = dateFormatter.string(from: targetDate)
            let identifier = "\(dailyChallengeIdentifierPrefix).\(dateString)"

            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("notification.dailyChallenge.title", value: "📚 每日3题来啦！", comment: "")
            content.body = NSLocalizedString("notification.dailyChallenge.body", value: "今天的练习题已经准备好，3题快速搞定！", comment: "")
            content.sound = .default
            content.badge = 1
            content.categoryIdentifier = "DAILY_CHALLENGE"

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            notificationCenter.add(request) { error in
                if let error = error {
                    debugPrint("📱 NotificationService: Failed to schedule daily challenge \(dateString): \(error)")
                }
            }
        }
        debugPrint("📱 NotificationService: Scheduled daily challenge reminders (4pm)")
    }

    func cancelDailyChallengeReminders() {
        notificationCenter.getPendingNotificationRequests { requests in
            let ids = requests.map { $0.identifier }.filter { $0.hasPrefix(self.dailyChallengeIdentifierPrefix) }
            if !ids.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    func cancelStudyReminders() {
        notificationCenter.getPendingNotificationRequests { requests in
            let studyReminderIds = requests
                .map { $0.identifier }
                .filter { $0.hasPrefix(self.studyReminderIdentifierPrefix) }

            if !studyReminderIds.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: studyReminderIds)
                debugPrint("📱 NotificationService: Cancelled \(studyReminderIds.count) study reminders")
            }
        }
    }

    func updateStudyReminders(config: StudyReminderConfig) {
        settings.studyReminders = config
        saveSettings()
        scheduleStudyReminders()
    }

    // MARK: - Helper Methods

    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }

    func removeAllPendingNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        debugPrint("📱 NotificationService: Removed all pending notifications")
    }

    // MARK: - Streak Protection Notification

    /// Schedule a notification at 8 PM if the user hasn't done any activity today and has a streak > 2.
    /// Called from HomeView.onAppear.
    func scheduleStreakProtectionReminder(currentStreak: Int) {
        guard settings.isEnabled && settings.streakReminders else { return }
        guard currentStreak > 2 else { return }

        let identifier = "com.studyai.streakProtection"

        // Cancel any existing streak reminder first
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("streak.reminder.title", comment: "Streak at risk notification title")
        content.body = String(format: NSLocalizedString("streak.reminder.body", comment: "Streak at risk body"), currentStreak)
        content.sound = .default
        content.categoryIdentifier = "STREAK_REMINDER"

        // Fire at 8 PM today
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        dateComponents.hour = 20
        dateComponents.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        notificationCenter.add(request) { error in
            if let error = error {
                debugPrint("📱 NotificationService: Failed to schedule streak reminder: \(error)")
            } else {
                debugPrint("📱 NotificationService: Scheduled streak protection reminder for streak=\(currentStreak)")
            }
        }
    }

    /// Cancel the streak protection reminder (called when user completes first activity today).
    func cancelStreakProtectionReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["com.studyai.streakProtection"])
        debugPrint("📱 NotificationService: Cancelled streak protection reminder")
    }

    // MARK: - Homework Completion Notification

    func sendHomeworkCompletionNotification(questionCount: Int) {
        guard settings.isEnabled && settings.homeworkNotifications else {
            debugPrint("📱 NotificationService: Homework notifications disabled, skipping")
            return
        }

        let identifier = "com.studyai.homeworkComplete.\(UUID().uuidString)"

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Homework Results Ready"
        content.body = "\(questionCount) question\(questionCount == 1 ? "" : "s") graded — tap to see how you did!"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "HOMEWORK_COMPLETE"

        // Deliver immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // Add notification
        notificationCenter.add(request) { error in
            if let error = error {
                debugPrint("📱 NotificationService: Failed to send homework completion notification: \(error)")
            } else {
                debugPrint("📱 NotificationService: Sent homework completion notification for \(questionCount) questions")
            }
        }
    }

    // MARK: - Parent Report Notifications

    /// Send notification when a new parent report is available
    /// - Parameters:
    ///   - period: Report period (weekly/monthly)
    ///   - reportCount: Number of reports in the batch (usually 8)
    ///   - overallGrade: Optional overall grade (A/B/C)
    func sendParentReportAvailableNotification(period: String, reportCount: Int, overallGrade: String? = nil) {
        guard settings.isEnabled && settings.reportNotifications else {
            debugPrint("📱 NotificationService: Report notifications disabled, skipping")
            return
        }

        let identifier = "com.studyai.parentReport.\(period).\(UUID().uuidString)"

        // Create notification content
        let content = UNMutableNotificationContent()

        // Title based on period
        if period.lowercased() == "weekly" {
            content.title = "Weekly Learning Report Ready"
        } else {
            content.title = "Monthly Learning Report Ready"
        }

        // Body with grade if available
        if let grade = overallGrade {
            content.body = "Your \(period) report is in — overall grade: \(grade). Tap to see \(reportCount) insights."
        } else {
            content.body = "Your \(period) learning report is ready with \(reportCount) insights. Tap to check it out."
        }

        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "PARENT_REPORT"

        // Add user info to help with navigation
        content.userInfo = [
            "reportType": "parent_report",
            "period": period,
            "reportCount": reportCount
        ]

        // Deliver immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // Add notification
        notificationCenter.add(request) { error in
            if let error = error {
                debugPrint("📱 NotificationService: Failed to send parent report notification: \(error)")
            } else {
                debugPrint("📱 NotificationService: Sent parent report notification for \(period) report with \(reportCount) insights")
            }
        }
    }

    /// Schedule a reminder to check parent reports
    /// - Parameter delay: Delay in seconds (default: 1 hour = 3600 seconds)
    func scheduleParentReportCheckReminder(delay: TimeInterval = 3600) {
        guard settings.isEnabled && settings.reportNotifications else {
            debugPrint("📱 NotificationService: Report notifications disabled, skipping report check reminder")
            return
        }

        let identifier = "com.studyai.parentReport.checkReminder"

        // Cancel any existing reminder first
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Check Your Learning Reports"
        content.body = "New reports may be available — tap to see your latest progress."
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = "PARENT_REPORT_REMINDER"

        // Create trigger with delay
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)

        // Create request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // Add notification
        notificationCenter.add(request) { error in
            if let error = error {
                debugPrint("📱 NotificationService: Failed to schedule report check reminder: \(error)")
            } else {
                debugPrint("📱 NotificationService: Scheduled report check reminder for \(Int(delay / 60)) minutes from now")
            }
        }
    }

    /// Cancel pending parent report check reminders
    func cancelParentReportCheckReminder() {
        let identifier = "com.studyai.parentReport.checkReminder"
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        debugPrint("📱 NotificationService: Cancelled parent report check reminder")
    }

    // MARK: - Badge Management

    /// Clear the app icon badge count. Call when app becomes active.
    func clearBadge() {
        if #available(iOS 16.0, *) {
            notificationCenter.setBadgeCount(0) { error in
                if let error = error {
                    debugPrint("📱 NotificationService: Failed to clear badge: \(error)")
                }
            }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        debugPrint("📱 NotificationService: Notification received in foreground")
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        debugPrint("📱 NotificationService: User tapped notification: \(response.notification.request.identifier)")

        // Handle different notification types here
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo

        if identifier.hasPrefix(studyReminderIdentifierPrefix) {
            // User tapped study reminder - could open app to specific view
            debugPrint("📱 NotificationService: Study reminder tapped")
        } else if identifier.hasPrefix(dailyChallengeIdentifierPrefix) {
            debugPrint("📱 NotificationService: Daily challenge notification tapped")
            DispatchQueue.main.async {
                AppState.shared.shouldOpenDailyChallenge = true
            }
        } else if identifier.hasPrefix("com.studyai.parentReport") {
            // User tapped parent report notification
            debugPrint("📱 NotificationService: Parent report notification tapped")

            // Post notification to open parent reports view
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenParentReports"),
                object: nil,
                userInfo: userInfo
            )
        } else if identifier.hasPrefix("com.studyai.homeworkComplete") {
            // User tapped homework completion notification
            debugPrint("📱 NotificationService: Homework completion notification tapped")
        }

        completionHandler()
    }
}