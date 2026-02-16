//
//  AuthenticationService.swift
//  StudyAI
//
//  Created by Claude Code on 9/5/25.
//

import Foundation
import SwiftUI
import AuthenticationServices
import LocalAuthentication
import Security
import Combine
import UIKit
import GoogleSignIn
import os.log

// MARK: - Production Logging Safety
// Disable debug print statements in production builds to prevent auth token/password exposure
#if !DEBUG
private func print(_ items: Any...) { }
private func debugPrint(_ items: Any...) { }
#endif

// MARK: - Authentication Models

struct User: Codable {
    let id: String
    let email: String
    let name: String
    let profileImageURL: String?
    let authProvider: AuthProvider
    let createdAt: Date
    let lastLoginAt: Date
}

enum AuthProvider: String, Codable {
    case email = "email"
    case google = "google"
    case apple = "apple"
    case phone = "phone"
}

enum AuthError: LocalizedError {
    case userCancelled
    case biometricNotAvailable
    case biometricNotEnrolled
    case biometricFailed
    case keychainError
    case networkError(String)
    case invalidCredentials
    case providerError(String)
    
    // MARK: - Enhanced Specific Error Cases
    case accountNotFound
    case incorrectPassword
    case invalidEmailFormat
    case accountAlreadyExists
    case serverError(String)
    case weakPassword
    case tooManyAttempts
    case accountDisabled
    
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Authentication was cancelled"
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device"
        case .biometricNotEnrolled:
            return "No biometric credentials are enrolled. Please set up Face ID or Touch ID in Settings"
        case .biometricFailed:
            return "Biometric authentication failed"
        case .keychainError:
            return "Unable to access secure storage"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidCredentials:
            return "Invalid email or password"
        case .providerError(let message):
            return message
            
        // MARK: - Enhanced Error Messages
        case .accountNotFound:
            return "No account found with this email address. Please check your email or create a new account."
        case .incorrectPassword:
            return "The password you entered is incorrect. Please try again."
        case .invalidEmailFormat:
            return "Please enter a valid email address."
        case .accountAlreadyExists:
            return "An account with this email already exists. Please sign in instead."
        case .serverError(let message):
            return "Server error: \(message). Please try again later."
        case .weakPassword:
            return "Password must be at least 6 characters long and contain letters and numbers."
        case .tooManyAttempts:
            return "Too many failed attempts. Please try again in a few minutes."
        case .accountDisabled:
            return "This account has been disabled. Please contact support."
        }
    }
}

// MARK: - Authentication Service

