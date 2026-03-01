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

/// Protected features that can require parent authentication
enum ProtectedFeature: String, CaseIterable, Codable, Hashable {
    case chatFunction = "chat"
    case homeworkGrader = "grader"
    case parentReports = "reports"

    var displayName: String {
        switch self {
        case .chatFunction: return "Chat Function"
        case .homeworkGrader: return "Homework Grader"
        case .parentReports: return "Parent Report"
        }
    }

    var icon: String {
        switch self {
        case .chatFunction: return "message.fill"
        case .homeworkGrader: return "camera.fill"
        case .parentReports: return "figure.2.and.child.holdinghands"
        }
    }

    var description: String {
        switch self {
        case .chatFunction: return "AI chat conversations"
        case .homeworkGrader: return "Scan and grade homework"
        case .parentReports: return "View progress reports"
        }
    }
}

/// Manages parent mode authentication and password storage
class ParentModeManager: ObservableObject {
    static let shared = ParentModeManager()

    @Published var isParentModeEnabled: Bool = false
    @Published var isParentAuthenticated: Bool = false
    @Published var protectedFeatures: Set<ProtectedFeature> = []

    private let logger = Logger(subsystem: "com.studyai", category: "ParentModeManager")
    private let biometricAuth = BiometricAuthService.shared
    private let keychainService = KeychainService.shared

    // Per-user identifiers
    private var uid: String { AuthenticationService.shared.currentUser?.id ?? "anonymous" }

    // Keychain key for parent password (sensitive — never stored in UserDefaults)
    private var parentPasswordKeychainKey: String { "parent_password_\(uid)" }

    // UserDefaults keys — per-user scoped so settings don't leak across accounts
    private var parentModeEnabledKey: String { "parent_mode_enabled_\(uid)" }
    private var protectedFeaturesKey: String { "parent_protected_features_\(uid)" }
    private var parentFaceIDEnabledKey: String { "parent_faceid_enabled_\(uid)" }

    private init() {
        loadParentModeStatus()
        loadProtectedFeatures()
    }

    // MARK: - Parent Mode Status

    func loadParentModeStatus() {
        isParentModeEnabled = UserDefaults.standard.bool(forKey: parentModeEnabledKey)
        logger.info("📱 Parent mode status loaded: \(self.isParentModeEnabled ? "enabled" : "disabled")")
    }

    func isParentPasswordSet() -> Bool {
        return (try? keychainService.load(for: parentPasswordKeychainKey)) != nil
    }

    // MARK: - Password Management

    /// Set or update parent password (must be 6 digits)
    func setParentPassword(_ password: String) -> Bool {
        guard password.count == 6, password.allSatisfy({ $0.isNumber }) else {
            logger.warning("⚠️ Invalid parent password format (must be 6 digits)")
            return false
        }

        // Store password securely in Keychain
        guard let data = password.data(using: .utf8) else {
            logger.error("❌ Failed to encode parent password")
            return false
        }
        do {
            try keychainService.save(data, for: parentPasswordKeychainKey)
        } catch {
            logger.error("❌ Failed to save parent password to Keychain: \(error.localizedDescription)")
            return false
        }
        UserDefaults.standard.set(true, forKey: parentModeEnabledKey)

        isParentModeEnabled = true
        logger.info("✅ Parent password set successfully")
        return true
    }

