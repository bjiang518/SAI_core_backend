//
//  DeepFocusService.swift
//  StudyAI
//
//  深度专注模式服务 - 屏蔽通知和干扰
//

import Foundation
import Combine
import UserNotifications
import AVFoundation
import UIKit

/// 深度专注模式服务
class DeepFocusService: ObservableObject {
    static let shared = DeepFocusService()

    // MARK: - Published Properties
    @Published var isDeepFocusEnabled: Bool = false
    @Published var previousRingerState: Bool = true
    @Published var blockedNotificationsCount: Int = 0

    // MARK: - Private Properties
    private var previousBrightness: CGFloat = UIScreen.main.brightness
    private var originalNotificationSettings: UNNotificationSettings?

    // MARK: - UserDefaults Keys (per-user)
    private var userKeyPrefix: String {
        let userId = AuthenticationService.shared.currentUser?.id ?? "anonymous"
        return "studyai_\(userId)_"
    }
    private var deepFocusEnabledKey: String { userKeyPrefix + "deepFocusEnabled" }
    private var autoEnableDeepFocusKey: String { userKeyPrefix + "autoEnableDeepFocus" }

    private init() {
        loadSettings()
    }

    // MARK: - Settings

    /// 是否自动启用深度专注
    var autoEnableDeepFocus: Bool {
        get {
            UserDefaults.standard.bool(forKey: autoEnableDeepFocusKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoEnableDeepFocusKey)
        }
    }

    private func loadSettings() {
        isDeepFocusEnabled = UserDefaults.standard.bool(forKey: deepFocusEnabledKey)
    }

    private func saveSettings() {
        UserDefaults.standard.set(isDeepFocusEnabled, forKey: deepFocusEnabledKey)
    }

    // MARK: - Enable Deep Focus

    /// 启用深度专注模式
    func enableDeepFocus() {
        guard !isDeepFocusEnabled else {
            debugPrint("⚡️ Deep focus already enabled")
            return
        }

        debugPrint("🔇 Enabling deep focus mode...")

        // 1. 保存当前状态
        savePreviousState()

        // 2. 暂停App内所有非关键通知
        suppressAppNotifications()

        // 3. 降低屏幕亮度（可选，保护眼睛）
        reduceBrightness()

        // 4. 设置音频会话为专注模式
        configureAudioSessionForFocus()

        // 5. 深度专注模式已启用（不再弹出提示通知）
        // suggestSystemFocusMode() // 已移除自动提示

        isDeepFocusEnabled = true
        saveSettings()

        // 触发震动反馈
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        debugPrint("✅ Deep focus mode enabled")
    }

    /// 禁用深度专注模式
    func disableDeepFocus() {
        guard isDeepFocusEnabled else {
            debugPrint("⚡️ Deep focus already disabled")
            return
        }

        debugPrint("🔊 Disabling deep focus mode...")

        // 1. 恢复通知
        restoreAppNotifications()

        // 2. 恢复屏幕亮度
        restoreBrightness()

        // 3. 恢复音频会话
        restoreAudioSession()

        isDeepFocusEnabled = false
        saveSettings()

        // 触发震动反馈
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        debugPrint("✅ Deep focus mode disabled")
    }

    /// 切换深度专注模式
    func toggleDeepFocus() {
        if isDeepFocusEnabled {
            disableDeepFocus()
        } else {
            enableDeepFocus()
        }
    }

    // MARK: - Private Methods

