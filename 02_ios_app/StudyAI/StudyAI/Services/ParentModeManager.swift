//
//  ParentModeManager.swift
//  StudyAI
//
//  Parent Mode & Password Management Service
//

import Foundation
import SwiftUI
import Combine
import os.log

/// Manages parent mode authentication and password storage
class ParentModeManager: ObservableObject {
    static let shared = ParentModeManager()

    @Published var isParentModeEnabled: Bool = false
    @Published var isParentAuthenticated: Bool = false

    private let logger = Logger(subsystem: "com.studyai", category: "ParentModeManager")

    // UserDefaults keys
    private let parentPasswordKey = "parent_password"
    private let parentModeEnabledKey = "parent_mode_enabled"

    private init() {
        loadParentModeStatus()
    }

    // MARK: - Parent Mode Status

    func loadParentModeStatus() {
        isParentModeEnabled = UserDefaults.standard.bool(forKey: parentModeEnabledKey)
        logger.info("📱 Parent mode status loaded: \(self.isParentModeEnabled ? "enabled" : "disabled")")
    }

    func isParentPasswordSet() -> Bool {
        return UserDefaults.standard.string(forKey: parentPasswordKey) != nil
    }

    // MARK: - Password Management

    /// Set or update parent password (must be 6 digits)
    func setParentPassword(_ password: String) -> Bool {
        guard password.count == 6, password.allSatisfy({ $0.isNumber }) else {
            logger.warning("⚠️ Invalid parent password format (must be 6 digits)")
            return false
        }

        // Store password (in production, should use Keychain for security)
        UserDefaults.standard.set(password, forKey: parentPasswordKey)
        UserDefaults.standard.set(true, forKey: parentModeEnabledKey)

        isParentModeEnabled = true
        logger.info("✅ Parent password set successfully")
        return true
    }

    /// Verify parent password
    func verifyParentPassword(_ password: String) -> Bool {
        guard let storedPassword = UserDefaults.standard.string(forKey: parentPasswordKey) else {
            logger.warning("⚠️ No parent password set")
            return false
        }

        let isValid = password == storedPassword
        if isValid {
            isParentAuthenticated = true
            logger.info("✅ Parent authentication successful")
        } else {
            logger.warning("❌ Parent authentication failed")
        }
        return isValid
    }

    /// Change existing parent password (requires current password)
    func changeParentPassword(currentPassword: String, newPassword: String) -> (success: Bool, error: String?) {
        // Verify current password
        guard verifyParentPassword(currentPassword) else {
            return (false, "Current password is incorrect")
        }

        // Validate new password
        guard newPassword.count == 6, newPassword.allSatisfy({ $0.isNumber }) else {
            return (false, "New password must be 6 digits")
        }

        // Update password
        UserDefaults.standard.set(newPassword, forKey: parentPasswordKey)
        logger.info("✅ Parent password changed successfully")
        return (true, nil)
    }

    /// Remove parent password (requires verification)
    func removeParentPassword(password: String) -> Bool {
        guard verifyParentPassword(password) else {
            logger.warning("❌ Cannot remove password: verification failed")
            return false
        }

        UserDefaults.standard.removeObject(forKey: parentPasswordKey)
        UserDefaults.standard.set(false, forKey: parentModeEnabledKey)

        isParentModeEnabled = false
        isParentAuthenticated = false

        logger.info("✅ Parent password removed")
        return true
    }

    // MARK: - Authentication Session

    /// Sign out from parent mode (require authentication again)
    func signOutParentMode() {
        isParentAuthenticated = false
        logger.info("🔒 Parent mode signed out")
    }

    /// Check if parent authentication is required for a feature
    func requiresParentAuthentication() -> Bool {
        return isParentModeEnabled && !isParentAuthenticated
    }
}