final class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastRegisteredEmail: String? // For pre-filling login after registration
    @Published var requiresFaceIDReauth = false // Session expired, needs Face ID re-auth

    private let keychainService = KeychainService.shared
    private let biometricAuth = BiometricAuthService.shared
    private let networkService = NetworkService.shared
    private let sessionManager = SessionManager.shared
    private let authLogger = Logger(subsystem: "com.studyai", category: "AuthService")

    // MARK: - Token Refresh (Phase 2.5)
    private var tokenRefreshTimer: Timer?

    private init() {
        let initStartTime = CFAbsoluteTimeGetCurrent()
        authLogger.info("🔐 === AUTHENTICATION SERVICE INIT STARTED ===")
        
        authLogger.info("🔧 Initializing KeychainService...")
        // KeychainService.shared is initialized here
        
        authLogger.info("🔧 Initializing BiometricAuthService...")
        // BiometricAuthService.shared is initialized here
        
        authLogger.info("🔧 Initializing NetworkService...")
        let networkInitStartTime = CFAbsoluteTimeGetCurrent()
        // NetworkService.shared is initialized here - this could be expensive
        _ = networkService // Force initialization
        let networkInitEndTime = CFAbsoluteTimeGetCurrent()
        let networkInitDuration = networkInitEndTime - networkInitStartTime
        authLogger.info("🔧 NetworkService initialized in: \(networkInitDuration * 1000, privacy: .public) ms")
        
        let initEndTime = CFAbsoluteTimeGetCurrent()
        let initDuration = initEndTime - initStartTime
        authLogger.info("🔐 AuthenticationService init completed in: \(initDuration * 1000, privacy: .public) ms")
        authLogger.info("🔐 === AUTHENTICATION SERVICE INIT FINISHED ===")
        
        // Move authentication status check to after initialization to avoid blocking
        authLogger.info("🔍 Scheduling async authentication status check...")
        Task {
            await checkAuthenticationStatusAsync()
        }
    }
    
    // MARK: - Authentication Status
    
    private func checkAuthenticationStatusAsync() async {
        let checkStartTime = CFAbsoluteTimeGetCurrent()
        authLogger.info("🔍 === CHECKING AUTHENTICATION STATUS (ASYNC) ===")

        let keychainStartTime = CFAbsoluteTimeGetCurrent()
        authLogger.info("🔑 Looking for stored user in keychain (background thread)...")

        // Perform keychain access on background thread
        let userData = await Task.detached {
            return await MainActor.run {
                self.keychainService.getUser()
            }
        }.value

        let keychainEndTime = CFAbsoluteTimeGetCurrent()
        let keychainDuration = keychainEndTime - keychainStartTime
        authLogger.info("🔑 Keychain access completed in: \(keychainDuration * 1000, privacy: .public) ms")

        // Update UI on main thread
        await MainActor.run {
            if let userData = userData {
                let userLoadTime = CFAbsoluteTimeGetCurrent()
                let userLoadDuration = userLoadTime - checkStartTime
                authLogger.info("✅ Found stored user: \(userData.email)")
                authLogger.info("🔑 User loaded from keychain in: \(userLoadDuration * 1000, privacy: .public) ms")

                // ✅ NEW: Check session validity
                let isSessionValid = sessionManager.checkSessionValidity()
                authLogger.info("🔐 Session validity check: \(isSessionValid ? "VALID" : "EXPIRED")")

                if isSessionValid {
                    // Session is valid, auto-login
                    authLogger.info("✅ Session is valid, auto-logging in user")
                    currentUser = userData
                    isAuthenticated = true
                    requiresFaceIDReauth = false

                    // Auto-load cached profile or fetch from server
                    authLogger.info("👤 Loading user profile after login...")
                    Task {
                        await loadUserProfileAfterLogin()
                    }
                } else {
                    // Session expired, require Face ID re-authentication
                    authLogger.info("⏰ Session expired, requiring Face ID re-authentication")
                    currentUser = userData  // Keep user data for Face ID context
                    isAuthenticated = false
                    requiresFaceIDReauth = true  // Signal UI to show Face ID prompt
                }
            } else {
                let noUserTime = CFAbsoluteTimeGetCurrent()
                let noUserDuration = noUserTime - checkStartTime
                authLogger.info("❌ No stored user found")
                authLogger.info("🔑 Keychain check completed in: \(noUserDuration * 1000, privacy: .public) ms")

                isAuthenticated = false
                currentUser = nil
                requiresFaceIDReauth = false
            }

            let totalCheckTime = CFAbsoluteTimeGetCurrent() - checkStartTime
            authLogger.info("🔍 Authentication status check completed in: \(totalCheckTime * 1000, privacy: .public) ms")
            authLogger.info("🔍 === AUTHENTICATION STATUS CHECK FINISHED ===")
        }
    }
    
    func checkAuthenticationStatus() {
        // Legacy method - now just calls the async version
        Task {
            await checkAuthenticationStatusAsync()
        }
    }
    
    // MARK: - Email Authentication
    
    func signInWithEmail(_ email: String, password: String) async throws {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        print("🔐 === EMAIL LOGIN DEBUG FLOW ===")
        print("📧 Attempting login for: \(email)")
        
        let result = await networkService.login(email: email, password: password)
        
        if result.success {


            
            // Extract server user ID from backend response
            guard let userData = result.userData,
                  let serverUserId = userData["id"] as? String ?? userData["userId"] as? String ?? userData["user_id"] as? String else {

                if let responseData = result.userData {
                    print("📄 Available keys in userData: \(responseData.keys.sorted())")
                } else {
                    print("📄 userData is nil")
                }
                throw AuthError.serverError("Backend response missing user ID")
            }
            

            print("🖥️ Server User ID Found: \(serverUserId)")
            print("📧 Email: \(userData["email"] as? String ?? email)")
            print("👤 Name: \(userData["name"] as? String ?? "N/A")")
            print("==========================================")
            
            let user = User(
                id: serverUserId,  // Use server UID instead of random UUID
                email: userData["email"] as? String ?? email,
                name: userData["name"] as? String ?? extractNameFromEmail(email),
                profileImageURL: userData["profileImageURL"] as? String ?? userData["profileImageUrl"] as? String ?? userData["profile_image_url"] as? String,
                authProvider: .email,
                createdAt: Date(),
                lastLoginAt: Date()
            )
            
            if let token = result.token {
                try keychainService.saveAuthToken(token)
                try keychainService.saveUser(user)
                
                print("💾 === KEYCHAIN SAVE COMPLETE ===")
                print("🔑 Token saved: \(String(token.prefix(20)))...")
                print("👤 User saved with Server UID: \(user.id)")
                print("================================")
                
                await MainActor.run {
                    currentUser = user
                    isAuthenticated = true


                    print("👤 Current user ID now: \(user.id)")
                    print("===========================")
                }

                // ✅ NEW: Start session after successful login
                sessionManager.startSession()
                authLogger.info("🔐 Session started for user: \(user.email)")

                // ✅ Phase 2.5: Start token monitoring to prevent expiration
                startTokenMonitoring()

                // Auto-load user profile after successful login
                await loadUserProfileAfterLogin()
            }
        } else {

            let specificError = mapBackendError(statusCode: result.statusCode ?? 0, message: result.message)
            throw specificError
        }
    }
    
    func signUpWithEmail(_ name: String, email: String, password: String) async throws {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Use the proper registration endpoint (no auto-login)
        let result = await networkService.register(name: name, email: email, password: password)
        
        if result.success {
            // Registration successful - DO NOT auto-login
            // The user will need to manually log in from the login screen

            
            // Store the registered email for pre-filling the login form
            await MainActor.run {
                lastRegisteredEmail = email
            }
            
            // Don't save tokens or set authentication state
            // Just return successfully - the UI will handle the transition back to login
            
        } else {
            let specificError = mapBackendError(statusCode: result.statusCode ?? 0, message: result.message)
            throw specificError
        }
    }

    // MARK: - Email Verification

    /// Send verification code to user's email
    func sendVerificationCode(email: String, name: String) async throws {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        let result = await networkService.sendVerificationCode(email: email, name: name)

        if !result.success {
            let specificError = mapBackendError(statusCode: result.statusCode ?? 0, message: result.message)
            throw specificError
        }
    }

    /// Verify email code and complete registration
    func verifyEmailCode(email: String, code: String, name: String, password: String) async throws {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        let result = await networkService.verifyEmailCode(
            email: email,
            code: code,
            name: name,
            password: password
        )

        if result.success {
            // Save authentication token
            if let token = result.token {
                try keychainService.saveAuthToken(token)
            }

            // Create user object
            if let userData = result.userData {
                let user = User(
                    id: userData["id"] as? String ?? "",
                    email: userData["email"] as? String ?? email,
                    name: userData["name"] as? String ?? name,
                    profileImageURL: userData["profileImageUrl"] as? String,
                    authProvider: .email,
                    createdAt: Date(),
                    lastLoginAt: Date()
                )

                // Save user data
                try keychainService.saveUser(user)

                await MainActor.run {
                    currentUser = user
                    isAuthenticated = true
                }

                // ✅ NEW: Start session after successful email verification
                sessionManager.startSession()
                authLogger.info("🔐 Session started for user: \(user.email)")

                // ✅ Phase 2.5: Start token monitoring to prevent expiration
                startTokenMonitoring()

                authLogger.info("✅ Email verified and user logged in: \(user.email)")
            }
        } else {
            let specificError = mapBackendError(statusCode: result.statusCode ?? 0, message: result.message)
            throw specificError
        }
    }

    /// Resend verification code
    func resendVerificationCode(email: String) async throws {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        let result = await networkService.resendVerificationCode(email: email)

        if !result.success {
            let specificError = mapBackendError(statusCode: result.statusCode ?? 0, message: result.message)
            throw specificError
        }
    }

    // MARK: - Apple Sign In

    func signInWithApple() async throws {
        print("🍎 === AuthenticationService.signInWithApple() STARTED ===")
        let appleSignIn = AppleSignInService()
        do {
            print("🍎 Step 1: Calling AppleSignInService.signIn()...")
            let appleUser = try await appleSignIn.signIn()

            print("🍎 Step 2: Received Apple user data:")
            print("   - User ID: \(appleUser.userIdentifier)")
            print("   - Email: \(appleUser.email ?? "nil")")
            print("   - Full Name: \(appleUser.fullName ?? "nil")")
            print("   - Identity Token: \(appleUser.identityToken != nil ? "✅ Present (\(appleUser.identityToken!.prefix(20))...)" : "❌ Missing")")
            print("   - Auth Code: \(appleUser.authorizationCode != nil ? "✅ Present (\(appleUser.authorizationCode!.prefix(20))...)" : "❌ Missing")")

            // Send Apple authentication data to our Railway backend
            print("🍎 Step 3: Calling backend at /api/auth/apple...")
            let networkService = NetworkService.shared
            let result = await networkService.appleLogin(
                identityToken: appleUser.identityToken ?? "",
                authorizationCode: appleUser.authorizationCode,
                userIdentifier: appleUser.userIdentifier,
                name: appleUser.fullName ?? "Apple User",
                email: appleUser.email ?? "apple_user@icloud.com"
            )

            print("🍎 Step 4: Backend response:")
            print("   - Success: \(result.success)")
            print("   - Message: \(result.message)")
            print("   - Status Code: \(result.statusCode ?? 0)")
            print("   - Token: \(result.token != nil ? "✅ Present (\(result.token!.prefix(20))...)" : "❌ Missing")")

            if result.success {
                // Extract server user ID from backend response
                guard let userData = result.userData,
                      let serverUserId = userData["id"] as? String ?? userData["userId"] as? String ?? userData["user_id"] as? String else {
                    print("🍎 ❌ ERROR: Backend response missing user ID")
                    print("🍎    Available keys: \(result.userData?.keys.sorted() ?? [])")
                    throw AuthError.serverError("Backend response missing user ID")
                }

                print("🍎 Step 5: Creating user object:")
                print("   - Server User ID: \(serverUserId)")
                print("   - Email: \(userData["email"] as? String ?? appleUser.email ?? "N/A")")
                print("   - Name: \(userData["name"] as? String ?? "N/A")")

                let user = User(
                    id: serverUserId,  // Use server UID instead of Apple UID
                    email: userData["email"] as? String ?? appleUser.email ?? "apple_user@icloud.com",
                    name: userData["name"] as? String ?? appleUser.fullName ?? "Apple User",
                    profileImageURL: userData["profileImageURL"] as? String ?? userData["profileImageUrl"] as? String ?? userData["profile_image_url"] as? String,
                    authProvider: .apple,
                    createdAt: Date(),
                    lastLoginAt: Date()
                )

                // Use the token from our backend instead of generating one locally
                if let token = result.token {
                    print("🍎 Step 6: Saving to keychain:")
                    print("   - Token (first 30 chars): \(token.prefix(30))...")
                    print("   - User ID: \(user.id)")
                    print("   - Email: \(user.email)")

                    try keychainService.saveAuthToken(token)
                    print("   ✅ Token saved to keychain")

                    try keychainService.saveUser(user)
                    print("   ✅ User saved to keychain")

                    // Verify keychain storage
                    if let savedToken = keychainService.getAuthToken() {
                        print("🍎 Step 7: Keychain verification:")
                        print("   ✅ Token retrieved: \(savedToken.prefix(30))...")
                        print("   ✅ Tokens match: \(savedToken == token)")
                    } else {
                        print("🍎 ❌ WARNING: Token not found in keychain after save!")
                    }

                    await MainActor.run {
                        currentUser = user
                        isAuthenticated = true
                        print("🍎 Step 8: Auth state updated on main thread")
                        print("   - isAuthenticated: \(isAuthenticated)")
                        print("   - currentUser.id: \(currentUser?.id ?? "nil")")
                    }

                    // ✅ NEW: Start session after successful Apple Sign-In
                    sessionManager.startSession()
                    authLogger.info("🔐 Session started for user: \(user.email)")

                    // ✅ Phase 2.5: Start token monitoring to prevent expiration
                    startTokenMonitoring()

                    // Auto-load user profile after successful login
                    print("🍎 Step 9: Loading user profile...")
                    await loadUserProfileAfterLogin()

                    print("🍎 === AuthenticationService.signInWithApple() COMPLETED SUCCESSFULLY ===")
                } else {
                    print("🍎 ❌ ERROR: No token in backend response")
                    throw AuthError.serverError("No authentication token received from backend")
                }
            } else {
                print("🍎 ❌ Backend authentication failed")
                let specificError = mapBackendError(statusCode: result.statusCode ?? 0, message: result.message)
                throw specificError
            }
        } catch {
            print("🍎 ❌ === AuthenticationService.signInWithApple() FAILED ===")
            print("🍎 Error: \(error)")

            // Handle specific Apple Sign-In errors with helpful messages
            if let authError = error as? AuthError {
                throw authError
            } else {
                let nsError = error as NSError

                // Handle specific Apple Sign-In errors
                if nsError.domain == "com.apple.AuthenticationServices.AuthorizationError" {
                    switch nsError.code {
                    case 1000: // Authorization error - often provisioning related
                        throw AuthError.providerError("Apple Sign-In is temporarily unavailable. This may be due to app configuration. Please use email authentication.")
                    case 1001: // User cancelled
                        throw AuthError.userCancelled
                    case 1004: // Failed authorization
                        throw AuthError.providerError("Apple Sign-In authorization failed. Please try again or use email authentication.")
                    default:
                        throw AuthError.providerError("Apple Sign-In error: \(error.localizedDescription)")
                    }
                } else {
                    // For any other errors (including provisioning issues), provide helpful message
                    throw AuthError.providerError("Apple Sign-In temporarily unavailable. Please use email authentication or try again later.")
                }
            }
        }
    }
    
    // MARK: - Google Sign In
    
    func signInWithGoogle() async throws {
        let googleSignIn = GoogleSignInService()
        let googleUser = try await googleSignIn.signIn()
        
        // Send Google authentication data to our Railway backend
        let networkService = NetworkService.shared
        let result = await networkService.googleLogin(
            idToken: googleUser.idToken ?? "",
            accessToken: googleUser.accessToken,
            name: googleUser.fullName ?? googleUser.email.components(separatedBy: "@").first?.capitalized ?? "Google User",
            email: googleUser.email,
            profileImageUrl: googleUser.profileImageURL?.absoluteString
        )
        
        if result.success {
            // Extract server user ID from backend response
            guard let userData = result.userData,
                  let serverUserId = userData["id"] as? String ?? userData["userId"] as? String ?? userData["user_id"] as? String else {
                throw AuthError.serverError("Backend response missing user ID")
            }
            

            
            let user = User(
                id: serverUserId,  // Use server UID instead of Google UID
                email: userData["email"] as? String ?? googleUser.email,
                name: userData["name"] as? String ?? googleUser.fullName ?? googleUser.email.components(separatedBy: "@").first?.capitalized ?? "Google User",
                profileImageURL: userData["profileImageURL"] as? String ?? userData["profileImageUrl"] as? String ?? userData["profile_image_url"] as? String ?? googleUser.profileImageURL?.absoluteString,
                authProvider: .google,
                createdAt: Date(),
                lastLoginAt: Date()
            )
            
            // Use the token from our backend instead of generating one locally
            if let token = result.token {
                try keychainService.saveAuthToken(token)
                try keychainService.saveUser(user)
                
                await MainActor.run {
                    currentUser = user
                    isAuthenticated = true
                }

                // ✅ NEW: Start session after successful Google Sign-In
                sessionManager.startSession()
                authLogger.info("🔐 Session started for user: \(user.email)")

                // ✅ Phase 2.5: Start token monitoring to prevent expiration
                startTokenMonitoring()

                // Auto-load user profile after successful login
                await loadUserProfileAfterLogin()
            }
        } else {
            let specificError = mapBackendError(statusCode: result.statusCode ?? 0, message: result.message)
            throw specificError
        }
    }
    
    // MARK: - Biometric Authentication

    private let faceIDEnabledKey = "faceIDEnabled"

    func signInWithBiometrics() async throws {
        guard biometricAuth.isBiometricAvailable() else {
            throw AuthError.biometricNotAvailable
        }

        guard biometricAuth.isBiometricEnrolled() else {
            throw AuthError.biometricNotEnrolled
        }

        // Check if we have stored credentials
        guard keychainService.hasStoredCredentials() else {
            throw AuthError.providerError("No stored credentials found. Please sign in with email first.")
        }

        let success = try await biometricAuth.authenticateWithBiometrics(reason: "Authenticate to access StudyMates")

        if success {
            // Load stored user data
            if let userData = keychainService.getUser() {
                await MainActor.run {
                    currentUser = userData
                    isAuthenticated = true
                }

                // ✅ NEW: Refresh session after successful biometric re-authentication
                sessionManager.refreshSessionAfterBiometricAuth()
                authLogger.info("🔐 Session refreshed after biometric authentication for user: \(userData.email)")

                // Auto-load user profile after successful login
                await loadUserProfileAfterLogin()
            } else {
                throw AuthError.keychainError
            }
        } else {
            throw AuthError.biometricFailed
        }
    }

    // MARK: - Face ID Management

    /// Check if Face ID is enabled for quick login
    func isFaceIDEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: faceIDEnabledKey)
    }

    /// Enable Face ID for future logins
    func enableFaceID() async throws {
        guard biometricAuth.isBiometricAvailable() else {
            throw AuthError.biometricNotAvailable
        }

        guard biometricAuth.isBiometricEnrolled() else {
            throw AuthError.biometricNotEnrolled
        }

        // Verify Face ID works by authenticating
        let success = try await biometricAuth.authenticateWithBiometrics(
            reason: "Enable \(getBiometricType()) for quick sign-in"
        )

        if success {
            // Enable Face ID flag
            await MainActor.run {
                UserDefaults.standard.set(true, forKey: faceIDEnabledKey)
            }

            authLogger.info("✅ Face ID enabled for user")
        } else {
            throw AuthError.biometricFailed
        }
    }

    /// Disable Face ID (credentials stay in keychain for manual login)
    func disableFaceID() {
        UserDefaults.standard.set(false, forKey: faceIDEnabledKey)
        authLogger.info("🔐 Face ID disabled for user")
    }

    /// Check if should prompt for Face ID setup
    func shouldPromptForFaceIDSetup() -> Bool {
        // Only prompt if:
        // 1. Device supports biometrics
        // 2. User hasn't enabled Face ID yet
        // 3. User has stored credentials (just logged in)
        return biometricAuth.isBiometricAvailable() &&
               biometricAuth.isBiometricEnrolled() &&
               !isFaceIDEnabled() &&
               keychainService.hasStoredCredentials()
    }
    
    // MARK: - Sign Out

    func signOut() {
        keychainService.clearAll()

        // ✅ NEW: End session on sign out
        sessionManager.endSession()
        authLogger.info("🔐 Session ended on sign out")

        // ✅ Phase 2.5: Cancel token refresh timer on sign out
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil

        Task { @MainActor in
            currentUser = nil
            isAuthenticated = false
            errorMessage = nil
            requiresFaceIDReauth = false
        }
    }

    // MARK: - Token Refresh (Phase 2.5)

    /// Parse JWT token expiration time
    /// NOTE: Not used for session tokens - backend handles expiration
    private func parseTokenExpiration(_ token: String) -> Date? {
        // Session tokens don't have embedded expiration
        // Backend tracks expiration in user_sessions table
        authLogger.debug("ℹ️ Session tokens don't have embedded expiration - backend handles this")
        return nil
    }

    /// Start monitoring token expiration and schedule proactive refresh
    /// NOTE: Not used for session tokens - backend handles expiration
    func startTokenMonitoring() {
        // Cancel existing timer
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil

        authLogger.debug("ℹ️ Token monitoring disabled - session tokens are managed by backend")
        authLogger.debug("   Backend will return 401 when session expires, triggering re-auth")

        // Session tokens (30-day expiration) are validated by backend
        // Client doesn't need proactive refresh - backend returns 401 on expired tokens
    }

    /// Refresh authentication token before expiration
    /// NOTE: Session tokens are refreshed by backend on 401 response
    private func refreshTokenAsync() async {
        guard let oldToken = getAuthToken() else {
            authLogger.error("❌ Cannot refresh token - no token found")
            return
        }

        authLogger.info("🔄 Attempting token refresh...")

        let result = await networkService.refreshAuthToken(oldToken)

        if result.success, let newToken = result.token {
            authLogger.info("✅ Token refreshed successfully")

            do {
                try keychainService.saveAuthToken(newToken)
                authLogger.info("✅ New token saved to keychain")
            } catch {
                authLogger.error("❌ Failed to save new token to keychain: \(error.localizedDescription)")
                // Token refresh succeeded but save failed - force logout for safety
                await MainActor.run {
                    signOut()
                }
            }
        } else {
            authLogger.error("❌ Token refresh failed: \(result.message)")
            // Refresh failed - logout user
            await MainActor.run {
                errorMessage = "Your session expired. Please sign in again."
                signOut()
            }
        }
    }

    /// Check and refresh token if needed before long operations (PUBLIC API)
    /// Call this before starting operations that may take >60 seconds
    /// @param operationName: Name of operation for logging (optional)
    /// @param minimumRemainingTime: Minimum time before expiry to trigger refresh (default: 5 minutes)
    /// NOTE: Session tokens don't have embedded expiration - backend tracks this
    public func ensureTokenFreshForLongOperation(
        operationName: String = "long operation",
        minimumRemainingTime: TimeInterval = 300 // 5 minutes
    ) async {
        guard let token = getAuthToken() else {
            authLogger.warning("⚠️ No token found for \(operationName)")
            await MainActor.run {
                errorMessage = "Authentication required. Please log in again."
                signOut() // Force logout
            }
            return
        }

        // Validate token exists and has reasonable format
        guard !token.isEmpty && token.count >= 32 else {
            authLogger.error("❌ INVALID TOKEN for \(operationName)")
            authLogger.error("   Token length: \(token.count) characters")
            authLogger.error("   Operation blocked")

            // Clear invalid token and force re-authentication
            await MainActor.run {
                errorMessage = "Your session is invalid. Please log in again."
                signOut()
            }
            return
        }

        authLogger.debug("✅ Token valid - proceeding with \(operationName)")
        // Note: Session tokens don't have client-side expiration checking
        // Backend will return 401 if token is expired, which will trigger re-auth
    }

    /// Validate token format (PUBLIC API)
    /// Returns true if token exists and has reasonable format
    /// NOTE: Session tokens are validated by backend, not client-side
    public func isTokenValid() -> Bool {
        guard let token = getAuthToken() else {
            return false
        }

        // Basic format validation - token should be reasonable length
        guard !token.isEmpty && token.count >= 32 && token.count <= 1024 else {
            authLogger.error("❌ Invalid token length: \(token.count)")
            return false
        }

        authLogger.debug("✅ Token format valid (length: \(token.count))")
        return true
    }

    // MARK: - Helper Methods
    
    private func extractNameFromEmail(_ email: String) -> String {
        let username = email.components(separatedBy: "@").first ?? "User"
        return username.capitalized
    }
    
    /// Fix existing user's UID by fetching server UID using current token
    func fixExistingUserUID() async throws {
        print("🔧 === FIXING EXISTING USER UID ===")
        
        guard getAuthToken() != nil else {

            throw AuthError.keychainError
        }
        

        let debugResult = await networkService.debugAuthTokenMapping()
        
        if debugResult.success, let serverUserId = debugResult.backendUserId {

            print("🖥️ Backend User ID: \(serverUserId)")
            
            // Update existing user with server UID
            if let currentUser = currentUser {
                let updatedUser = User(
                    id: serverUserId,  // Replace with server UID
                    email: currentUser.email,
                    name: currentUser.name,
                    profileImageURL: currentUser.profileImageURL,
                    authProvider: currentUser.authProvider,
                    createdAt: currentUser.createdAt,
                    lastLoginAt: Date()  // Update last login
                )
                
                try keychainService.saveUser(updatedUser)
                
                await MainActor.run {
                    self.currentUser = updatedUser

                }
            }
        } else {

            throw AuthError.networkError(debugResult.message)
        }
    }
    
    func getBiometricType() -> String {
        return biometricAuth.getBiometricType()
    }
    
    func canUseBiometrics() -> Bool {
        return biometricAuth.isBiometricAvailable() && biometricAuth.isBiometricEnrolled() && keychainService.hasStoredCredentials()
    }
    
    func getAuthToken() -> String? {
        return keychainService.getAuthToken()
    }
    
    // MARK: - Profile Auto-Loading
    
    /// Auto-load user profile after successful authentication
    private func loadUserProfileAfterLogin() async {

        
        // Use the ProfileService to load user profile
        await ProfileService.shared.loadProfileAfterLogin()
        

    }
    
    func isAppleSignInAvailable() -> Bool {
        // Check if Apple Sign-In capability is in the entitlements
        // This will gracefully handle provisioning profile issues while maintaining customer-facing functionality
        return Bundle.main.object(forInfoDictionaryKey: "com.apple.developer.applesignin") != nil
    }
    
    // MARK: - Error Mapping
    
    /// Maps Railway backend error messages to specific AuthError cases
    private func mapBackendError(statusCode: Int, message: String) -> AuthError {
        let lowercaseMessage = message.lowercased()
        
        switch statusCode {
        case 400:
            if lowercaseMessage.contains("invalid email") || lowercaseMessage.contains("email format") {
                return .invalidEmailFormat
            } else if lowercaseMessage.contains("password") && lowercaseMessage.contains("weak") {
                return .weakPassword
            } else if lowercaseMessage.contains("already exists") || lowercaseMessage.contains("duplicate") {
                return .accountAlreadyExists
            }
            return .invalidCredentials
            
        case 401:
            if lowercaseMessage.contains("password") && (lowercaseMessage.contains("incorrect") || lowercaseMessage.contains("wrong")) {
                return .incorrectPassword
            } else if lowercaseMessage.contains("not found") || lowercaseMessage.contains("no account") {
                return .accountNotFound
            }
            return .invalidCredentials
            
        case 403:
            if lowercaseMessage.contains("disabled") || lowercaseMessage.contains("suspended") {
                return .accountDisabled
            } else if lowercaseMessage.contains("attempts") || lowercaseMessage.contains("rate limit") {
                return .tooManyAttempts
            }
            return .invalidCredentials
            
        case 404:
            // Check if it's a route not found error (API gateway issue)
            if lowercaseMessage.contains("route") {
                return .networkError("API endpoint not configured. Please contact support or try again later.")
            }
            return .accountNotFound
            
        case 429:
            return .tooManyAttempts
            
        case 500...599:
            return .serverError(message)
            
        default:
            return .networkError(message)
        }
    }
}

