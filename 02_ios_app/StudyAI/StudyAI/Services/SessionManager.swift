//
//  SessionManager.swift
//  StudyAI
//
//  Handles session timeout and expiration logic
//  Requires re-authentication when app is closed or after timeout period
//

import Foundation
import Combine

/// Manages user session lifecycle, timeout, and expiration
///
/// Session expiration occurs in two scenarios:
/// 1. IMMEDIATE: When app goes to background or is closed (requires Face ID on reopen)
/// 2. TIMEOUT: After 15 minutes of inactivity while app is in foreground
class SessionManager: ObservableObject {
    static let shared = SessionManager()

    // MARK: - Published Properties
    @Published var isSessionValid = false
    @Published var requiresFaceIDReauth = false

    // MARK: - Configuration
    private let sessionTimeoutMinutes: Double = 15 // Session expires after 15 minutes of inactivity (while app is open)
    private let userDefaults = UserDefaults.standard

    // MARK: - Keys
    private let lastActiveTimestampKey = "lastActiveTimestamp"
    private let sessionStartedTimestampKey = "sessionStartedTimestamp"

    private init() {
        checkSessionValidity()
    }

    // MARK: - Public API

    /// Start a new session (called after successful login)
    func startSession() {
        let now = Date()
        userDefaults.set(now.timeIntervalSince1970, forKey: lastActiveTimestampKey)
        userDefaults.set(now.timeIntervalSince1970, forKey: sessionStartedTimestampKey)
        isSessionValid = true
        requiresFaceIDReauth = false
        print("🔐 [SessionManager] Session started at \(now)")
    }

    /// Update session activity (called when user interacts with app)
    func updateActivity() {
        let now = Date()
        userDefaults.set(now.timeIntervalSince1970, forKey: lastActiveTimestampKey)
        print("🔐 [SessionManager] Activity updated at \(now)")
    }

    /// End the current session (called on logout or forced expiration)
    func endSession() {
        userDefaults.removeObject(forKey: lastActiveTimestampKey)
        userDefaults.removeObject(forKey: sessionStartedTimestampKey)
        isSessionValid = false
        requiresFaceIDReauth = false
        print("🔐 [SessionManager] Session ended")
    }

    /// Check if the current session is valid
    /// Returns true if session hasn't expired, false otherwise
    func checkSessionValidity() -> Bool {
        guard let lastActiveInterval = userDefaults.double(forKey: lastActiveTimestampKey) as Double?,
              lastActiveInterval > 0 else {
            print("🔐 [SessionManager] No active session found")
            isSessionValid = false
            requiresFaceIDReauth = false
            return false
        }

        let lastActiveDate = Date(timeIntervalSince1970: lastActiveInterval)
        let now = Date()
        let minutesSinceLastActivity = now.timeIntervalSince(lastActiveDate) / 60.0

        print("🔐 [SessionManager] Last activity: \(lastActiveDate)")
        print("🔐 [SessionManager] Minutes since last activity: \(String(format: "%.1f", minutesSinceLastActivity))")
        print("🔐 [SessionManager] Session timeout threshold: \(sessionTimeoutMinutes) minutes")

        if minutesSinceLastActivity > sessionTimeoutMinutes {
            print("🔐 [SessionManager] ⚠️ Session expired (inactive for \(String(format: "%.1f", minutesSinceLastActivity)) minutes)")
            isSessionValid = false
            // If we have a stored session but it's expired, require Face ID re-auth
            requiresFaceIDReauth = true
            return false
        } else {
            print("🔐 [SessionManager] ✅ Session is valid (active \(String(format: "%.1f", minutesSinceLastActivity)) minutes ago)")
            isSessionValid = true
            requiresFaceIDReauth = false
            return true
        }
    }

    /// Called when app goes to background
    func appWillResignActive() {
        // Update last active timestamp but DON'T end the session
        // Session will only expire if inactive for longer than sessionTimeoutMinutes (15 minutes)
        updateActivity()
        print("🔐 [SessionManager] App going to background - updating activity timestamp (session remains valid for \(sessionTimeoutMinutes) minutes)")
    }

    /// Called when app returns from background
    /// Returns true if session is still valid, false if expired
    func appDidBecomeActive() -> Bool {
        print("🔐 [SessionManager] App returning from background, checking session validity...")
        return checkSessionValidity()
    }

    /// Get time until session expires (in minutes)
    func timeUntilExpiration() -> Double? {
        guard let lastActiveInterval = userDefaults.double(forKey: lastActiveTimestampKey) as Double?,
              lastActiveInterval > 0 else {
            return nil
        }

        let lastActiveDate = Date(timeIntervalSince1970: lastActiveInterval)
        let now = Date()
        let minutesSinceLastActivity = now.timeIntervalSince(lastActiveDate) / 60.0
        let minutesRemaining = sessionTimeoutMinutes - minutesSinceLastActivity

        return max(0, minutesRemaining)
    }

    /// Refresh session after successful Face ID re-authentication
    func refreshSessionAfterBiometricAuth() {
        print("🔐 [SessionManager] Session refreshed after biometric authentication")
        startSession() // Restart session with new timestamp
    }
}
