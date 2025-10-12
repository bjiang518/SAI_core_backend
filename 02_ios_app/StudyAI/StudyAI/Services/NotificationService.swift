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

    // MARK: - Initialization

    override init() {
        super.init()
        notificationCenter.delegate = self
        loadSettings()
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Settings Management

    func loadSettings() {
        settings = NotificationSettings.load()
        print("📱 NotificationService: Settings loaded")
    }

    func saveSettings() {
        settings.save()
        print("📱 NotificationService: Settings saved")
    }

    // MARK: - Permission Management

    @MainActor
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            await checkAuthorizationStatus()

            if granted {
                print("📱 NotificationService: Authorization granted")
            } else {
                print("📱 NotificationService: Authorization denied")
            }

            return granted
        } catch {
            print("📱 NotificationService: Authorization error: \(error)")
            return false
        }
    }

    @MainActor
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = (settings.authorizationStatus == .authorized)

        print("📱 NotificationService: Authorization status: \(authorizationStatus.rawValue)")
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Study Reminder Scheduling

    func scheduleStudyReminders() {
        guard settings.isEnabled && settings.studyReminders.isEnabled else {
            print("📱 NotificationService: Study reminders disabled, skipping scheduling")
            return
        }

        // Cancel existing reminders first
        cancelStudyReminders()

        let config = settings.studyReminders
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: config.time)

        guard let hour = timeComponents.hour, let minute = timeComponents.minute else {
            print("📱 NotificationService: Invalid time components")
            return
        }

        // Schedule for each selected day
        for day in config.days {
            let identifier = "\(studyReminderIdentifierPrefix).\(day.rawValue)"

            // Create date components for the reminder
            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute
            dateComponents.weekday = day.calendarWeekday

            // Create notification content
            let content = UNMutableNotificationContent()
            content.title = "Study Time 📚"
            content.body = StudyReminderMessage.allMessages.randomElement() ?? "Time to study!"
            content.sound = .default
            content.badge = 1
            content.categoryIdentifier = "STUDY_REMINDER"

            // Create trigger
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

            // Create request
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            // Add notification
            notificationCenter.add(request) { error in
                if let error = error {
                    print("📱 NotificationService: Failed to schedule \(day.displayName) reminder: \(error)")
                } else {
                    print("📱 NotificationService: Scheduled reminder for \(day.displayName) at \(hour):\(String(format: "%02d", minute))")
                }
            }
        }

        print("📱 NotificationService: Scheduled \(config.days.count) study reminders")
    }

    func cancelStudyReminders() {
        // Get all pending notifications with our prefix
        notificationCenter.getPendingNotificationRequests { requests in
            let studyReminderIds = requests
                .map { $0.identifier }
                .filter { $0.hasPrefix(self.studyReminderIdentifierPrefix) }

            if !studyReminderIds.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: studyReminderIds)
                print("📱 NotificationService: Cancelled \(studyReminderIds.count) study reminders")
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
        print("📱 NotificationService: Removed all pending notifications")
    }

    // MARK: - Homework Completion Notification

    func sendHomeworkCompletionNotification(questionCount: Int) {
        guard settings.isEnabled else {
            print("📱 NotificationService: Notifications disabled, skipping homework completion notification")
            return
        }

        let identifier = "com.studyai.homeworkComplete.\(UUID().uuidString)"

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Homework Graded! 🎉"
        content.body = "Your homework has been analyzed. \(questionCount) question\(questionCount == 1 ? "" : "s") graded. Tap to view results!"
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
                print("📱 NotificationService: Failed to send homework completion notification: \(error)")
            } else {
                print("📱 NotificationService: Sent homework completion notification for \(questionCount) questions")
            }
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
        print("📱 NotificationService: Notification received in foreground")
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("📱 NotificationService: User tapped notification: \(response.notification.request.identifier)")

        // Handle different notification types here
        let identifier = response.notification.request.identifier

        if identifier.hasPrefix(studyReminderIdentifierPrefix) {
            // User tapped study reminder - could open app to specific view
            print("📱 NotificationService: Study reminder tapped")
        }

        completionHandler()
    }
}