// MARK: - Keychain Service

class KeychainService {
    static let shared = KeychainService()

    private let service = "com.studyai.app"
    private let tokenKey = "auth_token"
    private let userKey = "user_data"

    // Thread-safe access to keychain
    private let keychainQueue = DispatchQueue(label: "com.studyai.keychain", qos: .userInitiated)
    private let authLogger = Logger(subsystem: "com.studyai", category: "KeychainService")

    private init() {}

    func saveAuthToken(_ token: String) throws {
        authLogger.info("💾 [Keychain] Saving auth token (length: \(token.count))")

        // CRITICAL: Validate token format BEFORE saving
        // Backend uses 64-character hex session tokens (32 bytes)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedToken.isEmpty else {
            authLogger.error("❌ [Keychain] TOKEN IS EMPTY")
            throw AuthError.keychainError
        }

        // Validate token is reasonable length (hex tokens are 64 chars, JWTs are 200-500+ chars)
        guard trimmedToken.count >= 32 && trimmedToken.count <= 1024 else {
            authLogger.error("❌ [Keychain] INVALID TOKEN LENGTH: \(trimmedToken.count) (expected 32-1024)")
            authLogger.error("   Token preview: \(trimmedToken.prefix(50))...")
            throw AuthError.keychainError
        }

        authLogger.info("✅ [Keychain] Token format validated (length: \(trimmedToken.count))")

