//
//  FocusSessionService.swift
//  StudyAI
//
//  Service for managing focus sessions with timer functionality
//

import Foundation
import Combine
import UIKit

class FocusSessionService: ObservableObject {
    static let shared = FocusSessionService()

    // MARK: - Published Properties
    @Published var currentSession: FocusSession?
    @Published var elapsedTime: TimeInterval = 0
    @Published var remainingTime: TimeInterval = 25 * 60  // 番茄钟：25分钟
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var isCompleted = false  // 标记是否已完成25分钟
    @Published var isDeepFocusEnabled = false  // 深度专注模式状态

    // MARK: - Constants
    let pomodoroDuration: TimeInterval = 25 * 60  // 25分钟倒计时

    // MARK: - Services
    private let deepFocusService = DeepFocusService.shared

    // MARK: - Private Properties
    private var timer: AnyCancellable?
    private var sessionStartTime: Date?
    private var backgroundStartTime: Date?
    private var previousPowerSavingMode: Bool = false

    private init() {
        setupLifecycleObservers()
    }

    // MARK: - Lifecycle Observers

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func appWillResignActive() {
        // Track when app goes to background
        if isRunning && !isPaused {
            backgroundStartTime = Date()
            debugPrint("📱 App entering background - timer at \(formatTime(elapsedTime))")

            // BATTERY OPTIMIZATION: Stop timer to save battery
            // Time will be recalculated based on actual elapsed time when returning
            stopTimer()
        }
    }

