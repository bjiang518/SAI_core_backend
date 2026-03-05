//
//  AppSessionManager.swift
//  StudyAI
//
//  Created by Claude Code on 1/30/25.
//

import Foundation
import Combine

/// Manages app session state to determine whether to show loading animation
/// - Shows animation on first launch (new session)
/// - Skips animation for continuous sessions (quick return to foreground)
class AppSessionManager: ObservableObject {
    static let shared = AppSessionManager()

    @Published var shouldShowLoadingAnimation = false

    private let sessionTimeoutKey = "lastAppBackgroundTime"
    private let sessionTimeout: TimeInterval = 30 * 60  // 30 minutes

    private init() {
        // Check if this is a new session on init
        checkSessionStatus()
    }

    /// Check if this is a new session or continuous session
    func checkSessionStatus() {
        let lastBackgroundTime = UserDefaults.standard.double(forKey: sessionTimeoutKey)

        if lastBackgroundTime == 0 {
            shouldShowLoadingAnimation = true
            return
        }

        let timeSinceBackground = Date().timeIntervalSince1970 - lastBackgroundTime

        if timeSinceBackground > sessionTimeout {
            shouldShowLoadingAnimation = true
        } else {
            shouldShowLoadingAnimation = false
        }
    }

    /// Mark app as entering background
    func appDidEnterBackground() {
        let currentTime = Date().timeIntervalSince1970
        UserDefaults.standard.set(currentTime, forKey: sessionTimeoutKey)
    }

    /// Mark app as becoming active
    func appDidBecomeActive() {
        // Session status is checked on init, no need to update here
    }

    /// Reset session (for testing)
    func resetSession() {
        UserDefaults.standard.removeObject(forKey: sessionTimeoutKey)
        shouldShowLoadingAnimation = true
    }
}
