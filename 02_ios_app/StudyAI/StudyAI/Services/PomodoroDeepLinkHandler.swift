//
//  PomodoroDeepLinkHandler.swift
//  StudyAI
//
//  Deep Link处理器 - 处理通知跳转到番茄专注
//

import Foundation
import SwiftUI
import Combine
import UserNotifications

/// 番茄专注Deep Link处理器
class PomodoroDeepLinkHandler: NSObject, ObservableObject {
    static let shared = PomodoroDeepLinkHandler()

    // MARK: - Published Properties
    @Published var shouldShowPomodoro: Bool = false
    @Published var shouldAutoStart: Bool = false
    @Published var pendingEventId: String?

    // MARK: - Deep Link Actions

    enum DeepLinkAction: String {
        case startPomodoro = "start_pomodoro"
        case showCalendar = "show_calendar"
        case showGarden = "show_garden"
    }

    private override init() {
        super.init()
        setupNotificationDelegate()
    }

    // MARK: - Setup

    private func setupNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = self
        debugPrint("🔗 Deep link handler initialized")
    }

    // MARK: - Handle Deep Link

    /// 处理Deep Link URL
    func handleDeepLink(url: URL) {
        debugPrint("🔗 Handling deep link: \(url.absoluteString)")

        guard url.scheme == "studyai" else {
            debugPrint("⚠️ Invalid URL scheme: \(url.scheme ?? "nil")")
            return
        }

        let path = url.host ?? ""

        switch path {
        case "pomodoro":
            handlePomodoroDeepLink(url: url)
        case "calendar":
            handleCalendarDeepLink()
        case "garden":
            handleGardenDeepLink()
        default:
            debugPrint("⚠️ Unknown deep link path: \(path)")
        }
    }

    /// 处理番茄专注Deep Link
    private func handlePomodoroDeepLink(url: URL) {
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if pathComponents.contains("start") {
            debugPrint("🍅 Starting pomodoro from deep link")
            DispatchQueue.main.async {
                self.shouldShowPomodoro = true
                self.shouldAutoStart = true
            }
        }
    }

    /// 处理日历Deep Link
    private func handleCalendarDeepLink() {
        debugPrint("📅 Opening calendar from deep link")
        // 可以添加显示日历的逻辑
    }

    /// 处理花园Deep Link
    private func handleGardenDeepLink() {
        debugPrint("🌳 Opening garden from deep link")
        // 可以添加显示花园的逻辑
    }

    // MARK: - Handle Notification Action

    /// 处理通知操作
    func handleNotificationAction(action: String, userInfo: [AnyHashable: Any]) {
        debugPrint("🔔 Handling notification action: \(action)")

        switch action {
        case PomodoroNotificationService.shared.startActionIdentifier:
            // 用户点击了"立即开始"按钮
            handleStartPomodoroAction(userInfo: userInfo)

        case PomodoroNotificationService.shared.snoozeActionIdentifier:
            // 用户点击了"稍后提醒"按钮
            handleSnoozeAction(userInfo: userInfo)

        default:
            break
        }
    }

    private func handleStartPomodoroAction(userInfo: [AnyHashable: Any]) {
        if let eventId = userInfo["eventId"] as? String {
            pendingEventId = eventId
        }

        DispatchQueue.main.async {
            self.shouldShowPomodoro = true
            self.shouldAutoStart = true
        }

        debugPrint("🍅 Starting pomodoro from notification action")
    }

    private func handleSnoozeAction(userInfo: [AnyHashable: Any]) {
        // 5分钟后再次提醒
        if let eventId = userInfo["eventId"] as? String,
           let title = userInfo["title"] as? String {
            let snoozeDate = Date().addingTimeInterval(5 * 60)

            _ = PomodoroNotificationService.shared.scheduleNotification(
                for: eventId,
                title: title,
                startDate: snoozeDate,
                minutesBefore: 0  // 立即提醒
            )

            debugPrint("⏰ Snoozed notification for 5 minutes")
        }
    }

    // MARK: - Reset State

    func resetState() {
        shouldShowPomodoro = false
        shouldAutoStart = false
        pendingEventId = nil
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PomodoroDeepLinkHandler: UNUserNotificationCenterDelegate {

    /// 当应用在前台时收到通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        debugPrint("🔔 Notification received while app in foreground")

        // 在iOS 14+显示横幅、声音和角标
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    /// 当用户点击通知时调用
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        debugPrint("🔔 Notification tapped: \(actionIdentifier)")

        // 处理用户操作
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            // 用户点击了通知本身
            if let deepLink = userInfo["deepLink"] as? String,
               let url = URL(string: deepLink) {
                handleDeepLink(url: url)
            }
        } else {
            // 用户点击了操作按钮
            handleNotificationAction(action: actionIdentifier, userInfo: userInfo)
        }

        // 清除角标
        PomodoroNotificationService.shared.clearBadge()

        completionHandler()
    }
}
