//
//  NetworkService.swift
//  StudyAI
//
//  Created by Claude Code on 8/30/25.
//

import Foundation
import SwiftUI
import Combine
import Network
import UIKit
import os.log

// MARK: - Production Logging Safety
// Disable debug print statements in production builds to prevent user data exposure
#if !DEBUG
private func print(_ items: Any...) { }
private func debugPrint(_ items: Any...) { }
#endif

// MARK: - Debug Configuration for Avatar/Profile Logs
#if DEBUG
private let enableProfileDebugLogs = false  // Set to true to enable profile/avatar debug logs
#else
private let enableProfileDebugLogs = false  // Always false in release
#endif

private func profileLog(_ message: String) {
    #if DEBUG
    if enableProfileDebugLogs {
        print(message)
    }
    #endif
}

class NetworkService: ObservableObject {
    static let shared = NetworkService()

    // MARK: - Logger
    private let logger = AppLogger.network

    // Primary: Production Railway backend with integrated AI proxy
    private let baseURL = "https://sai-backend-production.up.railway.app"

    // Language preference for AI responses
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    // Public getter for base URL
    var apiBaseURL: String {
        return baseURL
    }
    
    // MARK: - Legacy Cache Management (backward compatibility)
    private var cachedSessions: [[String: Any]]?
    private var lastCacheTime: Date?
    private let cacheValidityInterval: TimeInterval = 300 // 5 minutes
    
    private func isCacheValid() -> Bool {
        guard let lastCacheTime = lastCacheTime else { return false }
        return Date().timeIntervalSince(lastCacheTime) < cacheValidityInterval
    }
    
    private func invalidateCache() {
        cachedSessions = nil
        lastCacheTime = nil
    }
    
    private func updateCache(with sessions: [[String: Any]]) {
        cachedSessions = sessions
        lastCacheTime = Date()
    }
    