    /// Verify parent password
    func verifyParentPassword(_ password: String) -> Bool {
        guard let data = try? keychainService.load(for: parentPasswordKeychainKey),
              let storedPassword = String(data: data, encoding: .utf8) else {
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

        // Update password in Keychain
        guard let data = newPassword.data(using: .utf8) else {
            return (false, "Failed to encode new password")
        }
        do {
            try keychainService.save(data, for: parentPasswordKeychainKey)
        } catch {
            return (false, "Failed to save new password")
        }
        logger.info("✅ Parent password changed successfully")
        return (true, nil)
    }

    /// Remove parent password (requires verification)
    func removeParentPassword(password: String) -> Bool {
        guard verifyParentPassword(password) else {
            logger.warning("❌ Cannot remove password: verification failed")
            return false
        }

        try? keychainService.delete(for: parentPasswordKeychainKey)
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

    // MARK: - Feature Protection Management

    /// Load protected features from storage
    func loadProtectedFeatures() {
        if let data = UserDefaults.standard.data(forKey: protectedFeaturesKey),
           let features = try? JSONDecoder().decode(Set<ProtectedFeature>.self, from: data) {
            protectedFeatures = features
            logger.info("📱 Loaded \(features.count) protected features")
        } else {
            protectedFeatures = []
            logger.info("📱 No protected features configured")
        }
    }

    /// Save protected features to storage
    private func saveProtectedFeatures() {
        if let data = try? JSONEncoder().encode(protectedFeatures) {
            UserDefaults.standard.set(data, forKey: protectedFeaturesKey)
            logger.info("💾 Saved \(self.protectedFeatures.count) protected features")
        }
    }

    /// Check if a specific feature is protected
    func isFeatureProtected(_ feature: ProtectedFeature) -> Bool {
        return protectedFeatures.contains(feature)
    }

    /// Set protection status for a specific feature
    func setFeatureProtection(_ feature: ProtectedFeature, protected: Bool) {
        if protected {
            protectedFeatures.insert(feature)
            logger.info("🔒 Protected feature: \(feature.displayName)")
        } else {
            protectedFeatures.remove(feature)
            logger.info("🔓 Unprotected feature: \(feature.displayName)")
        }
        saveProtectedFeatures()
    }

    /// Check if authentication is required for a specific feature
    func requiresAuthentication(for feature: ProtectedFeature) -> Bool {
        // If parent mode is not enabled, no authentication needed
        guard isParentModeEnabled else {
            return false
        }

        // If feature is not protected, no authentication needed
        guard isFeatureProtected(feature) else {
            return false
        }

        // If already authenticated, no need to authenticate again
        return !isParentAuthenticated
    }

    // MARK: - Parent Face ID Management

    /// Check if Face ID is enabled for parent mode
    func isParentFaceIDEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: parentFaceIDEnabledKey)
    }

    /// Enable Face ID for parent mode authentication
    func enableParentFaceID() async throws {
        guard biometricAuth.isBiometricAvailable() else {
            throw AuthError.biometricNotAvailable
        }

        guard biometricAuth.isBiometricEnrolled() else {
            throw AuthError.biometricNotEnrolled
        }

        guard isParentModeEnabled else {
            throw AuthError.providerError("Please set up parent password first")
        }

        // Verify the parent password exists
        guard isParentPasswordSet() else {
            throw AuthError.providerError("No parent password set")
        }

        // Test biometric authentication
        let success = try await biometricAuth.authenticateWithBiometrics(
            reason: "Enable \(getBiometricType()) for Parent Mode"
        )

        if success {
            await MainActor.run {
                UserDefaults.standard.set(true, forKey: parentFaceIDEnabledKey)
            }
            logger.info("✅ Parent Face ID enabled")
        } else {
            throw AuthError.biometricFailed
        }
    }

    /// Disable Face ID for parent mode
    func disableParentFaceID() {
        UserDefaults.standard.set(false, forKey: parentFaceIDEnabledKey)
        logger.info("🔐 Parent Face ID disabled")
    }

    /// Verify parent authentication using biometrics
    func verifyWithBiometrics() async throws -> Bool {
        guard biometricAuth.isBiometricAvailable() else {
            throw AuthError.biometricNotAvailable
        }

        guard biometricAuth.isBiometricEnrolled() else {
            throw AuthError.biometricNotEnrolled
        }

        guard isParentFaceIDEnabled() else {
            throw AuthError.providerError("Face ID not enabled for parent mode")
        }

        let success = try await biometricAuth.authenticateWithBiometrics(
            reason: "Verify parent identity"
        )

        if success {
            await MainActor.run {
                isParentAuthenticated = true
            }
            logger.info("✅ Parent authenticated with biometrics")
        }

        return success
    }

    /// Get biometric type string
    func getBiometricType() -> String {
        return biometricAuth.getBiometricType()
    }

    /// Check if biometrics can be used for parent authentication
    func canUseParentBiometrics() -> Bool {
        return biometricAuth.isBiometricAvailable() &&
               biometricAuth.isBiometricEnrolled() &&
               isParentModeEnabled &&
               isParentFaceIDEnabled()
    }
}