    @objc private func appDidBecomeActive() {
        // Update elapsed time based on actual time passed
        if isRunning && !isPaused, let _ = backgroundStartTime, let startTime = sessionStartTime {
            // Calculate total elapsed time from session start
            let totalElapsed = Date().timeIntervalSince(startTime)
            elapsedTime = totalElapsed

            // 更新剩余时间（倒计时）
            remainingTime = max(0, pomodoroDuration - elapsedTime)

            // 检查是否已完成25分钟
            if remainingTime <= 0 && !isCompleted {
                isCompleted = true
                // 可以触发完成提示音或振动
                debugPrint("✅ Pomodoro completed!")
            }

            // Update current session duration
            if var session = currentSession {
                session.duration = elapsedTime
                currentSession = session
            }

            // BATTERY OPTIMIZATION: Restart timer if session is still active
            if remainingTime > 0 && !isCompleted {
                startTimer()
            }

            backgroundStartTime = nil
            debugPrint("📱 App returned to foreground - remaining: \(formatTime(remainingTime))")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Session Control

    /// Start a new focus session
    func startSession(withMusic trackId: String? = nil, enableDeepFocus: Bool = false) {
        guard currentSession == nil else {
            debugPrint("⚠️ Session already in progress")
            return
        }

        // Save current Power Saving Mode state and enable it for focus
        previousPowerSavingMode = AppState.shared.isPowerSavingMode
        if !previousPowerSavingMode {
            AppState.shared.isPowerSavingMode = true
            debugPrint("🔋 Enabled Power Saving Mode for focus session")
        }

        // 启用深度专注模式（如果用户选择）
        if enableDeepFocus || deepFocusService.autoEnableDeepFocus {
            deepFocusService.enableDeepFocus()
            isDeepFocusEnabled = true
            debugPrint("🔇 Deep Focus Mode enabled")
        }

        let session = FocusSession(
            startTime: Date(),
            backgroundMusicTrack: trackId,
            isCompleted: false
        )

        currentSession = session
        sessionStartTime = Date()
        elapsedTime = 0
        remainingTime = pomodoroDuration  // 重置为25分钟
        isRunning = true
        isPaused = false
        isCompleted = false  // 重置完成状态

        startTimer()

        debugPrint("✅ Pomodoro session started: 25:00")
    }

    // MARK: - Deep Focus Control

    /// 切换深度专注模式
    func toggleDeepFocus() {
        if isDeepFocusEnabled {
            deepFocusService.disableDeepFocus()
            isDeepFocusEnabled = false
        } else {
            deepFocusService.enableDeepFocus()
            isDeepFocusEnabled = true
        }
    }

    /// Pause the current session
    func pauseSession() {
        guard isRunning, !isPaused else { return }

        stopTimer()
        isPaused = true
        // Keep isRunning true to maintain session state
        // isRunning = false  // REMOVED: This was causing the UI issue

        debugPrint("⏸️ Session paused at \(formatTime(elapsedTime))")
    }

    /// Resume the paused session
    func resumeSession() {
        guard isPaused else { return }

        isPaused = false
        // isRunning should already be true from pause
        startTimer()

        debugPrint("▶️ Session resumed")
    }

    /// End the current session and save it
    func endSession() -> FocusSession? {
        guard var session = currentSession else {
            debugPrint("⚠️ No active session to end")
            return nil
        }

        stopTimer()

        // Update session details
        session.endTime = Date()
        session.duration = elapsedTime
        session.isCompleted = true
        session.earnedTreeType = TreeType.from(seconds: elapsedTime)

        // Save session
        saveSession(session)

        // Award points based on focus time
        awardFocusPoints(for: session)

        // 记录深度专注统计
        if isDeepFocusEnabled {
            deepFocusService.recordSession(duration: elapsedTime)
        }

        // 禁用深度专注模式
        if isDeepFocusEnabled {
            deepFocusService.disableDeepFocus()
            isDeepFocusEnabled = false
        }

        debugPrint("✅ Session ended: \(session.formattedDuration)")

        // Restore previous Power Saving Mode state
        if !previousPowerSavingMode && AppState.shared.isPowerSavingMode {
            AppState.shared.isPowerSavingMode = false
            debugPrint("🔋 Restored Power Saving Mode to: off")
        }

        // Reset state
        let completedSession = session
        reset()

        return completedSession
    }

    /// Cancel the current session without saving
    func cancelSession() {
        stopTimer()

        // 禁用深度专注模式
        if isDeepFocusEnabled {
            deepFocusService.disableDeepFocus()
            isDeepFocusEnabled = false
        }

        // Restore previous Power Saving Mode state
        if !previousPowerSavingMode && AppState.shared.isPowerSavingMode {
            AppState.shared.isPowerSavingMode = false
            debugPrint("🔋 Restored Power Saving Mode to: off")
        }

        reset()
        debugPrint("❌ Session cancelled")
    }

    // MARK: - Timer Management

    private func startTimer() {
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.elapsedTime += 1
                self.remainingTime = max(0, self.pomodoroDuration - self.elapsedTime)

                // 检查是否完成25分钟倒计时
                if self.remainingTime <= 0 && !self.isCompleted {
                    self.isCompleted = true
                    self.handlePomodoroCompletion()
                }

                // Update current session duration
                if var session = self.currentSession {
                    session.duration = self.elapsedTime
                    self.currentSession = session
                }
            }
    }

    /// 处理番茄钟完成
    private func handlePomodoroCompletion() {
        debugPrint("🍅 Pomodoro completed! 25 minutes focused.")
        // 触发震动反馈
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // 这里可以触发声音提示或其他反馈
        // AudioServicesPlaySystemSound(SystemSoundID(1016))  // 可选
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Session Persistence

    private func saveSession(_ session: FocusSession) {
        var sessions = loadAllSessions()
        sessions.append(session)

        if let encoded = try? JSONEncoder().encode(sessions) {
            let userId = AuthenticationService.shared.currentUser?.id ?? "anonymous"
            UserDefaults.standard.set(encoded, forKey: "focus_sessions_\(userId)")
            debugPrint("💾 Session saved to UserDefaults")
        }
    }

    func loadAllSessions() -> [FocusSession] {
        let userId = AuthenticationService.shared.currentUser?.id ?? "anonymous"
        guard let data = UserDefaults.standard.data(forKey: "focus_sessions_\(userId)"),
              let sessions = try? JSONDecoder().decode([FocusSession].self, from: data) else {
            return []
        }
        return sessions
    }

    func getTodaySessions() -> [FocusSession] {
        let sessions = loadAllSessions()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return sessions.filter { session in
            calendar.isDate(session.startTime, inSameDayAs: today)
        }
    }

    func getWeeklySessions() -> [FocusSession] {
        let sessions = loadAllSessions()
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        return sessions.filter { session in
            session.startTime >= weekAgo
        }
    }

    // MARK: - Points Integration

    private func awardFocusPoints(for session: FocusSession) {
        let pointsManager = PointsEarningManager.shared

        // Award 1 point per 5 minutes of focus
        let pointsToAward = Int(session.durationInMinutes / 5)

        if pointsToAward > 0 {
            pointsManager.trackFocusSession(
                durationMinutes: session.durationInMinutes,
                pointsEarned: pointsToAward
            )
            debugPrint("🎯 Awarded \(pointsToAward) points for \(session.durationInMinutes) min focus")
        }
    }

    // MARK: - Helper Methods

    private func reset() {
        currentSession = nil
        sessionStartTime = nil
        backgroundStartTime = nil
        elapsedTime = 0
        remainingTime = pomodoroDuration
        isRunning = false
        isPaused = false
        isCompleted = false
    }

    func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    // MARK: - Statistics

    func getTotalFocusTime() -> TimeInterval {
        return loadAllSessions().reduce(0) { $0 + $1.duration }
    }

    func getLongestSession() -> FocusSession? {
        return loadAllSessions().max(by: { $0.duration < $1.duration })
    }

    func getSessionCount() -> Int {
        return loadAllSessions().count
    }
}
