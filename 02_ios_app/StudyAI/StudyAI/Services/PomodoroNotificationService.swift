//
//  PomodoroNotificationService.swift
//  StudyAI
//
//  番茄专注通知服务 - 本地通知和Deep Linking
//

import Foundation
import UserNotifications
import Combine

class PomodoroNotificationService: ObservableObject {
    static let shared = PomodoroNotificationService()

    // MARK: - Published Properties
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var hasNotificationAccess: Bool = false

    // MARK: - Constants
    let notificationCategoryIdentifier = "POMODORO_CATEGORY"
    let startActionIdentifier = "START_POMODORO_ACTION"
    let snoozeActionIdentifier = "SNOOZE_POMODORO_ACTION"

    // Deep Link URL Scheme
    static let deepLinkScheme = "studyai://pomodoro/start"

    private init() {
        checkAuthorizationStatus()
        setupNotificationCategories()
    }

    // MARK: - Authorization

    /// 检查通知权限状态
    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
                self.hasNotificationAccess = (settings.authorizationStatus == .authorized)
                print("🔔 Notification authorization status: \(settings.authorizationStatus.rawValue)")
            }
        }
    }

    /// 请求通知权限
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])

            DispatchQueue.main.async {
                self.hasNotificationAccess = granted
                self.authorizationStatus = granted ? .authorized : .denied
            }

            print("🔔 Notification permission \(granted ? "granted" : "denied")")
            return granted
        } catch {
            print("❌ Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Setup

    /// 设置通知交互按钮
    private func setupNotificationCategories() {
        // 开始番茄钟按钮
        let startAction = UNNotificationAction(
            identifier: startActionIdentifier,
            title: "立即开始",
            options: [.foreground]
        )

        // 稍后提醒按钮
        let snoozeAction = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "5分钟后提醒",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: notificationCategoryIdentifier,
            actions: [startAction, snoozeAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
        print("✅ Notification categories configured")
    }

    // MARK: - Schedule Notifications

    /// 为番茄专注事件安排通知（提前5分钟）
    func scheduleNotification(for eventId: String,
                            title: String,
                            startDate: Date,
                            minutesBefore: Int = 5) -> String? {
        guard hasNotificationAccess else {
            print("⚠️ No notification access - cannot schedule notification")
            return nil
        }

        // 计算通知时间（提前5分钟）
        guard let notificationDate = Calendar.current.date(
            byAdding: .minute,
            value: -minutesBefore,
            to: startDate
        ) else {
            print("❌ Failed to calculate notification date")
            return nil
        }

        // 检查通知时间是否在未来
        guard notificationDate > Date() else {
            print("⚠️ Notification date is in the past, skipping")
            return nil
        }

        let content = UNMutableNotificationContent()
        content.title = "番茄专注提醒 🍅"
        content.body = "\(title) 将在 \(minutesBefore) 分钟后开始"
        content.sound = .default
        content.badge = 1
        content.categoryIdentifier = notificationCategoryIdentifier

        // 添加Deep Link数据
        content.userInfo = [
            "action": "start_pomodoro",
            "eventId": eventId,
            "deepLink": PomodoroNotificationService.deepLinkScheme
        ]

        // 创建触发器
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: notificationDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)

        // 创建请求
        let notificationId = "pomodoro_\(eventId)_\(UUID().uuidString)"
        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: trigger
        )

        // 添加到通知中心
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule notification: \(error.localizedDescription)")
            } else {
                print("✅ Notification scheduled: \(notificationId) at \(notificationDate)")
            }
        }

        return notificationId
    }

    /// 批量安排通知
    func scheduleMultipleNotifications(for eventIds: [(id: String, title: String, startDate: Date)]) -> [String] {
        var notificationIds: [String] = []

        for event in eventIds {
            if let notificationId = scheduleNotification(
                for: event.id,
                title: event.title,
                startDate: event.startDate
            ) {
                notificationIds.append(notificationId)
            }
        }

        print("✅ Scheduled \(notificationIds.count) notifications")
        return notificationIds
    }

    // MARK: - Manage Notifications

    /// 取消指定通知
    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        print("🗑️ Notification cancelled: \(identifier)")
    }

    /// 取消所有番茄专注通知
    func cancelAllPomodoroNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let pomodoroIds = requests
                .filter { $0.identifier.hasPrefix("pomodoro_") }
                .map { $0.identifier }

            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: pomodoroIds)
            print("🗑️ Cancelled \(pomodoroIds.count) pomodoro notifications")
        }
    }

    /// 获取所有待处理的通知
    func getPendingNotifications(completion: @escaping ([UNNotificationRequest]) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let pomodoroNotifications = requests.filter { $0.identifier.hasPrefix("pomodoro_") }
            DispatchQueue.main.async {
                completion(pomodoroNotifications)
            }
        }
    }

    // MARK: - Immediate Notifications

    /// 立即发送测试通知
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "番茄专注测试"
        content.body = "这是一个测试通知"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "test_\(UUID().uuidString)",
            content: content,
            trigger: nil  // 立即触发
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send test notification: \(error.localizedDescription)")
            } else {
                print("✅ Test notification sent")
            }
        }
    }

    /// 番茄钟完成通知
    func sendCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "番茄钟完成！🎉"
        content.body = "太棒了！你刚完成了25分钟的专注时间"
        content.sound = .default
        content.badge = 1

        let request = UNNotificationRequest(
            identifier: "completion_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
        print("✅ Completion notification sent")
    }

    // MARK: - Helper Methods

    /// 格式化时间
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 清除应用角标
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}
