//
//  AuthenticationNetworkService.swift
//  StudyAI
//
//  Authentication network service
//  Extracted from NetworkService.swift for modularity
//

import Foundation
import SwiftUI

/// Authentication network service for login, registration, and OAuth
class AuthenticationNetworkService: ObservableObject {

    // MARK: - Singleton
    static let shared = AuthenticationNetworkService()

    // MARK: - Dependencies
    private let client = NetworkClient.shared

    // MARK: - Initialization
    private init() {}

    // MARK: - Login Methods

    /// Login with email and password
    func login(email: String, password: String) async -> (success: Bool, message: String, token: String?, userData: [String: Any]?, statusCode: Int?) {

        let requestBody: [String: Any] = [
            "email": email,
            "password": password
        ]

        let result = await client.post(
            endpoint: "/api/auth/login",
            body: requestBody,
            timeout: 45
        )

        guard result.success, let data = result.data else {
            let errorMessage = result.error ?? "Login failed"
            return (false, errorMessage, nil, nil, result.statusCode)
        }

        // Parse response
        guard let json = client.parseDictionary(data) else {
            return (false, "Failed to parse server response", nil, nil, result.statusCode)
        }

        // Extract token and user data
        if let token = json["token"] as? String,
           let user = json["user"] as? [String: Any] {

            // Save token to keychain
            KeychainManager.shared.saveToken(token)

            // Save user ID
            if let userId = user["id"] as? String {
                UserDefaults.standard.set(userId, forKey: "userId")
            }

            return (true, "Login successful", token, user, result.statusCode)
        }

        return (false, "Invalid response format", nil, nil, result.statusCode)
    }

    /// Register new user
    func register(name: String, email: String, password: String) async -> (success: Bool, message: String, token: String?, userData: [String: Any]?, statusCode: Int?) {

        let requestBody: [String: Any] = [
            "name": name,
            "email": email,
            "password": password
        ]

        let result = await client.post(
            endpoint: "/api/auth/register",
            body: requestBody,
            timeout: 45
        )

        guard result.success, let data = result.data else {
            let errorMessage = result.error ?? "Registration failed"
            return (false, errorMessage, nil, nil, result.statusCode)
        }

        // Parse response
        guard let json = client.parseDictionary(data) else {
            return (false, "Failed to parse server response", nil, nil, result.statusCode)
        }

        // Check if requires email verification
        if let requiresVerification = json["requires_email_verification"] as? Bool, requiresVerification {
            return (true, "Please verify your email to continue", nil, nil, result.statusCode)
        }

        // Extract token and user data
        if let token = json["token"] as? String,
           let user = json["user"] as? [String: Any] {

            // Save token to keychain
            KeychainManager.shared.saveToken(token)

            // Save user ID
            if let userId = user["id"] as? String {
                UserDefaults.standard.set(userId, forKey: "userId")
            }

            return (true, "Registration successful", token, user, result.statusCode)
        }

        return (false, "Invalid response format", nil, nil, result.statusCode)
    }

    // MARK: - Email Verification

    /// Send verification code to email
    func sendVerificationCode(email: String, name: String) async -> (success: Bool, message: String, expiresIn: Int?, statusCode: Int?) {

        let requestBody: [String: Any] = [
            "email": email,
            "name": name
        ]

        let result = await client.post(
            endpoint: "/api/auth/send-verification-code",
            body: requestBody
        )

        guard result.success, let data = result.data else {
            let errorMessage = result.error ?? "Failed to send verification code"
            return (false, errorMessage, nil, result.statusCode)
        }

        // Parse response
        guard let json = client.parseDictionary(data) else {
            return (false, "Failed to parse server response", nil, result.statusCode)
        }

        let message = json["message"] as? String ?? "Verification code sent"
        let expiresIn = json["expires_in_seconds"] as? Int

        return (true, message, expiresIn, result.statusCode)
    }

    /// Verify email code and complete registration
    func verifyEmailCode(email: String, code: String, name: String, password: String) async -> (success: Bool, message: String, token: String?, userData: [String: Any]?, statusCode: Int?) {

        let requestBody: [String: Any] = [
            "email": email,
            "code": code,
            "name": name,
            "password": password
        ]

        let result = await client.post(
            endpoint: "/api/auth/verify-email-code",
            body: requestBody,
            timeout: 45
        )

        guard result.success, let data = result.data else {
            let errorMessage = result.error ?? "Verification failed"
            return (false, errorMessage, nil, nil, result.statusCode)
        }

        // Parse response
        guard let json = client.parseDictionary(data) else {
            return (false, "Failed to parse server response", nil, nil, result.statusCode)
        }

        // Extract token and user data
        if let token = json["token"] as? String,
           let user = json["user"] as? [String: Any] {

            // Save token to keychain
            KeychainManager.shared.saveToken(token)

            // Save user ID
            if let userId = user["id"] as? String {
                UserDefaults.standard.set(userId, forKey: "userId")
            }

            return (true, "Email verified successfully", token, user, result.statusCode)
        }

        return (false, "Invalid response format", nil, nil, result.statusCode)
    }

