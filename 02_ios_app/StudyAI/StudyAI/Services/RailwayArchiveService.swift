//
//  RailwayArchiveService.swift
//  StudyAI
//
//  Railway-based archive service replacing direct Supabase calls
//

import Foundation
import Combine

class RailwayArchiveService: ObservableObject {
    static let shared = RailwayArchiveService()
    
    // Use the same backend URL as NetworkService
    private let baseURL = "https://sai-backend-production.up.railway.app"
    
    private init() {}
    
    // Get authentication token from AuthenticationService
    private var authToken: String? {
        return AuthenticationService.shared.getAuthToken()
    }
    
    // MARK: - Archive Session
    
    func archiveSession(_ request: ArchiveSessionRequest) async throws -> ArchivedSession {
        guard let token = authToken else {
            throw ArchiveError.notAuthenticated
        }
        
        guard let currentUser = AuthenticationService.shared.currentUser else {
            throw ArchiveError.notAuthenticated
        }
        let userId = currentUser.id
        
        print("📁 Archiving session via Railway backend...")
        print("📚 Subject: \(request.subject)")
        print("📊 Questions: \(request.homeworkResult.questionCount)")
        
        guard let url = URL(string: "\(baseURL)/api/archive/sessions") else {
            throw ArchiveError.invalidURL
        }
        
        let requestData: [String: Any] = [
            "subject": request.subject.isEmpty ? "General" : request.subject,
            "title": generateTitle(request.homeworkResult, request.subject),
            "originalImageUrl": (request.originalImageUrl as String?) as Any,
            "thumbnailUrl": (nil as String?) as Any,
            "aiParsingResult": [
                "questions": request.homeworkResult.questions.map { question in
                    [
                        "questionNumber": question.questionNumber as Any,
                        "questionText": question.questionText,
                        "answerText": question.answerText,
                        "confidence": (question.confidence as Float?) as Any,
                        "hasVisualElements": question.hasVisualElements
                    ]
                },
                "questionCount": request.homeworkResult.questionCount,
                "parsingMethod": request.homeworkResult.parsingMethod,
                "processingTime": request.homeworkResult.processingTime,
                "overallConfidence": request.homeworkResult.overallConfidence
            ],
            "processingTime": request.homeworkResult.processingTime,
            "overallConfidence": request.homeworkResult.overallConfidence,
            "studentAnswers": request.studentAnswers ?? [:],
            "notes": request.notes ?? ""
        ]
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestData)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ArchiveError.invalidResponse
        }
        
        if httpResponse.statusCode == 201 {
            if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseData = jsonResponse["data"] as? [String: Any],
               let sessionId = responseData["id"] as? String {
                
                print("✅ Session archived successfully with ID: \(sessionId)")
                
                // Create archived session object
                return ArchivedSession(
                    id: sessionId,
                    userId: userId,
                    subject: request.subject,
                    title: generateTitle(request.homeworkResult, request.subject),
                    originalImageUrl: request.originalImageUrl,
                    aiParsingResult: request.homeworkResult,
                    processingTime: request.homeworkResult.processingTime,
                    overallConfidence: request.homeworkResult.overallConfidence,
                    studentAnswers: request.studentAnswers,
                    notes: request.notes
                )
            }
        }
        
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        print("❌ Archive failed: \(errorMessage)")
        throw ArchiveError.archiveFailed(errorMessage)
    }
    
    // MARK: - Fetch Combined Archives (Conversations + Questions)
    
    func fetchArchivedSessions(limit: Int = 50, offset: Int = 0) async throws -> [SessionSummary] {
        guard authToken != nil else {
            throw ArchiveError.notAuthenticated
        }
        
        print("📚 Fetching archived items from Railway backend...")
        
        // Fetch both conversations and questions
        let conversations = try await fetchUserConversations(limit: limit/2, offset: offset)
        let questions = try await fetchUserQuestions(limit: limit/2, offset: offset)
        
        // Convert to SessionSummary format for compatibility
        var sessions: [SessionSummary] = []
        
        // Add conversations as sessions
        for conversation in conversations {
            let session = SessionSummary(
                id: conversation.id,
                subject: conversation.subject,
                sessionDate: conversation.archivedDate,
                title: conversation.topic ?? "Conversation",
                questionCount: 1, // Conversations count as 1 item
                overallConfidence: 1.0,
                thumbnailUrl: nil,
                reviewCount: 0
            )
            sessions.append(session)
        }
        
        // Add questions as sessions  
        for question in questions {
            let session = SessionSummary(
                id: question.id,
                subject: question.subject,
                sessionDate: question.archivedAt,
                title: question.questionText.count > 50 ? String(question.questionText.prefix(50)) + "..." : question.questionText,
                questionCount: 1,
                overallConfidence: question.confidence ?? 0.0,  // Default to 0 if nil
                thumbnailUrl: nil,
                reviewCount: question.reviewCount
            )
            sessions.append(session)
        }
        
        // Sort by date
        sessions.sort { $0.sessionDate > $1.sessionDate }
        
        print("✅ Fetched \(sessions.count) items from Railway backend")
        return sessions
    }
    
    // MARK: - Fetch Conversations
    
    func fetchUserConversations(limit: Int = 25, offset: Int = 0) async throws -> [ArchivedConversation] {
        guard let token = authToken else {
            throw ArchiveError.notAuthenticated
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)/api/ai/conversations")
        urlComponents?.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        
        guard let url = urlComponents?.url else {
            throw ArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ArchiveError.fetchFailed(errorMessage)
        }
        
        if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let conversationsData = jsonResponse["data"] as? [[String: Any]] {

            // 🔍 DEBUG: Log API response
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🔍 [ARCHIVE DEBUG] Fetched \(conversationsData.count) conversations from API")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

            let conversations = try conversationsData.enumerated().map { index, data in
                print("\n📦 [CONVERSATION #\(index + 1)]")
                return try convertToArchivedConversation(data)
            }

            return conversations
        }

        throw ArchiveError.invalidData
    }
    
    // MARK: - Fetch Questions
    
    func fetchUserQuestions(limit: Int = 25, offset: Int = 0) async throws -> [ArchivedQuestion] {
        guard let token = authToken else {
            throw ArchiveError.notAuthenticated
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)/api/archive/sessions")
        urlComponents?.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        
        guard let url = urlComponents?.url else {
            throw ArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ArchiveError.fetchFailed(errorMessage)
        }
        
        if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let questionsData = jsonResponse["data"] as? [[String: Any]] {
            
            return try questionsData.map { try convertToArchivedQuestion($0) }
        }
        
        throw ArchiveError.invalidData
    }
    
    // MARK: - Fetch by Subject
    
    func fetchSessionsBySubject(_ subject: String) async throws -> [SessionSummary] {
        guard let token = authToken else {
            throw ArchiveError.notAuthenticated
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)/api/archive/sessions")
        urlComponents?.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "limit", value: "100")
        ]
        
        guard let url = urlComponents?.url else {
            throw ArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ArchiveError.fetchFailed(errorMessage)
        }
        
        if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let sessionsData = jsonResponse["data"] as? [[String: Any]] {
            
            return try sessionsData.map { try convertToSessionSummary($0) }
        }
        
        throw ArchiveError.invalidData
    }
    
    // MARK: - Get Full Session Details
    
    func getSessionDetails(sessionId: String) async throws -> ArchivedSession {
        guard let token = authToken else {
            throw ArchiveError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/api/archive/sessions/\(sessionId)") else {
            throw ArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                throw ArchiveError.sessionNotFound
            }
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ArchiveError.fetchFailed(errorMessage)
        }
        
        if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let sessionData = jsonResponse["data"] as? [String: Any] {
            
            return try convertToArchivedSession(sessionData)
        }
        
        throw ArchiveError.invalidData
    }
    
    // MARK: - Get Conversation Details (for archived chat sessions)
    
    func getConversationDetails(conversationId: String) async throws -> ArchivedConversation {
        guard let token = authToken else {
            throw ArchiveError.notAuthenticated
        }

        // Try multiple endpoints since conversations are stored across different tables
        let endpoints = [
            "\(baseURL)/api/ai/archives/conversations/\(conversationId)",
            "\(baseURL)/api/archive/conversations/\(conversationId)",
            "\(baseURL)/api/conversations/\(conversationId)",
            "\(baseURL)/api/user/conversations/\(conversationId)"
        ]

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        // Try to parse the response
                        if let jsonResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            // Try different response formats
                            var conversationData: [String: Any]?

                            if let data = jsonResponse["data"] as? [String: Any] {
                                conversationData = data
                            } else if let conversation = jsonResponse["conversation"] as? [String: Any] {
                                conversationData = conversation
                            } else if jsonResponse["id"] != nil {
                                // Direct format
                                conversationData = jsonResponse
                            }

                            if let conversationData = conversationData {
                                return try convertToArchivedConversation(conversationData)
                            }
                        }
                    } else if httpResponse.statusCode == 404 {
                        continue
                    } else {
                        continue
                    }
                }
            } catch {
                continue
            }
        }

        // If no endpoint worked, throw not found error
        throw ArchiveError.sessionNotFound
    }
    
    // MARK: - Update Review Count
    
    func incrementReviewCount(sessionId: String) async throws {
        guard let token = authToken else {
            throw ArchiveError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/api/archive/sessions/\(sessionId)/review") else {
            throw ArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ArchiveError.updateFailed
        }
    }
    
    // MARK: - Get Statistics
    
    func getArchiveStatistics() async throws -> ArchiveStatistics {
        guard let token = authToken else {
            throw ArchiveError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/api/archive/stats") else {
            throw ArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ArchiveError.fetchFailed(errorMessage)
        }
        
        if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let statsData = jsonResponse["data"] as? [String: Any] {
            
            return try convertToArchiveStatistics(statsData)
        }
        
        throw ArchiveError.invalidData
    }
    
    // MARK: - Helper Methods
    
    private func convertToSessionSummary(_ data: [String: Any]) throws -> SessionSummary {
        guard let id = data["id"] as? String,
              let subject = data["subject"] as? String,
              let title = data["title"] as? String,
              let questionCount = data["questionCount"] as? Int,
              let overallConfidence = data["overallConfidence"] as? Double else {
            throw ArchiveError.invalidData
        }
        
        // Parse date
        let sessionDate: Date
        if let dateString = data["sessionDate"] as? String {
            let formatter = ISO8601DateFormatter()
            sessionDate = formatter.date(from: dateString) ?? Date()
        } else {
            sessionDate = Date()
        }
        
        return SessionSummary(
            id: id,
            subject: subject,
            sessionDate: sessionDate,
            title: title,
            questionCount: questionCount,
            overallConfidence: Float(overallConfidence),
            thumbnailUrl: data["thumbnailUrl"] as? String,
            reviewCount: data["reviewCount"] as? Int ?? 0
        )
    }
    
    private func convertToArchivedSession(_ data: [String: Any]) throws -> ArchivedSession {
        // Similar conversion logic but for full session data
        guard let id = data["id"] as? String,
              let userId = data["userId"] as? String,
              let subject = data["subject"] as? String,
              let originalImageUrl = data["originalImageUrl"] as? String,
              let aiParsingData = data["aiParsingResult"] as? [String: Any],
              let processingTime = data["processingTime"] as? Double,
              let overallConfidence = data["overallConfidence"] as? Double else {
            throw ArchiveError.invalidData
        }
        
        // Parse date
        let sessionDate: Date
        if let dateString = data["sessionDate"] as? String {
            let formatter = ISO8601DateFormatter()
            sessionDate = formatter.date(from: dateString) ?? Date()
        } else {
            sessionDate = Date()
        }
        
        // Convert AI parsing result
        let aiParsingResult = try convertToHomeworkParsingResult(aiParsingData)
        
        return ArchivedSession(
            id: id,
            userId: userId,
            subject: subject,
            sessionDate: sessionDate,
            title: data["title"] as? String,
            originalImageUrl: originalImageUrl,
            thumbnailUrl: data["thumbnailUrl"] as? String,
            aiParsingResult: aiParsingResult,
            processingTime: processingTime,
            overallConfidence: Float(overallConfidence),
            studentAnswers: data["studentAnswers"] as? [String: String],
            notes: data["notes"] as? String,
            reviewCount: data["reviewCount"] as? Int ?? 0,
            lastReviewedAt: nil, // Parse if needed
            createdAt: sessionDate, // Use session date as fallback
            updatedAt: sessionDate  // Use session date as fallback
        )
    }
    
    private func convertToArchivedConversation(_ data: [String: Any]) throws -> ArchivedConversation {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔄 [ARCHIVE DEBUG] Converting conversation data")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        // Log all available keys in the data dictionary
        print("\n📋 [RAW DATA] Available keys and values:")
        for key in data.keys.sorted() {
            let value = data[key]
            if let stringValue = value as? String {
                let preview = stringValue.count > 100 ? String(stringValue.prefix(100)) + "..." : stringValue
                print("   • \(key): \(preview)")
            } else if let intValue = value as? Int {
                print("   • \(key): \(intValue)")
            } else if let arrayValue = value as? [Any] {
                print("   • \(key): [Array with \(arrayValue.count) items]")
            } else if let dictValue = value as? [String: Any] {
                print("   • \(key): [Dictionary with \(dictValue.keys.count) keys]")
            } else {
                print("   • \(key): \(type(of: value))")
            }
        }

        // Handle different field name variations from different tables
        guard let id = data["id"] as? String else {
            print("❌ [EXTRACT ERROR] Missing required field: id")
            throw ArchiveError.invalidData
        }
        print("\n✅ [EXTRACT] id = \(id)")
        
        // Try different user ID field names
        let userId = data["user_id"] as? String ?? 
                    data["userId"] as? String ?? 
                    data["user"] as? String
        
        guard let userId = userId else {
            print("❌ [EXTRACT ERROR] Missing required field: user_id/userId")
            throw ArchiveError.invalidData
        }
        print("✅ [EXTRACT] userId = \(userId)")

        // Try different subject field names
        let subject = data["subject"] as? String ?? "General"
        print("✅ [EXTRACT] subject = \(subject)")

        // Try different conversation content field names
        let conversationContent = data["conversation_content"] as? String ??
                                 data["conversationContent"] as? String ??
                                 data["content"] as? String ??
                                 data["messages"] as? String

        guard let conversationContent = conversationContent else {
            print("❌ [EXTRACT ERROR] Missing required field: conversation_content/conversationContent")
            throw ArchiveError.invalidData
        }
        let contentPreview = conversationContent.count > 200 ? String(conversationContent.prefix(200)) + "..." : conversationContent
        print("✅ [EXTRACT] conversationContent (length: \(conversationContent.count)): \(contentPreview)")

        // Parse date - try multiple field names and formats
        let archivedDate: Date
        let dateString = data["archived_date"] as? String ??
                        data["archivedDate"] as? String ??
                        data["archived_at"] as? String ??
                        data["created_at"] as? String ??
                        data["createdAt"] as? String

        if let dateString = dateString {
            let formatter = ISO8601DateFormatter()
            archivedDate = formatter.date(from: dateString) ?? Date()
        } else {
            archivedDate = Date()
        }
        print("✅ [EXTRACT] archivedDate = \(archivedDate)")

        // ✅ NEW: Extract AI-generated analysis fields from backend
        print("\n🤖 [AI ANALYSIS] Extracting AI-generated fields from backend:")

        let title = data["title"] as? String
        if let title = title {
            print("   ✅ title = \(title)")
        } else {
            print("   ⚠️ title = nil (NOT PROVIDED BY BACKEND)")
        }

        let summary = data["summary"] as? String
        if let summary = summary {
            print("   ✅ summary = \(summary)")
        } else {
            print("   ⚠️ summary = nil (NOT PROVIDED BY BACKEND)")
        }

        // Parse keyTopics (can be array or JSON string)
        print("\n🔍 [PARSING] keyTopics:")
        let keyTopics: [String]?
        if let topicsArray = data["keyTopics"] as? [String] {
            keyTopics = topicsArray
            print("   ✅ Found as array: \(topicsArray)")
        } else if let topicsArray = data["key_topics"] as? [String] {
            keyTopics = topicsArray
            print("   ✅ Found as array (snake_case): \(topicsArray)")
        } else if let topicsJSON = data["keyTopics"] as? String,
                  let jsonData = topicsJSON.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
            keyTopics = decoded
            print("   ✅ Parsed from JSON string: \(decoded)")
        } else if let topicsJSON = data["key_topics"] as? String,
                  let jsonData = topicsJSON.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
            keyTopics = decoded
            print("   ✅ Parsed from JSON string (snake_case): \(decoded)")
        } else {
            keyTopics = nil
            print("   ⚠️ keyTopics = nil (NOT PROVIDED BY BACKEND)")
        }

        // Parse learningOutcomes (can be array or JSON string)
        print("\n🔍 [PARSING] learningOutcomes:")
        let learningOutcomes: [String]?
        if let outcomesArray = data["learningOutcomes"] as? [String] {
            learningOutcomes = outcomesArray
            print("   ✅ Found as array: \(outcomesArray)")
        } else if let outcomesArray = data["learning_outcomes"] as? [String] {
            learningOutcomes = outcomesArray
            print("   ✅ Found as array (snake_case): \(outcomesArray)")
        } else if let outcomesJSON = data["learningOutcomes"] as? String,
                  let jsonData = outcomesJSON.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
            learningOutcomes = decoded
            print("   ✅ Parsed from JSON string: \(decoded)")
        } else if let outcomesJSON = data["learning_outcomes"] as? String,
                  let jsonData = outcomesJSON.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
            learningOutcomes = decoded
            print("   ✅ Parsed from JSON string (snake_case): \(decoded)")
        } else {
            learningOutcomes = nil
            print("   ⚠️ learningOutcomes = nil (NOT PROVIDED BY BACKEND)")
        }

        let messageCount = data["messageCount"] as? Int ?? data["message_count"] as? Int
        print("\n✅ [EXTRACT] messageCount = \(messageCount?.description ?? "nil")")

        let durationMinutes = data["durationMinutes"] as? Int ?? data["duration_minutes"] as? Int
        print("✅ [EXTRACT] durationMinutes = \(durationMinutes?.description ?? "nil")")

        // Use title first, then topic, then fallback
        let topic = title ?? data["topic"] as? String

        print("\n🏁 [FINAL VALUES] Creating ArchivedConversation:")
        print("   • id: \(id)")
        print("   • userId: \(userId)")
        print("   • subject: \(subject)")
        print("   • topic: \(topic ?? "nil")")
        print("   • title (for display): \(title ?? "nil")")
        print("   • summary (for display): \(summary ?? "nil")")
        print("   • keyTopics: \(keyTopics?.description ?? "nil")")
        print("   • learningOutcomes: \(learningOutcomes?.description ?? "nil")")
        print("   • messageCount: \(messageCount?.description ?? "nil")")
        print("   • durationMinutes: \(durationMinutes?.description ?? "nil")")
        print("   • conversationContent length: \(conversationContent.count)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")

        return ArchivedConversation(
            id: id,
            userId: userId,
            subject: subject,
            topic: topic,
            conversationContent: conversationContent,
            archivedDate: archivedDate,
            createdAt: archivedDate,
            diagrams: nil,
            summary: summary,
            keyTopics: keyTopics,
            learningOutcomes: learningOutcomes,
            estimatedDuration: durationMinutes,
            behaviorSummary: nil
        )
    }
    
    private func convertToHomeworkParsingResult(_ data: [String: Any]) throws -> HomeworkParsingResult {
        guard let questionsData = data["questions"] as? [[String: Any]],
              let _ = data["questionCount"] as? Int else {
            throw ArchiveError.invalidData
        }
        
        let questions = try questionsData.map { questionData in
            try convertToParsedQuestion(questionData)
        }
        
        return HomeworkParsingResult(
            questions: questions,
            processingTime: data["processingTime"] as? Double ?? 0,
            overallConfidence: Float(data["overallConfidence"] as? Double ?? 0),
            parsingMethod: data["parsingMethod"] as? String ?? "Railway Backend",
            rawAIResponse: "Parsed via Railway Backend",
            performanceSummary: nil
        )
    }
    
    private func convertToParsedQuestion(_ data: [String: Any]) throws -> ParsedQuestion {
        guard let questionText = data["questionText"] as? String,
              let answerText = data["answerText"] as? String,
              let confidence = data["confidence"] as? Double else {
            throw ArchiveError.invalidData
        }
        
        return ParsedQuestion(
            questionNumber: data["questionNumber"] as? Int,
            questionText: questionText,
            answerText: answerText,
            confidence: Float(confidence),
            hasVisualElements: data["hasVisualElements"] as? Bool ?? false
        )
    }
    
    private func convertToArchiveStatistics(_ data: [String: Any]) throws -> ArchiveStatistics {
        let totalSessions = data["totalSessions"] as? Int ?? 0
        let _ = data["subjectsStudied"] as? Int ?? 0
        let averageConfidence = Float(data["averageConfidence"] as? Double ?? 0)
        let totalQuestions = data["totalQuestions"] as? Int ?? 0
        let thisWeekSessions = data["thisWeekSessions"] as? Int ?? 0
        let thisMonthSessions = data["thisMonthSessions"] as? Int ?? 0
        
        // Convert subject breakdown
        var subjectBreakdown: [SubjectCategory: Int] = [:]
        if let breakdownData = data["subjectBreakdown"] as? [[String: Any]] {
            for item in breakdownData {
                if let subject = item["subject"] as? String,
                   let count = item["sessionCount"] as? Int {
                    let category = SubjectCategory(rawValue: subject) ?? .other
                    subjectBreakdown[category] = count
                }
            }
        }
        
        return ArchiveStatistics(
            totalSessions: totalSessions,
            totalQuestions: totalQuestions,
            averageConfidence: averageConfidence,
            mostStudiedSubject: subjectBreakdown.max(by: { $0.value < $1.value })?.key,
            streakDays: 0, // TODO: Implement from backend
            thisWeekSessions: thisWeekSessions,
            thisMonthSessions: thisMonthSessions,
            subjectBreakdown: subjectBreakdown
        )
    }
    
    // MARK: - Helper Functions
    
    private func convertToArchivedQuestion(_ data: [String: Any]) throws -> ArchivedQuestion {
        guard let _ = data["id"] as? String,
              let userId = data["userId"] as? String ?? data["user_id"] as? String,
              let subject = data["subject"] as? String,
              let questionText = data["questionText"] as? String ?? data["question_text"] as? String else {
            throw ArchiveError.invalidData
        }
        
        // Parse date
        let archivedDate: Date
        if let dateString = data["archivedDate"] as? String ?? data["archived_date"] as? String {
            let formatter = ISO8601DateFormatter()
            archivedDate = formatter.date(from: dateString) ?? Date()
        } else {
            archivedDate = Date()
        }
        
        // Map backend question format to existing ArchivedQuestion structure
        let answerText = data["aiAnswer"] as? String ?? data["ai_answer"] as? String ?? ""
        let confidence = data["confidenceScore"] as? Float ?? data["confidence_score"] as? Float ?? 0.0
        
        return ArchivedQuestion(
            userId: userId,
            subject: subject,
            questionText: questionText,
            answerText: answerText,
            confidence: confidence,
            hasVisualElements: false, // Backend doesn't store this currently
            originalImageUrl: nil,
            questionImageUrl: nil,
            processingTime: 0.0,
            archivedAt: archivedDate,
            parentQuestionId: nil,
            subquestionId: nil
        )
    }
    
    private func generateTitle(_ homeworkResult: HomeworkParsingResult, _ subject: String) -> String {
        let questionCount = homeworkResult.questionCount
        let date = Date().formatted(date: .abbreviated, time: .omitted)
        
        if questionCount == 1 {
            return "\(subject) - 1 Question (\(date))"
        } else if questionCount > 1 {
            return "\(subject) - \(questionCount) Questions (\(date))"
        } else {
            return "\(subject) Study Session (\(date))"
        }
    }
}

// MARK: - Archive Errors

enum ArchiveError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case invalidData
    case archiveFailed(String)
    case fetchFailed(String)
    case updateFailed
    case sessionNotFound
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidData:
            return "Invalid data format"
        case .archiveFailed(let message):
            return "Failed to archive session: \(message)"
        case .fetchFailed(let message):
            return "Failed to fetch sessions: \(message)"
        case .updateFailed:
            return "Failed to update session"
        case .sessionNotFound:
            return "Session not found"
        }
    }
}
