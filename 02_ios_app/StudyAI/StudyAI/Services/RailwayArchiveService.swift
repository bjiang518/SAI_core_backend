//
//  RailwayArchiveService.swift
//  StudyAI
//
//  Railway-based archive service replacing direct Supabase calls
//

import Foundation

class RailwayArchiveService: ObservableObject {
    static let shared = RailwayArchiveService()
    
    // Use the same backend URL as NetworkService
    private let baseURL = "https://sai-backend-production.up.railway.app"
    
    private init() {}
    
    // Get current user ID (same logic as before)
    private var currentUserId: String? {
        return UserDefaults.standard.string(forKey: "user_email")
    }
    
    // MARK: - Archive Session
    
    func archiveSession(_ request: ArchiveSessionRequest) async throws -> ArchivedSession {
        guard let userId = currentUserId else {
            throw ArchiveError.notAuthenticated
        }
        
        print("📁 Archiving session via Railway backend...")
        print("📚 Subject: \(request.subject)")
        print("📊 Questions: \(request.homeworkResult.questionCount)")
        
        guard let url = URL(string: "\(baseURL)/api/archive/sessions") else {
            throw ArchiveError.invalidURL
        }
        
        let requestData: [String: Any] = [
            "subject": request.subject.isEmpty ? "General" : request.subject,
            "title": request.customTitle,
            "originalImageUrl": request.originalImageUrl ?? "temp://local-image",
            "thumbnailUrl": request.thumbnailUrl,
            "aiParsingResult": [
                "questions": request.homeworkResult.questions.map { question in
                    [
                        "questionNumber": question.questionNumber as Any,
                        "questionText": question.questionText,
                        "answerText": question.answerText,
                        "confidence": question.confidence,
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
        urlRequest.setValue(userId, forHTTPHeaderField: "X-User-ID") // Send user ID in header
        
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
                    title: request.customTitle,
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
    
    // MARK: - Fetch Archived Sessions
    
    func fetchArchivedSessions(limit: Int = 50, offset: Int = 0) async throws -> [SessionSummary] {
        guard let userId = currentUserId else {
            throw ArchiveError.notAuthenticated
        }
        
        print("📚 Fetching archived sessions from Railway backend...")
        
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
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ArchiveError.fetchFailed(errorMessage)
        }
        
        if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let sessionsData = jsonResponse["data"] as? [[String: Any]] {
            
            let sessions = try sessionsData.map { sessionData in
                try convertToSessionSummary(sessionData)
            }
            
            print("✅ Fetched \(sessions.count) sessions from Railway backend")
            return sessions
        }
        
        throw ArchiveError.invalidData
    }
    
    // MARK: - Fetch by Subject
    
    func fetchSessionsBySubject(_ subject: String) async throws -> [SessionSummary] {
        guard let userId = currentUserId else {
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
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        
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
        guard let userId = currentUserId else {
            throw ArchiveError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/api/archive/sessions/\(sessionId)") else {
            throw ArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        
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
    
    // MARK: - Update Review Count
    
    func incrementReviewCount(sessionId: String) async throws {
        guard let userId = currentUserId else {
            throw ArchiveError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/api/archive/sessions/\(sessionId)/review") else {
            throw ArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ArchiveError.updateFailed
        }
    }
    
    // MARK: - Get Statistics
    
    func getArchiveStatistics() async throws -> ArchiveStatistics {
        guard let userId = currentUserId else {
            throw ArchiveError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/api/archive/stats") else {
            throw ArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        
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
    
    private func convertToHomeworkParsingResult(_ data: [String: Any]) throws -> HomeworkParsingResult {
        guard let questionsData = data["questions"] as? [[String: Any]],
              let questionCount = data["questionCount"] as? Int else {
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
            rawAIResponse: "Parsed via Railway Backend"
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
        let subjectsStudied = data["subjectsStudied"] as? Int ?? 0
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