    /// Resend verification code
    func resendVerificationCode(email: String) async -> (success: Bool, message: String, expiresIn: Int?, statusCode: Int?) {

        let requestBody: [String: Any] = [
            "email": email
        ]

        let result = await client.post(
            endpoint: "/api/auth/resend-verification-code",
            body: requestBody
        )

        guard result.success, let data = result.data else {
            let errorMessage = result.error ?? "Failed to resend verification code"
            return (false, errorMessage, nil, result.statusCode)
        }

        // Parse response
        guard let json = client.parseDictionary(data) else {
            return (false, "Failed to parse server response", nil, result.statusCode)
        }

        let message = json["message"] as? String ?? "Verification code resent"
        let expiresIn = json["expires_in_seconds"] as? Int

        return (true, message, expiresIn, result.statusCode)
    }

    // MARK: - OAuth Methods

    /// Google OAuth login
    func googleLogin(
        idToken: String,
        accessToken: String?,
        name: String,
        email: String,
        profileImageUrl: String?
    ) async -> (success: Bool, message: String, token: String?, userData: [String: Any]?, statusCode: Int?) {

        var requestBody: [String: Any] = [
            "id_token": idToken,
            "name": name,
            "email": email
        ]

        if let accessToken = accessToken {
            requestBody["access_token"] = accessToken
        }

        if let profileImageUrl = profileImageUrl {
            requestBody["profile_image_url"] = profileImageUrl
        }

        let result = await client.post(
            endpoint: "/api/auth/google-login",
            body: requestBody,
            timeout: 45
        )

        guard result.success, let data = result.data else {
            let errorMessage = result.error ?? "Google login failed"
            return (false, errorMessage, nil, nil, result.statusCode)
        }

        // Parse response
        guard let json = client.parseDictionary(data) else {
            return (false, "Failed to parse server response", nil, nil, result.statusCode)
        }

        // Extract token and user data
        if let token = json["token"] as? String,
           let user = json["user"] as? [String: Any] {

            // Save token to keychain
            KeychainManager.shared.saveToken(token)

            // Save user ID
            if let userId = user["id"] as? String {
                UserDefaults.standard.set(userId, forKey: "userId")
            }

            return (true, "Google login successful", token, user, result.statusCode)
        }

        return (false, "Invalid response format", nil, nil, result.statusCode)
    }

    /// Apple OAuth login
    func appleLogin(
        identityToken: String,
        authorizationCode: String?,
        userIdentifier: String,
        name: String,
        email: String
    ) async -> (success: Bool, message: String, token: String?, userData: [String: Any]?, statusCode: Int?) {

        var requestBody: [String: Any] = [
            "identity_token": identityToken,
            "user_identifier": userIdentifier,
            "name": name,
            "email": email
        ]

        if let authorizationCode = authorizationCode {
            requestBody["authorization_code"] = authorizationCode
        }

        let result = await client.post(
            endpoint: "/api/auth/apple-login",
            body: requestBody,
            timeout: 45
        )

        guard result.success, let data = result.data else {
            let errorMessage = result.error ?? "Apple login failed"
            return (false, errorMessage, nil, nil, result.statusCode)
        }

        // Parse response
        guard let json = client.parseDictionary(data) else {
            return (false, "Failed to parse server response", nil, nil, result.statusCode)
        }

        // Extract token and user data
        if let token = json["token"] as? String,
           let user = json["user"] as? [String: Any] {

            // Save token to keychain
            KeychainManager.shared.saveToken(token)

            // Save user ID
            if let userId = user["id"] as? String {
                UserDefaults.standard.set(userId, forKey: "userId")
            }

            return (true, "Apple login successful", token, user, result.statusCode)
        }

        return (false, "Invalid response format", nil, nil, result.statusCode)
    }

    // MARK: - Logout

    /// Logout user (clear local data)
    func logout() {
        KeychainManager.shared.deleteToken()
        UserDefaults.standard.removeObject(forKey: "userId")
    }
}