        // Convert to data with error handling
        guard let data = trimmedToken.data(using: .utf8) else {
            authLogger.error("❌ [Keychain] Failed to encode token to UTF-8")
            throw AuthError.keychainError
        }

        authLogger.info("   Data size: \(data.count) bytes")

        // Save to keychain (thread-safe)
        try keychainQueue.sync {
            try saveToKeychain(key: tokenKey, data: data)
        }

        // CRITICAL: Verify the token was saved correctly by reading it back
        guard let retrievedToken = getAuthToken() else {
            authLogger.error("❌ [Keychain] Verification FAILED: Token not found after save")
            throw AuthError.keychainError
        }

        guard retrievedToken == trimmedToken else {
            authLogger.error("❌ [Keychain] Verification FAILED: Retrieved token doesn't match")
            authLogger.error("   Original length: \(trimmedToken.count)")
            authLogger.error("   Retrieved length: \(retrievedToken.count)")
            throw AuthError.keychainError
        }

        authLogger.info("✅ [Keychain] Token saved and verified successfully")
    }

    func getAuthToken() -> String? {
        return keychainQueue.sync {
            guard let data = getFromKeychain(key: tokenKey) else {
                authLogger.debug("ℹ️ [Keychain] No auth token found in keychain")
                return nil
            }

            authLogger.debug("📖 [Keychain] Retrieved token data (\(data.count) bytes)")

            // Convert data to string
            guard let token = String(data: data, encoding: .utf8) else {
                authLogger.error("❌ [Keychain] Failed to decode token from UTF-8")
                return nil
            }

            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            authLogger.debug("   Token length: \(trimmedToken.count)")

            // CRITICAL: Validate token format BEFORE returning
            // Backend uses 64-character hex session tokens
            guard !trimmedToken.isEmpty else {
                authLogger.error("❌ [Keychain] EMPTY TOKEN on retrieval")
                deleteFromKeychain(key: tokenKey)
                return nil
            }

            // Validate reasonable length
            guard trimmedToken.count >= 32 && trimmedToken.count <= 1024 else {
                authLogger.error("❌ [Keychain] INVALID TOKEN LENGTH on retrieval: \(trimmedToken.count)")
                authLogger.error("   Token preview: \(trimmedToken.prefix(50))...")
                authLogger.error("   This token is corrupted in keychain - clearing it")
                deleteFromKeychain(key: tokenKey)
                return nil
            }

            authLogger.debug("✅ [Keychain] Token format validated on retrieval (length: \(trimmedToken.count))")
            return trimmedToken
        }
    }
    
    func saveUser(_ user: User) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(user)
        try keychainQueue.sync {
            try saveToKeychain(key: userKey, data: data)
        }
        authLogger.info("✅ [Keychain] User data saved successfully")
    }

    func getUser() -> User? {
        return keychainQueue.sync {
            guard let data = getFromKeychain(key: userKey) else { return nil }
            let decoder = JSONDecoder()
            return try? decoder.decode(User.self, from: data)
        }
    }

    func hasStoredCredentials() -> Bool {
        return getAuthToken() != nil && getUser() != nil
    }

    func clearAll() {
        keychainQueue.sync {
            authLogger.info("🗑️ [Keychain] Clearing all keychain data")
            deleteFromKeychain(key: tokenKey)
            deleteFromKeychain(key: userKey)
        }
    }
    
    private func saveToKeychain(key: String, data: Data) throws {
        authLogger.debug("💾 [Keychain] saveToKeychain called for key: \(key), data size: \(data.count) bytes")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        let deleteStatus = SecItemDelete(query as CFDictionary)
        authLogger.debug("   Delete status: \(deleteStatus) (\(deleteStatus == errSecSuccess ? "success" : deleteStatus == errSecItemNotFound ? "not found" : "error"))")

        // Add new item
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        authLogger.debug("   Add status: \(addStatus) (\(addStatus == errSecSuccess ? "success" : "error"))")

        if addStatus != errSecSuccess {
            authLogger.error("❌ [Keychain] SecItemAdd failed with status: \(addStatus)")
            throw AuthError.keychainError
        }

        authLogger.debug("✅ [Keychain] Item saved successfully")
    }

    private func getFromKeychain(key: String) -> Data? {
        authLogger.debug("📖 [Keychain] getFromKeychain called for key: \(key)")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        authLogger.debug("   Retrieve status: \(status) (\(status == errSecSuccess ? "success" : status == errSecItemNotFound ? "not found" : "error"))")

        if status == errSecSuccess {
            if let data = result as? Data {
                authLogger.debug("   Retrieved \(data.count) bytes")
                return data
            } else {
                authLogger.error("❌ [Keychain] Result is not Data type")
                return nil
            }
        }
        return nil
    }
    
    private func deleteFromKeychain(key: String) {
        authLogger.debug("🗑️ [Keychain] deleteFromKeychain called for key: \(key)")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        authLogger.debug("   Delete status: \(status) (\(status == errSecSuccess ? "success" : status == errSecItemNotFound ? "not found" : "error"))")
    }
}

