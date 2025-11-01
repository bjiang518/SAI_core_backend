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
    @Published var isRunning = false
    @Published var isPaused = false

    // MARK: - Private Properties
    private var timer: AnyCancellable?
    private var sessionStartTime: Date?
    private var backgroundStartTime: Date?

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
            print("📱 App entering background - timer at \(formatTime(elapsedTime))")
        }
    }

    @objc private func appDidBecomeActive() {
        // Update elapsed time based on actual time passed
        if isRunning && !isPaused, let bgStartTime = backgroundStartTime, let startTime = sessionStartTime {
            // Calculate total elapsed time from session start
            let totalElapsed = Date().timeIntervalSince(startTime)
            elapsedTime = totalElapsed

            // Update current session duration
            if var session = currentSession {
                session.duration = elapsedTime
                currentSession = session
            }

            backgroundStartTime = nil
            print("📱 App returned to foreground - timer updated to \(formatTime(elapsedTime))")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Session Control

    /// Start a new focus session
    func startSession(withMusic trackId: String? = nil) {
        guard currentSession == nil else {
            print("⚠️ Session already in progress")
            return
        }

        let session = FocusSession(
            startTime: Date(),
            backgroundMusicTrack: trackId,
            isCompleted: false
        )

        currentSession = session
        sessionStartTime = Date()
        elapsedTime = 0
        isRunning = true
        isPaused = false

        startTimer()

        print("✅ Focus session started: \(session.id)")
    }

    /// Pause the current session
    func pauseSession() {
        guard isRunning, !isPaused else { return }

        stopTimer()
        isPaused = true
        // Keep isRunning true to maintain session state
        // isRunning = false  // REMOVED: This was causing the UI issue

        print("⏸️ Session paused at \(formatTime(elapsedTime))")
    }

    /// Resume the paused session
    func resumeSession() {
        guard isPaused else { return }

        isPaused = false
        // isRunning should already be true from pause
        startTimer()

        print("▶️ Session resumed")
    }

    /// End the current session and save it
    func endSession() -> FocusSession? {
        guard var session = currentSession else {
            print("⚠️ No active session to end")
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

        print("✅ Session ended: \(session.formattedDuration)")

        // Reset state
        let completedSession = session
        reset()

        return completedSession
    }

    /// Cancel the current session without saving
    func cancelSession() {
        stopTimer()
        reset()
        print("❌ Session cancelled")
    }

    // MARK: - Timer Management

    private func startTimer() {
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.elapsedTime += 1

                // Update current session duration
                if var session = self.currentSession {
                    session.duration = self.elapsedTime
                    self.currentSession = session
                }
            }
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
            UserDefaults.standard.set(encoded, forKey: "focus_sessions")
            print("💾 Session saved to UserDefaults")
        }
    }

    func loadAllSessions() -> [FocusSession] {
        guard let data = UserDefaults.standard.data(forKey: "focus_sessions"),
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
            print("🎯 Awarded \(pointsToAward) points for \(session.durationInMinutes) min focus")
        }
    }

    // MARK: - Helper Methods

    private func reset() {
        currentSession = nil
        sessionStartTime = nil
        backgroundStartTime = nil
        elapsedTime = 0
        isRunning = false
        isPaused = false
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
