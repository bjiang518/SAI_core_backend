//
//  NetworkService.swift
//  StudyAI
//
//  Created by Claude Code on 8/30/25.
//

import Foundation
import Combine
import Network
import UIKit
import os.log

class NetworkService: ObservableObject {
    static let shared = NetworkService()
    
    // Primary: Production Railway backend with integrated AI proxy
    private let baseURL = "https://sai-backend-production.up.railway.app"
    
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
        print("🗑️ Archive cache invalidated")
    }
    
    private func updateCache(with sessions: [[String: Any]]) {
        cachedSessions = sessions
        lastCacheTime = Date()
        print("💾 Archive cache updated with \(sessions.count) sessions")
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
    private func addToConversationHistory(role: String, content: String) {
        let message = ConversationMessage(role: role, content: content, timestamp: Date())
        internalConversationHistory.append(message)
        
        // Update published dictionary format for backward compatibility
        conversationHistory.append(["role": role, "content": content])
        
        // Limit history size to prevent memory issues
        if internalConversationHistory.count > maxHistorySize {
            internalConversationHistory.removeFirst(internalConversationHistory.count - maxHistorySize)
            conversationHistory.removeFirst(conversationHistory.count - maxHistorySize)
        }
    }
    
    // MARK: - Public Conversation Management (for SessionChatView)
    
    /// Add user message to conversation history immediately (for optimistic UI updates)
    func addUserMessageToHistory(_ message: String) {
        addToConversationHistory(role: "user", content: message)
        print("📤 User message added to history optimistically: '\(message.prefix(50))...'")
    }
    
    /// Remove the last message from conversation history (for error recovery)
    func removeLastMessageFromHistory() {
        if !internalConversationHistory.isEmpty {
            let removedMessage = internalConversationHistory.removeLast()
            conversationHistory.removeLast()
            print("🗑️ Removed last message from history: '\(removedMessage.content.prefix(50))...'")
        } else {
            print("⚠️ Attempted to remove message from empty conversation history")
        }
    }
    
    private init() {
        let initStartTime = CFAbsoluteTimeGetCurrent()
        print("🌐 === NETWORK SERVICE INIT STARTED ===")
        
        print("🔧 Setting up network monitoring...")
        let networkStartTime = CFAbsoluteTimeGetCurrent()
        setupNetworkMonitoring()
        let networkEndTime = CFAbsoluteTimeGetCurrent()
        let networkDuration = networkEndTime - networkStartTime
        print("✅ Network monitoring setup completed in: \(networkDuration * 1000) ms")
        
        print("🔧 Setting up URL cache...")
        let cacheStartTime = CFAbsoluteTimeGetCurrent()
        setupURLCache()
        let cacheEndTime = CFAbsoluteTimeGetCurrent()
        let cacheDuration = cacheEndTime - cacheStartTime
        print("✅ URL cache setup completed in: \(cacheDuration * 1000) ms")
        
        let initEndTime = CFAbsoluteTimeGetCurrent()
        let initDuration = initEndTime - initStartTime
        print("🌐 NetworkService init completed in: \(initDuration * 1000) ms")
        print("🌐 === NETWORK SERVICE INIT FINISHED ===")
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
        print("🔍 Starting network path monitor setup...")
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
                print("📡 Network status updated: \(path.status == .satisfied ? "Connected" : "Disconnected")")
            }
        }
        print("🔍 Starting network monitor on background queue...")
        networkMonitor.start(queue: networkQueue)
        print("✅ Network monitoring fully configured")
    }
    
    private func setupURLCache() {
        print("🗂️ Configuring URLSession cache (50MB memory, 200MB disk)...")
        URLSession.shared.configuration.urlCache = cache
        print("📋 Setting cache policy to useProtocolCachePolicy...")
        URLSession.shared.configuration.requestCachePolicy = .useProtocolCachePolicy
        print("✅ URL cache configuration complete")
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
            print("⚡ Circuit breaker opened due to \(failureCount) failures")
        }
    }
    
    // MARK: - Optimized Request Helper
    private func addAuthHeader(to request: inout URLRequest) {
        if let token = AuthenticationService.shared.getAuthToken() {
            print("🔐 Adding auth header with token: \(String(token.prefix(20)))...")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("StudyAI-iOS/1.0", forHTTPHeaderField: "User-Agent")
            request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        } else {
            print("⚠️ No auth token available for request")
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
        print("🌐 DEBUG: performRequest called")
        print("🔗 Request URL: \(request.url?.absoluteString ?? "Unknown")")
        print("📤 Request Method: \(request.httpMethod ?? "Unknown")")
        
        // Check circuit breaker
        guard canMakeRequest() else {
            print("⚡ Circuit breaker is open, rejecting request")
            throw NetworkError.circuitBreakerOpen
        }
        
        // Check network availability
        guard isNetworkAvailable else {
            print("📡 Network unavailable, rejecting request")
            throw NetworkError.noConnection
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Handle HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 HTTP Response Status: \(httpResponse.statusCode)")
                print("📄 Response Headers: \(httpResponse.allHeaderFields)")
                
                if httpResponse.statusCode >= 400 {
                    let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                    print("❌ HTTP Error \(httpResponse.statusCode): \(rawResponse)")
                    
                    if httpResponse.statusCode == 401 {
                        print("🔐 Authentication failed - token may be expired")
                        throw NetworkError.authenticationRequired
                    } else if httpResponse.statusCode == 404 {
                        print("🔗 Endpoint not found - URL may be incorrect")
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
            print("✅ Request completed successfully")
            return (data, response)
            
        } catch {
            recordFailure()
            print("❌ Request failed with error: \(error.localizedDescription)")
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
        print("🔍 Testing Railway backend connectivity...")
        
        let healthURL = "\(baseURL)/health"
        print("🔗 Using Railway backend URL: \(healthURL)")
        
        guard let url = URL(string: healthURL) else {
            let errorMsg = "❌ Invalid URL"
            print(errorMsg)
            return (false, errorMsg)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Status Code: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                            print("✅ Vercel Backend Response: \(json)")
                            
                            // Check AI status specifically
                            if let aiInfo = json["ai"] as? [String: Any] {
                                let aiStatus = aiInfo["status"] as? String ?? "unknown"
                                let aiMessage = aiInfo["message"] as? String ?? "No message"
                                return (true, "Railway Backend connected! AI: \(aiStatus) - \(aiMessage)")
                            } else {
                                return (true, "Railway Backend connected successfully")
                            }
                        } else {
                            let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                            print("📄 Raw response: \(rawResponse)")
                            return (false, "Invalid JSON format")
                        }
                    } catch {
                        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                        print("❌ JSON Parse Error: \(error)")
                        print("📄 Raw response: \(rawResponse)")
                        return (false, "JSON parsing failed: \(error.localizedDescription)")
                    }
                } else {
                    let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                    print("❌ HTTP \(httpResponse.statusCode) Response: \(rawResponse)")
                    return (false, "Railway Backend HTTP \(httpResponse.statusCode): \(String(rawResponse.prefix(100)))")
                }
            }
            return (false, "No HTTP response from Railway Backend")
        } catch {
            let errorMsg = "❌ Railway Backend connection failed: \(error.localizedDescription)"
            print(errorMsg)
            return (false, errorMsg)
        }
    }
    
    // MARK: - Authentication
    // Note: Authentication is now handled exclusively by AuthenticationService
    // These methods only interact with backend, do not store auth data locally
    
    func login(email: String, password: String) async -> (success: Bool, message: String, token: String?, userData: [String: Any]?, statusCode: Int?) {
        print("🔐 Testing login functionality...")
        
        let loginURL = "\(baseURL)/api/auth/login"
        print("🔗 Using Railway backend for login")
        
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
                print("✅ Login Status: \(statusCode)")
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ Login Response: \(json)")
                    
                    if statusCode == 200 {
                        let token = json["token"] as? String
                        let message = json["message"] as? String ?? "Login successful"
                        let userData = json["user"] as? [String: Any] ?? json  // Try 'user' key first, fallback to full response
                        print("🔍 Extracted user data: \(userData)")
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
            let errorMsg = "Login request failed: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (false, errorMsg, nil, nil, nil)
        }
    }
    
    // MARK: - Question Processing
    func submitQuestion(question: String, subject: String = "general") async -> (success: Bool, answer: String?) {
        print("🚀 === StudyAI DEBUG INFO ===")
        print("🤖 Processing question with AI Engine (improved LaTeX prompts)...")
        print("🔗 AI Proxy URL: \(baseURL)/api/ai")
        print("📝 Question: \(question)")
        print("📚 Subject: \(subject)")
        print("🌐 Using LOCAL AI Engine with advanced LaTeX formatting")
        print("⚡ This will use improved prompt engineering for clean math rendering")
        
        // Try AI Engine first (with improved prompts)
        let aiEngineResult = await tryAIEngine(question: question, subject: subject)
        if aiEngineResult.success {
            return aiEngineResult
        }
        
        // Fallback to Railway backend if AI Engine is unavailable
        print("⚠️ AI Engine unavailable, falling back to Railway backend...")
        return await tryRailwayBackend(question: question, subject: subject)
    }
    
    // MARK: - AI Engine (Primary)
    private func tryAIEngine(question: String, subject: String) async -> (success: Bool, answer: String?) {
        let aiProcessURL = "\(baseURL)/api/ai/process-question"
        print("🔗 AI Proxy URL: \(aiProcessURL)")
        
        guard let url = URL(string: aiProcessURL) else {
            print("❌ Invalid AI Engine URL")
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
            
            print("📡 Sending request to AI Engine...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ AI Engine Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let responseData = json["response"] as? [String: Any],
                       let answer = responseData["answer"] as? String {
                        
                        print("🎉 === AI ENGINE SUCCESS ===")
                        print("✅ Enhanced AI Response with LaTeX formatting")
                        print("📏 Answer Length: \(answer.count) characters")
                        print("🔍 Answer Preview: \(String(answer.prefix(100)))")
                        print("🎨 Using improved prompt engineering for clean math rendering")
                        
                        return (true, answer)
                    }
                }
                
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("❌ AI Engine HTTP \(httpResponse.statusCode): \(String(rawResponse.prefix(200)))")
                return (false, nil)
            }
            
            return (false, nil)
        } catch {
            print("❌ AI Engine request failed: \(error.localizedDescription)")
            return (false, nil)
        }
    }
    
    // MARK: - Railway Backend (Fallback)
    private func tryRailwayBackend(question: String, subject: String) async -> (success: Bool, answer: String?) {
        print("🔄 Trying Railway backend as fallback...")
        print("🔗 Backend URL: \(baseURL)")
        print("🌐 Using PRODUCTION Railway backend fallback")
        print("⚡ This will call OpenAI through Railway backend (basic prompting)")
        
        let questionURL = "\(baseURL)/api/questions"
        print("🔗 Full Railway URL: \(questionURL)")
        
        guard let url = URL(string: questionURL) else {
            print("❌ Invalid Railway URL generated")
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
            
            print("📡 Sending request to Railway backend...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Railway Backend Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("🎉 === RAILWAY BACKEND SUCCESS ===")
                            print("✅ Raw AI Response: \(json)")
                            
                            let answer = json["answer"] as? String
                            let aiPowered = json["ai_powered"] as? Bool ?? false
                            let isMock = json["is_mock"] as? Bool ?? true
                            let model = json["model"] as? String ?? "unknown"
                            
                            // Enhanced debug logging
                            print("📊 === AI PROCESSING DETAILS ===")
                            print("🧠 AI Powered: \(aiPowered)")
                            print("🎭 Is Mock: \(isMock)")
                            print("🤖 Model: \(model)")
                            print("📏 Answer Length: \(answer?.count ?? 0) characters")
                            print("🔍 Answer Preview: \(String(answer?.prefix(100) ?? "No answer"))")
                            
                            if aiPowered && !isMock {
                                print("🎉 SUCCESS: Using REAL OpenAI through Railway backend!")
                            } else {
                                print("⚠️ WARNING: Using mock/fallback response")
                            }
                            
                            return (true, answer)
                        } else {
                            let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                            print("❌ Invalid JSON: \(rawResponse)")
                            return (false, "Invalid response format")
                        }
                    } catch {
                        let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                        print("❌ JSON Parse Error: \(error)")
                        print("📄 Raw response: \(rawResponse)")
                        return (false, "JSON parsing failed")
                    }
                } else {
                    let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                    print("❌ HTTP \(httpResponse.statusCode): \(rawResponse)")
                    return (false, "HTTP \(httpResponse.statusCode)")
                }
            }
            
            return (false, "No HTTP response from Railway Backend")
        } catch {
            print("❌ Railway Backend request failed: \(error.localizedDescription)")
            return (false, nil)
        }
    }
    
    // MARK: - Authentication Debugging
    
    /// Debug method to check what user ID the backend thinks we are based on our token
    func debugAuthTokenMapping() async -> (success: Bool, backendUserId: String?, message: String) {
        guard let token = AuthenticationService.shared.getAuthToken() else {
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
    
    // MARK: - Enhanced Progress Tracking
    func getProgress() async -> (success: Bool, progress: [String: Any]?) {
        let progressURL = "\(baseURL)/api/progress"
        
        guard let url = URL(string: progressURL) else {
            return (false, nil)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return (true, json)
                }
            }
            
            return (false, nil)
        } catch {
            return (false, nil)
        }
    }
    
    func getEnhancedProgress() async -> (success: Bool, progress: [String: Any]?) {
        print("📊 === GET ENHANCED PROGRESS ===")
        
        let progressURL = "\(baseURL)/api/progress/enhanced"
        
        guard let url = URL(string: progressURL) else {
            return (false, nil)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add authentication header
        addAuthHeader(to: &request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Enhanced Progress Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("✅ Enhanced Progress Response: \(json)")
                        return (true, json)
                    }
                } else if httpResponse.statusCode == 401 {
                    print("❌ Authentication expired in getEnhancedProgress")
                    return (false, nil)
                }
                
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("❌ Enhanced Progress HTTP \(httpResponse.statusCode): \(String(rawResponse.prefix(200)))")
                return (false, nil)
            }
            
            return (false, nil)
        } catch {
            print("❌ Enhanced progress request failed: \(error.localizedDescription)")
            return (false, nil)
        }
    }
    
    // MARK: - Progress Tracking Integration
    
    /// Track question answered for progress system
    func trackQuestionAnswered(subject: String, isCorrect: Bool, studyTimeSeconds: Int = 0) async {
        print("📈 Tracking question progress: \(subject), correct: \(isCorrect)")
        
        let trackURL = "\(baseURL)/api/progress/track-question"
        
        guard let url = URL(string: trackURL) else {
            print("❌ Invalid track question URL")
            return
        }
        
        let trackData = [
            "subject": subject,
            "is_correct": isCorrect,
            "study_time_seconds": studyTimeSeconds
        ] as [String: Any]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        // Add authentication header
        addAuthHeader(to: &request)
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: trackData)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("🎉 Progress tracked successfully")
                        
                        // Check for achievements or level ups
                        if let achievements = json["new_achievements"] as? [[String: Any]], !achievements.isEmpty {
                            print("🏆 New achievements unlocked: \(achievements.count)")
                            // TODO: Trigger achievement notifications when AchievementManager is added to project
                        }
                        
                        if let levelUp = json["level_up"] as? Bool, levelUp {
                            print("🎊 User leveled up!")
                            // TODO: Create level up achievement notification when AchievementManager is added to project
                        }
                    }
                }
            }
        } catch {
            print("❌ Progress tracking failed: \(error.localizedDescription)")
            // Fail silently for progress tracking
        }
    }
    
    // MARK: - User Progress Server Sync Methods
    
    /// Update user progress on server (for weekly progress sync)
    func updateUserProgress(questionCount: Int = 1, subject: String, currentScore: Int, clientTimezone: String) async -> (success: Bool, progress: [String: Any]?, message: String?) {
        let updateURL = "\(baseURL)/api/progress/update"
        
        guard let url = URL(string: updateURL) else {
            return (false, nil, "Invalid URL")
        }
        
        let requestData: [String: Any] = [
            "questionCount": questionCount,
            "subject": subject,
            "currentScore": currentScore,
            "clientTimezone": clientTimezone
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestData)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let success = json["success"] as? Bool ?? false
                        let progressData = (json["data"] as? [String: Any])?["progress"] as? [String: Any]
                        let message = (json["data"] as? [String: Any])?["message"] as? String
                        
                        print("📊 DEBUG: Server progress update successful")
                        return (success, progressData, message)
                    }
                } else {
                    let errorMessage = "Server returned status code: \(httpResponse.statusCode)"
                    print("📊 DEBUG: Server progress update failed: \(errorMessage)")
                    return (false, nil, errorMessage)
                }
            }
            
            return (false, nil, "Invalid response")
        } catch {
            print("📊 DEBUG: Server progress update error: \(error.localizedDescription)")
            return (false, nil, error.localizedDescription)
        }
    }
    
    /// Get current week progress from server
    func getCurrentWeekProgress(timezone: String) async -> (success: Bool, progress: [String: Any]?, message: String?) {
        // Get user ID from stored auth data
        guard let userData = getCurrentUserData(),
              let userId = userData["id"] as? String else {
            return (false, nil, "User not authenticated")
        }
        
        let currentURL = "\(baseURL)/api/progress/current/\(userId)?timezone=\(timezone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? timezone)"
        
        guard let url = URL(string: currentURL) else {
            return (false, nil, "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let success = json["success"] as? Bool ?? false
                        let progressData = (json["data"] as? [String: Any])?["progress"] as? [String: Any]
                        
                        print("📊 DEBUG: Current week progress loaded from server")
                        return (success, progressData, nil)
                    }
                } else {
                    let errorMessage = "Server returned status code: \(httpResponse.statusCode)"
                    print("📊 DEBUG: Get current week failed: \(errorMessage)")
                    return (false, nil, errorMessage)
                }
            }
            
            return (false, nil, "Invalid response")
        } catch {
            print("📊 DEBUG: Get current week error: \(error.localizedDescription)")
            return (false, nil, error.localizedDescription)
        }
    }
    
    /// Get progress history from server
    func getProgressHistory(limit: Int = 12) async -> (success: Bool, history: [[String: Any]]?, message: String?) {
        // Get user ID from stored auth data
        guard let userData = getCurrentUserData(),
              let userId = userData["id"] as? String else {
            return (false, nil, "User not authenticated")
        }
        
        let historyURL = "\(baseURL)/api/progress/history/\(userId)?limit=\(limit)"
        
        guard let url = URL(string: historyURL) else {
            return (false, nil, "Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addAuthHeader(to: &request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let success = json["success"] as? Bool ?? false
                        let historyData = (json["data"] as? [String: Any])?["history"] as? [[String: Any]]
                        
                        print("📊 DEBUG: Progress history loaded from server")
                        return (success, historyData, nil)
                    }
                } else {
                    let errorMessage = "Server returned status code: \(httpResponse.statusCode)"
                    print("📊 DEBUG: Get progress history failed: \(errorMessage)")
                    return (false, nil, errorMessage)
                }
            }
            
            return (false, nil, "Invalid response")
        } catch {
            print("📊 DEBUG: Get progress history error: \(error.localizedDescription)")
            return (false, nil, error.localizedDescription)
        }
    }
    
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
        
        let sessionData = [
            "subject": subject
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15.0
        
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
    
    func sendSessionMessage(sessionId: String, message: String) async -> (success: Bool, aiResponse: String?, tokensUsed: Int?, compressed: Bool?) {
        // Check authentication first - use unified auth system
        guard AuthenticationService.shared.getAuthToken() != nil else {
            print("❌ Authentication required to send messages")
            return (false, nil, nil, nil)
        }
        
        print("💬 Sending message to session...")
        print("🆔 Session ID: \(sessionId.prefix(8))...")
        print("📝 Message: \(message.prefix(100))...")
        
        let messageURL = "\(baseURL)/api/ai/sessions/\(sessionId)/message"
        print("🔗 Message URL: \(messageURL)")
        
        guard let url = URL(string: messageURL) else {
            print("❌ Invalid message URL")
            return (false, nil, nil, nil)
        }
        
        let messageData = ["message": message]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90.0 // Extended timeout for AI processing
        
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
                    
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let aiResponse = json["ai_response"] as? String {
                        
                        print("🎉 === SESSION MESSAGE SUCCESS ===")
                        print("🤖 Raw AI Response: '\(aiResponse)'")
                        print("📏 AI Response Length: \(aiResponse.count) characters")
                        print("🔍 Response Preview: \(String(aiResponse.prefix(200)))...")
                        
                        let tokensUsed = json["tokens_used"] as? Int
                        let compressed = json["compressed"] as? Bool
                        
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
                        
                        return (true, aiResponse, tokensUsed, compressed)
                    }
                } else if httpResponse.statusCode == 401 {
                    // Authentication failed - let AuthenticationService handle it
                    print("❌ Authentication expired in sendSessionMessage")
                    return (false, "Authentication expired", nil, nil)
                } else if httpResponse.statusCode == 403 {
                    return (false, "Access denied - session belongs to different user", nil, nil)
                }
                
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("❌ Session Message HTTP \(httpResponse.statusCode): \(String(rawResponse.prefix(200)))")
                return (false, nil, nil, nil)
            }
            
            return (false, nil, nil, nil)
        } catch {
            print("❌ Session message failed: \(error.localizedDescription)")
            return (false, nil, nil, nil)
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
        print("📝 Processing homework for AI parsing with subject detection...")
        print("📄 Base64 Image Length: \(base64Image.count) characters")
        print("🤖 Using enhanced AI parsing with subject detection")
        
        guard let url = URL(string: "\(baseURL)/api/ai/process-homework-image-json") else {
            print("❌ Invalid homework parsing URL")
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
            
            print("📡 Sending homework to AI engine for enhanced parsing...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Enhanced Homework Parsing Response Status: \(httpResponse.statusCode)")
                
                if let responseData = String(data: data, encoding: .utf8) {
                    if httpResponse.statusCode == 200 {
                        print("✅ Enhanced homework parsing successful")
                        print("📄 Response preview: \(String(responseData.prefix(200)))...")
                        return (true, responseData)
                    } else {
                        print("❌ Enhanced homework parsing failed: HTTP \(httpResponse.statusCode)")
                        return (false, "HTTP \(httpResponse.statusCode): \(responseData)")
                    }
                } else {
                    print("❌ No response data for enhanced homework parsing")
                    return (false, "No response data")
                }
            } else {
                print("❌ No HTTP response for enhanced homework parsing")
                return (false, "No HTTP response")
            }
        } catch {
            print("❌ Enhanced homework parsing request failed: \(error.localizedDescription)")
            return (false, error.localizedDescription)
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
    
    // MARK: - Session Archive Management
    
    /// Archive a session conversation to the backend database with image processing
    func archiveSession(sessionId: String, title: String? = nil, topic: String? = nil, subject: String? = nil, notes: String? = nil) async -> (success: Bool, message: String) {
        print("📦 === ARCHIVE CONVERSATION SESSION (WITH IMAGE PROCESSING) ===")
        print("📁 Session ID: \(sessionId)")
        print("📝 Title: \(title ?? "Auto-generated")")
        print("🏷️ Topic: \(topic ?? "Auto-generated from subject")")
        print("📚 Subject: \(subject ?? "General")")
        print("💭 Notes: \(notes ?? "None")")
        print("🔐 Auth Token Available: \(AuthenticationService.shared.getAuthToken() != nil)")
        
        // Check authentication first - use unified auth system  
        let token = AuthenticationService.shared.getAuthToken()
        guard let token = token else {
            print("❌ Authentication required for archiving")
            return (false, "Authentication required. Please login first.")
        }
        
        // ENHANCED: Process conversation history to handle images
        let processedConversation = await processConversationForArchive()
        print("🔍 Processed conversation: \(processedConversation.messageCount) messages")
        print("📷 Images processed: \(processedConversation.imagesProcessed)")
        if processedConversation.imagesProcessed > 0 {
            print("📝 Image summaries created: \(processedConversation.imageSummariesCreated)")
        }
        
        let archiveURL = "\(baseURL)/api/ai/sessions/\(sessionId)/archive"
        print("🔗 Archive URL: \(archiveURL)")
        
        guard let url = URL(string: archiveURL) else {
            print("❌ Invalid archive URL: \(archiveURL)")
            return (false, "Invalid URL")
        }
        
        // Build archive request body - ENHANCED FORMAT with processed conversation
        var archiveData: [String: Any] = [:]
        
        if let title = title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            archiveData["title"] = title
        } else {
            // Generate auto title based on subject and date
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            archiveData["title"] = "\(subject ?? "Study") Session - \(dateFormatter.string(from: Date()))"
        }
        
        if let subject = subject, !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            archiveData["subject"] = subject
        }
        
        if let topic = topic, !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            archiveData["topic"] = topic
        } else {
            // Use subject as default topic if no topic provided
            archiveData["topic"] = subject ?? "General Discussion"
        }
        
        if let notes = notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            archiveData["notes"] = notes
        }
        
        // ENHANCED: Add processed conversation content (images converted to summaries)
        archiveData["conversationContent"] = processedConversation.textContent
        archiveData["messageCount"] = processedConversation.messageCount
        archiveData["hasImageSummaries"] = processedConversation.imagesProcessed > 0
        archiveData["imageCount"] = processedConversation.imagesProcessed
        
        // Add detailed breakdown for debugging
        if processedConversation.imagesProcessed > 0 {
            let enhancedNotes = """
            \(notes ?? "")
            
            📸 Session contained \(processedConversation.imagesProcessed) image(s) that were converted to text summaries for storage.
            """
            archiveData["notes"] = enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        print("📤 Sending enhanced archive data: \(archiveData)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90.0 // Extended timeout for AI processing
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: archiveData)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Archive HTTP Status: \(httpResponse.statusCode)")
                
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("📄 Raw Archive Response: \(rawResponse)")
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        print("✅ Archive JSON Response: \(json)")
                        
                        if httpResponse.statusCode == 200 {
                            let success = json["success"] as? Bool ?? false
                            
                            if success {
                                let messageCount = json["messageCount"] as? Int ?? 0
                                let archiveId = json["archivedConversationId"] as? String ?? "unknown"
                                let archiveType = json["type"] as? String ?? "conversation"
                                
                                print("🎉 === ARCHIVE SUCCESS ===")
                                print("📁 Archive ID: \(archiveId)")
                                print("💬 Messages archived: \(messageCount)")
                                print("📦 Archive type: \(archiveType)")
                                print("🔍 IMPORTANT: Archive endpoint used: /api/ai/sessions/\(sessionId)/archive")
                                print("🔍 IMPORTANT: Response format: \(json)")
                                print("🔍 IMPORTANT: To retrieve, try endpoints like:")
                                print("   - /api/ai/sessions/archived")
                                print("   - /api/ai/archives/conversations")
                                print("   - /api/archive/conversations")
                                if let currentUserId = AuthenticationService.shared.currentUser?.id {
                                    print("   - /api/user/\(currentUserId)/conversations")
                                }
                                
                                // Invalidate cache so fresh data is loaded
                                invalidateCache()
                                
                                return (true, "Session archived successfully with \(messageCount) messages")
                            } else {
                                let error = json["error"] as? String ?? "Archive failed"
                                print("❌ Archive failed: \(error)")
                                return (false, error)
                            }
                        } else if httpResponse.statusCode == 401 {
                            print("❌ Authentication failed during archive")
                            // Let AuthenticationService handle auth state
                            return (false, "Authentication expired. Please login again.")
                        } else if httpResponse.statusCode == 404 {
                            print("❌ Session not found for archiving")
                            return (false, "Session not found or already archived")
                        } else if httpResponse.statusCode == 400 {
                            let error = json["error"] as? String ?? "Invalid request"
                            print("❌ Bad request: \(error)")
                            return (false, error)
                        } else {
                            let error = json["error"] as? String ?? "Archive failed"
                            print("❌ Archive HTTP \(httpResponse.statusCode): \(error)")
                            return (false, "Server error: \(error)")
                        }
                    } else {
                        print("❌ Failed to parse JSON response")
                        return (false, "Invalid response format: \(rawResponse)")
                    }
                } catch {
                    print("❌ JSON parsing error: \(error)")
                    print("📄 Raw response: \(rawResponse)")
                    return (false, "Invalid response format")
                }
            } else {
                print("❌ No HTTP response received")
                return (false, "No response from server")
            }
            
        } catch {
            print("❌ Archive request failed: \(error.localizedDescription)")
            return (false, "Network error: \(error.localizedDescription)")
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
    private func processConversationForArchive() async -> ProcessedConversation {
        print("🔄 === PROCESSING CONVERSATION FOR ARCHIVE ===")
        
        var processedMessages: [String] = []
        var imageCount = 0
        var summaryCount = 0
        
        for (index, message) in conversationHistory.enumerated() {
            let role = message["role"] ?? "unknown"
            let content = message["content"] ?? ""
            let hasImage = message["hasImage"] == "true"
            let messageId = message["messageId"] ?? ""
            
            print("📝 Processing message \(index): role=\(role), hasImage=\(hasImage)")
            
            if hasImage && !messageId.isEmpty {
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
        
        // Then, fetch archived questions (sequential, not concurrent)
        print("🔗 Step 2: Trying archived questions...")
        let questionsResult = await fetchArchivedQuestions(queryParams)
        if questionsResult.success, let questions = questionsResult.sessions {
            print("✅ Step 2: Found \(questions.count) archived questions")
            allSessions.append(contentsOf: questions)
        } else {
            print("⚠️ Step 2: No archived questions found")
        }
        
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
    
    private func fetchArchivedQuestions(_ queryParams: [String: String]) async -> (success: Bool, sessions: [[String: Any]]?) {
        // Try multiple endpoints for archived questions
        let endpoints = [
            "\(baseURL)/api/archive/questions",
            "\(baseURL)/api/user/questions/archived",
            "\(baseURL)/api/archive/homework"
        ]
        
        for endpoint in endpoints {
            let result = await tryFetchQuestionsFrom(endpoint, queryParams: queryParams)
            if result.success {
                return result
            }
        }
        
        // If no endpoint works, try to get from user's archived questions directly
        print("ℹ️ No questions endpoints available, will show empty list")
        return (true, [])
    }
    
    private func tryFetchQuestionsFrom(_ endpoint: String, queryParams: [String: String]) async -> (success: Bool, sessions: [[String: Any]]?) {
        var urlComponents = URLComponents(string: endpoint)!
        var allQueryParams = queryParams
        
        // Add user ID from centralized UserSessionManager
        if let userId = UserSessionManager.shared.currentUserId {
            allQueryParams["userId"] = userId
        }
        
        urlComponents.queryItems = allQueryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = urlComponents.url else {
            return (false, nil)
        }
        
        print("🔗 Trying Questions URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Add authentication if available from AuthenticationService only
        addAuthHeader(to: &request)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Questions Status (\(endpoint)): \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let success = json["success"] as? Bool, success,
                       let questions = json["data"] as? [[String: Any]] {
                        
                        print("📚 Found \(questions.count) archived questions from \(endpoint)")
                        
                        // Convert questions to session format for unified display
                        let convertedSessions = questions.map { question -> [String: Any] in
                            var session = question
                            // Ensure consistent format for display
                            if session["title"] == nil {
                                session["title"] = "Homework Session - \(session["subject"] as? String ?? "Study")"
                            }
                            if session["type"] == nil {
                                session["type"] = "homework"
                            }
                            // Add question count
                            if let questionsData = session["questions"] as? [[String: Any]] {
                                session["questionCount"] = questionsData.count
                            } else {
                                session["questionCount"] = 1 // Single question
                            }
                            // Add a session date if missing
                            if session["created_at"] == nil && session["sessionDate"] == nil {
                                session["created_at"] = ISO8601DateFormatter().string(from: Date())
                            }
                            return session
                        }
                        
                        return (true, convertedSessions)
                    } else if let rawResponse = String(data: data, encoding: .utf8) {
                        print("📄 Raw response: \(String(rawResponse.prefix(200)))")
                        // Try parsing as array directly
                        if let questions = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                            print("📚 Found \(questions.count) questions in direct array format")
                            return (true, questions)
                        }
                    }
                } else if httpResponse.statusCode == 404 {
                    print("ℹ️ Endpoint \(endpoint) not available (404)")
                    return (false, nil)
                } else {
                    print("⚠️ Endpoint \(endpoint) returned \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("❌ Questions request failed for \(endpoint): \(error.localizedDescription)")
        }
        
        return (false, nil)
    }
    
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
        print("👤 === GET USER PROFILE ===")
        
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
                print("✅ Profile Status: \(statusCode)")
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ Profile Response: \(json)")
                    
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
                print("✅ Update Profile Status: \(statusCode)")
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ Update Profile Response: \(json)")
                    
                    if statusCode == 200 {
                        let profile = json["profile"] as? [String: Any] ?? json
                        let message = json["message"] as? String ?? "Profile updated successfully"
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
    
    // MARK: - Subject Breakdown API Methods
    
    func fetchSubjectBreakdown(userId: String, timeframe: String = "current_week") async throws -> SubjectBreakdownResponse {
        let endpoint = "/api/progress/subject/breakdown/\(userId)"
        let fullURL = "\(baseURL)\(endpoint)?timeframe=\(timeframe)"
        
        print("🔍 DEBUG: Subject Breakdown API Call")
        print("🔗 Base URL: \(baseURL)")
        print("📍 Endpoint: \(endpoint)")
        print("🌐 Full URL: \(fullURL)")
        print("👤 User ID: \(userId)")
        print("⏰ Timeframe: \(timeframe)")
        print("🔐 Auth Token Available: \(AuthenticationService.shared.getAuthToken() != nil)")
        
        guard let url = URL(string: fullURL) else {
            print("❌ Invalid URL constructed: \(fullURL)")
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        
        print("📤 Making subject breakdown request...")
        print("🔍 Request Headers: \(request.allHTTPHeaderFields ?? [:])")
        
        do {
            let (data, response) = try await performRequest(request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Subject Breakdown Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    print("🎉 Subject breakdown API call successful")
                    
                    // Add comprehensive JSON debugging
                    let rawResponseString = String(data: data, encoding: .utf8) ?? "Unable to decode raw response"
                    print("🔍 === RAW API RESPONSE DEBUG ===")
                    print("📄 Raw JSON Response: \(rawResponseString)")
                    print("📏 Response Length: \(data.count) bytes")
                    print("🔍 Response Preview: \(String(rawResponseString.prefix(500)))...")
                    print("=====================================")
                    
                    do {
                        let decodedResponse = try JSONDecoder().decode(SubjectBreakdownResponse.self, from: data)
                        print("✅ JSON decoding successful!")
                        print("📊 Decoded response with \(decodedResponse.data?.subjectProgress.count ?? 0) subjects")
                        return decodedResponse
                    } catch {
                        print("❌ === JSON DECODING FAILED ===")
                        print("🚨 Decoding Error: \(error)")
                        print("🔍 Error Details: \(error.localizedDescription)")
                        
                        if let decodingError = error as? DecodingError {
                            switch decodingError {
                            case .typeMismatch(let type, let context):
                                print("🔴 Type Mismatch: Expected \(type), Context: \(context)")
                            case .valueNotFound(let type, let context):
                                print("🔴 Value Not Found: \(type), Context: \(context)")
                            case .keyNotFound(let key, let context):
                                print("🔴 Key Not Found: \(key), Context: \(context)")
                            case .dataCorrupted(let context):
                                print("🔴 Data Corrupted: \(context)")
                            @unknown default:
                                print("🔴 Unknown decoding error: \(decodingError)")
                            }
                        }
                        
                        // Try to decode as generic JSON to see the structure
                        do {
                            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                print("🔍 === JSON STRUCTURE ANALYSIS ===")
                                print("📊 Root Keys: \(Array(jsonObject.keys))")
                                
                                if let success = jsonObject["success"] as? Bool {
                                    print("✅ Success Field: \(success)")
                                }
                                
                                if let data = jsonObject["data"] as? [String: Any] {
                                    print("📦 Data Keys: \(Array(data.keys))")
                                    
                                    if let subjectProgress = data["subjectProgress"] as? [[String: Any]] {
                                        print("📚 Subject Progress Array Count: \(subjectProgress.count)")
                                        if let firstSubject = subjectProgress.first {
                                            print("🔍 First Subject Keys: \(Array(firstSubject.keys))")
                                            print("🔍 First Subject Data: \(firstSubject)")
                                        }
                                    }
                                    
                                    if let summary = data["summary"] as? [String: Any] {
                                        print("📋 Summary Keys: \(Array(summary.keys))")
                                    }
                                    
                                    if let insights = data["insights"] as? [String: Any] {
                                        print("💡 Insights Keys: \(Array(insights.keys))")
                                    }
                                } else {
                                    print("❌ No 'data' field found in response")
                                }
                                print("===================================")
                            }
                        } catch {
                            print("❌ Failed to parse as generic JSON: \(error)")
                        }
                        
                        throw error
                    }
                } else {
                    let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                    print("❌ Subject breakdown failed with status \(httpResponse.statusCode)")
                    print("📄 Raw response: \(rawResponse)")
                }
            }
            
            return try JSONDecoder().decode(SubjectBreakdownResponse.self, from: data)
        } catch {
            print("❌ Subject breakdown request failed: \(error.localizedDescription)")
            if let networkError = error as? NetworkError {
                print("🔍 Network error details: \(networkError.errorDescription ?? "Unknown")")
            }
            throw error
        }
    }
    
    func updateSubjectProgress(
        subject: String,
        questionCount: Int = 1,
        correctAnswers: Int = 0,
        studyTimeMinutes: Int = 0,
        topicBreakdown: [String: Int] = [:],
        difficultyLevel: String = "intermediate"
    ) async throws -> (success: Bool, message: String) {
        let endpoint = "/api/progress/subject/update"
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw NetworkError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "subject": subject,
            "questionCount": questionCount,
            "correctAnswers": correctAnswers,
            "studyTimeMinutes": studyTimeMinutes,
            "topicBreakdown": topicBreakdown,
            "difficultyLevel": difficultyLevel,
            "clientTimezone": TimeZone.current.identifier
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
        print("🔍 === CHECKING CONVERSATION EXISTS ===")
        print("🆔 Conversation ID: \(conversationId)")

        // Check authentication first
        guard AuthenticationService.shared.getAuthToken() != nil else {
            print("❌ No auth token available for conversation check")
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
                    print("✅ Conversation check (\(endpoint)): \(httpResponse.statusCode)")

                    if httpResponse.statusCode == 200 {
                        print("✅ Conversation exists: \(conversationId)")
                        return (true, nil)
                    } else if httpResponse.statusCode == 404 {
                        print("❌ Conversation not found at \(endpoint)")
                        continue // Try next endpoint
                    } else if httpResponse.statusCode == 401 {
                        print("❌ Authentication failed for conversation check")
                        return (false, "Authentication expired")
                    }
                }
            } catch {
                print("❌ Conversation check failed for \(endpoint): \(error.localizedDescription)")
                continue // Try next endpoint
            }
        }

        print("❌ Conversation does not exist: \(conversationId)")
        return (false, "Conversation not found")
    }

    // MARK: - Mistake Review Methods
    func getMistakeSubjects() async throws -> [SubjectMistakeCount] {
        guard let user = AuthenticationService.shared.currentUser else {
            throw NetworkError.authenticationRequired
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/api/archived-questions/mistakes/subjects/\(user.id)")!)
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