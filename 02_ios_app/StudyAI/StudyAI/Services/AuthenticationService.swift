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
    
    private let keychainService = KeychainService.shared
    private let biometricAuth = BiometricAuthService.shared
    private let networkService = NetworkService.shared
    
    private init() {
        checkAuthenticationStatus()
    }
    
    // MARK: - Authentication Status
    
    func checkAuthenticationStatus() {
        Task { @MainActor in
            if let userData = keychainService.getUser() {
                currentUser = userData
                isAuthenticated = true
            } else {
                isAuthenticated = false
                currentUser = nil
            }
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
        
        let result = await networkService.login(email: email, password: password)
        
        if result.success {
            let user = User(
                id: UUID().uuidString,
                email: email,
                name: extractNameFromEmail(email),
                profileImageURL: nil,
                authProvider: .email,
                createdAt: Date(),
                lastLoginAt: Date()
            )
            
            if let token = result.token {
                try keychainService.saveAuthToken(token)
                try keychainService.saveUser(user)
                
                await MainActor.run {
                    currentUser = user
                    isAuthenticated = true
                }
            }
        } else {
            throw AuthError.networkError(result.message)
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
        
        // For now, we'll simulate registration by calling the login endpoint
        // In a real app, you'd have a separate registration endpoint
        let result = await networkService.login(email: email, password: password)
        
        if result.success {
            let user = User(
                id: UUID().uuidString,
                email: email,
                name: name,
                profileImageURL: nil,
                authProvider: .email,
                createdAt: Date(),
                lastLoginAt: Date()
            )
            
            if let token = result.token {
                try keychainService.saveAuthToken(token)
                try keychainService.saveUser(user)
                
                await MainActor.run {
                    currentUser = user
                    isAuthenticated = true
                }
            }
        } else {
            throw AuthError.networkError(result.message)
        }
    }
    
    // MARK: - Apple Sign In
    
    func signInWithApple() async throws {
        let appleSignIn = AppleSignInService()
        do {
            let appleUser = try await appleSignIn.signIn()
            
            let user = User(
                id: appleUser.userIdentifier,
                email: appleUser.email ?? "apple_user@icloud.com",
                name: appleUser.fullName ?? "Apple User",
                profileImageURL: nil,
                authProvider: .apple,
                createdAt: Date(),
                lastLoginAt: Date()
            )
            
            // Generate a token for Apple Sign In users
            let token = "apple_token_\(UUID().uuidString)"
            try keychainService.saveAuthToken(token)
            try keychainService.saveUser(user)
            
            await MainActor.run {
                currentUser = user
                isAuthenticated = true
            }
        } catch {
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
        
        let user = User(
            id: googleUser.userID,
            email: googleUser.email,
            name: googleUser.fullName ?? googleUser.email.components(separatedBy: "@").first?.capitalized ?? "Google User",
            profileImageURL: googleUser.profileImageURL?.absoluteString,
            authProvider: .google,
            createdAt: Date(),
            lastLoginAt: Date()
        )
        
        // Generate a token for Google Sign In users
        let token = "google_token_\(UUID().uuidString)"
        try keychainService.saveAuthToken(token)
        try keychainService.saveUser(user)
        
        await MainActor.run {
            currentUser = user
            isAuthenticated = true
        }
    }
    
    // MARK: - Biometric Authentication
    
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
        
        let success = try await biometricAuth.authenticateWithBiometrics(reason: "Authenticate to access StudyAI")
        
        if success {
            // Load stored user data
            if let userData = keychainService.getUser() {
                await MainActor.run {
                    currentUser = userData
                    isAuthenticated = true
                }
            } else {
                throw AuthError.keychainError
            }
        } else {
            throw AuthError.biometricFailed
        }
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        keychainService.clearAll()
        Task { @MainActor in
            currentUser = nil
            isAuthenticated = false
            errorMessage = nil
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractNameFromEmail(_ email: String) -> String {
        let username = email.components(separatedBy: "@").first ?? "User"
        return username.capitalized
    }
    
    func getBiometricType() -> String {
        return biometricAuth.getBiometricType()
    }
    
    func canUseBiometrics() -> Bool {
        return biometricAuth.isBiometricAvailable() && biometricAuth.isBiometricEnrolled() && keychainService.hasStoredCredentials()
    }
    
    func isAppleSignInAvailable() -> Bool {
        // Check if Apple Sign-In capability is in the entitlements
        // This will gracefully handle provisioning profile issues while maintaining customer-facing functionality
        return Bundle.main.object(forInfoDictionaryKey: "com.apple.developer.applesignin") != nil
    }
}

// MARK: - Keychain Service

class KeychainService {
    static let shared = KeychainService()
    
    private let service = "com.studyai.app"
    private let tokenKey = "auth_token"
    private let userKey = "user_data"
    
    private init() {}
    
    func saveAuthToken(_ token: String) throws {
        let data = token.data(using: .utf8)!
        try saveToKeychain(key: tokenKey, data: data)
    }
    
    func getAuthToken() -> String? {
        guard let data = getFromKeychain(key: tokenKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func saveUser(_ user: User) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(user)
        try saveToKeychain(key: userKey, data: data)
    }
    
    func getUser() -> User? {
        guard let data = getFromKeychain(key: userKey) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(User.self, from: data)
    }
    
    func hasStoredCredentials() -> Bool {
        return getAuthToken() != nil && getUser() != nil
    }
    
    func clearAll() {
        deleteFromKeychain(key: tokenKey)
        deleteFromKeychain(key: userKey)
    }
    
    private func saveToKeychain(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw AuthError.keychainError
        }
    }
    
    private func getFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        }
        return nil
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
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
            let user = AppleUser(
                userIdentifier: appleIDCredential.user,
                email: appleIDCredential.email,
                fullName: appleIDCredential.fullName?.givenName
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
        
        // Real Google Sign-In implementation - now active!
        let config = GIDConfiguration(clientID: clientID)
        
        GIDSignIn.sharedInstance.configuration = config
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            if let error = error {
                let nsError = error as NSError
                if nsError.code == -5 { // User cancelled
                    continuation.resume(throwing: AuthError.userCancelled)
                } else {
                    continuation.resume(throwing: AuthError.providerError("Google Sign-In failed: \(error.localizedDescription)"))
                }
                return
            }
            
            guard let result = result else {
                continuation.resume(throwing: AuthError.providerError("Failed to get Google user profile"))
                return
            }
            
            let user = result.user
            
            guard let profile = user.profile else {
                continuation.resume(throwing: AuthError.providerError("Failed to get Google user profile"))
                return
            }
            
            let googleUser = GoogleUser(
                userID: user.userID ?? UUID().uuidString,
                email: profile.email,
                fullName: profile.name,
                profileImageURL: profile.imageURL(withDimension: 200)
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
               • Add bundle ID: com.bo-jiang-StudyAI
            
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
