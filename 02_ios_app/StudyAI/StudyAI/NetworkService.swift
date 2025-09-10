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
    
    // Authentication
    @Published var authToken: String?
    @Published var currentUser: [String: Any]?
    
    // Session Management
    @Published var currentSessionId: String?
    @Published var conversationHistory: [[String: String]] = []
    
    private init() {
        // Load saved token from UserDefaults on init
        loadSavedAuth()
    }
    
    // MARK: - Authentication Management
    private func saveAuth(token: String, user: [String: Any]) {
        UserDefaults.standard.set(token, forKey: "studyai_auth_token")
        
        // Clean the user dictionary to ensure it's property list compatible
        let cleanUser = cleanUserDictionary(user)
        UserDefaults.standard.set(cleanUser, forKey: "studyai_current_user")
        
        DispatchQueue.main.async {
            self.authToken = token
            self.currentUser = cleanUser
        }
    }
    
    // Clean user dictionary to be property list compatible
    private func cleanUserDictionary(_ user: [String: Any]) -> [String: Any] {
        var cleanedUser: [String: Any] = [:]
        
        for (key, value) in user {
            // Skip nil values entirely
            if value is NSNull {
                continue
            }
            
            // Handle different value types
            if let stringValue = value as? String {
                // Handle string values, including "null" strings
                if stringValue.lowercased() == "null" || stringValue == "<null>" {
                    continue  // Skip null string representations
                }
                cleanedUser[key] = stringValue
            } else if let numberValue = value as? NSNumber {
                cleanedUser[key] = numberValue
            } else if let boolValue = value as? Bool {
                cleanedUser[key] = boolValue
            } else if let dateValue = value as? Date {
                cleanedUser[key] = dateValue
            } else if let arrayValue = value as? [Any] {
                // Clean arrays recursively (though we don't expect them in user data)
                let cleanedArray = arrayValue.compactMap { item -> Any? in
                    if item is NSNull { return nil }
                    if let dict = item as? [String: Any] {
                        return cleanUserDictionary(dict)
                    }
                    return item
                }
                cleanedUser[key] = cleanedArray
            } else if let dictValue = value as? [String: Any] {
                // Recursively clean nested dictionaries
                let cleanedDict = cleanUserDictionary(dictValue)
                if !cleanedDict.isEmpty {
                    cleanedUser[key] = cleanedDict
                }
            } else {
                // Convert other types to string representation, but check for null representations
                let stringRep = String(describing: value)
                if stringRep.lowercased() != "null" && stringRep != "<null>" && stringRep != "nil" {
                    cleanedUser[key] = stringRep
                }
            }
        }
        
        print("🧹 Cleaned user dictionary: \(cleanedUser)")
        return cleanedUser
    }
    
    private func loadSavedAuth() {
        if let token = UserDefaults.standard.string(forKey: "studyai_auth_token"),
           let userData = UserDefaults.standard.dictionary(forKey: "studyai_current_user") {
            DispatchQueue.main.async {
                self.authToken = token
                self.currentUser = userData
            }
        }
    }
    
    func clearAuth() {
        UserDefaults.standard.removeObject(forKey: "studyai_auth_token")
        UserDefaults.standard.removeObject(forKey: "studyai_current_user")
        
        DispatchQueue.main.async {
            self.authToken = nil
            self.currentUser = nil
            self.currentSessionId = nil
            self.conversationHistory.removeAll()
        }
    }
    
    private func addAuthHeader(to request: inout URLRequest) {
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
    func login(email: String, password: String) async -> (success: Bool, message: String, token: String?, statusCode: Int?) {
        print("🔐 Testing login functionality...")
        
        let loginURL = "\(baseURL)/api/auth/login"
        print("🔗 Using Railway backend for login")
        
        guard let url = URL(string: loginURL) else {
            return (false, "Invalid URL", nil, nil)
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
                        if let token = json["token"] as? String,
                           let user = json["user"] as? [String: Any] {
                            // Save authentication data
                            saveAuth(token: token, user: user)
                            return (true, "Login successful", token, statusCode)
                        } else {
                            let token = json["token"] as? String
                            let message = json["message"] as? String ?? "Login successful"
                            return (true, message, token, statusCode)
                        }
                    } else {
                        let message = json["message"] as? String ?? "Login failed"
                        return (false, message, nil, statusCode)
                    }
                }
            }
            
            return (false, "Invalid response", nil, nil)
        } catch {
            let errorMsg = "Login request failed: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (false, errorMsg, nil, nil)
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
        // Check authentication first
        guard authToken != nil else {
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
                    // Authentication failed - clear stored auth
                    clearAuth()
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
        // Check authentication first
        guard authToken != nil else {
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
                    // Authentication failed - clear stored auth
                    clearAuth()
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
        // Check authentication first
        guard authToken != nil else {
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
                    // Authentication failed - clear stored auth
                    clearAuth()
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
            "prompt": prompt.isEmpty ? nil : prompt,
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
    func register(name: String, email: String, password: String) async -> (success: Bool, message: String, token: String?, statusCode: Int?) {
        print("📝 Testing registration functionality...")
        
        let registerURL = "\(baseURL)/api/auth/register"
        print("🔗 Using Railway backend for registration")
        
        guard let url = URL(string: registerURL) else {
            return (false, "Invalid URL", nil, nil)
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
                        if let token = json["token"] as? String,
                           let user = json["user"] as? [String: Any] {
                            // Save authentication data
                            saveAuth(token: token, user: user)
                            return (true, "Registration successful", token, statusCode)
                        } else {
                            let token = json["token"] as? String
                            return (true, "Registration successful", token, statusCode)
                        }
                    } else {
                        let message = json["message"] as? String ?? "Registration failed"
                        return (false, message, nil, statusCode)
                    }
                }
            }
            
            return (false, "Invalid response", nil, nil)
        } catch {
            let errorMsg = "Registration request failed: \(error.localizedDescription)"
            print("❌ \(errorMsg)")
            return (false, errorMsg, nil, nil)
        }
    }
    
    // MARK: - Google Authentication
    func googleLogin(idToken: String, accessToken: String?, name: String, email: String, profileImageUrl: String?) async -> (success: Bool, message: String, token: String?, statusCode: Int?) {
        print("🔐 Google authentication with Railway backend...")
        
        let googleURL = "\(baseURL)/api/auth/google"
        print("🔗 Using Railway backend for Google auth")
        
        guard let url = URL(string: googleURL) else {
            return (false, "Invalid URL", nil, nil)
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
                        
                        if success, let token = token, let user = json["user"] as? [String: Any] {
                            // Save authentication data
                            saveAuth(token: token, user: user)
                        }
                        
                        return (success, message, token, httpResponse.statusCode)
                    }
                } catch {
                    print("❌ JSON parsing error: \(error)")
                }
            }
            
        } catch {
            print("❌ Network error: \(error)")
            return (false, "Network error: \(error.localizedDescription)", nil, nil)
        }
        
        return (false, "Unknown error", nil, nil)
    }
    
    // MARK: - Session Archive Management
    
    /// Archive a session conversation to the backend database
    func archiveSession(sessionId: String, title: String? = nil, subject: String? = nil, notes: String? = nil) async -> (success: Bool, message: String) {
        print("📦 === ARCHIVE CONVERSATION SESSION ===")
        print("📁 Session ID: \(sessionId)")
        print("📝 Title: \(title ?? "Auto-generated")")
        print("📚 Subject: \(subject ?? "General")")
        print("💭 Notes: \(notes ?? "None")")
        print("🔐 Auth Token Available: \(authToken != nil)")
        
        // Check authentication first - CRITICAL FIX
        guard let token = authToken else {
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
                                
                                return (true, "Session archived successfully with \(messageCount) messages")
                            } else {
                                let error = json["error"] as? String ?? "Archive failed"
                                print("❌ Archive failed: \(error)")
                                return (false, error)
                            }
                        } else if httpResponse.statusCode == 401 {
                            print("❌ Authentication failed during archive")
                            clearAuth()
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
        
        // Add authentication if available
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
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