//
//  NetworkService.swift
//  StudyAI
//
//  Created by Claude Code on 8/30/25.
//

import Foundation
import Combine

class NetworkService: ObservableObject {
    static let shared = NetworkService()
    
    // Primary: Production Railway backend with integrated AI proxy
    private let baseURL = "https://sai-backend-production.up.railway.app"
    
    // Note: Authentication now managed by AuthenticationService only
    // NetworkService no longer stores auth data independently
    
    // Session Management
    @Published var currentSessionId: String?
    @Published var conversationHistory: [[String: String]] = []
    
    // MARK: - Caching for Archive Data
    private var cachedSessions: [[String: Any]]?
    private var lastCacheTime: Date?
    private let cacheValidityInterval: TimeInterval = 300 // 5 minutes cache validity
    
    private init() {
        // NetworkService no longer manages independent authentication
        // All auth is handled by AuthenticationService
    }
    
    // MARK: - Cache Management
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
    
    private func addAuthHeader(to request: inout URLRequest) {
        // Use AuthenticationService token exclusively
        if let unifiedToken = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(unifiedToken)", forHTTPHeaderField: "Authorization")
            
            // CRITICAL DEBUG: Show UID mismatch issue
            let currentUserId = UserSessionManager.shared.currentUserId ?? "unknown"
            let expectedServerUid = "81de989d-75ed-4c22-bbd3-146b8f6dcd26"
            let isFirebaseUid = currentUserId.contains("-") && currentUserId.count > 30
            
            print("🚨 === CRITICAL UID DEBUG ===")
            print("📱 iOS Current User ID: \(currentUserId)")
            print("🖥️ Expected Server UID: \(expectedServerUid)")
            print("🔍 Is using Firebase UID: \(isFirebaseUid)")
            print("❌ UID MISMATCH: \(currentUserId != expectedServerUid ? "YES - This is the bug!" : "NO - Fixed!")")
            print("🔍 Token preview: \(String(unifiedToken.prefix(20)))...")
            
            // Add debug info about expected user
            if let currentUser = AuthenticationService.shared.currentUser {
                print("📱 iOS User Info: ID=\(currentUser.id), Email=\(currentUser.email), Provider=\(currentUser.authProvider.rawValue)")
                print("🔍 User created at: \(currentUser.createdAt)")
            }
            print("===============================")
        } else {
            print("❌ No auth token available from AuthenticationService")
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
        request.timeoutInterval = 30.0
        
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
        print("🔍 === DEBUGGING AUTH TOKEN MAPPING ===")
        
        guard let token = AuthenticationService.shared.getAuthToken() else {
            return (false, nil, "No auth token available")
        }
        
        print("📱 iOS Expected User: \(UserSessionManager.shared.currentUserId ?? "unknown")")
        print("🔐 Token Preview: \(String(token.prefix(20)))...")
        
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
                print("✅ Debug Auth Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let backendUserId = json["id"] as? String ?? json["userId"] as? String {
                        print("🎯 Backend User ID: \(backendUserId)")
                        print("📊 Full Backend Response: \(json)")
                        return (true, backendUserId, "Backend maps token to user: \(backendUserId)")
                    }
                }
                
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("❌ Debug Auth Response: \(rawResponse)")
                return (false, nil, "HTTP \(httpResponse.statusCode): \(rawResponse)")
            }
            
        } catch {
            print("❌ Debug auth request failed: \(error.localizedDescription)")
            return (false, nil, "Network error: \(error.localizedDescription)")
        }
        
        return (false, nil, "Unknown error")
    }
    
    // MARK: - Progress Tracking
    func getProgress() async -> (success: Bool, progress: [String: Any]?) {
        print("📊 Testing progress tracking...")
        
        let progressURL = "\(baseURL)/api/progress"
        print("🔗 Using progress URL with bypass token")
        
        guard let url = URL(string: progressURL) else {
            return (false, nil)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Progress Status: \(httpResponse.statusCode)")
                
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ Progress: \(json)")
                    return (true, json)
                }
            }
            
            return (false, nil)
        } catch {
            print("❌ Progress fetch failed: \(error.localizedDescription)")
            return (false, nil)
        }
    }
    
    // MARK: - Debug OpenAI
    func debugOpenAI() async -> (success: Bool, debug: [String: Any]?) {
        print("🐛 Testing OpenAI debug endpoint...")
        
        let debugURL = "\(baseURL)/debug/openai"
        print("🔗 Using debug URL with bypass token")
        
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
    
    // MARK: - Image Upload and Analysis
    func uploadImageForAnalysis(imageData: Data, subject: String = "general") async -> (success: Bool, result: [String: Any]?) {
        print("📷 === IMAGE UPLOAD FOR ANALYSIS ===")
        print("🔗 AI Proxy URL: \(baseURL)/api/ai")
        print("📊 Image data size: \(imageData.count) bytes")
        print("📚 Subject: \(subject)")
        
        let imageUploadURL = "\(baseURL)/api/ai/analyze-image"
        print("🔗 Full upload URL: \(imageUploadURL)")
        
        guard let url = URL(string: imageUploadURL) else {
            print("❌ Invalid image upload URL")
            return (false, nil)
        }
        
        do {
            // Create multipart form data request
            let boundary = "StudyAI-iOS-\(UUID().uuidString)"
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 45.0  // Longer timeout for image processing
            
            // Build multipart form data
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
            
            request.httpBody = formData
            
            print("📡 Uploading image to AI Engine...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Image Upload Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("🎉 === IMAGE ANALYSIS SUCCESS ===")
                        print("✅ Server Response: \(json)")
                        
                        let extractedText = json["extracted_text"] as? String ?? ""
                        let hasMath = json["mathematical_content"] as? Bool ?? false
                        let confidence = json["confidence_score"] as? Double ?? 0.0
                        let suggestions = json["suggestions"] as? [String] ?? []
                        
                        print("📄 Extracted Text Length: \(extractedText.count)")
                        print("🧮 Contains Math: \(hasMath)")
                        print("🎯 Confidence: \(confidence)")
                        print("💡 Suggestions: \(suggestions.count) items")
                        
                        return (true, json)
                    }
                }
                
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("❌ Image Upload HTTP \(httpResponse.statusCode): \(String(rawResponse.prefix(200)))")
                return (false, ["error": "HTTP \(httpResponse.statusCode)", "details": rawResponse])
            }
            
            return (false, ["error": "No HTTP response"])
        } catch {
            print("❌ Image upload failed: \(error.localizedDescription)")
            return (false, ["error": error.localizedDescription])
        }
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
        request.timeoutInterval = 30.0
        
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
                        
                        // Update conversation history
                        await MainActor.run {
                            self.conversationHistory.append(["role": "user", "content": message])
                            self.conversationHistory.append(["role": "assistant", "content": aiResponse])
                            
                            // Additional debug for conversation history update
                            print("📚 === CONVERSATION HISTORY UPDATE ===")
                            print("👤 User Message Added: '\(message)'")
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
    
    // MARK: - Process Image with Question Context
    func processImageWithQuestion(imageData: Data, question: String = "", subject: String = "general") async -> (success: Bool, result: [String: Any]?) {
        print("📷 === IMAGE PROCESSING WITH QUESTION CONTEXT ===")
        print("🔗 AI Proxy URL: \(baseURL)/api/ai")
        print("📊 Image data size: \(imageData.count) bytes") 
        print("❓ Question: \(question)")
        print("📚 Subject: \(subject)")
        
        let imageProcessURL = "\(baseURL)/api/ai/process-image-question"
        print("🔗 Full process URL: \(imageProcessURL)")
        
        guard let url = URL(string: imageProcessURL) else {
            print("❌ Invalid image processing URL")
            return (false, nil)
        }
        
        do {
            // Create multipart form data request
            let boundary = "StudyAI-Process-\(UUID().uuidString)"
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 60.0  // Longer timeout for comprehensive processing
            
            // Build multipart form data
            var formData = Data()
            
            // Add image data
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition: form-data; name=\"image\"; filename=\"homework.jpg\"\r\n".data(using: .utf8)!)
            formData.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            formData.append(imageData)
            formData.append("\r\n".data(using: .utf8)!)
            
            // Add question parameter
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition: form-data; name=\"question\"\r\n\r\n".data(using: .utf8)!)
            formData.append(question.data(using: .utf8)!)
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
            
            request.httpBody = formData
            
            print("📡 Processing image with question context...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Image Processing Response Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("🎉 === IMAGE PROCESSING SUCCESS ===")
                        print("✅ Comprehensive AI Response received")
                        
                        // Extract the answer from the nested response structure
                        if let response = json["response"] as? [String: Any],
                           let answer = response["answer"] as? String {
                            print("📏 AI Answer Length: \(answer.count) characters")
                            print("🔍 Answer Preview: \(String(answer.prefix(100)))")
                            
                            // Create a simplified response format for compatibility
                            let simplifiedResponse = [
                                "answer": answer,
                                "success": true,
                                "processing_method": "image_analysis_with_gpt4o",
                                "image_analysis": json["image_analysis"] as Any,
                                "learning_analysis": json["learning_analysis"] as Any,
                                "processing_time_ms": json["processing_time_ms"] as Any
                            ] as [String: Any]
                            
                            return (true, simplifiedResponse)
                        }
                        
                        return (true, json)
                    }
                }
                
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("❌ Image Processing HTTP \(httpResponse.statusCode): \(String(rawResponse.prefix(200)))")
                return (false, ["error": "HTTP \(httpResponse.statusCode)", "details": rawResponse])
            }
            
            return (false, ["error": "No HTTP response"])
        } catch {
            print("❌ Image processing failed: \(error.localizedDescription)")
            return (false, ["error": error.localizedDescription])
        }
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
        request.timeoutInterval = 60.0 // Longer timeout for AI processing
        
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
        request.timeoutInterval = 60.0 // Longer timeout for AI processing
        
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
    
    /// Archive a session conversation to the backend database
    func archiveSession(sessionId: String, title: String? = nil, topic: String? = nil, subject: String? = nil, notes: String? = nil) async -> (success: Bool, message: String) {
        print("📦 === ARCHIVE CONVERSATION SESSION ===")
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
        
        let archiveURL = "\(baseURL)/api/ai/sessions/\(sessionId)/archive"
        print("🔗 Archive URL: \(archiveURL)")
        
        guard let url = URL(string: archiveURL) else {
            print("❌ Invalid archive URL: \(archiveURL)")
            return (false, "Invalid URL")
        }
        
        // Build archive request body - FIXED FORMAT
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
        
        print("📤 Sending archive data: \(archiveData)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0
        
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
    
    /// Get archived sessions list with query parameters for server-side filtering
    func getArchivedSessionsWithParams(_ queryParams: [String: String], forceRefresh: Bool = false) async -> (success: Bool, sessions: [[String: Any]]?, message: String) {
        print("📦 === GET ARCHIVED SESSIONS WITH CACHING ==")
        print("📄 Query Params: \(queryParams)")
        print("🔄 Force Refresh: \(forceRefresh)")
        
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
                return result
            }
        }
        
        // Then try the search endpoint with corrected parameters
        print("🔍 Trying search endpoint as fallback...")
        return await tryConversationSearch(queryParams)
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
}