    /// 保存当前状态
    private func savePreviousState() {
        previousBrightness = UIScreen.main.brightness

        // 获取当前通知设置
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            self.originalNotificationSettings = settings
        }
    }

    /// 暂停App内通知
    private func suppressAppNotifications() {
        // 移除所有待处理的App内通知（除了番茄专注相关）
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let nonPomodoroIds = requests
                .filter { !$0.identifier.hasPrefix("pomodoro_") }
                .map { $0.identifier }

            if !nonPomodoroIds.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(
                    withIdentifiers: nonPomodoroIds
                )
                self.blockedNotificationsCount = nonPomodoroIds.count
                debugPrint("🔇 Blocked \(nonPomodoroIds.count) non-pomodoro notifications")
            }
        }

        // 移除已展示的通知
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// 恢复App内通知
    private func restoreAppNotifications() {
        debugPrint("🔊 Restoring app notifications")
        blockedNotificationsCount = 0
        // 通知会在后续自动重新安排
    }

    /// 降低屏幕亮度
    private func reduceBrightness() {
        // 降低到50%亮度，保护眼睛
        UIScreen.main.brightness = min(previousBrightness, 0.5)
        debugPrint("🔅 Reduced brightness to \(UIScreen.main.brightness)")
    }

    /// 恢复屏幕亮度
    private func restoreBrightness() {
        UIScreen.main.brightness = previousBrightness
        debugPrint("🔆 Restored brightness to \(previousBrightness)")
    }

    /// 配置音频会话为专注模式
    private func configureAudioSessionForFocus() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // 设置为仅播放背景音乐，不响铃
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            debugPrint("🎵 Audio session configured for focus mode")
        } catch {
            debugPrint("❌ Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    /// 恢复音频会话
    private func restoreAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false)
            debugPrint("🎵 Audio session restored")
        } catch {
            debugPrint("❌ Failed to restore audio session: \(error.localizedDescription)")
        }
    }

    /// 建议启用系统专注模式（iOS 15+）
    private func suggestSystemFocusMode() {
        // iOS不允许第三方App直接启用系统勿扰模式
        // 但我们可以提供快捷指令建议

        // 发送本地通知，建议用户手动开启
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showFocusModeReminder()
        }
    }

    /// 显示专注模式提醒
    private func showFocusModeReminder() {
        let content = UNMutableNotificationContent()
        content.title = "💡 提示"
        content.body = "建议开启系统勿扰模式以获得最佳专注效果。下拉控制中心 → 点击专注模式"
        content.sound = .default
        content.categoryIdentifier = "DEEP_FOCUS_TIP"

        let request = UNNotificationRequest(
            identifier: "focus_tip_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
        debugPrint("💡 Sent focus mode suggestion")
    }

    // MARK: - Status Check

    /// 检查当前通知状态
    func checkNotificationStatus(completion: @escaping (UNNotificationSettings) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings)
            }
        }
    }

    /// 获取当前专注状态描述
    func getStatusDescription() -> String {
        if isDeepFocusEnabled {
            return "深度专注模式已启用"
        } else {
            return "深度专注模式已关闭"
        }
    }

    // MARK: - Integration with iOS Focus Mode (iOS 16+)

    /// 打开iOS设置中的专注模式页面
    func openSystemFocusSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
            debugPrint("📱 Opening system settings")
        }
    }

    /// 创建快捷指令建议（Siri Shortcuts）
    @available(iOS 16.0, *)
    func createFocusShortcut() {
        // 创建启用专注模式的Siri快捷指令
        // 用户可以说 "Hey Siri, 开始学习专注"
        debugPrint("📎 Creating Siri shortcut for focus mode")

        // 这需要使用App Intents Framework
        // 在实际应用中需要创建Intent定义文件
    }
}

// MARK: - Focus Mode Tips

extension DeepFocusService {

    /// 提供专注模式使用建议
    func getFocusModeTips() -> [String] {
        return [
            "在iOS控制中心启用「勿扰模式」可以屏蔽所有来电和通知",
            "可以在「设置 → 专注模式」中创建自定义专注模式",
            "建议允许重要联系人的来电，以应对紧急情况",
            "使用「时间表」功能可以让专注模式自动启动",
            "专注模式会在所有Apple设备间同步"
        ]
    }

    /// 获取使用指南
    func getSetupGuide() -> String {
        return NSLocalizedString("pomodoro.deepFocusGuide", comment: "Deep focus mode setup guide")
    }
}

// MARK: - Statistics

extension DeepFocusService {

    /// 深度专注统计
    struct FocusStatistics {
        var totalSessions: Int
        var totalFocusTime: TimeInterval
        var notificationsBlocked: Int
    }

    /// 获取深度专注统计数据
    func getStatistics() -> FocusStatistics {
        return FocusStatistics(
            totalSessions: UserDefaults.standard.integer(forKey: userKeyPrefix + "deepFocusSessions"),
            totalFocusTime: UserDefaults.standard.double(forKey: userKeyPrefix + "deepFocusTotalTime"),
            notificationsBlocked: UserDefaults.standard.integer(forKey: userKeyPrefix + "deepFocusBlockedNotifications")
        )
    }

    /// 记录一次深度专注会话
    func recordSession(duration: TimeInterval) {
        var stats = getStatistics()
        stats.totalSessions += 1
        stats.totalFocusTime += duration
        stats.notificationsBlocked += blockedNotificationsCount

        UserDefaults.standard.set(stats.totalSessions, forKey: userKeyPrefix + "deepFocusSessions")
        UserDefaults.standard.set(stats.totalFocusTime, forKey: userKeyPrefix + "deepFocusTotalTime")
        UserDefaults.standard.set(stats.notificationsBlocked, forKey: userKeyPrefix + "deepFocusBlockedNotifications")

        debugPrint("📊 Recorded deep focus session: \(duration)s")
    }
}