// MARK: - Biometric Authentication Service

class BiometricAuthService {
    static let shared = BiometricAuthService()
    
    private let context = LAContext()
    
    private init() {}
    
    func isBiometricAvailable() -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    func isBiometricEnrolled() -> Bool {
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        
        if let error = error {
            switch error.code {
            case LAError.biometryNotEnrolled.rawValue:
                return false
            default:
                return canEvaluate
            }
        }
        
        return canEvaluate
    }
    
    func getBiometricType() -> String {
        guard isBiometricAvailable() else { return "None" }
        
        switch context.biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "None"
        @unknown default:
            return "Biometric ID"
        }
    }
    
    func authenticateWithBiometrics(reason: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if let error = error {
                    let laError = error as? LAError
                    switch laError?.code {
                    case .userCancel, .userFallback, .systemCancel:
                        continuation.resume(throwing: AuthError.userCancelled)
                    case .biometryNotAvailable:
                        continuation.resume(throwing: AuthError.biometricNotAvailable)
                    case .biometryNotEnrolled:
                        continuation.resume(throwing: AuthError.biometricNotEnrolled)
                    default:
                        continuation.resume(throwing: AuthError.biometricFailed)
                    }
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

// MARK: - Apple Sign In Service

class AppleSignInService: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    
    struct AppleUser {
        let userIdentifier: String
        let email: String?
        let fullName: String?
        let identityToken: String?
        let authorizationCode: String?
    }
    
    private var continuation: CheckedContinuation<AppleUser, Error>?
    
    func signIn() async throws -> AppleUser {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
    
    // MARK: - ASAuthorizationControllerDelegate
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            // Extract identity token and authorization code from credential
            var identityTokenString: String?
            var authorizationCodeString: String?

            if let identityToken = appleIDCredential.identityToken,
               let tokenString = String(data: identityToken, encoding: .utf8) {
                identityTokenString = tokenString
            }

            if let authorizationCode = appleIDCredential.authorizationCode,
               let codeString = String(data: authorizationCode, encoding: .utf8) {
                authorizationCodeString = codeString
            }

            let user = AppleUser(
                userIdentifier: appleIDCredential.user,
                email: appleIDCredential.email,
                fullName: appleIDCredential.fullName?.givenName,
                identityToken: identityTokenString,
                authorizationCode: authorizationCodeString
            )
            continuation?.resume(returning: user)
        } else {
            continuation?.resume(throwing: AuthError.providerError("Invalid Apple ID credential"))
        }
        continuation = nil
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let authError = error as NSError
        
        // Provide detailed error handling for better user experience
        switch authError.code {
        case ASAuthorizationError.canceled.rawValue:
            continuation?.resume(throwing: AuthError.userCancelled)
        case ASAuthorizationError.failed.rawValue:
            // This often indicates provisioning profile issues
            continuation?.resume(throwing: AuthError.providerError("Apple Sign-In is temporarily unavailable. This may be due to app configuration. Please use email authentication."))
        case ASAuthorizationError.invalidResponse.rawValue:
            continuation?.resume(throwing: AuthError.providerError("Invalid response from Apple. Please try again or use email authentication."))
        case ASAuthorizationError.notHandled.rawValue:
            continuation?.resume(throwing: AuthError.providerError("Apple Sign-In not handled. Please try again or use email authentication."))
        case ASAuthorizationError.unknown.rawValue:
            continuation?.resume(throwing: AuthError.providerError("Apple Sign-In temporarily unavailable. Please use email authentication."))
        case 1000: // Common authorization error code
            continuation?.resume(throwing: AuthError.providerError("Apple Sign-In is temporarily unavailable. This may be due to app configuration. Please use email authentication."))
        default:
            // For any unhandled error, provide a user-friendly message
            continuation?.resume(throwing: AuthError.providerError("Apple Sign-In temporarily unavailable. Please use email authentication or try again later."))
        }
        continuation = nil
    }
    
    // MARK: - ASAuthorizationControllerPresentationContextProviding
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Google Sign In Service

import UIKit

class GoogleSignInService: NSObject {
    
    struct GoogleUser {
        let userID: String
        let email: String
        let fullName: String?
        let profileImageURL: URL?
        let idToken: String?
        let accessToken: String?
    }
    
    func signIn() async throws -> GoogleUser {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                guard let presentingViewController = self.getPresentingViewController() else {
                    continuation.resume(throwing: AuthError.providerError("No presenting view controller available"))
                    return
                }
                
                // Check if GoogleSignIn SDK is available
                if NSClassFromString("GIDSignIn") != nil {
                    // SDK is available - use real Google Sign-In
                    self.performRealGoogleSignIn(from: presentingViewController, continuation: continuation)
                } else {
                    // SDK not available - show setup instructions
                    #if DEBUG
                    self.showGoogleSignInSetupAlert(from: presentingViewController, continuation: continuation)
                    #else
                    continuation.resume(throwing: AuthError.providerError("Google Sign-In is not configured. Please contact support."))
                    #endif
                }
            }
        }
    }
    
    private func performRealGoogleSignIn(from presentingViewController: UIViewController, continuation: CheckedContinuation<GoogleUser, Error>) {
        // Check if GoogleService-Info.plist exists and has required configuration
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientID = plist["CLIENT_ID"] as? String,
              !clientID.contains("YOUR_CLIENT_ID_HERE") else {
            continuation.resume(throwing: AuthError.providerError("GoogleService-Info.plist not found or not configured. Please follow the setup guide."))
            return
        }
        
        print("🔐 Configuring Google Sign-In with client ID: \(clientID.prefix(20))...")
        
        // Configure Google Sign-In
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // Perform Google Sign-In
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            if let error = error {
                print("🔴 Google Sign-In Error: \(error.localizedDescription)")
                continuation.resume(throwing: AuthError.providerError("Google Sign-In failed: \(error.localizedDescription)"))
                return
            }
            
            guard let result = result,
                  let idToken = result.user.idToken?.tokenString else {
                print("🔴 Google Sign-In: Missing user data or token")
                continuation.resume(throwing: AuthError.providerError("Google Sign-In failed: Missing authentication data"))
                return
            }
            
            let user = result.user
            
            let googleUser = GoogleUser(
                userID: user.userID ?? "",
                email: user.profile?.email ?? "",
                fullName: user.profile?.name,
                profileImageURL: user.profile?.imageURL(withDimension: 120),
                idToken: idToken,
                accessToken: user.accessToken.tokenString
            )
            

            continuation.resume(returning: googleUser)
        }
    }
    
    private func showGoogleSignInSetupAlert(from presentingViewController: UIViewController, continuation: CheckedContinuation<GoogleUser, Error>) {
        let alert = UIAlertController(
            title: "Google Sign-In Setup Required",
            message: """
            To enable Google Sign-In:
            
            1. Add GoogleSignIn SDK:
               • File → Add Package Dependencies
               • https://github.com/google/GoogleSignIn-iOS
            
            2. Create OAuth client:
               • Visit Google Cloud Console
               • Create iOS OAuth 2.0 client ID
               • Add bundle ID: com.OliOli.StudyMatesAI
            
            3. Add GoogleService-Info.plist:
               • Download from Google Cloud Console
               • Add to Xcode project
            
            4. Add URL scheme to Info.plist:
               • Key: CFBundleURLTypes
               • Value: REVERSED_CLIENT_ID from plist
            
            For now, please use email authentication.
            """,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Copy GitHub URL", style: .default) { _ in
            UIPasteboard.general.string = "https://github.com/google/GoogleSignIn-iOS"
            continuation.resume(throwing: AuthError.providerError("Google Sign-In setup required. GitHub URL copied to clipboard."))
        })
        
        alert.addAction(UIAlertAction(title: "OK", style: .cancel) { _ in
            continuation.resume(throwing: AuthError.providerError("Google Sign-In not configured. Please use email authentication."))
        })
        
        presentingViewController.present(alert, animated: true)
    }
    
    private func getPresentingViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let window = windowScene.windows.first else {
            return nil
        }
        
        var topController = window.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        return topController
    }
}