    // MARK: - Enhanced Cache Management
    private let cache = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, diskPath: "StudyAI_Cache")
    private var responseCache: [String: CachedResponse] = [:]
    private let cacheQueue = DispatchQueue(label: "com.studyai.cache", qos: .utility)
    
    // MARK: - Circuit Breaker Pattern
    private var failureCount = 0
    private let maxFailures = 3
    private var circuitBreakerOpenUntil: Date?
    private let circuitBreakerTimeout: TimeInterval = 30
    
    // MARK: - Request Management
    private var activeRequests: [String: URLSessionDataTask] = [:]
    private let requestQueue = DispatchQueue(label: "com.studyai.network", qos: .userInitiated)

    // MARK: - Streaming Retry Management (Phase 2.3)
    private var streamingRetryState: StreamingRetryState?
    private let maxStreamingRetries = 3

    // MARK: - Network Monitoring
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    @Published var isNetworkAvailable = true
    
    // Session Management (Optimized)
    @Published var currentSessionId: String? {
        willSet {
            if newValue != currentSessionId {
                clearConversationHistory()
            }
        }
    }
    
    // Conversation History - Public for backward compatibility
    private var internalConversationHistory: [ConversationMessage] = []
    private let maxHistorySize = 50 // Prevent unlimited growth
    
    // Backward compatibility: Provide dictionary format for existing views
    @Published var conversationHistory: [[String: String]] = []
    
    // Internal conversation management
    internal func addToConversationHistory(role: String, content: String, deepMode: Bool = false) {
        let message = ConversationMessage(role: role, content: content, timestamp: Date())
        internalConversationHistory.append(message)

        // Update published dictionary format for backward compatibility
        var messageDict: [String: String] = ["role": role, "content": content]

        // ✅ Add deep mode flag for user messages sent with deep thinking mode
        if deepMode && role == "user" {
            messageDict["deepMode"] = "true"
        }

        conversationHistory.append(messageDict)

        // Limit history size to prevent memory issues
        if internalConversationHistory.count > maxHistorySize {
            internalConversationHistory.removeFirst(internalConversationHistory.count - maxHistorySize)
            conversationHistory.removeFirst(conversationHistory.count - maxHistorySize)
        }
    }

    // MARK: - Public Conversation Management (for SessionChatView)

    /// Add user message to conversation history immediately (for optimistic UI updates)
    func addUserMessageToHistory(_ message: String, deepMode: Bool = false) {
        addToConversationHistory(role: "user", content: message, deepMode: deepMode)
    }
    
    /// Remove the last message from conversation history (for error recovery)
    func removeLastMessageFromHistory() {
        if !internalConversationHistory.isEmpty {
            let _ = internalConversationHistory.removeLast()
            conversationHistory.removeLast()
        }
    }
    
    private init() {
        setupNetworkMonitoring()
        setupURLCache()
    }
    
    // MARK: - Enhanced Cache Management
    private struct CachedResponse {
        let data: Data
        let response: URLResponse
        let timestamp: Date
        let ttl: TimeInterval
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > ttl
        }
    }
    
    private struct ConversationMessage {
        let role: String
        let content: String
        let timestamp: Date
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        networkMonitor.start(queue: networkQueue)
    }
    
    private func setupURLCache() {
        URLSession.shared.configuration.urlCache = cache
        URLSession.shared.configuration.requestCachePolicy = .useProtocolCachePolicy
    }
    
    private func getCachedResponse(for key: String) -> CachedResponse? {
        return cacheQueue.sync {
            guard let cached = responseCache[key], !cached.isExpired else {
                responseCache.removeValue(forKey: key)
                return nil
            }
            return cached
        }
    }
    
    private func setCachedResponse(_ response: CachedResponse, for key: String) {
        cacheQueue.async {
            self.responseCache[key] = response
            
            // Clean expired entries periodically
            if self.responseCache.count > 100 {
                self.cleanExpiredCache()
            }
        }
    }
    
    private func cleanExpiredCache() {
        responseCache = responseCache.filter { !$1.isExpired }
    }
    
    private func clearConversationHistory() {
        internalConversationHistory.removeAll()
        conversationHistory.removeAll()
    }
    
    // MARK: - Circuit Breaker Implementation
    private func canMakeRequest() -> Bool {
        if let openUntil = circuitBreakerOpenUntil {
            if Date() < openUntil {
                return false // Circuit breaker is open
            } else {
                circuitBreakerOpenUntil = nil
                failureCount = 0 // Reset on timeout
            }
        }
        return true
    }
    
    private func recordSuccess() {
        failureCount = 0
        circuitBreakerOpenUntil = nil
    }
    
    private func recordFailure() {
        failureCount += 1
        if failureCount >= maxFailures {
            circuitBreakerOpenUntil = Date().addingTimeInterval(circuitBreakerTimeout)
            print("Circuit breaker opened due to failures")
        }
    }
    
    // MARK: - Optimized Request Helper
    private func addAuthHeader(to request: inout URLRequest) {
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("StudyAI-iOS/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        }
    }
    
    // MARK: - Network Errors
    enum NetworkError: LocalizedError {
        case circuitBreakerOpen
        case noConnection
        case invalidResponse
        case authenticationRequired
        case rateLimited
        case serverError(Int)
        case httpError(Int)
        case networkFailure(String)
        case decodingError(String)
        case invalidURL
        case invalidData
        
        var errorDescription: String? {
            switch self {
            case .circuitBreakerOpen:
                return "Service temporarily unavailable. Please try again later."
            case .noConnection:
                return "No internet connection available."
            case .invalidResponse:
                return "Invalid response from server."
            case .authenticationRequired:
                return "Authentication required. Please sign in again."
            case .rateLimited:
                return "Too many requests. Please wait a moment and try again."
            case .serverError(let code):
                return "Server error (\(code)). Please try again later."
            case .httpError(let code):
                return "Request failed with error \(code)."
            case .networkFailure(let message):
                return "Network error: \(message)"
            case .decodingError(let message):
                return "Data parsing error: \(message)"
            case .invalidURL:
                return "Invalid URL provided"
            case .invalidData:
                return "Invalid data received from server"
            }
        }
    }
    
    // MARK: - Optimized Network Request Manager
    
    // Simple performRequest method that returns (Data, URLResponse)
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        
        // Check circuit breaker
        guard canMakeRequest() else {
            throw NetworkError.circuitBreakerOpen
        }
        
        // Check network availability
        guard isNetworkAvailable else {
            throw NetworkError.noConnection
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Handle HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 400 {
                    let _ = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                    
                    if httpResponse.statusCode == 401 {
                        throw NetworkError.authenticationRequired
                    } else if httpResponse.statusCode == 404 {
                        throw NetworkError.httpError(httpResponse.statusCode)
                    } else if httpResponse.statusCode == 429 {
                        throw NetworkError.rateLimited
                    } else if httpResponse.statusCode >= 500 {
                        throw NetworkError.serverError(httpResponse.statusCode)
                    } else {
                        throw NetworkError.httpError(httpResponse.statusCode)
                    }
                }
            }
            
            recordSuccess()
            return (data, response)
            
        } catch {
            recordFailure()
            if error is NetworkError {
                throw error
            } else {
                throw NetworkError.networkFailure(error.localizedDescription)
            }
        }
    }
    
    private func performRequest<T>(
        _ request: URLRequest,
        cacheKey: String? = nil,
        cacheTTL: TimeInterval = 300,
        decoder: @escaping (Data) throws -> T
    ) async throws -> T {
        
        // Check circuit breaker
        guard canMakeRequest() else {
            throw NetworkError.circuitBreakerOpen
        }
        
        // Check network availability
        guard isNetworkAvailable else {
            throw NetworkError.noConnection
        }
        
        // Check cache first
        if let cacheKey = cacheKey,
           let cached = getCachedResponse(for: cacheKey) {
            do {
                let result = try decoder(cached.data)
                return result
            } catch {
                // Cache is corrupted, remove it
                cacheQueue.async {
                    self.responseCache.removeValue(forKey: cacheKey)
                }
            }
        }
        
        // Cancel any existing request with same URL
        if let existingTask = activeRequests[request.url?.absoluteString ?? ""] {
            existingTask.cancel()
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                recordFailure()
                throw NetworkError.invalidResponse
            }
            
            // Handle HTTP errors
            switch httpResponse.statusCode {
            case 200...299:
                recordSuccess()
                
                // Cache successful responses
                if let cacheKey = cacheKey {
                    let cachedResponse = CachedResponse(
                        data: data,
                        response: response,
                        timestamp: Date(),
                        ttl: cacheTTL
                    )
                    setCachedResponse(cachedResponse, for: cacheKey)
                }
                
                return try decoder(data)
                
            case 401:
                // Token expired, let AuthenticationService handle it
                throw NetworkError.authenticationRequired
                
            case 429:
                // Rate limited
                recordFailure()
                throw NetworkError.rateLimited
                
            case 500...599:
                // Server error
                recordFailure()
                throw NetworkError.serverError(httpResponse.statusCode)
                
            default:
                recordFailure()
                throw NetworkError.httpError(httpResponse.statusCode)
            }
            
        } catch {
            // Remove from active requests
            activeRequests.removeValue(forKey: request.url?.absoluteString ?? "")
            
            if error is NetworkError {
                throw error
            } else {
                recordFailure()
                throw NetworkError.networkFailure(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Health Check
    func testHealthCheck() async -> (success: Bool, message: String) {
        let healthURL = "\(baseURL)/health"

        guard let url = URL(string: healthURL) else {
            return (false, "Invalid URL")
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                            // Check AI status specifically
                            if let aiInfo = json["ai"] as? [String: Any] {
                                let aiStatus = aiInfo["status"] as? String ?? "unknown"
                                let aiMessage = aiInfo["message"] as? String ?? "No message"
                                return (true, "Railway Backend connected! AI: \(aiStatus) - \(aiMessage)")
                            } else {
                                return (true, "Railway Backend connected successfully")
                            }
                        } else {
                            return (false, "Invalid JSON format")
                        }
                    } catch {
                        return (false, "JSON parsing failed: \(error.localizedDescription)")
                    }
                } else {
                    return (false, "Railway Backend HTTP \(httpResponse.statusCode)")
                }
            }
            return (false, "No HTTP response from Railway Backend")
        } catch {
            return (false, "Railway Backend connection failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Authentication
    // Note: Authentication is now handled exclusively by AuthenticationService
    // These methods only interact with backend, do not store auth data locally
    
    func login(email: String, password: String) async -> (success: Bool, message: String, token: String?, userData: [String: Any]?, statusCode: Int?) {
        let loginURL = "\(baseURL)/api/auth/login"

        guard let url = URL(string: loginURL) else {
            return (false, "Invalid URL", nil, nil, nil)
        }

        let loginData = [
            "email": email,
            "password": password
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: loginData)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if statusCode == 200 {
                        let token = json["token"] as? String
                        let message = json["message"] as? String ?? "Login successful"
                        let userData = json["user"] as? [String: Any] ?? json  // Try 'user' key first, fallback to full response
                        // NOTE: Do not save auth data here - AuthenticationService will handle it
                        return (true, message, token, userData, statusCode)
                    } else {
                        let message = json["message"] as? String ?? "Login failed"
                        return (false, message, nil, nil, statusCode)
                    }
                }
            }

            return (false, "Invalid response", nil, nil, nil)
        } catch {
            return (false, "Login request failed: \(error.localizedDescription)", nil, nil, nil)
        }
    }
    
    // MARK: - Question Processing
    func submitQuestion(question: String, subject: String = "general") async -> (success: Bool, answer: String?) {
        // Try AI Engine first (with improved prompts)
        let aiEngineResult = await tryAIEngine(question: question, subject: subject)
        if aiEngineResult.success {
            return aiEngineResult
        }

        // Fallback to Railway backend if AI Engine is unavailable
        return await tryRailwayBackend(question: question, subject: subject)
    }
    
    // MARK: - AI Engine (Primary)
    private func tryAIEngine(question: String, subject: String) async -> (success: Bool, answer: String?) {
        let aiProcessURL = "\(baseURL)/api/ai/process-question"

        guard let url = URL(string: aiProcessURL) else {
            return (false, nil)
        }

        let requestData = [
            "student_id": "test_student_001",
            "question": question,
            "subject": subject,
            "context": [
                "learning_level": "high_school",
                "mobile_optimized": true
            ],
            "include_followups": true
        ] as [String: Any]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90.0 // Extended timeout for AI processing

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                // Track rate limits for question processing
                RateLimitManager.shared.updateFromHeaders(httpResponse, endpoint: .question)

                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let responseData = json["response"] as? [String: Any],
                       let answer = responseData["answer"] as? String {

                        print("✅ Raw AI Response: \(answer)")

                        return (true, answer)
                    }
                }

                return (false, nil)
            }

            return (false, nil)
        } catch {
            return (false, nil)
        }
    }
    
    // MARK: - Railway Backend (Fallback)
    private func tryRailwayBackend(question: String, subject: String) async -> (success: Bool, answer: String?) {
        let questionURL = "\(baseURL)/api/questions"

        guard let url = URL(string: questionURL) else {
            return (false, nil)
        }

        let questionData = [
            "question": question,
            "subject": subject
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: questionData)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("✅ Raw AI Response: \(json)")

                            let answer = json["answer"] as? String

                            return (true, answer)
                        } else {
                            return (false, "Invalid response format")
                        }
                    } catch {
                        return (false, "JSON parsing failed")
                    }
                } else {
                    return (false, "HTTP \(httpResponse.statusCode)")
                }
            }

            return (false, "No HTTP response from Railway Backend")
        } catch {
            return (false, nil)
        }
    }
    
    // MARK: - Authentication Debugging
    
    /// Debug method to check what user ID the backend thinks we are based on our token
    func debugAuthTokenMapping() async -> (success: Bool, backendUserId: String?, message: String) {
        guard AuthenticationService.shared.getAuthToken() != nil else {
            return (false, nil, "No auth token available")
        }
        
        // Try to get user info from backend using current token
        let debugURL = "\(baseURL)/api/user/profile"
        
        guard let url = URL(string: debugURL) else {
            return (false, nil, "Invalid debug URL")
        }
        
        var request = URLRequest(url: url)
        addAuthHeader(to: &request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = json["success"] as? Bool, success == true,
                       let profileData = json["profile"] as? [String: Any],
                       let backendUserId = profileData["id"] as? String {
                        return (true, backendUserId, "Successfully retrieved user profile")
                    }
                }
                
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                return (false, nil, "HTTP \(httpResponse.statusCode): \(rawResponse)")
            }
            
        } catch {
            return (false, nil, "Network error: \(error.localizedDescription)")
        }
        
        return (false, nil, "Unknown error")
    }

    /// ❌ DEPRECATED: getEnhancedProgress() - Removed 2025-10-17
    /// REASON: Only used in archived view (_Archived_Views/EngagingProgressView.swift)
    /// REPLACEMENT: Use PointsEarningSystem.shared directly for local progress data

    /// ❌ DEPRECATED: getProgressHistory() - Removed 2025-10-17
    /// REASON: Not used by any active iOS views
    /// REPLACEMENT: Calculate historical data from local storage

    /// Helper method to get current user data for API calls
    private func getCurrentUserData() -> [String: Any]? {
        if let userDataString = UserDefaults.standard.string(forKey: "user_data"),
           let userData = userDataString.data(using: .utf8),
           let userDict = try? JSONSerialization.jsonObject(with: userData) as? [String: Any] {
            return userDict
        }
        return nil
    }
    
    // MARK: - Debug OpenAI
    func debugOpenAI() async -> (success: Bool, debug: [String: Any]?) {
        let debugURL = "\(baseURL)/debug/openai"
        
        guard let url = URL(string: debugURL) else {
            return (false, nil)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Debug Status: \(httpResponse.statusCode)")
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ Debug Response: \(json)")
                    return (true, json)
                }
            }
            
            return (false, nil)
        } catch {
            print("❌ Debug test failed: \(error.localizedDescription)")
            return (false, nil)
        }
    }
    
    // MARK: - Optimized Image Upload and Analysis
    func uploadImageForAnalysis(imageData: Data, subject: String = "general") async -> (success: Bool, result: [String: Any]?) {
        // Memory optimization: Compress image if too large
        let optimizedImageData = optimizeImageData(imageData)
        
        print("📷 === OPTIMIZED IMAGE UPLOAD ===")
        print("📊 Original size: \(imageData.count) bytes")
        print("📊 Optimized size: \(optimizedImageData.count) bytes")
        print("📚 Subject: \(subject)")
        
        let imageUploadURL = "\(baseURL)/api/ai/analyze-image"
        
        guard let url = URL(string: imageUploadURL) else {
            return (false, ["error": "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45.0
        
        addAuthHeader(to: &request)
        
        do {
            // Use streaming for large uploads
            let formData = createMultipartFormData(
                imageData: optimizedImageData,
                subject: subject,
                boundary: "StudyAI-iOS-\(UUID().uuidString)"
            )
            
            request.setValue("multipart/form-data; boundary=\(formData.boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = formData.data
            
            let decoder: (Data) throws -> [String: Any] = { data in
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw NetworkError.decodingError("Invalid JSON response")
                }
                return json
            }
            
            let result = try await performRequest(
                request,
                cacheKey: nil, // Don't cache image uploads
                decoder: decoder
            )
            
            return (true, result)
            
        } catch {
            return (false, ["error": error.localizedDescription])
        }
    }
    
    // MARK: - Image Optimization
    private func optimizeImageData(_ imageData: Data) -> Data {
        // Maximum size: 5MB
        let maxSize = 5 * 1024 * 1024
        
        if imageData.count <= maxSize {
            return imageData
        }
        
        guard let image = UIImage(data: imageData) else {
            return imageData
        }
        
        // Calculate compression ratio
        let compressionRatio = Double(maxSize) / Double(imageData.count)
        let targetQuality = min(0.8, compressionRatio)
        
        // Compress image
        if let compressedData = image.jpegData(compressionQuality: targetQuality) {
            print("🗜️ Image compressed from \(imageData.count) to \(compressedData.count) bytes")
            return compressedData
        }
        
        return imageData
    }
    
    private struct MultipartFormData {
        let data: Data
        let boundary: String
    }
    
    private func createMultipartFormData(imageData: Data, subject: String, boundary: String) -> MultipartFormData {
        var formData = Data()
        
        // Add image data
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"image\"; filename=\"homework.jpg\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        formData.append(imageData)
        formData.append("\r\n".data(using: .utf8)!)
        
        // Add subject parameter
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"subject\"\r\n\r\n".data(using: .utf8)!)
        formData.append(subject.data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        
        // Add student_id parameter
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"student_id\"\r\n\r\n".data(using: .utf8)!)
        formData.append("ios_user".data(using: .utf8)!)
        formData.append("\r\n".data(using: .utf8)!)
        
        // Close boundary
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return MultipartFormData(data: formData, boundary: boundary)
    }
    
    // MARK: - Session Management
    func createSession(subject: String) async -> (success: Bool, sessionId: String?, message: String) {
        // Check authentication first - use unified auth system
        guard AuthenticationService.shared.getAuthToken() != nil else {
            print("❌ Authentication required to create session")
            return (false, nil, "Authentication required")
        }
        
        print("🆕 Creating new study session...")
        print("📚 Subject: \(subject)")
        
        let sessionURL = "\(baseURL)/api/ai/sessions/create"
        print("🔗 Session URL: \(sessionURL)")
        
        guard let url = URL(string: sessionURL) else {
            print("❌ Invalid session URL")
            return (false, nil, "Invalid URL")
        }
        
        // Get current AI character from voice settings
        let currentCharacter = VoiceInteractionService.shared.voiceSettings.voiceType.rawValue

        let sessionData: [String: Any] = [
            "subject": subject,
            "language": appLanguage,  // Pass user's language preference
            "character": currentCharacter  // ✅ NEW: Pass AI character for personality-based responses
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0  // Increased timeout for email verification
        
        // Add authentication header
        addAuthHeader(to: &request)
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: sessionData)
            
            print("📡 Creating session...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Session Creation Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let sessionId = json["session_id"] as? String {
                        
                        print("🎉 === SESSION CREATED ===")
                        print("🆔 Session ID: \(sessionId)")
                        print("👤 User: \(json["user_id"] as? String ?? "unknown")")
                        print("📚 Subject: \(json["subject"] as? String ?? "unknown")")
                        
                        await MainActor.run {
                            self.currentSessionId = sessionId
                            self.conversationHistory.removeAll()
                        }
                        
                        return (true, sessionId, "Session created successfully")
                    }
                } else if httpResponse.statusCode == 401 {
                    // Authentication failed - let AuthenticationService handle it
                    print("❌ Authentication expired in createSession")
                    return (false, nil, "Authentication expired")
                }
                
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("❌ Session Creation HTTP \(httpResponse.statusCode): \(String(rawResponse.prefix(200)))")
                return (false, nil, "HTTP \(httpResponse.statusCode)")
            }
            
            return (false, nil, "No HTTP response")
        } catch {
            print("❌ Session creation failed: \(error.localizedDescription)")
            return (false, nil, error.localizedDescription)
        }
    }

    // MARK: - Session Validation (Phase 2.6)

    /// Validate if a session still exists on the backend
    func validateSession(_ sessionId: String) async -> Bool {
        guard AuthenticationService.shared.getAuthToken() != nil else {
            print("❌ Authentication required to validate session")
            return false
        }

        let sessionURL = "\(baseURL)/api/ai/sessions/\(sessionId)"
        guard let url = URL(string: sessionURL) else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0
        addAuthHeader(to: &request)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let isValid = httpResponse.statusCode == 200
                print(isValid ? "✅ Session \(sessionId.prefix(8))... is valid" : "❌ Session \(sessionId.prefix(8))... is invalid (status: \(httpResponse.statusCode))")
                return isValid
            }
            return false
        } catch {
            print("❌ Session validation error: \(error.localizedDescription)")
            return false
        }
    }

    /// Ensure we have a valid session - create new one if current is invalid
    func ensureValidSession() async -> String? {
        // Check if we have a current session
        if let sessionId = await MainActor.run(body: { self.currentSessionId }) {
            // Validate it
            let isValid = await validateSession(sessionId)
            if isValid {
                print("✅ Using existing session: \(sessionId.prefix(8))...")
                return sessionId
            } else {
                print("⚠️ Current session invalid - creating new one")
            }
        }

        // No session or invalid session - create new one
        let result = await createSession(subject: "general")
        if result.success, let newSessionId = result.sessionId {
            print("✅ Created new session: \(newSessionId.prefix(8))...")
            return newSessionId
        } else {
            print("❌ Failed to create session: \(result.message)")
            return nil
        }
    }

    func sendSessionMessage(sessionId: String, message: String, questionContext: [String: Any]? = nil) async -> (success: Bool, aiResponse: String?, suggestions: [FollowUpSuggestion]?, tokensUsed: Int?, compressed: Bool?) {
        print("🌐 ============================================")
        print("🌐 === NETWORK SERVICE: SEND SESSION MESSAGE ===")
        print("🌐 ============================================")
        print("🌐 Timestamp: \(Date())")
        // Thread.current not available in async context
        // print("🌐 Thread: \(Thread.current)")

        // Check authentication first - use unified auth system
        guard AuthenticationService.shared.getAuthToken() != nil else {
            print("❌ Authentication required to send messages")
            return (false, nil, nil, nil, nil)
        }

        print("🌐 Session ID: \(sessionId)")
        print("🌐 Message: \(message)")
        print("🌐 Language: \(appLanguage)")
        print("🌐 ============================================")
        print("🌐 === QUESTION CONTEXT CHECK ===")
        print("🌐 ============================================")
        print("🌐 questionContext parameter is nil: \(questionContext == nil)")

        if let context = questionContext {
            print("🌐 ✅ QUESTION CONTEXT PROVIDED!")
            print("🌐 Context keys: \(context.keys.sorted())")
            print("🌐 Full context data: \(context)")
            if let questionText = context["questionText"] as? String {
                print("🌐    - questionText: \(questionText.prefix(100))")
            }
            if let studentAnswer = context["studentAnswer"] as? String {
                print("🌐    - studentAnswer: \(studentAnswer.prefix(50))")
            }
            if let correctAnswer = context["correctAnswer"] as? String {
                print("🌐    - correctAnswer: \(correctAnswer.prefix(50))")
            }
            if let currentGrade = context["currentGrade"] as? String {
                print("🌐    - currentGrade: \(currentGrade)")
            }
        } else {
            print("🌐 ℹ️ No question context - regular chat message")
        }
        print("🌐 ============================================")

        let messageURL = "\(baseURL)/api/ai/sessions/\(sessionId)/message"
        print("🌐 Message URL: \(messageURL)")

        guard let url = URL(string: messageURL) else {
            print("❌ Invalid message URL")
            return (false, nil, nil, nil, nil)
        }

        var messageData: [String: Any] = [
            "message": message,
            "language": appLanguage  // Pass user's language preference
        ]

        // Add homework context if provided (for grade correction support)
        if let context = questionContext {
            messageData["question_context"] = context
            print("🌐 ✅ Added question_context to messageData")
            print("🌐 Final messageData keys: \(messageData.keys.sorted())")
        } else {
            print("🌐 ℹ️ No question_context added to messageData")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180.0 // Aligned with backend timeout (170s) + buffer

        // Add authentication header
        addAuthHeader(to: &request)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: messageData)

            print("📡 Sending session message...")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Session Message Response Status: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 200 {
                    // Log raw response for debugging
                    let rawResponseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                    print("🔍 === RAW AI ENDPOINT RESPONSE ===")
                    print("📡 Full Raw Response: \(rawResponseString)")
                    print("=====================================")

                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Try parsing as new structured format first
                        var aiResponse: String?
                        var suggestions: [FollowUpSuggestion]? = nil
                        var tokensUsed: Int?
                        var compressed: Bool?

                        // Check if response has new structured format
                        if let textBody = json["text_body"] as? String {
                            // New structured format
                            aiResponse = textBody
                            tokensUsed = json["tokens_used"] as? Int
                            compressed = json["compressed"] as? Bool

                            // Parse follow-up suggestions
                            if let suggestionsArray = json["follow_up_suggestions"] as? [[String: String]] {
                                suggestions = suggestionsArray.compactMap { suggestionDict in
                                    guard let key = suggestionDict["key"],
                                          let value = suggestionDict["value"] else {
                                        return nil
                                    }
                                    return FollowUpSuggestion(key: key, value: value)
                                }
                                print("✨ Parsed \(suggestions?.count ?? 0) AI-generated suggestions")
                            }
                        } else if let oldFormatResponse = json["ai_response"] as? String {
                            // Legacy format fallback
                            aiResponse = oldFormatResponse
                            tokensUsed = json["tokens_used"] as? Int
                            compressed = json["compressed"] as? Bool
                            print("⚠️ Using legacy response format (no suggestions)")
                        }

                        if let aiResponse = aiResponse {
                            print("🎉 === SESSION MESSAGE SUCCESS ===")
                            print("🤖 Raw AI Response: '\(aiResponse)'")
                            print("📏 AI Response Length: \(aiResponse.count) characters")
                            print("🔍 Response Preview: \(String(aiResponse.prefix(200)))...")
                            print("📊 Tokens Used: \(tokensUsed ?? 0)")
                            print("🗜️ Context Compressed: \(compressed ?? false)")

                            // Update conversation history - only add AI response since user message was already added optimistically
                            await MainActor.run {
                                self.addToConversationHistory(role: "assistant", content: aiResponse)

                                // Additional debug for conversation history update
                                print("📚 === CONVERSATION HISTORY UPDATE ===")
                                print("👤 User Message Already Added: '\(message)' (optimistic update)")
                                print("🤖 AI Message Added: '\(aiResponse)'")
                                print("📈 Total Messages in History: \(self.conversationHistory.count)")
                                print("=====================================")
                            }

                            return (true, aiResponse, suggestions, tokensUsed, compressed)
                        }
                    }
                } else if httpResponse.statusCode == 401 {
                    // Authentication failed - let AuthenticationService handle it
                    print("❌ Authentication expired in sendSessionMessage")
                    return (false, "Authentication expired", nil, nil, nil)
                } else if httpResponse.statusCode == 403 {
                    return (false, "Access denied - session belongs to different user", nil, nil, nil)
                }

                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("❌ Session Message HTTP \(httpResponse.statusCode): \(String(rawResponse.prefix(200)))")
                return (false, nil, nil, nil, nil)
            }

            return (false, nil, nil, nil, nil)
        } catch {
            print("❌ Session message failed: \(error.localizedDescription)")
            return (false, nil, nil, nil, nil)
        }
    }

    // MARK: - 🚀 STREAMING Session Message with Retry (Phase 2.3)

    /// Send a session message with STREAMING response and automatic retry with partial response recovery
    /// - Parameters:
    ///   - sessionId: The session ID
    ///   - message: The user message
    ///   - deepMode: Enable deep thinking mode (o4-mini)
    ///   - questionContext: Optional homework question context
    ///   - onChunk: Callback for each streaming chunk (delta text)
    ///   - onSuggestions: Callback when AI-generated follow-up suggestions arrive
    ///   - onComplete: Callback when streaming is complete (success, full text, tokens, compressed)
    ///   - onRetryAvailable: Callback when retry is available with partial response
    /// - Returns: Success status
    @MainActor
    func sendSessionMessageStreamingWithRetry(
        sessionId: String,
        message: String,
        deepMode: Bool = false,
        questionContext: [String: Any]? = nil,
        onChunk: @escaping (String) -> Void,
        onSuggestions: @escaping ([FollowUpSuggestion]) -> Void,
        onComplete: @escaping (Bool, String?, Int?, Bool?) -> Void,
        onRetryAvailable: @escaping (String) -> Void  // Called with partial text when retry is available
    ) async -> Bool {
        print("🔄 === STREAMING WITH RETRY (Phase 2.3) ===")

        // Initialize retry state if this is the first attempt
        if streamingRetryState == nil {
            streamingRetryState = StreamingRetryState(
                sessionId: sessionId,
                message: message,
                deepMode: deepMode,
                questionContext: questionContext
            )
            print("🔄 Initialized retry state for new request")
        }

        // Check max retries
        guard let retryState = streamingRetryState, retryState.retryCount < maxStreamingRetries else {
            print("❌ Max retries (\(maxStreamingRetries)) exceeded")
            if let partialText = streamingRetryState?.accumulatedText, !partialText.isEmpty {
                onComplete(false, partialText, nil, nil)
            } else {
                onComplete(false, nil, nil, nil)
            }
            streamingRetryState = nil
            return false
        }

        print("🔄 Attempt \(retryState.retryCount + 1) of \(maxStreamingRetries)")

        var latestAccumulatedText = retryState.accumulatedText

        // Attempt streaming with text accumulation
        let success = await sendSessionMessageStreaming(
            sessionId: sessionId,
            message: message,
            deepMode: deepMode,
            questionContext: questionContext,
            onChunk: { text in
                latestAccumulatedText = text
                self.streamingRetryState?.updateAccumulatedText(text)
                onChunk(text)
            },
            onSuggestions: onSuggestions,
            onComplete: onComplete
        )

        if success {
            // Success - clear retry state
            print("✅ Streaming succeeded, clearing retry state")
            streamingRetryState = nil
            return true
        } else {
            // Failure - increment retry count and notify about partial response
            streamingRetryState?.retryCount += 1

            print("⚠️ Streaming failed (attempt \(retryState.retryCount + 1))")
            print("📦 Partial response saved: \(latestAccumulatedText.count) characters")

            if !latestAccumulatedText.isEmpty && retryState.retryCount < maxStreamingRetries {
                // Partial response available and retries remaining
                onRetryAvailable(latestAccumulatedText)
            } else if retryState.retryCount >= maxStreamingRetries {
                // Max retries exhausted
                print("❌ Max retries exhausted")
                streamingRetryState = nil
            }

            return false
        }
    }

    /// Manually retry streaming after failure (called by UI)
    @MainActor
    func retryStreaming(
        onChunk: @escaping (String) -> Void,
        onSuggestions: @escaping ([FollowUpSuggestion]) -> Void,
        onComplete: @escaping (Bool, String?, Int?, Bool?) -> Void,
        onRetryAvailable: @escaping (String) -> Void
    ) async -> Bool {
        guard let retryState = streamingRetryState else {
            print("❌ No retry state available")
            return false
        }

        print("🔄 Manual retry requested")
        return await sendSessionMessageStreamingWithRetry(
            sessionId: retryState.sessionId,
            message: retryState.message,
            deepMode: retryState.deepMode,
            questionContext: retryState.questionContext,
            onChunk: onChunk,
            onSuggestions: onSuggestions,
            onComplete: onComplete,
            onRetryAvailable: onRetryAvailable
        )
    }

    // MARK: - 🚀 STREAMING Session Message

    /// Send a session message with STREAMING response (real-time token-by-token)
    /// - Parameters:
    ///   - sessionId: The session ID
    ///   - message: The user message
    ///   - questionContext: Optional homework question context
    ///   - onChunk: Callback for each streaming chunk (delta text)
    ///   - onSuggestions: Callback when AI-generated follow-up suggestions arrive
    ///   - onComplete: Callback when streaming is complete (full text, tokens, compressed)
    /// - Returns: Success status
    @MainActor
    func sendSessionMessageStreaming(
        sessionId: String,
        message: String,
        deepMode: Bool = false,
        questionContext: [String: Any]? = nil,
        onChunk: @escaping (String) -> Void,
        onSuggestions: @escaping ([FollowUpSuggestion]) -> Void,
        onComplete: @escaping (Bool, String?, Int?, Bool?) -> Void
    ) async -> Bool {
        print("🟢 ============================================")
        print("🟢 === NETWORK SERVICE: STREAMING SESSION MESSAGE ===")
        print("🟢 ============================================")
        print("🟢 Timestamp: \(Date())")
        // Thread.current not available in async context
        // print("🟢 Thread: \(Thread.current)")
        print("🟢 Session ID: \(sessionId)")
        print("🟢 Message: \(message)")
        print("🟢 Deep Mode: \(deepMode ? "YES (o4-mini)" : "NO (intelligent routing)")")  // ✅ NEW: Log deep mode
        print("🟢 Language: \(appLanguage)")
        print("🟢 ============================================")
        print("🟢 === QUESTION CONTEXT CHECK ===")
        print("🟢 ============================================")
        print("🟢 questionContext parameter: \(questionContext != nil ? "PROVIDED ✓" : "NIL ✗")")

        // Enhanced logging for homework context
        if let questionContext = questionContext {
            print("🟢 ✅ HOMEWORK CONTEXT DETECTED IN NETWORKSERVICE!")
            print("🟢 Context keys: \(questionContext.keys.sorted())")
            print("🟢 Full context: \(questionContext)")

            if let questionText = questionContext["questionText"] as? String {
                print("🟢    - questionText: \(questionText)")
            }
            if let rawQuestionText = questionContext["rawQuestionText"] as? String {
                print("🟢    - rawQuestionText: \(rawQuestionText.prefix(100))")
            }
            if let studentAnswer = questionContext["studentAnswer"] as? String {
                print("🟢    - studentAnswer: \(studentAnswer)")
            }
            if let correctAnswer = questionContext["correctAnswer"] as? String {
                print("🟢    - correctAnswer: \(correctAnswer)")
            }
            if let currentGrade = questionContext["currentGrade"] as? String {
                print("🟢    - currentGrade: \(currentGrade)")
            }
            if let originalFeedback = questionContext["originalFeedback"] as? String {
                print("🟢    - originalFeedback: \(originalFeedback.prefix(100))")
            }
            if let points = questionContext["pointsEarned"] as? Float,
               let possible = questionContext["pointsPossible"] as? Float {
                print("🟢    - points: \(points)/\(possible)")
            }
            if let questionNumber = questionContext["questionNumber"] as? Int {
                print("🟢    - questionNumber: \(questionNumber)")
            }
            if let subject = questionContext["subject"] as? String {
                print("🟢    - subject: \(subject)")
            }
            print("🟢 📤 Will include question_context in request body...")
        } else {
            print("🟢 ℹ️ No question context - regular chat message")
        }
        print("🟢 ============================================")

        let streamURL = "\(baseURL)/api/ai/sessions/\(sessionId)/message/stream"

        guard let url = URL(string: streamURL) else {
            print("❌ Invalid streaming URL")
            onComplete(false, nil, nil, nil)
            return false
        }

        var messageData: [String: Any] = [
            "message": message,
            "deep_mode": deepMode,  // ✅ NEW: Pass deep mode flag to backend
            "language": appLanguage
        ]

        // Add question context if provided (for homework follow-up)
        if let questionContext = questionContext {
            messageData["question_context"] = questionContext
            print("✅ Added question_context to request body")
            print("📦 Request body keys: \(messageData.keys)")
        } else {
            print("ℹ️ No question_context - regular chat message")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 180.0 // Aligned with backend timeout (170s) + buffer

        addAuthHeader(to: &request)

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: messageData)

            print("📡 Sending request to AI Engine...")

            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid HTTP response")
                onComplete(false, nil, nil, nil)
                return false
            }

            guard httpResponse.statusCode == 200 else {
                print("❌ Streaming request failed with status: \(httpResponse.statusCode)")

                // Try to read error body
                var errorBody = ""
                for try await byte in asyncBytes {
                    let character = String(bytes: [byte], encoding: .utf8) ?? ""
                    errorBody += character
                    if errorBody.count > 1000 { break }
                }
                print("❌ Error: \(errorBody)")

                onComplete(false, nil, nil, nil)
                return false
            }

            print("✅ Streaming connection established, receiving AI response...")

            var accumulatedText = ""
            var buffer = ""
            var streamComplete = false  // Track if "end" event received

            for try await byte in asyncBytes {
                let character = String(bytes: [byte], encoding: .utf8) ?? ""
                buffer += character

                // SSE format: data: {...}\n\n
                if buffer.hasSuffix("\n\n") {
                    let lines = buffer.components(separatedBy: "\n")

                    for line in lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))

                            if let jsonData = jsonString.data(using: .utf8) {
                                do {
                                    let event = try JSONDecoder().decode(SSEEvent.self, from: jsonData)

                                    switch event.type {
                                    case "start":
                                        break  // Silent start

                                    case "content":
                                        accumulatedText = event.content ?? ""

                                        // Call the chunk callback on main thread
                                        await MainActor.run {
                                            onChunk(accumulatedText)
                                        }

                                        // Check for AI-generated suggestions in content events
                                        if let suggestions = event.suggestions, !suggestions.isEmpty {
                                            await MainActor.run {
                                                onSuggestions(suggestions)
                                            }
                                        }

                                    case "end":
                                        print("✅ AI response complete (\(accumulatedText.count) chars)")

                                        // Show first 200 chars of final response for debugging
                                        if accumulatedText.count > 0 {
                                            print("📄 Response preview: \(accumulatedText.prefix(200))...")
                                        }

                                        // 🚀 OPTIMIZATION: Suggestions now sent separately
                                        // Legacy support: Check for suggestions in end event (will be empty after backend update)
                                        if let suggestions = event.suggestions, !suggestions.isEmpty {
                                            print("💡 Received suggestions in 'end' event (legacy format)")
                                            await MainActor.run {
                                                onSuggestions(suggestions)
                                            }
                                        }

                                        // ⚠️ BUG FIX: Don't return here! Keep reading stream for suggestions/grade_correction events
                                        // Call completion callback but DON'T exit the loop
                                        print("📡 Stream complete, continuing to listen for suggestions/grade_correction...")
                                        streamComplete = true  // Mark as complete but continue listening

                                        await MainActor.run {
                                            onComplete(true, accumulatedText, nil, nil)
                                        }

                                    case "suggestions":
                                        // 🚀 NEW: Handle deferred suggestions event (sent after 'end' event)
                                        print("💡 === SUGGESTIONS EVENT (deferred) ===")
                                        if let suggestions = event.suggestions, !suggestions.isEmpty {
                                            print("📋 Received \(suggestions.count) follow-up suggestions")
                                            await MainActor.run {
                                                onSuggestions(suggestions)
                                            }
                                        } else {
                                            print("ℹ️ No suggestions provided")
                                        }

                                    case "error":
                                        print("❌ Stream error: \(event.error ?? "Unknown error")")
                                        onComplete(false, nil, nil, nil)
                                        return false

                                    default:
                                        break  // Ignore unknown event types
                                    }
                                } catch {
                                    print("❌ JSON decode error: \(error)")
                                }
                            }
                        }
                    }

                    buffer = ""
                }
            }

            // Only report failure if we never received the "end" event
            if !streamComplete {
                print("⚠️ Stream ended without completion event")
                onComplete(false, accumulatedText.isEmpty ? nil : accumulatedText, nil, nil)
                return false
            } else {
                print("✅ Stream closed naturally after completion event")
                return true
            }

        } catch {
            print("❌ Streaming failed: \(error.localizedDescription)")
            onComplete(false, nil, nil, nil)
            return false
        }
    }

    // SSE Event structure for streaming
    private struct SSEEvent: Codable {
        let type: String
        let content: String?
        let delta: String?
        let session_id: String?
        let error: String?
        let finish_reason: String?
        let timestamp: String?
        let suggestions: [FollowUpSuggestion]?
    }

    // MARK: - Streaming Retry State (Phase 2.3)

    /// State for streaming retry with partial response recovery
    private struct StreamingRetryState {
        let accumulatedText: String
        let sessionId: String
        let message: String
        let deepMode: Bool
        let questionContext: [String: Any]?
        var retryCount: Int

        init(sessionId: String, message: String, deepMode: Bool, questionContext: [String: Any]?) {
            self.accumulatedText = ""
            self.sessionId = sessionId
            self.message = message
            self.deepMode = deepMode
            self.questionContext = questionContext
            self.retryCount = 0
        }

        mutating func updateAccumulatedText(_ text: String) {
            self = StreamingRetryState(
                accumulatedText: text,
                sessionId: sessionId,
                message: message,
                deepMode: deepMode,
                questionContext: questionContext,
                retryCount: retryCount
            )
        }

        private init(accumulatedText: String, sessionId: String, message: String, deepMode: Bool, questionContext: [String: Any]?, retryCount: Int) {
            self.accumulatedText = accumulatedText
            self.sessionId = sessionId
            self.message = message
            self.deepMode = deepMode
            self.questionContext = questionContext
            self.retryCount = retryCount
        }
    }

    // MARK: - Interactive Streaming (Phase 3: Real-time synchronized TTS)

    /// Send message with interactive streaming (text + audio synchronized)
    /// Uses ElevenLabs WebSocket for real-time TTS generation
    ///
    /// - Parameters:
    ///   - sessionId: The session ID
    ///   - message: The user message
    ///   - voiceId: ElevenLabs voice ID (e.g., 'zZLmKvCp1i04X8E0FJ8B' for Max)
    ///   - systemPrompt: Optional system prompt override
    ///   - onTextDelta: Callback for each text chunk (accumulated text)
    ///   - onAudioChunk: Callback for each audio chunk (base64 MP3)
    ///   - onComplete: Callback when complete (success, full text)
    @MainActor
    func sendSessionMessageInteractive(
        sessionId: String,
        message: String,
        voiceId: String,
        systemPrompt: String? = nil,
        onTextDelta: @escaping (String) -> Void,
        onAudioChunk: @escaping (String, Data?) -> Void,  // ✅ Added alignment data parameter
        onComplete: @escaping (Bool, String?) -> Void
    ) async {
        guard let url = URL(string: "\(baseURL)/api/ai/sessions/\(sessionId)/interactive-stream") else {
            logger.error("❌ Invalid interactive streaming URL")
            onComplete(false, nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180 // 3 minutes

        // Add auth token
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build request payload
        let payload: [String: Any] = [
            "message": message,
            "voiceId": voiceId,
            "systemPrompt": systemPrompt ?? "You are a helpful AI tutor.",
            "deepMode": false // Interactive mode not compatible with deep mode
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            logger.error("❌ Failed to encode interactive request: \(error)")
            onComplete(false, nil)
            return
        }

        logger.info("🎙️ Starting interactive streaming session...")

        do {
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("❌ Invalid response type")
                onComplete(false, nil)
                return
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("❌ Interactive streaming failed: \(httpResponse.statusCode)")
                onComplete(false, nil)
                return
            }

            logger.info("✅ Interactive streaming connected")

            var buffer = ""
            var fullText = ""
            var streamComplete = false

            // Parse SSE events
            for try await byte in asyncBytes {
                let char = String(bytes: [byte], encoding: .utf8) ?? ""
                buffer += char

                if buffer.hasSuffix("\n\n") {
                    let lines = buffer.components(separatedBy: "\n")

                    for line in lines {
                        if line.hasPrefix("data: ") {
                            let jsonStr = String(line.dropFirst(6))
                            guard let jsonData = jsonStr.data(using: .utf8) else { continue }

                            do {
                                let event = try JSONDecoder().decode(InteractiveStreamEvent.self, from: jsonData)

                                logger.debug("📨 [Interactive] Event type: \(event.type)")

                                switch event.type {
                                case "connected":
                                    logger.debug("🔗 Interactive mode connected")

                                case "text_delta":
                                    if let content = event.content {
                                        fullText = content
                                        logger.debug("📝 [Interactive] Text delta: \(content.count) chars")
                                        onTextDelta(content)
                                    }

                                case "audio_chunk":
                                    if let audio = event.audio {
                                        logger.info("🔊 [Interactive] Audio chunk received: \(audio.count) chars base64")

                                        // ✅ Convert alignment to Data for passing to callback
                                        var alignmentData: Data? = nil
                                        if let alignment = event.alignment {
                                            alignmentData = try? JSONEncoder().encode(alignment)
                                        }

                                        onAudioChunk(audio, alignmentData)
                                    } else {
                                        logger.warning("⚠️ [Interactive] audio_chunk event but no audio data")
                                    }

                                case "complete":
                                    logger.info("✅ Interactive streaming complete")
                                    streamComplete = true
                                    onComplete(true, fullText)

                                case "error":
                                    logger.error("❌ Interactive stream error: \(event.error ?? "Unknown")")
                                    onComplete(false, fullText.isEmpty ? nil : fullText)
                                    return

                                default:
                                    break
                                }
                            } catch {
                                logger.error("❌ Failed to decode interactive event: \(error)")
                            }
                        }
                    }

                    buffer = ""
                }
            }

            if !streamComplete {
                logger.warning("⚠️ Interactive stream ended without completion")
                onComplete(false, fullText.isEmpty ? nil : fullText)
            }

        } catch {
            logger.error("❌ Interactive streaming error: \(error)")
            onComplete(false, nil)
        }
    }

    /// Interactive stream event structure
    private struct InteractiveStreamEvent: Codable {
        let type: String
        let content: String?
        let audio: String?
        let alignment: AlignmentData?  // ✅ NEW: Character timing data from ElevenLabs
        let error: String?
        let sessionId: String?
        let metrics: [String: AnyCodable]?

        enum CodingKeys: String, CodingKey {
            case type
            case content
            case audio
            case alignment
            case error
            case sessionId
            case metrics
        }
    }

    /// Alignment data from ElevenLabs
    private struct AlignmentData: Codable {
        let characters: [String]?
        let characterStartTimesMs: [Double]?
        let characterEndTimesMs: [Double]?

        enum CodingKeys: String, CodingKey {
            case characters
            case characterStartTimesMs = "character_start_times_ms"
            case characterEndTimesMs = "character_end_times_ms"
        }
    }

    /// Helper for decoding arbitrary JSON values
    private struct AnyCodable: Codable {
        let value: Any

        init(_ value: Any) {
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intVal = try? container.decode(Int.self) {
                value = intVal
            } else if let doubleVal = try? container.decode(Double.self) {
                value = doubleVal
            } else if let stringVal = try? container.decode(String.self) {
                value = stringVal
            } else if let boolVal = try? container.decode(Bool.self) {
                value = boolVal
            } else {
                value = NSNull()
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if let intVal = value as? Int {
                try container.encode(intVal)
            } else if let doubleVal = value as? Double {
                try container.encode(doubleVal)
            } else if let stringVal = value as? String {
                try container.encode(stringVal)
            } else if let boolVal = value as? Bool {
                try container.encode(boolVal)
            }
        }
    }

    // MARK: - AI Response Models

    /// Structured AI response with follow-up suggestions
    struct StructuredAIResponse: Codable {
        let textBody: String
        let followUpSuggestions: [FollowUpSuggestion]
        let tokensUsed: Int?
        let compressed: Bool?

        enum CodingKeys: String, CodingKey {
            case textBody = "text_body"
            case followUpSuggestions = "follow_up_suggestions"
            case tokensUsed = "tokens_used"
            case compressed
        }
    }

    /// Follow-up suggestion with key (button label) and value (full prompt)
    struct FollowUpSuggestion: Codable, Identifiable {
        let id = UUID()
        let key: String    // Short label for button (e.g., "Show examples")
        let value: String  // Full prompt to send (e.g., "Can you give me concrete examples?")

        enum CodingKeys: String, CodingKey {
            case key, value
        }
    }

    // MARK: - Homework Follow-up

    // MARK: - Diagram Generation Models

    /// Request model for diagram generation
    struct DiagramGenerationRequest: Codable {
        let conversationHistory: [[String: String]]
        let diagramRequest: String
        let sessionId: String?
        let subject: String
        let language: String
        let regenerate: Bool  // If true, uses better model (o1-mini) for two-step reasoning

        enum CodingKeys: String, CodingKey {
            case conversationHistory = "conversation_history"
            case diagramRequest = "diagram_request"
            case sessionId = "session_id"
            case subject
            case language
            case regenerate
        }
    }

    /// Rendering hints for diagram display
    struct DiagramRenderingHint: Codable {
        let width: Int
        let height: Int
        let background: String
        let scaleFactor: Double?

        enum CodingKeys: String, CodingKey {
            case width
            case height
            case background
            case scaleFactor = "scale_factor"
        }
    }

    /// Response model for diagram generation
    struct DiagramGenerationResponse: Codable {
        let success: Bool
        let diagramType: String?
        let diagramCode: String?
        let diagramTitle: String?
        let explanation: String?
        let reasoning: String?  // AI's analysis and tool selection reasoning (two-step process)
        let renderingHint: DiagramRenderingHint?
        let processingTimeMs: Int?
        let tokensUsed: Int?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case success
            case diagramType = "diagram_type"
            case diagramCode = "diagram_code"
            case diagramTitle = "diagram_title"
            case explanation
            case reasoning
            case renderingHint = "rendering_hint"
            case processingTimeMs = "processing_time_ms"
            case tokensUsed = "tokens_used"
            case error
        }
    }

    func getSessionInfo(sessionId: String) async -> (success: Bool, sessionInfo: [String: Any]?) {
        // Check authentication first - use unified auth system
        guard AuthenticationService.shared.getAuthToken() != nil else {
            print("❌ Authentication required to get session info")
            return (false, nil)
        }
        
        print("📊 Getting session info...")
        print("🆔 Session ID: \(sessionId.prefix(8))...")
        
        let infoURL = "\(baseURL)/api/ai/sessions/\(sessionId)"
        print("🔗 Info URL: \(infoURL)")
        
        guard let url = URL(string: infoURL) else {
            print("❌ Invalid info URL")
            return (false, nil)
        }
        
        var request = URLRequest(url: url)
        // Add authentication header
        addAuthHeader(to: &request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Session Info Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("🎉 === SESSION INFO SUCCESS ===")
                        print("📊 Session Info: \(json)")
                        
                        return (true, json)
                    }
                } else if httpResponse.statusCode == 401 {
                    // Authentication failed - let AuthenticationService handle it
                    print("❌ Authentication expired in getSessionInfo")
                    return (false, nil)
                } else if httpResponse.statusCode == 403 {
                    print("❌ Access denied - session belongs to different user")
                    return (false, nil)
                }
                
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("❌ Session Info HTTP \(httpResponse.statusCode): \(String(rawResponse.prefix(200)))")
                return (false, nil)
            }
            
            return (false, nil)
        } catch {
            print("❌ Session info failed: \(error.localizedDescription)")
            return (false, nil)
        }
    }

    // MARK: - Diagram Generation

    /// Generate diagram from conversation context
    func generateDiagram(
        conversationHistory: [[String: String]],
        diagramRequest: String,
        sessionId: String,
        subject: String,
        language: String = "en",
        regenerate: Bool = false  // If true, uses o1-mini for two-step reasoning
    ) async -> DiagramGenerationResponse {
        print("📊 ============================================")
        print("📊 === NETWORK SERVICE: GENERATE DIAGRAM ===")
        print("📊 ============================================")
        print("📊 Timestamp: \(Date())")
        print("📊 Session ID: \(sessionId)")
        print("📊 Subject: \(subject)")
        print("📊 Language: \(language)")
        print("📊 Regenerate mode: \(regenerate ? "YES (o1-mini)" : "NO (gpt-4o)")")
        print("📊 Request: \(diagramRequest)")
        print("📊 Conversation history length: \(conversationHistory.count)")

        // Check authentication first
        guard AuthenticationService.shared.getAuthToken() != nil else {
            print("❌ Authentication required to generate diagrams")
            return DiagramGenerationResponse(
                success: false,
                diagramType: nil,
                diagramCode: nil,
                diagramTitle: nil,
                explanation: nil,
                reasoning: nil,
                renderingHint: nil,
                processingTimeMs: nil,
                tokensUsed: nil,
                error: "Authentication required"
            )
        }

        let diagramURL = "\(baseURL)/api/ai/generate-diagram"
        guard let url = URL(string: diagramURL) else {
            print("❌ Invalid diagram generation URL")
            return DiagramGenerationResponse(
                success: false,
                diagramType: nil,
                diagramCode: nil,
                diagramTitle: nil,
                explanation: nil,
                reasoning: nil,
                renderingHint: nil,
                processingTimeMs: nil,
                tokensUsed: nil,
                error: "Invalid URL"
            )
        }

        let requestData = DiagramGenerationRequest(
            conversationHistory: conversationHistory,
            diagramRequest: diagramRequest,
            sessionId: sessionId,
            subject: subject,
            language: language,
            regenerate: regenerate  // Pass regenerate flag for model selection
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45.0 // Extended timeout for diagram generation

        // Add authentication header
        addAuthHeader(to: &request)

        do {
            request.httpBody = try JSONEncoder().encode(requestData)

            print("📊 Sending diagram generation request...")
            let startTime = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            let networkTime = Date().timeIntervalSince(startTime) * 1000

            if let httpResponse = response as? HTTPURLResponse {
                print("📊 HTTP Status Code: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 200 {
                    do {
                        let decodedResponse = try JSONDecoder().decode(DiagramGenerationResponse.self, from: data)

                        print("📊 ============================================")
                        print("📊 === AI RESPONSE ANALYSIS ===")
                        print("📊 ============================================")
                        print("📊 Diagram generation successful!")
                        print("📊 Type: \(decodedResponse.diagramType ?? "unknown")")
                        print("📊 Title: '\(decodedResponse.diagramTitle ?? "No title")'")
                        print("📊 Code length: \(decodedResponse.diagramCode?.count ?? 0) characters")
                        print("📊 Has explanation: \(decodedResponse.explanation != nil)")
                        if let explanation = decodedResponse.explanation {
                            print("📊 Explanation preview: '\(explanation.prefix(100))...'")
                        }
                        if let renderingHint = decodedResponse.renderingHint {
                            print("📊 Rendering hint: \(renderingHint.width)x\(renderingHint.height), bg=\(renderingHint.background), scale=\(renderingHint.scaleFactor ?? 1.0)")
                        }
                        print("📊 Processing time: \(decodedResponse.processingTimeMs ?? 0)ms")
                        print("📊 Tokens used: \(decodedResponse.tokensUsed ?? 0)")
                        print("📊 Network time: \(Int(networkTime))ms")

                        // Log the actual diagram code (truncated for readability)
                        if let diagramCode = decodedResponse.diagramCode {
                            print("📊 Diagram code preview:")
                            let preview = diagramCode.prefix(200)
                            print("📊 \(preview)\(diagramCode.count > 200 ? "..." : "")")
                        }
                        print("📊 ============================================")

                        return decodedResponse

                    } catch {
                        print("❌ Failed to decode diagram response: \(error)")

                        // Try to get error message from raw response
                        if let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errorMessage = jsonData["error"] as? String {
                            return DiagramGenerationResponse(
                                success: false,
                                diagramType: nil,
                                diagramCode: nil,
                                diagramTitle: nil,
                                explanation: nil,
                                reasoning: nil,
                                renderingHint: nil,
                                processingTimeMs: Int(networkTime),
                                tokensUsed: nil,
                                error: errorMessage
                            )
                        }

                        return DiagramGenerationResponse(
                            success: false,
                            diagramType: nil,
                            diagramCode: nil,
                            diagramTitle: nil,
                            explanation: nil,
                            reasoning: nil,
                            renderingHint: nil,
                            processingTimeMs: Int(networkTime),
                            tokensUsed: nil,
                            error: "Failed to parse response"
                        )
                    }
                } else {
                    print("❌ HTTP Error: \(httpResponse.statusCode)")

                    // Try to get error message from response body
                    if let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = jsonData["error"] as? String {
                        return DiagramGenerationResponse(
                            success: false,
                            diagramType: nil,
                            diagramCode: nil,
                            diagramTitle: nil,
                            explanation: nil,
                            reasoning: nil,
                            renderingHint: nil,
                            processingTimeMs: Int(networkTime),
                            tokensUsed: nil,
                            error: errorMessage
                        )
                    }

                    return DiagramGenerationResponse(
                        success: false,
                        diagramType: nil,
                        diagramCode: nil,
                        diagramTitle: nil,
                        explanation: nil,
                        reasoning: nil,
                        renderingHint: nil,
                        processingTimeMs: Int(networkTime),
                        tokensUsed: nil,
                        error: "HTTP \(httpResponse.statusCode)"
                    )
                }
            } else {
                print("❌ No HTTP response")
                return DiagramGenerationResponse(
                    success: false,
                    diagramType: nil,
                    diagramCode: nil,
                    diagramTitle: nil,
                    explanation: nil,
                    reasoning: nil,
                    renderingHint: nil,
                    processingTimeMs: Int(networkTime),
                    tokensUsed: nil,
                    error: "No response"
                )
            }

        } catch {
            print("❌ Diagram generation error: \(error.localizedDescription)")
            return DiagramGenerationResponse(
                success: false,
                diagramType: nil,
                diagramCode: nil,
                diagramTitle: nil,
                explanation: nil,
                reasoning: nil,
                renderingHint: nil,
                processingTimeMs: nil,
                tokensUsed: nil,
                error: error.localizedDescription
            )
        }
    }

    func startNewSession(subject: String) async -> (success: Bool, message: String) {
        let result = await createSession(subject: subject)
        return (result.success, result.message)
    }
    
    // MARK: - Enhanced Image Processing with Fallback Strategy
    func processImageWithQuestion(imageData: Data, question: String = "", subject: String = "general") async -> (success: Bool, result: [String: Any]?) {
        print("📷 === NEW CHAT IMAGE PROCESSING ===")
        print("📊 Original image size: \(imageData.count) bytes")
        print("❓ Question: \(question)")
        print("📚 Subject: \(subject)")
        
        // Apply aggressive compression for better performance
        let optimizedImageData = aggressivelyOptimizeImageData(imageData)
        print("🗜️ Optimized image size: \(optimizedImageData.count) bytes")
        
        // Use the new chat-image endpoint directly
        let chatImageURL = "\(baseURL)/api/ai/chat-image"
        print("🔗 Using new chat-image endpoint: \(chatImageURL)")
        
        guard let url = URL(string: chatImageURL) else {
            print("❌ Invalid chat-image URL")
            return (false, ["error": "Invalid URL"])
        }
        
        // Convert image to base64
        let base64Image = optimizedImageData.base64EncodedString()
        
        let requestData: [String: Any] = [
            "base64_image": base64Image,
            "prompt": question.isEmpty ? "What do you see in this image?" : question,
            "subject": subject,
            "student_id": "ios_user"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90.0 // Extended timeout for AI processing // 30 second timeout
        
        // Add authentication header
        addAuthHeader(to: &request)
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
            
            print("📡 Sending request to new chat-image endpoint...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Chat Image Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("🎉 === NEW CHAT IMAGE SUCCESS ===")
                        print("✅ Response: \(json)")
                        
                        // Extract the response in the expected format
                        if let success = json["success"] as? Bool, success,
                           let response = json["response"] as? String {
                            return (true, ["answer": response, "processing_method": "chat_image_endpoint"])
                        } else if let response = json["response"] as? String {
                            // Handle case where success field might be missing but response exists
                            return (true, ["answer": response, "processing_method": "chat_image_endpoint"])
                        } else {
                            print("⚠️ Unexpected response format: \(json)")
                            return (false, ["error": "Unexpected response format"])
                        }
                    } else {
                        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                        print("❌ Failed to parse JSON: \(rawResponse)")
                        return (false, ["error": "Invalid JSON response"])
                    }
                } else {
                    let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                    print("❌ HTTP \(httpResponse.statusCode): \(rawResponse)")
                    
                    // If the new endpoint fails, fall back to the working homework endpoint
                    print("🔄 Falling back to homework endpoint...")
                    return await fallbackToHomeworkEndpoint(imageData: optimizedImageData, question: question, subject: subject)
                }
            }
            
            return (false, ["error": "No HTTP response"])
        } catch {
            print("❌ Chat image request failed: \(error.localizedDescription)")
            
            // If network error, fall back to the working homework endpoint
            print("🔄 Network error, falling back to homework endpoint...")
            return await fallbackToHomeworkEndpoint(imageData: optimizedImageData, question: question, subject: subject)
        }
    }
    
    // MARK: - Fallback to Working Homework Endpoint
    private func fallbackToHomeworkEndpoint(imageData: Data, question: String, subject: String) async -> (success: Bool, result: [String: Any]?) {
        print("🔄 === FALLBACK TO HOMEWORK ENDPOINT ===")
        
        let homeworkURL = "\(baseURL)/api/ai/process-homework-image-json"
        print("🔗 Fallback URL: \(homeworkURL)")
        
        guard let url = URL(string: homeworkURL) else {
            return (false, ["error": "Invalid fallback URL"])
        }
        
        let base64Image = imageData.base64EncodedString()
        let requestData: [String: Any] = [
            "base64_image": base64Image,
            "prompt": question.isEmpty ? "Analyze this image and provide a detailed explanation." : question,
            "student_id": "ios_user"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90.0 // Extended timeout for AI processing
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
            
            print("📡 Sending fallback request...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Fallback Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let responseText = String(data: data, encoding: .utf8) {
                        print("✅ Fallback success with homework endpoint")
                        return (true, ["answer": responseText, "processing_method": "homework_endpoint_fallback"])
                    }
                } else {
                    let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                    print("❌ Fallback failed: HTTP \(httpResponse.statusCode): \(rawResponse)")
                }
            }
            
            return (false, ["error": "Fallback endpoint failed"])
        } catch {
            print("❌ Fallback request failed: \(error.localizedDescription)")
            return (false, ["error": "All endpoints failed: \(error.localizedDescription)"])
        }
    }
    
    // MARK: - Try Individual Image Processing Endpoint
    private func tryImageProcessingEndpoint(endpoint: String, imageData: Data, question: String, subject: String, isHomeworkEndpoint: Bool) async -> (success: Bool, result: [String: Any]?) {
        guard let url = URL(string: endpoint) else {
            return (false, ["error": "Invalid URL: \(endpoint)"])
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 45.0  // Reasonable timeout
            
            if isHomeworkEndpoint {
                // Use JSON format for homework endpoint
                let base64Image = imageData.base64EncodedString()
                let requestData: [String: Any] = [
                    "base64_image": base64Image,
                    "prompt": question.isEmpty ? "Analyze this image and provide a detailed explanation." : question,
                    "student_id": "ios_user"
                ]
                
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
            } else {
                // Use multipart form data for other endpoints
                let boundary = "StudyAI-Enhanced-\(UUID().uuidString)"
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                
                var formData = Data()
                
                // Add image data
                formData.append("--\(boundary)\r\n".data(using: .utf8)!)
                formData.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
                formData.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
                formData.append(imageData)
                formData.append("\r\n".data(using: .utf8)!)
                
                // Add question parameter
                if !question.isEmpty {
                    formData.append("--\(boundary)\r\n".data(using: .utf8)!)
                    formData.append("Content-Disposition: form-data; name=\"question\"\r\n\r\n".data(using: .utf8)!)
                    formData.append(question.data(using: .utf8)!)
                    formData.append("\r\n".data(using: .utf8)!)
                }
                
                // Add subject parameter
                formData.append("--\(boundary)\r\n".data(using: .utf8)!)
                formData.append("Content-Disposition: form-data; name=\"subject\"\r\n\r\n".data(using: .utf8)!)
                formData.append(subject.data(using: .utf8)!)
                formData.append("\r\n".data(using: .utf8)!)
                
                // Add student_id parameter
                formData.append("--\(boundary)\r\n".data(using: .utf8)!)
                formData.append("Content-Disposition: form-data; name=\"student_id\"\r\n\r\n".data(using: .utf8)!)
                formData.append("ios_user".data(using: .utf8)!)
                formData.append("\r\n".data(using: .utf8)!)
                
                // Close boundary
                formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
                
                request.httpBody = formData
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Response status: \(httpResponse.statusCode) from \(endpoint)")
                
                if httpResponse.statusCode == 200 {
                    if isHomeworkEndpoint {
                        // Handle homework endpoint response (text format)
                        if let responseText = String(data: data, encoding: .utf8) {
                            return (true, ["answer": responseText, "processing_method": "homework_endpoint"])
                        }
                    } else {
                        // Handle JSON response from other endpoints
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            // Extract answer from nested response structure
                            if let response = json["response"] as? [String: Any],
                               let answer = response["answer"] as? String {
                                return (true, ["answer": answer, "processing_method": "ai_endpoint"])
                            } else if let answer = json["answer"] as? String {
                                return (true, ["answer": answer, "processing_method": "direct_answer"])
                            } else {
                                return (true, json)
                            }
                        }
                    }
                } else {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("❌ HTTP \(httpResponse.statusCode): \(errorText)")
                    return (false, ["error": "HTTP \(httpResponse.statusCode)", "details": errorText])
                }
            }
            
            return (false, ["error": "No HTTP response"])
        } catch {
            print("❌ Request failed: \(error.localizedDescription)")
            return (false, ["error": error.localizedDescription])
        }
    }
    
    // MARK: - Aggressive Image Optimization
    private func aggressivelyOptimizeImageData(_ imageData: Data) -> Data {
        guard let image = UIImage(data: imageData) else {
            print("❌ Failed to create UIImage from data")
            return imageData
        }
        
        print("🖼️ Original image dimensions: \(image.size)")
        
        // Target: 1MB max, but prefer smaller for faster uploads
        let targetSize = 1024 * 1024 // 1MB
        var currentData = imageData
        
        // Detect original format
        let originalFormat = detectImageFormat(imageData)
        print("🔍 Detected original format: \(originalFormat)")
        
        // Step 1: Resize if image is too large
        let maxDimension: CGFloat = 1024
        var processedImage = image
        
        if image.size.width > maxDimension || image.size.height > maxDimension {
            let scale = maxDimension / max(image.size.width, image.size.height)
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            processedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
            
            print("📐 Resized to: \(newSize)")
        }
        
        // Step 2: Try to preserve original format first, then compress
        if originalFormat == "png" {
            // For PNG, try PNG compression first
            if let pngData = processedImage.pngData() {
                print("🖼️ PNG format preserved: \(pngData.count) bytes")
                if pngData.count <= targetSize {
                    return pngData
                }
                currentData = pngData
            }
        }
        
        // Step 3: If still too large or was JPEG, try JPEG compression
        let qualities: [CGFloat] = [0.9, 0.8, 0.6, 0.4, 0.3, 0.2]
        
        for quality in qualities {
            if let compressedData = processedImage.jpegData(compressionQuality: quality) {
                print("🗜️ JPEG Quality \(quality): \(compressedData.count) bytes")
                if compressedData.count <= targetSize {
                    currentData = compressedData
                    break
                }
                currentData = compressedData
            }
        }
        
        // Step 4: If JPEG is still too large, fallback to PNG (for better compatibility)
        if currentData.count > targetSize {
            if let pngData = processedImage.pngData() {
                print("🔄 Fallback to PNG: \(pngData.count) bytes")
                currentData = pngData
            }
        }
        
        print("✅ Final optimized size: \(currentData.count) bytes (\(String(format: "%.1f", Double(currentData.count) / Double(imageData.count) * 100))% of original)")
        
        return currentData
    }
    
    // Helper method to detect image format from data
    private func detectImageFormat(_ data: Data) -> String {
        guard data.count >= 8 else { return "unknown" }
        
        let bytes = data.prefix(8)
        let header = bytes.map { String(format: "%02x", $0) }.joined()
        
        if header.hasPrefix("89504e47") { // PNG signature
            return "png"
        } else if header.hasPrefix("ffd8ff") { // JPEG signature
            return "jpeg"
        } else if header.hasPrefix("47494638") { // GIF signature
            return "gif"
        } else if header.hasPrefix("52494646") { // WEBP signature (partial)
            return "webp"
        }
        
        return "unknown"
    }
    
    // MARK: - Enhanced Homework Parsing with Subject Detection
    
    /// Send homework image for AI-powered parsing with automatic subject detection
    func processHomeworkImageWithSubjectDetection(base64Image: String, prompt: String = "") async -> (success: Bool, response: String?) {
        guard let url = URL(string: "\(baseURL)/api/ai/process-homework-image-json") else {
            return (false, nil)
        }
        
        // Enhanced prompt that includes subject detection
        let enhancedPrompt = """
        Please analyze this homework image and provide:
        1. SUBJECT_DETECTION: Identify the academic subject (Mathematics, Physics, Chemistry, Biology, English, History, Geography, Computer Science, Foreign Language, Arts, or Other)
        2. CONFIDENCE_LEVEL: Your confidence in the subject detection (0.0-1.0)
        3. QUESTIONS_AND_ANSWERS: Extract and solve all questions as usual
        
        Format your response exactly as follows:
        SUBJECT: [detected subject]
        SUBJECT_CONFIDENCE: [0.0-1.0]
        
        Then continue with the normal question format using ═══QUESTION_SEPARATOR═══ between questions.
        
        Additional context: \(prompt.isEmpty ? "General homework analysis" : prompt)
        """
        
        let requestData: [String: Any] = [
            "base64_image": base64Image,
            "prompt": enhancedPrompt,
            "student_id": "ios_user",
            "include_subject_detection": true
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120.0 // Extended timeout for AI processing - prevents timeouts
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if let responseData = String(data: data, encoding: .utf8) {
                    if httpResponse.statusCode == 200 {
                        print("✅ Raw AI Response: \(String(responseData.prefix(200)))...")
                        return (true, responseData)
                    } else {
                        return (false, "HTTP \(httpResponse.statusCode): \(responseData)")
                    }
                } else {
                    return (false, "No response data")
                }
            } else {
                return (false, "No HTTP response")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Batch Homework Processing

    /// Process multiple homework images with batch API
    func processHomeworkImagesBatch(base64Images: [String], prompt: String = "", subject: String? = nil, parsingMode: String = "hierarchical", modelProvider: String = "openai") async -> (success: Bool, responses: [[String: Any]]?, totalImages: Int, successCount: Int) {
        guard let url = URL(string: "\(baseURL)/api/ai/process-homework-images-batch") else {
            return (false, nil, base64Images.count, 0)
        }

        // Enhanced prompt for batch processing with optional subject
        var enhancedPrompt = ""
        if let selectedSubject = subject {
            enhancedPrompt = """
            SUBJECT: \(selectedSubject)
            The user has indicated this homework is for \(selectedSubject). Please grade accordingly using subject-specific criteria.

            Please analyze this \(selectedSubject) homework and provide:
            1. Grade all questions using \(selectedSubject)-specific grading standards
            2. Extract and solve all questions
            3. Provide detailed feedback (up to 30 words per question)

            Format your response exactly as follows using ═══QUESTION_SEPARATOR═══ between questions.

            Additional context: \(prompt.isEmpty ? "General homework analysis" : prompt)
            """
        } else {
            enhancedPrompt = """
            Please analyze this homework image and provide:
            1. SUBJECT_DETECTION: Identify the academic subject (Mathematics, Physics, Chemistry, Biology, English, History, Geography, Computer Science, Foreign Language, Arts, or Other)
            2. CONFIDENCE_LEVEL: Your confidence in the subject detection (0.0-1.0)
            3. QUESTIONS_AND_ANSWERS: Extract and solve all questions as usual

            Format your response exactly as follows:
            SUBJECT: [detected subject]
            SUBJECT_CONFIDENCE: [0.0-1.0]

            Then continue with the normal question format using ═══QUESTION_SEPARATOR═══ between questions.

            Additional context: \(prompt.isEmpty ? "General homework analysis" : prompt)
            """
        }

        var requestData: [String: Any] = [
            "base64_images": base64Images,
            "prompt": enhancedPrompt,
            "student_id": "ios_user",
            "include_subject_detection": true,
            "parsing_mode": parsingMode,  // Pass parsing mode to backend
            "model_provider": modelProvider  // NEW: Pass AI model selection (OpenAI/Gemini)
        ]

        // Add subject if provided by user
        if let selectedSubject = subject {
            requestData["subject"] = selectedSubject
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Dynamic timeout based on parsing mode
        // Hierarchical: 5 minutes (more complex parsing)
        // Baseline: 3 minutes (faster flat parsing)
        request.timeoutInterval = parsingMode == "hierarchical" ? 300.0 : 180.0

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                // Track rate limits for batch processing
                RateLimitManager.shared.updateFromHeaders(httpResponse, endpoint: .batchImage)

                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("✅ Raw AI Response: \(json)")

                        let totalImages = json["totalImages"] as? Int ?? base64Images.count
                        let successfulImages = json["successfulImages"] as? Int ?? 0
                        let results = json["results"] as? [[String: Any]] ?? []

                        return (true, results, totalImages, successfulImages)
                    } else {
                        return (false, nil, base64Images.count, 0)
                    }
                } else {
                    return (false, nil, base64Images.count, 0)
                }
            } else {
                return (false, nil, base64Images.count, 0)
            }
        } catch {
            return (false, nil, base64Images.count, 0)
        }
    }

    // MARK: - Homework Parsing (Original)
    
    /// Send homework image for AI-powered parsing and question extraction
    func processHomeworkImage(base64Image: String, prompt: String) async -> (success: Bool, response: String?) {
        print("📝 Processing homework for AI parsing...")
        print("📄 Base64 Image Length: \(base64Image.count) characters")
        print("🤖 Using structured AI parsing with deterministic format")
        
        guard let url = URL(string: "\(baseURL)/api/ai/process-homework-image-json") else {
            print("❌ Invalid homework parsing URL")
            return (false, nil)
        }
        
        let requestData: [String: Any] = [
            "base64_image": base64Image,
            "prompt": prompt.isEmpty ? "" : prompt,
            "student_id": "ios_user"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120.0 // Extended timeout for AI processing - prevents timeouts
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
            
            print("📡 Sending homework to AI engine for structured parsing...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Homework Parsing Response Status: \(httpResponse.statusCode)")

                // Track rate limits
                RateLimitManager.shared.updateFromHeaders(httpResponse, endpoint: .homeworkImage)

                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("🎉 === HOMEWORK PARSING SUCCESS ===")
                        
                        // Check if parsing was successful
                        if let success = json["success"] as? Bool, success {
                            if let structuredResponse = json["response"] as? String {
                                print("📈 Structured Response Length: \(structuredResponse.count) characters")
                                print("🔍 Response Preview: \(String(structuredResponse.prefix(200)))")
                                
                                // Verify the response has the expected format
                                if structuredResponse.contains("═══QUESTION_SEPARATOR═══") {
                                    print("✅ Structured format verified")
                                    return (true, structuredResponse)
                                } else {
                                    print("⚠️ Response lacks expected structure, but proceeding...")
                                    return (true, structuredResponse)
                                }
                            } else {
                                print("⚠️ No response field in successful result")
                                return (false, "AI parsing succeeded but no response content")
                            }
                        } else {
                            // Handle error case from AI engine
                            let errorMessage = json["error"] as? String ?? "Unknown parsing error"
                            print("❌ AI Engine Error: \(errorMessage)")
                            return (false, errorMessage)
                        }
                    } else {
                        print("❌ Failed to parse JSON response")
                        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                        return (false, "Invalid JSON: \(rawResponse)")
                    }
                } else {
                    let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                    print("❌ Homework Parsing HTTP \(httpResponse.statusCode): \(String(rawResponse.prefix(200)))")
                    return (false, "HTTP \(httpResponse.statusCode): \(rawResponse)")
                }
            } else {
                print("❌ No HTTP response for homework parsing")
                return (false, "No HTTP response")
            }
        } catch {
            print("❌ Homework parsing failed: \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Progressive Homework Grading (New System)

    /// Parse homework questions with normalized image coordinates (Phase 1)
    /// Returns parsed questions with image region coordinates [0-1]
    func parseHomeworkQuestions(
        base64Image: String,
        parsingMode: String = "standard",
        skipBboxDetection: Bool = false,
        expectedQuestions: [Int]? = nil,
        modelProvider: String = "openai",  // NEW: AI model selection (openai/gemini)
        subject: String? = nil  // NEW: Subject-specific parsing rules (Math, Physics, etc.)
    ) async throws -> ParseHomeworkQuestionsResponse {
        print("📝 === PHASE 1: PARSING HOMEWORK QUESTIONS ===")
        print("🔧 Mode: \(parsingMode)")
        print("🤖 AI Model: \(modelProvider)")
        if let subj = subject {
            print("📚 Subject: \(subj)")
        }
        print("📄 Image size: \(base64Image.count) characters")
        if skipBboxDetection {
            print("🎨 Pro Mode: Skip bbox detection, expected questions: \(expectedQuestions?.count ?? 0)")
        }

        guard let url = URL(string: "\(baseURL)/api/ai/parse-homework-questions") else {
            throw NetworkError.invalidURL
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180.0  // 3 minutes for parsing ALL questions (Pro Mode)

        // Add auth token if available
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var requestData: [String: Any] = [
            "base64_image": base64Image,
            "parsing_mode": parsingMode,
            "model_provider": modelProvider  // NEW: Pass selected AI model
        ]

        // Add Pro Mode parameters if provided
        if skipBboxDetection {
            requestData["skip_bbox_detection"] = true
        }
        if let questions = expectedQuestions {
            requestData["expected_questions"] = questions
        }

        // Add subject if provided
        if let subj = subject {
            requestData["subject"] = subj
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

        print("📡 Sending to backend for question parsing...")
        let startTime = Date()

        let (data, response) = try await URLSession.shared.data(for: request)

        let duration = Date().timeIntervalSince(startTime)
        print("⏱️ Parsing completed in \(String(format: "%.1f", duration))s")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        print("📊 Response status: \(httpResponse.statusCode)")

        // Track rate limits
        RateLimitManager.shared.updateFromHeaders(httpResponse, endpoint: .homeworkImage)

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 429 {
                throw NetworkError.rateLimited
            }
            throw NetworkError.serverError(httpResponse.statusCode)
        }

        // ========================================
        // 🔍 RAW RESPONSE LOGGING - PHASE 1
        // ========================================
        print("\n" + String(repeating: "=", count: 80))
        print("🔍 === RAW AI ENGINE RESPONSE - PHASE 1 (PARSING) ===")
        print(String(repeating: "=", count: 80))

        // Log raw JSON response
        if let rawJSON = String(data: data, encoding: .utf8) {
            print("\n📄 RAW JSON RESPONSE:")
            print(String(repeating: "-", count: 80))

            // Try to pretty-print JSON
            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
               let prettyJSON = String(data: prettyData, encoding: .utf8) {
                print(prettyJSON)
            } else {
                // Fallback to raw JSON if pretty-print fails
                print(rawJSON)
            }
            print(String(repeating: "-", count: 80))

            // Log data size
            let jsonSizeKB = Double(data.count) / 1024.0
            print("\n📊 Response Size: \(String(format: "%.2f", jsonSizeKB)) KB")
            print("⏱️ Processing Time: \(String(format: "%.1f", duration))s")
        } else {
            print("⚠️ WARNING: Unable to decode raw response as UTF-8 string")
            print("Data size: \(data.count) bytes")
        }

        print(String(repeating: "=", count: 80) + "\n")
        // ========================================

        // Decode response
        let decoder = JSONDecoder()
        let parseResponse = try decoder.decode(ParseHomeworkQuestionsResponse.self, from: data)

        // 🔍 DEBUG: Log handwriting evaluation specifically
        print("\n" + String(repeating: "=", count: 80))
        print("🔍 [HANDWRITING DEBUG - iOS NetworkService]")
        print(String(repeating: "=", count: 80))
        if let handwriting = parseResponse.handwritingEvaluation {
            print("✅ Handwriting Evaluation RECEIVED from backend:")
            print("   - has_handwriting: \(handwriting.hasHandwriting)")
            print("   - score: \(handwriting.score ?? -1)")
            print("   - feedback: \(handwriting.feedback ?? "N/A")")
        } else {
            print("⚠️ NO handwriting_evaluation in parseResponse")
            print("   Available response keys: subject, subjectConfidence, totalQuestions, questions, processingTimeMs, error")
        }
        print(String(repeating: "=", count: 80) + "\n")

        print("✅ === PHASE 1 COMPLETE ===")
        print("📚 Subject: \(parseResponse.subject) (confidence: \(parseResponse.subjectConfidence))")
        print("📊 Questions found: \(parseResponse.totalQuestions)")
        print("🖼️ Questions with images: \(parseResponse.questions.filter { $0.hasImage == true }.count)")

        return parseResponse
    }

    /// Parse multiple homework images (Phase 1 - Batch) - Use when 2+ pages
    /// This is more efficient than calling parseHomeworkQuestions multiple times
    func parseHomeworkQuestionsBatch(
        base64Images: [String],
        parsingMode: String = "standard",
        modelProvider: String = "openai",
        subject: String? = nil
    ) async throws -> ParseHomeworkQuestionsResponse {
        guard base64Images.count >= 2 else {
            throw NetworkError.invalidData
        }

        print("📝 === PHASE 1: BATCH PARSING (\(base64Images.count) PAGES) ===")
        print("🔧 Mode: \(parsingMode)")
        print("🤖 AI Model: \(modelProvider)")
        if let subj = subject {
            print("📚 Subject: \(subj)")
        }

        guard let url = URL(string: "\(baseURL)/api/ai/parse-homework-questions-batch") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300.0  // 5 minutes for batch parsing (multiple images)

        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var requestData: [String: Any] = [
            "base64_images": base64Images,
            "parsing_mode": parsingMode,
            "model_provider": modelProvider
        ]

        if let subj = subject {
            requestData["subject"] = subj
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

        print("📡 Sending batch request to backend...")
        let startTime = Date()

        let (data, response) = try await URLSession.shared.data(for: request)

        let duration = Date().timeIntervalSince(startTime)
        print("⏱️ Batch parsing completed in \(String(format: "%.1f", duration))s")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        print("📊 Response status: \(httpResponse.statusCode)")

        // Track rate limits
        RateLimitManager.shared.updateFromHeaders(httpResponse, endpoint: .homeworkImage)

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 429 {
                throw NetworkError.rateLimited
            }
            throw NetworkError.serverError(httpResponse.statusCode)
        }

        // Log raw response for debugging
        if let rawJSON = String(data: data, encoding: .utf8) {
            print("\n" + String(repeating: "=", count: 80))
            print("🔍 === RAW BATCH PARSING RESPONSE ===")
            print(String(repeating: "=", count: 80))

            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
               let prettyJSON = String(data: prettyData, encoding: .utf8) {
                print(prettyJSON)
            } else {
                print(rawJSON)
            }

            let jsonSizeKB = Double(data.count) / 1024.0
            print("\n📊 Response Size: \(String(format: "%.2f", jsonSizeKB)) KB")
            print("⏱️ Processing Time: \(String(format: "%.1f", duration))s")
            print(String(repeating: "=", count: 80) + "\n")
        }

        // Decode response
        let decoder = JSONDecoder()
        let parseResponse = try decoder.decode(ParseHomeworkQuestionsResponse.self, from: data)

        print("✅ === BATCH PARSING COMPLETE ===")
        print("📚 Subject: \(parseResponse.subject) (confidence: \(parseResponse.subjectConfidence))")
        print("📊 Total questions: \(parseResponse.totalQuestions) from \(base64Images.count) pages")
        print("🖼️ Questions with page numbers: \(parseResponse.questions.filter { $0.pageNumber != nil }.count)")

        return parseResponse
    }

    /// Grade a single question (Phase 2)
    /// Uses gpt-4o-mini for fast, low-cost grading or Gemini Thinking for deep reasoning
    func gradeSingleQuestion(
        questionText: String,
        studentAnswer: String,
        subject: String?,
        questionType: String? = nil,  // NEW: Question type for specialized grading (e.g., "multiple_choice", "calculation")
        contextImageBase64: String? = nil,
        parentQuestionContent: String? = nil,  // NEW: Parent question context for subquestions
        useDeepReasoning: Bool = false,
        modelProvider: String = "gemini"  // NEW: "openai" or "gemini"
    ) async throws -> GradeSingleQuestionResponse {

        guard let url = URL(string: "\(baseURL)/api/ai/grade-question") else {
            throw NetworkError.invalidURL
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Increase timeout for grading - Pro Mode needs sufficient time
        // Standard: 90s (gemini-2.5-flash: 1.5-3s/question + network latency)
        // Deep reasoning: 120s (extended thinking mode)
        request.timeoutInterval = useDeepReasoning ? 120.0 : 90.0

        // Add auth token if available
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build request data (exclude nil values)
        var requestData: [String: Any] = [
            "question_text": questionText,
            "student_answer": studentAnswer,
            "model_provider": modelProvider,  // NEW: Pass AI model selection (openai/gemini)
            "use_deep_reasoning": useDeepReasoning  // Pass deep reasoning flag
        ]

        if let subject = subject {
            requestData["subject"] = subject
        }

        if let questionType = questionType {
            requestData["question_type"] = questionType  // NEW: Pass question type for specialized grading
        }

        if let contextImage = contextImageBase64 {
            requestData["context_image_base64"] = contextImage
        }

        if let parentContent = parentQuestionContent {
            requestData["parent_question_content"] = parentContent
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 429 {
                throw NetworkError.rateLimited
            }
            throw NetworkError.serverError(httpResponse.statusCode)
        }

        // ========================================
        // 🔍 RAW RESPONSE LOGGING - PHASE 2
        // ========================================
        print("\n" + String(repeating: "=", count: 80))
        print("🔍 === RAW AI ENGINE RESPONSE - PHASE 2 (GRADING) ===")
        print(String(repeating: "=", count: 80))

        // Log raw JSON response
        if let rawJSON = String(data: data, encoding: .utf8) {
            print("\n📄 RAW JSON RESPONSE:")
            print(String(repeating: "-", count: 80))

            // Try to pretty-print JSON
            if let jsonObject = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
               let prettyJSON = String(data: prettyData, encoding: .utf8) {
                print(prettyJSON)
            } else {
                // Fallback to raw JSON if pretty-print fails
                print(rawJSON)
            }
            print(String(repeating: "-", count: 80))

            // Log data size
            let jsonSizeKB = Double(data.count) / 1024.0
            print("\n📊 Response Size: \(String(format: "%.2f", jsonSizeKB)) KB")
        } else {
            print("⚠️ WARNING: Unable to decode raw response as UTF-8 string")
            print("Data size: \(data.count) bytes")
        }

        print(String(repeating: "=", count: 80) + "\n")
        // ========================================

        // Decode response
        let decoder = JSONDecoder()
        let gradeResponse = try decoder.decode(GradeSingleQuestionResponse.self, from: data)

        // 🔍 DEBUG: Log decoded grade response structure
        print("\n" + String(repeating: "=", count: 80))
        print("🔍 === DECODED GRADE RESPONSE (NetworkService) ===")
        print(String(repeating: "=", count: 80))
        print("📊 Success: \(gradeResponse.success)")
        if let grade = gradeResponse.grade {
            print("✅ Grade Object Present:")
            print("   - score: \(grade.score)")
            print("   - isCorrect: \(grade.isCorrect)")
            print("   - feedback: '\(grade.feedback)'")
            print("   - confidence: \(grade.confidence)")
            print("   - correctAnswer: '\(grade.correctAnswer ?? "NIL")'")  // ✅ CRITICAL: Log correctAnswer
            print("   - feedback length: \(grade.feedback.count) chars")
            print("   - feedback empty: \(grade.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")

            // ✅ CRITICAL: Additional correctAnswer validation
            if let correctAnswer = grade.correctAnswer {
                print("   - correctAnswer present: YES (\(correctAnswer.count) chars)")
                print("   - correctAnswer preview: '\(correctAnswer.prefix(100))...'")
            } else {
                print("   - ⚠️  WARNING: correctAnswer is NIL! Backend may not be returning this field!")
            }
        } else {
            print("❌ Grade Object is NIL")
        }
        if let error = gradeResponse.error {
            print("⚠️ Error: \(error)")
        }
        print(String(repeating: "=", count: 80) + "\n")

        return gradeResponse
    }
    
    // MARK: - Registration
    func register(name: String, email: String, password: String) async -> (success: Bool, message: String, token: String?, userData: [String: Any]?, statusCode: Int?) {
        print("📝 Testing registration functionality...")
        
        let registerURL = "\(baseURL)/api/auth/register"
        print("🔗 Using Railway backend for registration")
        
        guard let url = URL(string: registerURL) else {
            return (false, "Invalid URL", nil, nil, nil)
        }
        
        let registerData = [
            "name": name,
            "email": email,
            "password": password
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: registerData)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                print("✅ Registration Status: \(statusCode)")
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ Registration Response: \(json)")
                    
                    if statusCode == 201 {  // 201 Created for successful registration
                        let token = json["token"] as? String
                        let userData = json["user"] as? [String: Any] ?? json  // Try 'user' key first, fallback to full response
                        print("🔍 Registration - Extracted user data: \(userData)")
                        // NOTE: Do not save auth data here - AuthenticationService will handle it
                        return (true, "Registration successful", token, userData, statusCode)
                    } else {
                        let message = json["message"] as? String ?? "Registration failed"
                        return (false, message, nil, nil, statusCode)
                    }
                }
            }
            
            return (false, "Invalid response", nil, nil, nil)
        } catch {
            let errorMsg = "Registration request failed: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (false, errorMsg, nil, nil, nil)
        }
    }

    // MARK: - Email Verification

    /// Send verification code to user's email during registration
    func sendVerificationCode(email: String, name: String) async -> (success: Bool, message: String, expiresIn: Int?, statusCode: Int?) {
        print("📧 Sending verification code to: \(email)")

        let verificationURL = "\(baseURL)/api/auth/send-verification-code"

        guard let url = URL(string: verificationURL) else {
            return (false, "Invalid URL", nil, nil)
        }

        let requestData = [
            "email": email,
            "name": name
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0  // Increased timeout for email sending

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                print("📧 Verification code send status: \(statusCode)")

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("📧 Response: \(json)")

                    if statusCode == 200 {
                        let message = json["message"] as? String ?? "Verification code sent"
                        let expiresIn = json["expiresIn"] as? Int ?? 600
                        return (true, message, expiresIn, statusCode)
                    } else {
                        let message = json["message"] as? String ?? "Failed to send verification code"
                        return (false, message, nil, statusCode)
                    }
                }
            }

            return (false, "Invalid response", nil, nil)
        } catch {
            let errorMsg = "Failed to send verification code: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (false, errorMsg, nil, nil)
        }
    }

    /// Verify email with code and complete registration
    func verifyEmailCode(email: String, code: String, name: String, password: String) async -> (success: Bool, message: String, token: String?, userData: [String: Any]?, statusCode: Int?) {
        print("✅ Verifying email code for: \(email)")

        let verifyURL = "\(baseURL)/api/auth/verify-email"

        guard let url = URL(string: verifyURL) else {
            return (false, "Invalid URL", nil, nil, nil)
        }

        let requestData = [
            "email": email,
            "code": code,
            "name": name,
            "password": password
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0  // Increased timeout for email verification

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                print("✅ Email verification status: \(statusCode)")

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ Verification Response: \(json)")

                    // Backend returns 201 (Created) for successful verification
                    if statusCode == 200 || statusCode == 201 {
                        let token = json["token"] as? String
                        let userData = json["user"] as? [String: Any] ?? json
                        let message = json["message"] as? String ?? "Email verified successfully"
                        return (true, message, token, userData, statusCode)
                    } else {
                        let message = json["message"] as? String ?? "Email verification failed"
                        return (false, message, nil, nil, statusCode)
                    }
                }
            }

            return (false, "Invalid response", nil, nil, nil)
        } catch {
            let errorMsg = "Email verification request failed: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (false, errorMsg, nil, nil, nil)
        }
    }

    /// Resend verification code to user's email
    func resendVerificationCode(email: String) async -> (success: Bool, message: String, expiresIn: Int?, statusCode: Int?) {
        print("🔄 Resending verification code to: \(email)")

        let resendURL = "\(baseURL)/api/auth/resend-verification-code"

        guard let url = URL(string: resendURL) else {
            return (false, "Invalid URL", nil, nil)
        }

        let requestData = [
            "email": email
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0  // Increased timeout for email verification

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                print("🔄 Resend verification status: \(statusCode)")

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("🔄 Response: \(json)")

                    if statusCode == 200 {
                        let message = json["message"] as? String ?? "Verification code resent"
                        let expiresIn = json["expiresIn"] as? Int ?? 600
                        return (true, message, expiresIn, statusCode)
                    } else {
                        let message = json["message"] as? String ?? "Failed to resend verification code"
                        return (false, message, nil, statusCode)
                    }
                }
            }

            return (false, "Invalid response", nil, nil)
        } catch {
            let errorMsg = "Failed to resend verification code: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (false, errorMsg, nil, nil)
        }
    }

    // MARK: - Google Authentication
    func googleLogin(idToken: String, accessToken: String?, name: String, email: String, profileImageUrl: String?) async -> (success: Bool, message: String, token: String?, userData: [String: Any]?, statusCode: Int?) {
        print("🔐 Google authentication with Railway backend...")
        
        let googleURL = "\(baseURL)/api/auth/google"
        print("🔗 Using Railway backend for Google auth")
        
        guard let url = URL(string: googleURL) else {
            return (false, "Invalid URL", nil, nil, nil)
        }
        
        let googleData: [String: Any] = [
            "idToken": idToken,
            "accessToken": accessToken ?? "",
            "name": name,
            "email": email,
            "profileImageUrl": profileImageUrl ?? ""
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: googleData)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Google Auth Status: \(httpResponse.statusCode)")
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        print("✅ Google Auth Response: \(json)")
                        
                        let success = json["success"] as? Bool ?? false
                        let message = json["message"] as? String ?? "Unknown error"
                        let token = json["token"] as? String
                        let userData = json["user"] as? [String: Any] ?? json  // Try 'user' key first, fallback to full response
                        print("🔍 Google Auth - Extracted user data: \(userData)")
                        
                        // NOTE: Do not save auth data here - AuthenticationService will handle it
                        return (success, message, token, userData, httpResponse.statusCode)
                    }
                } catch {
                    print("❌ JSON parsing error: \(error)")
                }
            }
            
        } catch {
            print("❌ Network error: \(error)")
            return (false, "Network error: \(error.localizedDescription)", nil, nil, nil)
        }
        
        return (false, "Unknown error", nil, nil, nil)
    }

    // MARK: - Apple Authentication
    func appleLogin(identityToken: String, authorizationCode: String?, userIdentifier: String, name: String, email: String) async -> (success: Bool, message: String, token: String?, userData: [String: Any]?, statusCode: Int?) {
        print("🍏 === NetworkService.appleLogin() STARTED ===")
        print("🍏 Request details:")
        print("   - Identity Token: \(identityToken.isEmpty ? "❌ EMPTY" : "✅ \(identityToken.prefix(20))...")")
        print("   - Auth Code: \(authorizationCode?.isEmpty ?? true ? "❌ EMPTY/NIL" : "✅ \(authorizationCode!.prefix(20))...")")
        print("   - User Identifier: \(userIdentifier)")
        print("   - Name: \(name)")
        print("   - Email: \(email)")

        let appleURL = "\(baseURL)/api/auth/apple"
        print("🍏 Backend URL: \(appleURL)")

        guard let url = URL(string: appleURL) else {
            print("🍏 ❌ Invalid URL")
            return (false, "Invalid URL", nil, nil, nil)
        }

        let appleData: [String: Any] = [
            "identityToken": identityToken,
            "authorizationCode": authorizationCode ?? "",
            "userIdentifier": userIdentifier,
            "name": name,
            "email": email
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: appleData)
            print("🍏 Sending request to backend...")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("🍏 Backend Response Status: \(httpResponse.statusCode)")

                // Log raw response for debugging
                if let rawResponse = String(data: data, encoding: .utf8) {
                    print("🍏 Raw Response (first 500 chars): \(rawResponse.prefix(500))")
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        print("🍏 Parsed JSON Response:")
                        print("   - Success: \(json["success"] as? Bool ?? false)")
                        print("   - Message: \(json["message"] as? String ?? "No message")")
                        print("   - Token present: \(json["token"] != nil)")
                        print("   - User data present: \(json["user"] != nil)")

                        let success = json["success"] as? Bool ?? false
                        let message = json["message"] as? String ?? "Unknown error"
                        let token = json["token"] as? String
                        let userData = json["user"] as? [String: Any] ?? json

                        if let token = token {
                            print("🍏 ✅ Token received (first 30 chars): \(token.prefix(30))...")
                        } else {
                            print("🍏 ❌ No token in response")
                        }

                        if let userData = json["user"] as? [String: Any] {
                            print("🍏 User data keys: \(userData.keys.sorted())")
                        }

                        print("🍏 === NetworkService.appleLogin() COMPLETED ===")
                        return (success, message, token, userData, httpResponse.statusCode)
                    } else {
                        print("🍏 ❌ Failed to parse JSON")
                    }
                } catch {
                    print("🍏 ❌ JSON parsing error: \(error)")
                }
            } else {
                print("🍏 ❌ Invalid HTTP response")
            }

        } catch {
            print("🍏 ❌ Network error: \(error)")
            return (false, "Network error: \(error.localizedDescription)", nil, nil, nil)
        }

        print("🍏 ❌ === NetworkService.appleLogin() FAILED - Unknown error ===")
        return (false, "Unknown error", nil, nil, nil)
    }

    // MARK: - Token Refresh (Phase 2.5)

    /// Refresh authentication token before expiration
    func refreshAuthToken(_ oldToken: String) async -> (success: Bool, message: String, token: String?) {
        print("🔄 === TOKEN REFRESH STARTED ===")
        print("🔄 Old Token (first 20 chars): \(oldToken.prefix(20))...")

        let refreshURL = "\(baseURL)/api/auth/refresh"
        guard let url = URL(string: refreshURL) else {
            print("🔄 ❌ Invalid refresh URL")
            return (false, "Invalid URL", nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let refreshData: [String: Any] = ["token": oldToken]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: refreshData)
            print("🔄 Sending refresh request to backend...")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("🔄 Response Status: \(httpResponse.statusCode)")

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let success = json["success"] as? Bool ?? false
                    let message = json["message"] as? String ?? "Unknown error"
                    let newToken = json["token"] as? String

                    if success, let newToken = newToken {
                        print("🔄 ✅ Token refreshed successfully (first 20 chars): \(newToken.prefix(20))...")
                        return (true, "Token refreshed", newToken)
                    } else {
                        print("🔄 ❌ Refresh failed: \(message)")
                        return (false, message, nil)
                    }
                }
            }
        } catch {
            print("🔄 ❌ Network error: \(error.localizedDescription)")
            return (false, "Network error: \(error.localizedDescription)", nil)
        }

        print("🔄 ❌ Token refresh failed - unknown error")
        return (false, "Unknown error", nil)
    }

    // MARK: - Session Archive Management
    
    /// Archive a session conversation to LOCAL storage only (with image processing)
    func archiveSession(sessionId: String, title: String? = nil, topic: String? = nil, subject: String? = nil, notes: String? = nil, diagrams: [String: DiagramGenerationResponse]? = nil) async -> (success: Bool, message: String, conversation: [String: Any]?) {
        print("📦 === ARCHIVE CONVERSATION SESSION ===")
        print("📁 Session ID: \(sessionId)")
        print("📝 Title: \(title ?? "Auto-generated")")
        print("🏷️ Topic: \(topic ?? "Auto-generated from subject")")
        print("📚 Subject: \(subject ?? "General")")
        print("💭 Notes: \(notes ?? "None")")

        // ✅ STEP 1: Try to call backend for AI-generated summary and behavior analysis
        let backendResult = await archiveSessionToBackend(
            sessionId: sessionId,
            title: title,
            topic: topic,
            subject: subject,
            notes: notes
        )

        // ✅ STEP 2: Process conversation to handle images
        let processedConversation = await processConversationForArchive()
        print("🔍 Processed conversation: \(processedConversation.messageCount) messages")
        print("📷 Images processed: \(processedConversation.imagesProcessed)")
        if processedConversation.imagesProcessed > 0 {
            print("📝 Image summaries created: \(processedConversation.imageSummariesCreated)")
        }

        // ✅ STEP 3: Generate local UUID for conversation
        let conversationId = UUID().uuidString

        // ✅ STEP 4: Build conversation data with backend summary if available
        var conversationData: [String: Any] = [
            "id": conversationId,
            "subject": subject ?? "General",
            "topic": topic ?? (subject ?? "General Discussion"),
            "conversationContent": processedConversation.textContent,
            "archivedDate": ISO8601DateFormatter().string(from: Date()),
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "messageCount": processedConversation.messageCount,
            "hasImageSummaries": processedConversation.imagesProcessed > 0,
            "imageCount": processedConversation.imagesProcessed
        ]

        // ✅ STEP 5: Add AI-generated summary if backend call succeeded
        if backendResult.success, let summary = backendResult.summary {
            conversationData["summary"] = summary
            print("✨ Added AI-generated summary: \(summary.prefix(100))...")
        } else {
            print("⚠️ No AI summary available (backend call failed or not authenticated)")
        }

        // ✅ STEP 6: Add behavior insights if available
        if let behaviorInsights = backendResult.behaviorInsights {
            conversationData["behaviorSummary"] = behaviorInsights
            if let hasRedFlags = behaviorInsights["hasRedFlags"] as? Bool, hasRedFlags {
                print("🚨 Conversation has red flags detected")
            }
        }

        // ✅ NEW: Save diagram data for retrieval in library
        if let diagrams = diagrams, !diagrams.isEmpty {
            var diagramsArray: [[String: Any]] = []

            for (key, diagramResponse) in diagrams {
                var diagramDict: [String: Any] = [
                    "key": key,
                    "type": diagramResponse.diagramType ?? "svg",
                    "code": diagramResponse.diagramCode ?? "",
                    "title": diagramResponse.diagramTitle ?? "Diagram",
                    "explanation": diagramResponse.explanation ?? ""
                ]

                if let hint = diagramResponse.renderingHint {
                    diagramDict["width"] = hint.width
                    diagramDict["height"] = hint.height
                    diagramDict["background"] = hint.background
                }

                diagramsArray.append(diagramDict)
            }

            conversationData["diagrams"] = diagramsArray
            conversationData["diagramCount"] = diagramsArray.count
            print("📊 Saved \(diagramsArray.count) diagram(s) to archive")
        }

        // Add title
        if let title = title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            conversationData["title"] = title
        } else {
            // Generate auto title based on subject and date
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            conversationData["title"] = "\(subject ?? "Study") Session - \(dateFormatter.string(from: Date()))"
        }

        // Add notes
        if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            conversationData["notes"] = notes
        }

        // Add image summary note if applicable
        if processedConversation.imagesProcessed > 0 {
            let enhancedNotes = """
            \(notes ?? "")

            📸 Session contained \(processedConversation.imagesProcessed) image(s) that were converted to text summaries for storage.
            """
            conversationData["notes"] = enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        print("💾 Built conversation data for local storage:")
        print("   - ID: \(conversationId)")
        print("   - Title: \(conversationData["title"] ?? "N/A")")
        print("   - Subject: \(conversationData["subject"] ?? "N/A")")
        print("   - Topic: \(conversationData["topic"] ?? "N/A")")
        print("   - Message count: \(processedConversation.messageCount)")

        // ✅ Save to local storage with backend summary (if available)
        ConversationLocalStorage.shared.saveConversation(conversationData)

        let hasSummary = conversationData["summary"] != nil
        let summaryStatus = hasSummary ? "with AI summary" : "without AI summary (offline mode)"

        print("✅ [Archive] Saved conversation to local storage (ID: \(conversationId))")
        print("   📝 Summary: \(summaryStatus)")
        print("   💬 Messages: \(processedConversation.messageCount)")

        // Invalidate cache so fresh data is loaded
        invalidateCache()

        let message = hasSummary
            ? "Session archived with \(processedConversation.messageCount) messages and AI summary"
            : "Session archived locally with \(processedConversation.messageCount) messages (offline mode)"

        return (true, message, conversationData)
    }

    // MARK: - Backend Archive with Summary & Behavior Analysis (NEW)

    /// Archive session to backend and receive AI-generated summary + behavior insights
    /// Returns: (success, summary, behaviorInsights, message)
    func archiveSessionToBackend(
        sessionId: String,
        title: String? = nil,
        topic: String? = nil,
        subject: String? = nil,
        notes: String? = nil
    ) async -> (success: Bool, summary: String?, behaviorInsights: [String: Any]?, message: String) {

        // Check authentication
        guard AuthenticationService.shared.getAuthToken() != nil else {
            print("❌ Authentication required to archive session")
            return (false, nil, nil, "Authentication required")
        }

        print("📦 === ARCHIVING SESSION TO BACKEND ===")
        print("🆔 Session ID: \(sessionId)")
        print("📝 Title: \(title ?? "Auto-generated")")
        print("📚 Subject: \(subject ?? "General")")

        let archiveURL = "\(baseURL)/api/ai/sessions/\(sessionId)/archive"
        guard let url = URL(string: archiveURL) else {
            print("❌ Invalid archive URL")
            return (false, nil, nil, "Invalid URL")
        }

        // Build request body
        var requestData: [String: Any] = [:]
        if let title = title { requestData["title"] = title }
        if let topic = topic { requestData["topic"] = topic }
        if let subject = subject { requestData["subject"] = subject }
        if let notes = notes { requestData["notes"] = notes }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60.0  // Longer timeout for AI analysis

        // Add authentication header
        addAuthHeader(to: &request)

        do {
            if !requestData.isEmpty {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
            }

            print("📡 Archiving session to backend...")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Archive Response Status: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {

                        let summary = json["summary"] as? String
                        let behaviorInsights = json["behaviorInsights"] as? [String: Any]

                        print("🎉 === SESSION ARCHIVED TO BACKEND ===")
                        print("📝 Summary: \(summary ?? "No summary generated")")
                        if let insights = behaviorInsights {
                            print("🧠 Behavior Insights:")
                            print("   - Frustration Level: \(insights["frustrationLevel"] ?? "N/A")")
                            print("   - Has Red Flags: \(insights["hasRedFlags"] ?? "N/A")")
                            print("   - Engagement Score: \(insights["engagementScore"] ?? "N/A")")
                            print("   - Curiosity Count: \(insights["curiosityCount"] ?? "N/A")")
                        }

                        return (true, summary, behaviorInsights, "Session archived successfully")
                    }
                } else if httpResponse.statusCode == 404 {
                    print("❌ Session not found on backend")
                    return (false, nil, nil, "Session not found")
                } else if httpResponse.statusCode == 400 {
                    print("❌ Cannot archive empty session")
                    return (false, nil, nil, "Cannot archive empty session")
                } else if httpResponse.statusCode == 401 {
                    print("❌ Authentication expired in archiveSessionToBackend")
                    return (false, nil, nil, "Authentication expired")
                }

                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("❌ Archive Failed HTTP \(httpResponse.statusCode): \(String(rawResponse.prefix(200)))")
                return (false, nil, nil, "HTTP \(httpResponse.statusCode)")
            }

            return (false, nil, nil, "No HTTP response")
        } catch {
            print("❌ Session archive to backend failed: \(error.localizedDescription)")
            return (false, nil, nil, error.localizedDescription)
        }
    }

    // MARK: - Conversation Processing for Archive
    
    /// Result structure for processed conversation content
    struct ProcessedConversation {
        let textContent: String
        let messageCount: Int
        let imagesProcessed: Int
        let imageSummariesCreated: Int
    }
    
    /// Process conversation history to create text-only archive content
    /// Images are converted to detailed summaries to preserve context while avoiding database storage issues
    /// Diagrams are saved with their full data for later retrieval
    private func processConversationForArchive() async -> ProcessedConversation {
        print("🔄 === PROCESSING CONVERSATION FOR ARCHIVE ===")

        var processedMessages: [String] = []
        var imageCount = 0
        var summaryCount = 0
        var diagramCount = 0

        for (index, message) in conversationHistory.enumerated() {
            let role = message["role"] ?? "unknown"
            let content = message["content"] ?? ""
            let hasImage = message["hasImage"] == "true"
            let messageId = message["messageId"] ?? ""
            let diagramKey = message["diagramKey"]

            print("📝 Processing message \(index): role=\(role), hasImage=\(hasImage), hasDiagram=\(diagramKey != nil)")

            // Check if this message has a diagram attached
            if let diagramKey = diagramKey {
                // Message contains a generated diagram - preserve diagram data
                diagramCount += 1

                // The diagram content is already in the message content
                // Just format it nicely for archive
                let formattedMessage = "\(role.uppercased()): \(content)"
                processedMessages.append(formattedMessage)

                // Add a note that diagram was generated
                processedMessages.append("[DIAGRAM: Saved and available in library]")

                print("✅ Preserved diagram message \(index) with key: \(diagramKey)")
            }
            else if hasImage && !messageId.isEmpty {
                // This message contains an image - create a detailed summary instead
                imageCount += 1
                
                let imageSummary = await createImageSummary(
                    content: content,
                    messageIndex: index,
                    role: role
                )
                
                if !imageSummary.isEmpty {
                    processedMessages.append(imageSummary)
                    summaryCount += 1
                    print("✅ Created image summary for message \(index)")
                } else {
                    // Fallback if summary creation fails
                    let fallbackMessage = """
                    \(role.uppercased()): [Image uploaded - content could not be preserved]
                    User prompt: \(content.isEmpty ? "No additional text provided" : content)
                    """
                    processedMessages.append(fallbackMessage)
                    print("⚠️ Used fallback summary for message \(index)")
                }
            } else {
                // Regular text message - preserve as-is
                let formattedMessage = "\(role.uppercased()): \(content)"
                processedMessages.append(formattedMessage)
                print("✅ Preserved text message \(index)")
            }
        }
        
        let finalContent = processedMessages.joined(separator: "\n\n")
        
        print("📊 Processing complete:")
        print("   - Total messages: \(conversationHistory.count)")
        print("   - Images processed: \(imageCount)")
        print("   - Summaries created: \(summaryCount)")
        print("   - Final content length: \(finalContent.count) characters")
        
        return ProcessedConversation(
            textContent: finalContent,
            messageCount: conversationHistory.count,
            imagesProcessed: imageCount,
            imageSummariesCreated: summaryCount
        )
    }
    
    /// Create a detailed text summary for an image message
    private func createImageSummary(content: String, messageIndex: Int, role: String) async -> String {
        // Generate timestamp for the image
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        // Try to get the AI response from the next message for enhanced context
        var aiResponseContext = ""
        if role == "user" && messageIndex + 1 < conversationHistory.count {
            let nextMessage = conversationHistory[messageIndex + 1]
            if nextMessage["role"] == "assistant" {
                let aiResponse = nextMessage["content"] ?? ""
                // Extract first 200 characters of AI response for context
                aiResponseContext = String(aiResponse.prefix(200))
                if aiResponse.count > 200 {
                    aiResponseContext += "..."
                }
            }
        }
        
        // Create a comprehensive summary that preserves context
        let summary = """
        \(role.uppercased()): [IMAGE UPLOADED - \(formatter.string(from: timestamp))]
        
        📷 Image Context:
        • User prompt: \(content.isEmpty ? "No additional text provided with image" : content)
        • Position in conversation: Message #\(messageIndex + 1)
        • Type: Visual content analysis request
        
        📝 Note: This message originally contained an image that was processed for visual analysis. 
        The image content has been converted to this text summary for database storage compatibility.
        
        \(content.isEmpty ? "" : "User's question about the image: \"\(content)\"")
        
        \(aiResponseContext.isEmpty ? "" : "AI's analysis of the image: \"\(aiResponseContext)\"")
        """
        
        return summary
    }
    
    /// Get archived sessions list with query parameters for server-side filtering
    func getArchivedSessionsWithParams(_ queryParams: [String: String], forceRefresh: Bool = false) async -> (success: Bool, sessions: [[String: Any]]?, message: String) {
        print("📦 === GET ARCHIVED SESSIONS WITH CACHING ===")
        print("📄 Query Params: \(queryParams)")
        print("🔄 Force Refresh: \(forceRefresh)")
        print("🔐 Auth Status: \(AuthenticationService.shared.getAuthToken() != nil ? "✅ Token OK" : "❌ No Token")")
        print("👤 User: \(AuthenticationService.shared.currentUser?.email ?? "None")")
        
        // Check cache first (unless force refresh is requested or search parameters are present)
        let hasSearchParams = queryParams.keys.contains { ["search", "subject", "startDate", "endDate"].contains($0) }
        
        if !forceRefresh && !hasSearchParams && isCacheValid(), let cached = cachedSessions {
            print("⚡ Using cached data with \(cached.count) sessions")
            return (true, cached, "Loaded from cache")
        }
        
        print("🌐 Fetching fresh data from server...")
        
        // Fetch from both homework sessions and conversation sessions
        let homeworkResult = await fetchHomeworkSessions(queryParams)
        
        // Also try to fetch conversation sessions
        let conversationResult = await fetchConversationSessions(queryParams)
        
        var allSessions: [[String: Any]] = []
        
        if homeworkResult.success, let homeworkSessions = homeworkResult.sessions {
            print("📚 Found \(homeworkSessions.count) homework sessions")
            allSessions.append(contentsOf: homeworkSessions)
        }
        
        // Add conversation sessions if found
        if conversationResult.success, let conversationSessions = conversationResult.sessions {
            print("💬 Found \(conversationSessions.count) conversation sessions")
            allSessions.append(contentsOf: conversationSessions)
        }
        
        // Update cache only if no search parameters (cache general list, not searches)
        if !hasSearchParams && (homeworkResult.success || conversationResult.success) {
            updateCache(with: allSessions)
        }
        
        // Log what we're returning for debugging
        print("📦 Total archived items: \(allSessions.count)")
        if allSessions.isEmpty {
            print("ℹ️ No archives found. Try using 'AI Homework' feature to create some content.")
        }
        
        return (true, allSessions, "Successfully loaded \(allSessions.count) archived items")
    }
    
    private func fetchHomeworkSessions(_ queryParams: [String: String]) async -> (success: Bool, sessions: [[String: Any]]?) {
        print("📊 === FETCHING HOMEWORK SESSIONS SEQUENTIALLY ===")
        var allSessions: [[String: Any]] = []
        
        // First, fetch sessions from /api/archive/sessions (sequential, not concurrent)
        print("🔗 Step 1: Trying archived sessions...")
        let sessionsResult = await fetchArchivedSessions(queryParams)
        if sessionsResult.success, let sessions = sessionsResult.sessions {
            print("✅ Step 1: Found \(sessions.count) archived sessions")
            allSessions.append(contentsOf: sessions)
        } else {
            print("⚠️ Step 1: No archived sessions found")
        }
        
        // Note: Archived questions endpoints not yet available on backend
        // Skipping questions fetch to avoid unnecessary failed API calls
        
        print("📊 Total homework sessions found: \(allSessions.count)")
        return (allSessions.count > 0, allSessions)
    }
    
    private func fetchArchivedSessions(_ queryParams: [String: String]) async -> (success: Bool, sessions: [[String: Any]]?) {
        // Try multiple endpoints for archived sessions/conversations
        let endpoints = [
            "\(baseURL)/api/archive/sessions",
            "\(baseURL)/api/ai/archives/conversations", 
            "\(baseURL)/api/user/conversations/archived"
        ]
        
        for endpoint in endpoints {
            let result = await tryFetchSessionsFrom(endpoint, queryParams: queryParams)
            if result.success {
                return result
            }
        }
        
        return (false, nil)
    }
    
    private func tryFetchSessionsFrom(_ endpoint: String, queryParams: [String: String]) async -> (success: Bool, sessions: [[String: Any]]?) {
        // Build URL with query parameters
        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = urlComponents.url else {
            return (false, nil)
        }
        
        print("🔗 Trying Sessions URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add authentication if available from AuthenticationService only
        addAuthHeader(to: &request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Sessions Status (\(endpoint)): \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let success = json["success"] as? Bool, success,
                       let sessions = json["data"] as? [[String: Any]] {
                        print("📦 Found \(sessions.count) sessions from \(endpoint)")
                        return (true, sessions)
                    } else if let rawResponse = String(data: data, encoding: .utf8) {
                        print("📄 Raw sessions response: \(String(rawResponse.prefix(200)))")
                        // Try parsing as array directly
                        if let sessions = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                            print("📦 Found \(sessions.count) sessions in direct array format from \(endpoint)")
                            return (true, sessions)
                        }
                    }
                } else if httpResponse.statusCode == 404 {
                    print("ℹ️ Endpoint \(endpoint) not available (404)")
                } else {
                    print("⚠️ Endpoint \(endpoint) returned \(httpResponse.statusCode)")
                    if let rawResponse = String(data: data, encoding: .utf8) {
                        print("📄 Error response: \(String(rawResponse.prefix(200)))")
                    }
                }
            }
        } catch {
            print("❌ Sessions request failed for \(endpoint): \(error.localizedDescription)")
        }
        
        return (false, nil)
    }
    
    // REMOVED: fetchArchivedQuestions and tryFetchQuestionsFrom functions
    // These endpoints are not yet available on the backend:
    // - /api/archive/questions
    // - /api/user/questions/archived
    // - /api/archive/homework
    // Removed to eliminate unnecessary failed API calls (all return 404)

    private func fetchConversationSessions(_ queryParams: [String: String]) async -> (success: Bool, sessions: [[String: Any]]?) {
        print("🔄 === FETCHING CONVERSATION SESSIONS ===")
        print("📄 Input Query Params: \(queryParams)")
        print("🔐 Auth Token Available: \(AuthenticationService.shared.getAuthToken() != nil)")
        print("🌐 Base URL: \(baseURL)")
        
        // Try multiple endpoints for conversation sessions - AVOID /api/ai/sessions/archived due to routing conflict
        let endpoints = [
            "\(baseURL)/api/ai/archives/conversations",
            "\(baseURL)/api/archive/conversations", 
            "\(baseURL)/api/user/conversations",
            "\(baseURL)/api/conversations/archived"
        ]
        
        // First try direct endpoints
        for endpoint in endpoints {
            print("🔗 Trying conversation endpoint: \(endpoint)")
            let result = await tryFetchConversationsFrom(endpoint, queryParams: queryParams)
            if result.success {
                print("✅ SUCCESS: Found conversations from \(endpoint)")
                return result
            } else {
                print("❌ FAILED: No data from \(endpoint)")
            }
        }
        
        // Then try the search endpoint with corrected parameters
        print("🔍 Trying search endpoint as fallback...")
        let fallbackResult = await tryConversationSearch(queryParams)
        print("🔍 Fallback result: success=\(fallbackResult.success), sessions=\(fallbackResult.sessions?.count ?? 0)")
        return fallbackResult
    }
    
    private func tryFetchConversationsFrom(_ endpoint: String, queryParams: [String: String]) async -> (success: Bool, sessions: [[String: Any]]?) {
        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = urlComponents.url else {
            print("❌ Invalid URL for \(endpoint)")
            return (false, nil)
        }
        
        print("🔗 Conversation URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add authentication if available from AuthenticationService only
        addAuthHeader(to: &request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Conversation Status (\(endpoint)): \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let rawResponse = String(data: data, encoding: .utf8) {
                        print("📄 Raw conversation response (\(endpoint)): \(String(rawResponse.prefix(300)))")
                    }
                    
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let success = json["success"] as? Bool, success,
                       let conversations = json["data"] as? [[String: Any]] {
                        print("💬 Found \(conversations.count) conversations from \(endpoint)")
                        return (true, conversations)
                    } else if let conversations = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                        print("💬 Found \(conversations.count) conversations in direct array format from \(endpoint)")
                        return (true, conversations)
                    }
                } else if httpResponse.statusCode == 404 {
                    print("ℹ️ Endpoint \(endpoint) not available (404)")
                } else {
                    print("⚠️ Endpoint \(endpoint) returned \(httpResponse.statusCode)")
                    if let rawResponse = String(data: data, encoding: .utf8) {
                        print("📄 Error response: \(String(rawResponse.prefix(200)))")
                    }
                }
            }
        } catch {
            print("❌ Conversation request failed for \(endpoint): \(error.localizedDescription)")
        }
        
        return (false, nil)
    }
    
    private func tryConversationSearch(_ queryParams: [String: String]) async -> (success: Bool, sessions: [[String: Any]]?) {
        // Skip search endpoint for now since it has validation issues
        // The error "querystring/datePattern must be equal to one of the allowed values" 
        // indicates the API expects specific date format parameters we don't have
        print("⚠️ Skipping search endpoint due to datePattern validation requirements")
        return (false, nil)
    }
    
    private func extractDate(from session: [String: Any]) -> Date {
        // Try different date fields
        let dateFormatter = ISO8601DateFormatter()
        
        if let sessionDateString = session["sessionDate"] as? String {
            return dateFormatter.date(from: sessionDateString) ?? Date()
        }
        
        if let archivedAtString = session["archived_at"] as? String ?? session["archivedAt"] as? String {
            return dateFormatter.date(from: archivedAtString) ?? Date()
        }
        
        if let createdAtString = session["created_at"] as? String ?? session["createdAt"] as? String {
            return dateFormatter.date(from: createdAtString) ?? Date()
        }
        
        return Date()
    }
    
    
    /// Get archived sessions list
    func getArchivedSessions(limit: Int = 20, offset: Int = 0) async -> (success: Bool, sessions: [[String: Any]]?, message: String) {
        print("📦 === GET ARCHIVED SESSIONS ===")
        print("📄 Limit: \(limit), Offset: \(offset)")
        
        let archiveURL = "\(baseURL)/api/ai/archives/conversations?limit=\(limit)&offset=\(offset)"
        
        guard let url = URL(string: archiveURL) else {
            return (false, nil, "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add authentication if available from AuthenticationService only
        addAuthHeader(to: &request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Archived Sessions Status: \(httpResponse.statusCode)")
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        print("✅ Archived Sessions Response: \(json)")
                        
                        let success = json["success"] as? Bool ?? false
                        
                        if success, let sessions = json["data"] as? [[String: Any]] {
                            print("📦 Found \(sessions.count) archived sessions")
                            return (true, sessions, "Successfully loaded archived sessions")
                        } else {
                            let error = json["error"] as? String ?? "Failed to load archived sessions"
                            return (false, nil, error)
                        }
                    }
                } catch {
                    print("❌ JSON parsing error: \(error)")
                    return (false, nil, "Invalid response format")
                }
            }
            
        } catch {
            print("❌ Get archived sessions request failed: \(error.localizedDescription)")
            return (false, nil, "Network error: \(error.localizedDescription)")
        }
        
        return (false, nil, "Unknown error occurred")
    }
    
    // MARK: - Profile Management Functions
    
    /// Get detailed user profile from server
    func getUserProfile() async -> (success: Bool, profile: [String: Any]?, message: String) {
        profileLog("👤 === GET USER PROFILE ===")
        
        let profileURL = "\(baseURL)/api/user/profile-details"
        
        guard let url = URL(string: profileURL) else {
            return (false, nil, "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication header
        addAuthHeader(to: &request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    if statusCode == 200 {
                        let profile = json["profile"] as? [String: Any] ?? json
                        let message = json["message"] as? String ?? "Profile loaded successfully"
                        return (true, profile, message)
                    } else {
                        let message = json["message"] as? String ?? "Failed to load profile"
                        return (false, nil, message)
                    }
                }
            }
            
            return (false, nil, "Invalid response")
        } catch {
            let errorMsg = "Profile request failed: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (false, nil, errorMsg)
        }
    }
    
    /// Update user profile on server
    func updateUserProfile(_ profileData: [String: Any]) async -> (success: Bool, profile: [String: Any]?, message: String) {
        print("✏️ === UPDATE USER PROFILE ===")
        
        let profileURL = "\(baseURL)/api/user/profile"
        
        guard let url = URL(string: profileURL) else {
            return (false, nil, "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication header
        addAuthHeader(to: &request)
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: profileData)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {

                    if statusCode == 200 {
                        let profile = json["profile"] as? [String: Any] ?? json
                        let message = json["message"] as? String ?? "Profile updated successfully"

                        print("✅ [NetworkService] Update successful")
                        print("📦 [NetworkService] Profile data from backend:")
                        print("   - city: \(profile["city"] as? String ?? "nil")")
                        print("   - stateProvince: \(profile["stateProvince"] as? String ?? "nil")")
                        print("   - country: \(profile["country"] as? String ?? "nil")")
                        print("   - kidsAges: \(profile["kidsAges"] as? [Int] ?? [])")

                        return (true, profile, message)
                    } else {
                        let message = json["message"] as? String ?? "Failed to update profile"
                        return (false, nil, message)
                    }
                }
            }
            
            return (false, nil, "Invalid response")
        } catch {
            let errorMsg = "Update profile request failed: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (false, nil, errorMsg)
        }
    }

    /// Upload custom avatar image
    func uploadCustomAvatar(base64Image: String) async -> (success: Bool, avatarUrl: String?, message: String) {
        print("📸 === UPLOAD CUSTOM AVATAR ===")

        let uploadURL = "\(baseURL)/api/user/upload-avatar"

        guard let url = URL(string: uploadURL) else {
            return (false, nil, "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add authentication header
        addAuthHeader(to: &request)

        let requestBody: [String: Any] = [
            "image": base64Image
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                print("📸 [NetworkService] Response status code: \(statusCode)")

                // Try to parse JSON response
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("📸 [NetworkService] Response JSON: \(json)")

                    if statusCode == 200 {
                        let avatarUrl = json["avatarUrl"] as? String ?? json["avatar_url"] as? String
                        let message = json["message"] as? String ?? "Avatar uploaded successfully"

                        print("✅ [NetworkService] Avatar upload successful: \(avatarUrl ?? "no URL")")
                        return (true, avatarUrl, message)
                    } else {
                        let message = json["message"] as? String ?? "Failed to upload avatar"
                        let code = json["code"] as? String ?? "UNKNOWN_ERROR"
                        let errorDetail = json["error"] as? String

                        print("❌ [NetworkService] Upload failed with status \(statusCode)")
                        print("❌ [NetworkService] Error code: \(code)")
                        print("❌ [NetworkService] Error message: \(message)")
                        if let errorDetail = errorDetail {
                            print("❌ [NetworkService] Error detail: \(errorDetail)")
                        }
                        return (false, nil, message)
                    }
                } else {
                    // Failed to parse JSON
                    let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                    print("❌ [NetworkService] Failed to parse JSON response")
                    print("❌ [NetworkService] Raw response: \(responseString)")
                    return (false, nil, "Invalid response format")
                }
            }

            return (false, nil, "Invalid response")
        } catch {
            let errorMsg = "Upload avatar request failed: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (false, nil, errorMsg)
        }
    }

    /// Get profile completion status
    func getProfileCompletion() async -> (success: Bool, completion: [String: Any]?, message: String) {
        print("📊 === GET PROFILE COMPLETION ===")
        
        let completionURL = "\(baseURL)/api/user/profile-completion"
        
        guard let url = URL(string: completionURL) else {
            return (false, nil, "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication header
        addAuthHeader(to: &request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                print("✅ Profile Completion Status: \(statusCode)")
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ Profile Completion Response: \(json)")
                    
                    if statusCode == 200 {
                        let completion = json["completion"] as? [String: Any] ?? json
                        let message = json["message"] as? String ?? "Profile completion loaded successfully"
                        return (true, completion, message)
                    } else {
                        let message = json["message"] as? String ?? "Failed to load profile completion"
                        return (false, nil, message)
                    }
                }
            }
            
            return (false, nil, "Invalid response")
        } catch {
            let errorMsg = "Profile completion request failed: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (false, nil, errorMsg)
        }
    }

    /// ❌ DEPRECATED: fetchSubjectBreakdown() - Removed 2025-10-17
    /// REASON: Replaced by local-first approach
    /// REPLACEMENT: Use LocalProgressService.calculateSubjectBreakdown()

    /// ❌ DEPRECATED: fetchMonthlyActivity() - Removed 2025-10-17
    /// REASON: Not used by any active iOS views
    /// REPLACEMENT: Use LocalProgressService.calculateMonthlyActivity()

    /// ❌ DEPRECATED: updateSubjectProgress() - Removed 2025-10-17
    /// REASON: Not used by any active iOS views
    /// REPLACEMENT: Use PointsEarningSystem.markHomeworkProgress() for local tracking
    ///               and syncDailyProgress() for backend sync
    
    func fetchSubjectInsights(userId: String) async throws -> SubjectInsights? {
        let endpoint = "/api/progress/subject/insights/\(userId)"
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        
        do {
            let (data, _) = try await performRequest(request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success,
               let dataDict = json["data"] as? [String: Any],
               let insightsDict = dataDict["insights"] as? [String: Any] {
                
                // Parse insights manually since it's complex JSON
                let focusSubjects = (insightsDict["focus_subjects"] as? [String] ?? []).compactMap { SubjectCategory(rawValue: $0) }
                let maintainSubjects = (insightsDict["maintain_subjects"] as? [String] ?? []).compactMap { SubjectCategory(rawValue: $0) }
                let studyRecommendations = insightsDict["study_recommendations"] as? [String: Int] ?? [:]
                let personalizedTips = insightsDict["personalized_tips"] as? [String] ?? []
                
                // Convert to SubjectCategory keys for study recommendations
                let convertedRecommendations: [SubjectCategory: Int] = studyRecommendations.compactMapKeys { key in
                    SubjectCategory(rawValue: key)
                }
                
                let insights = SubjectInsights(
                    subjectToFocus: focusSubjects,
                    subjectsToMaintain: maintainSubjects,
                    studyTimeRecommendations: convertedRecommendations,
                    crossSubjectConnections: [], // Could be enhanced
                    achievementOpportunities: [], // Could be enhanced
                    personalizedTips: personalizedTips,
                    optimalStudySchedule: WeeklyStudySchedule(
                        monday: [], tuesday: [], wednesday: [], thursday: [],
                        friday: [], saturday: [], sunday: []
                    )
                )
                
                return insights
            }
            
            return nil
        } catch {
            throw error
        }
    }
    
    func generateSubjectInsights(userId: String) async throws -> (success: Bool, message: String) {
        let endpoint = "/api/progress/subject/generate-insights/\(userId)"
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw NetworkError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "timezone": TimeZone.current.identifier
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw NetworkError.invalidData
        }
        
        do {
            let (data, _) = try await performRequest(request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let success = json["success"] as? Bool ?? false
                let message = json["message"] as? String ?? ""
                return (success, message)
            }
            
            return (false, "Invalid response format")
        } catch {
            throw error
        }
    }
    
    func fetchSubjectTrends(userId: String, subject: String? = nil, periodType: String = "weekly", limit: Int = 12) async throws -> [SubjectTrendData] {
        var endpoint = "/api/progress/subject/trends/\(userId)?period_type=\(periodType)&limit=\(limit)"
        if let subject = subject {
            endpoint += "&subject=\(subject)"
        }
        
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        
        do {
            let (data, _) = try await performRequest(request)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success,
               let dataDict = json["data"] as? [String: Any],
               let trendsArray = dataDict["trends"] as? [[String: Any]] {
                
                // Parse trends manually (simplified version)
                var trendData: [SubjectTrendData] = []
                
                for trendDict in trendsArray {
                    if let subjectString = trendDict["subject"] as? String,
                       let subject = SubjectCategory(rawValue: subjectString) {
                        
                        let trend = SubjectTrendData(
                            subject: subject,
                            weeklyTrends: [], // Could be populated from API
                            monthlyTrends: [], // Could be populated from API
                            trendDirection: .stable, // Could be parsed from API
                            projectedPerformance: trendDict["projected_performance"] as? Double ?? 0.0,
                            seasonalPattern: nil // Could be parsed from API
                        )
                        
                        trendData.append(trend)
                    }
                }
                
                return trendData
            }
            
            return []
        } catch {
            throw error
        }
    }

    // MARK: - Conversation Validation

    /// Check if a conversation exists without fetching full content
    func checkConversationExists(conversationId: String) async -> (exists: Bool, error: String?) {
        // Check authentication first
        guard AuthenticationService.shared.getAuthToken() != nil else {
            return (false, "Authentication required")
        }

        // Try multiple endpoints to check if conversation exists
        let endpoints = [
            "\(baseURL)/api/ai/archives/conversations/\(conversationId)",
            "\(baseURL)/api/archive/conversations/\(conversationId)",
            "\(baseURL)/api/user/conversations/\(conversationId)"
        ]

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "HEAD" // Use HEAD for lightweight check
            request.timeoutInterval = 10.0 // Quick timeout
            addAuthHeader(to: &request)

            do {
                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        return (true, nil)
                    } else if httpResponse.statusCode == 404 {
                        continue // Try next endpoint
                    } else if httpResponse.statusCode == 401 {
                        return (false, "Authentication expired")
                    }
                }
            } catch {
                continue // Try next endpoint
            }
        }

        return (false, "Conversation not found")
    }

    // MARK: - Mistake Review Methods
    func getMistakeSubjects(timeRange: String? = nil) async throws -> [SubjectMistakeCount] {
        guard let user = AuthenticationService.shared.currentUser else {
            throw NetworkError.authenticationRequired
        }

        var urlString = "\(baseURL)/api/archived-questions/mistakes/subjects/\(user.id)"
        if let timeRange = timeRange {
            urlString += "?timeRange=\(timeRange)"
        }

        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "GET"

        // Add authentication header
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await performRequest(request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = json["success"] as? Bool, success,
           let subjectsData = json["data"] as? [[String: Any]] {

            var subjects: [SubjectMistakeCount] = []
            for subjectDict in subjectsData {
                if let subject = subjectDict["subject"] as? String,
                   let mistakeCount = subjectDict["mistakeCount"] as? Int,
                   let icon = subjectDict["icon"] as? String {

                    subjects.append(SubjectMistakeCount(
                        subject: subject,
                        mistakeCount: mistakeCount,
                        icon: icon
                    ))
                }
            }
            return subjects
        } else {
            throw NetworkError.invalidResponse
        }
    }

    func getMistakes(subject: String?, timeRange: String) async throws -> [MistakeQuestion] {
        guard let user = AuthenticationService.shared.currentUser else {
            throw NetworkError.authenticationRequired
        }

        var urlComponents = URLComponents(string: "\(baseURL)/api/archived-questions/mistakes/\(user.id)")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "range", value: timeRange)
        ]

        if let subject = subject {
            queryItems.append(URLQueryItem(name: "subject", value: subject))
        }

        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"

        // Add authentication header
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await performRequest(request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = json["success"] as? Bool, success,
           let mistakesData = json["data"] as? [[String: Any]] {

            var mistakes: [MistakeQuestion] = []
            let formatter = ISO8601DateFormatter()

            for mistakeDict in mistakesData {
                if let id = mistakeDict["id"] as? String,
                   let subject = mistakeDict["subject"] as? String,
                   let question = mistakeDict["question"] as? String,
                   let correctAnswer = mistakeDict["correctAnswer"] as? String,
                   let studentAnswer = mistakeDict["studentAnswer"] as? String,
                   let explanation = mistakeDict["explanation"] as? String,
                   let createdAtString = mistakeDict["createdAt"] as? String,
                   let confidence = mistakeDict["confidence"] as? Double,
                   let pointsEarned = mistakeDict["pointsEarned"] as? Double,
                   let pointsPossible = mistakeDict["pointsPossible"] as? Double,
                   let tags = mistakeDict["tags"] as? [String],
                   let notes = mistakeDict["notes"] as? String {

                    let createdAt = formatter.date(from: createdAtString) ?? Date()

                    mistakes.append(MistakeQuestion(
                        id: id,
                        subject: subject,
                        question: question,
                        correctAnswer: correctAnswer,
                        studentAnswer: studentAnswer,
                        explanation: explanation,
                        createdAt: createdAt,
                        confidence: confidence,
                        pointsEarned: pointsEarned,
                        pointsPossible: pointsPossible,
                        tags: tags,
                        notes: notes
                    ))
                }
            }
            return mistakes
        } else {
            throw NetworkError.invalidResponse
        }
    }

    func getMistakeStats() async throws -> MistakeStats {
        guard let user = AuthenticationService.shared.currentUser else {
            throw NetworkError.authenticationRequired
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/api/archived-questions/mistakes/stats/\(user.id)")!)
        request.httpMethod = "GET"

        // Add authentication header
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await performRequest(request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = json["success"] as? Bool, success,
           let statsData = json["data"] as? [String: Any],
           let totalMistakes = statsData["totalMistakes"] as? Int,
           let subjectsWithMistakes = statsData["subjectsWithMistakes"] as? Int,
           let mistakesLastWeek = statsData["mistakesLastWeek"] as? Int,
           let mistakesLastMonth = statsData["mistakesLastMonth"] as? Int {

            return MistakeStats(
                totalMistakes: totalMistakes,
                subjectsWithMistakes: subjectsWithMistakes,
                mistakesLastWeek: mistakesLastWeek,
                mistakesLastMonth: mistakesLastMonth
            )
        } else {
            throw NetworkError.invalidResponse
        }
    }

    /// Helper method to get current date string in specified timezone
    // MARK: - Total Points and User Level Sync

    /// Sync total points with backend user level system
    func syncTotalPoints(userId: String, totalPoints: Int) async -> (success: Bool, updatedLevel: [String: Any]?, message: String?) {
                
        let syncURL = "\(baseURL)/api/user/sync-points"

        guard let url = URL(string: syncURL) else {
            print("❌ Invalid sync URL: \(syncURL)")
            return (false, nil, "Invalid URL")
        }

        let requestBody: [String: Any] = [
            "userId": userId,
            "totalPoints": totalPoints,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ Failed to serialize sync request")
            return (false, nil, "Failed to serialize request")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add authentication headers
        if let authToken = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                
                if let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    if httpResponse.statusCode == 200 {
                        let success = responseDict["success"] as? Bool ?? false
                        let message = responseDict["message"] as? String
                        let levelData = responseDict["userLevel"] as? [String: Any]

                        return (success, levelData, message)
                    } else {
                        let message = responseDict["message"] as? String ?? "Sync failed"
                        return (false, nil, message)
                    }
                }
            }

            return (false, nil, "Invalid response")
        } catch {
            print("❌ Sync error: \(error.localizedDescription)")
            return (false, nil, error.localizedDescription)
        }
    }

    /// Get user level information from backend
    func getUserLevel(userId: String) async -> (success: Bool, levelData: [String: Any]?, message: String?) {
                
        let levelURL = "\(baseURL)/api/user/level/\(userId)"

        guard let url = URL(string: levelURL) else {
            print("❌ Invalid level URL: \(levelURL)")
            return (false, nil, "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Add authentication headers
        if let authToken = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                
                if let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    if httpResponse.statusCode == 200 {
                        let success = responseDict["success"] as? Bool ?? false
                        let message = responseDict["message"] as? String
                        let levelData = responseDict["data"] as? [String: Any]

                        return (success, levelData, message)
                    } else {
                        let message = responseDict["message"] as? String ?? "Failed to get user level"
                        return (false, nil, message)
                    }
                }
            }

            return (false, nil, "Invalid response")
        } catch {
            print("❌ Level fetch error: \(error.localizedDescription)")
            return (false, nil, error.localizedDescription)
        }
    }

    /// Sync daily progress data with backend
    /// Sends subject-specific counters and aggregated daily totals
    func syncDailyProgress(userId: String, dailyProgress: DailyProgress) async -> (success: Bool, message: String?) {
        print("🔄 [NetworkService] === SYNCING DAILY PROGRESS ===")
        print("🔄 [NetworkService] Date: \(dailyProgress.date)")
        print("🔄 [NetworkService] Total questions: \(dailyProgress.totalQuestions)")
        print("🔄 [NetworkService] Correct answers: \(dailyProgress.correctAnswers)")
        print("🔄 [NetworkService] Accuracy: \(String(format: "%.1f%%", dailyProgress.accuracy))")

        let syncURL = "\(baseURL)/api/user/sync-daily-progress"

        guard let url = URL(string: syncURL) else {
            print("❌ Invalid sync URL: \(syncURL)")
            return (false, "Invalid URL")
        }

        // Convert SubjectDailyProgress to JSON-serializable format
        var subjectProgressArray: [[String: Any]] = []
        for (subject, progress) in dailyProgress.subjectProgress {
            subjectProgressArray.append([
                "subject": subject,
                "numberOfQuestions": progress.numberOfQuestions,
                "numberOfCorrectQuestions": progress.numberOfCorrectQuestions,
                "accuracy": progress.accuracy
            ])
        }

        let requestBody: [String: Any] = [
            "userId": userId,
            "date": dailyProgress.date,
            "subjectProgress": subjectProgressArray,
            "totalQuestions": dailyProgress.totalQuestions,
            "correctAnswers": dailyProgress.correctAnswers,
            "accuracy": dailyProgress.accuracy,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ Failed to serialize sync request")
            return (false, "Failed to serialize request")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add authentication headers
        if let authToken = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if let responseDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if httpResponse.statusCode == 200 {
                        let success = responseDict["success"] as? Bool ?? false
                        let message = responseDict["message"] as? String

                        print("🔄 [NetworkService] ✅ Daily progress synced successfully")
                        return (success, message)
                    } else {
                        let message = responseDict["message"] as? String ?? "Sync failed"
                        print("🔄 [NetworkService] ❌ Sync failed: \(message)")
                        return (false, message)
                    }
                }
            }

            print("🔄 [NetworkService] ❌ Invalid response")
            return (false, "Invalid response")
        } catch {
            print("🔄 [NetworkService] ❌ Sync error: \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }

    private func getCurrentDateString(timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: timezone) ?? TimeZone.current
        return formatter.string(from: Date())
    }

    // MARK: - Parental Consent (COPPA Compliance)

    /// Check if current user requires parental consent
    func checkConsentStatus() async -> (requiresConsent: Bool, consentStatus: String?, isRestricted: Bool, message: String?) {
        let url = URL(string: "\(baseURL)/api/auth/consent-status")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Add authentication
        if let authToken = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if httpResponse.statusCode == 200 {
                        let consentData = json["consentStatus"] as? [String: Any]
                        let requiresConsent = consentData?["requiresParentalConsent"] as? Bool ?? false
                        let consentStatus = consentData?["consentStatus"] as? String
                        let isRestricted = consentData?["accountRestricted"] as? Bool ?? false
                        let message = json["message"] as? String

                        print("📋 Consent Status: requires=\(requiresConsent), status=\(consentStatus ?? "none"), restricted=\(isRestricted)")
                        return (requiresConsent, consentStatus, isRestricted, message)
                    } else {
                        let message = json["message"] as? String ?? "Failed to check consent status"
                        print("❌ Consent status check failed: \(message)")
                        return (false, nil, false, message)
                    }
                }
            }

            return (false, nil, false, "Invalid response")
        } catch {
            print("❌ Consent status error: \(error.localizedDescription)")
            return (false, nil, false, error.localizedDescription)
        }
    }

    /// Request parental consent for a user under 13
    func requestParentalConsent(childEmail: String, childDateOfBirth: String, parentEmail: String, parentName: String) async -> (success: Bool, message: String, verificationCode: String?) {
        let url = URL(string: "\(baseURL)/api/auth/request-parental-consent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add authentication
        if let authToken = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        // Get current user ID
        guard let childUserId = AuthenticationService.shared.currentUser?.id else {
            print("❌ Cannot request consent: User ID not available")
            return (false, "User not authenticated", nil)
        }

        let requestData: [String: Any] = [
            "childUserId": childUserId,
            "childEmail": childEmail,
            "childDateOfBirth": childDateOfBirth,
            "parentEmail": parentEmail,
            "parentName": parentName
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

            let (data, response) = try await URLSession.shared.data(for: request)

            if (response as? HTTPURLResponse) != nil {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let success = json["success"] as? Bool ?? false
                    let message = json["message"] as? String ?? "Unknown error"

                    if success {
                        let consent = json["consent"] as? [String: Any]
                        let verificationCode = consent?["verification_code"] as? String
                        print("✅ Parental consent requested successfully")
                        return (true, message, verificationCode)
                    } else {
                        print("❌ Consent request failed: \(message)")
                        return (false, message, nil)
                    }
                }
            }

            return (false, "Invalid response", nil)
        } catch {
            print("❌ Consent request error: \(error.localizedDescription)")
            return (false, error.localizedDescription, nil)
        }
    }

    /// Verify parental consent with 6-digit code
    func verifyParentalConsent(code: String) async -> (success: Bool, message: String) {
        let url = URL(string: "\(baseURL)/api/auth/verify-parental-consent")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add authentication
        if let authToken = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        // Get current user ID
        guard let childUserId = AuthenticationService.shared.currentUser?.id else {
            print("❌ Cannot verify consent: User ID not available")
            return (false, "User not authenticated")
        }

        let requestData: [String: Any] = [
            "childUserId": childUserId,
            "code": code
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

            let (data, response) = try await URLSession.shared.data(for: request)

            if (response as? HTTPURLResponse) != nil {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let success = json["success"] as? Bool ?? false
                    let message = json["message"] as? String ?? "Unknown error"

                    if success {
                        print("✅ Parental consent verified successfully")
                        return (true, message)
                    } else {
                        print("❌ Consent verification failed: \(message)")
                        return (false, message)
                    }
                }
            }

            return (false, "Invalid response")
        } catch {
            print("❌ Consent verification error: \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Error Analysis (Pass 2)

    /// Analyze errors for wrong answers (Pass 2 of two-pass grading)
    /// Backend processes and returns results WITHOUT storing to database
    func analyzeErrorsBatch(questions: [ErrorAnalysisRequest]) async throws -> [ErrorAnalysisResponse] {
        let url = URL(string: "\(baseURL)/api/ai/analyze-errors-batch")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(["questions": questions])

        print("📊 [Network] POST /api/ai/analyze-errors-batch (\(questions.count) questions)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            print("❌ [Network] Error analysis failed: HTTP \(httpResponse.statusCode)")
            throw NetworkError.invalidResponse
        }

        // 🔍 DEBUG: Print raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📄 [Network] Raw response: \(jsonString)")
        }

        // Backend returns: {"success": true, "analyses": [...], "count": 1}
        struct ErrorAnalysisBatchResponse: Codable {
            let success: Bool
            let analyses: [ErrorAnalysisResponse]
            let count: Int
        }

        let decoder = JSONDecoder()

        do {
            let result = try decoder.decode(ErrorAnalysisBatchResponse.self, from: data)

            guard result.success else {
                print("❌ [Network] Backend reported failure")
                throw NetworkError.invalidResponse
            }

            print("✅ [Network] Received \(result.analyses.count) error analyses")
            return result.analyses
        } catch {
            print("❌ [Network] Decoding error: \(error)")
            print("❌ [Network] Error details: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Concept Extraction (Bidirectional Status Tracking)

    /// Extract curriculum taxonomy for CORRECT answers (lightweight, no error analysis)
    /// Used for bidirectional status tracking: correct answers reduce weakness values
    func extractConceptsBatch(questions: [ConceptExtractionRequest]) async throws -> [ConceptExtractionResponse] {
        let url = URL(string: "\(baseURL)/api/ai/extract-concepts-batch")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(["questions": questions])

        print("📊 [Network] POST /api/ai/extract-concepts-batch (\(questions.count) questions)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            print("❌ [Network] Concept extraction failed: HTTP \(httpResponse.statusCode)")
            throw NetworkError.invalidResponse
        }

        // Backend returns: {"success": true, "concepts": [...], "count": N}
        struct ConceptBatchResponse: Codable {
            let success: Bool
            let concepts: [ConceptExtractionResponse]
            let count: Int
        }

        let decoder = JSONDecoder()

        do {
            let result = try decoder.decode(ConceptBatchResponse.self, from: data)

            guard result.success else {
                print("❌ [Network] Backend reported concept extraction failure")
                throw NetworkError.invalidResponse
            }

            print("✅ [Network] Received \(result.concepts.count) concept extractions")
            return result.concepts
        } catch {
            print("❌ [Network] Concept extraction decoding error: \(error)")
            throw error
        }
    }

    // MARK: - Weakness Description Generation (Short-Term Status Architecture)

    /// Generate AI-powered natural language descriptions for weakness points
    func generateWeaknessDescriptions(_ weaknesses: [[String: Any]]) async throws -> [WeaknessDescriptionResponse] {
        let url = URL(string: "\(baseURL)/api/ai/generate-weakness-descriptions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: ["weaknesses": weaknesses])

        print("📊 [Network] POST /api/ai/generate-weakness-descriptions (\(weaknesses.count) weaknesses)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            print("❌ [Network] Weakness description generation failed: HTTP \(httpResponse.statusCode)")
            throw NetworkError.invalidResponse
        }

        // Backend returns: {"descriptions": [...]}
        struct WeaknessDescriptionsResponse: Codable {
            let descriptions: [WeaknessDescriptionResponse]
        }

        let decoder = JSONDecoder()

        do {
            let result = try decoder.decode(WeaknessDescriptionsResponse.self, from: data)
            print("✅ [Network] Received \(result.descriptions.count) weakness descriptions")
            return result.descriptions
        } catch {
            print("❌ [Network] Decoding error: \(error)")
            throw error
        }
    }
}

// MARK: - Weakness Description Models

struct WeaknessDescriptionResponse: Codable {
    let key: String
    let description: String
    let severity: String
    let confidence: Double
}

// MARK: - Dictionary Extension for Key Conversion
extension Dictionary {
    func compactMapKeys<T>(_ transform: (Key) throws -> T?) rethrows -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            if let transformedKey = try transform(key) {
                result[transformedKey] = value
            }
        }
        return result
    }
}
