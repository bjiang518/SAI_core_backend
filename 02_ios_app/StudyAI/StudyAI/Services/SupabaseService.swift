//
//  SupabaseService.swift
//  StudyAI
//
//  Created by Claude Code on 9/4/25.
//

import Foundation
import Combine

class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    // Supabase Configuration for study.ai project
    // TODO: Replace with your actual study.ai project details
    private let supabaseURL = "https://zfrjpqmhezfcxzqbkivg.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpmcmpwcW1oZXpmY3h6cWJraXZnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTYzOTUxMTUsImV4cCI6MjA3MTk3MTExNX0._ePT9qbKj0-MjzXPjofLKBbYLZWQGsLyqNx6H4FgJ7c"
    
    private init() {}
    
    // Get current user ID from existing auth system
    private var currentUserId: String? {
        return UserDefaults.standard.string(forKey: "user_email") // Using email as user ID for now
    }
    
    // MARK: - Archive Session
    
    func archiveSession(_ request: ArchiveSessionRequest) async throws -> ArchivedSession {
        guard let userId = currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        print("📁 Archiving session for user: \(userId)")
        print("📚 Subject: \(request.subject)")
        print("📊 Questions: \(request.homeworkResult.questionCount)")
        
        // Detect subject category
        let detectedSubject = SubjectCategory.detectSubject(from: request.homeworkResult)
        let finalSubject = request.subject.isEmpty ? detectedSubject.rawValue : request.subject
        
        // Create archived session
        let archivedSession = ArchivedSession(
            userId: userId,
            subject: finalSubject,
            title: generateTitle(from: request.homeworkResult, subject: finalSubject),
            originalImageUrl: request.originalImageUrl,
            aiParsingResult: request.homeworkResult,
            processingTime: request.homeworkResult.processingTime,
            overallConfidence: request.homeworkResult.overallConfidence,
            studentAnswers: request.studentAnswers,
            notes: request.notes
        )
        
        // Convert to database format
        let dbData = try convertToDBFormat(archivedSession)
        
        // Insert into Supabase
        guard let url = URL(string: "\(supabaseURL)/rest/v1/archived_sessions") else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: dbData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        if httpResponse.statusCode == 201 {
            print("✅ Session archived successfully")
            return archivedSession
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Archive failed: \(errorMessage)")
            throw SupabaseError.archiveFailed(errorMessage)
        }
    }
    
    // MARK: - Fetch Archived Sessions
    
    func fetchArchivedSessions(limit: Int = 50, offset: Int = 0) async throws -> [SessionSummary] {
        guard let userId = currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        print("📚 Fetching archived sessions for user: \(userId)")
        
        let queryParams = [
            "select=id,subject,session_date,title,ai_parsing_result",
            "user_id=eq.\(userId)",
            "order=session_date.desc",
            "limit=\(limit)",
            "offset=\(offset)"
        ].joined(separator: "&")
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/archived_sessions?\(queryParams)") else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print("🔍 Response status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        print("🔍 Response data: \(String(data: data, encoding: .utf8) ?? "nil")")
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Fetch failed with status \((response as? HTTPURLResponse)?.statusCode ?? -1): \(errorMessage)")
            throw SupabaseError.fetchFailed(errorMessage)
        }
        
        print("🔍 Parsing JSON data...")
        let sessionData = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        print("🔍 Found \(sessionData.count) raw sessions")
        
        print("🔍 Converting sessions...")
        let sessions = try sessionData.map { sessionRecord in
            print("🔍 Converting session: \(sessionRecord["id"] as? String ?? "unknown")")
            return try convertFromDBFormat(sessionRecord)
        }
        
        print("✅ Fetched \(sessions.count) sessions")
        return sessions
    }
    
    // MARK: - Fetch by Subject
    
    func fetchSessionsBySubject(_ subject: String) async throws -> [SessionSummary] {
        guard let userId = currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        let queryParams = [
            "select=id,subject,session_date,title,ai_parsing_result",
            "user_id=eq.\(userId)",
            "subject=eq.\(subject)",
            "order=session_date.desc"
        ].joined(separator: "&")
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/archived_sessions?\(queryParams)") else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.fetchFailed(errorMessage)
        }
        
        let sessionData = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        let sessions = try sessionData.map { try convertFromDBFormat($0) }
        
        return sessions
    }
    
    // MARK: - Fetch by Date Range
    
    func fetchSessionsByDateRange(from startDate: Date, to endDate: Date) async throws -> [SessionSummary] {
        guard let userId = currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        let formatter = ISO8601DateFormatter()
        let startDateString = formatter.string(from: startDate)
        let endDateString = formatter.string(from: endDate)
        
        let queryParams = [
            "select=id,subject,session_date,title,ai_parsing_result",
            "user_id=eq.\(userId)",
            "session_date=gte.\(startDateString)",
            "session_date=lte.\(endDateString)",
            "order=session_date.desc"
        ].joined(separator: "&")
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/archived_sessions?\(queryParams)") else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.fetchFailed(errorMessage)
        }
        
        let sessionData = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        let sessions = try sessionData.map { try convertFromDBFormat($0) }
        
        return sessions
    }
    
    // MARK: - Get Full Session Details
    
    func getSessionDetails(sessionId: String) async throws -> ArchivedSession {
        guard let userId = currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        let queryParams = [
            "select=*",
            "id=eq.\(sessionId)",
            "user_id=eq.\(userId)"
        ].joined(separator: "&")
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/archived_sessions?\(queryParams)") else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.fetchFailed(errorMessage)
        }
        
        let sessionData = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        guard let firstSession = sessionData.first else {
            throw SupabaseError.sessionNotFound
        }
        
        return try convertFullSessionFromDBFormat(firstSession)
    }
    
    // MARK: - Update Review Count
    
    func incrementReviewCount(sessionId: String) async throws {
        guard let userId = currentUserId else {
            throw SupabaseError.notAuthenticated
        }
        
        let updateData = [
            "review_count": "review_count + 1",
            "last_reviewed_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        let queryParams = "id=eq.\(sessionId)&user_id=eq.\(userId)"
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/archived_sessions?\(queryParams)") else {
            throw SupabaseError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: updateData)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 204 else {
            throw SupabaseError.updateFailed
        }
    }
    
    // MARK: - Get Statistics
    
    func getArchiveStatistics() async throws -> ArchiveStatistics {
        // This would typically involve multiple database queries
        // For now, we'll implement a simplified version
        let sessions = try await fetchArchivedSessions(limit: 1000)
        
        let totalSessions = sessions.count
        let totalQuestions = sessions.reduce(0) { $0 + $1.questionCount }
        let averageConfidence = sessions.isEmpty ? 0 : sessions.reduce(0) { $0 + $1.overallConfidence } / Float(sessions.count)
        
        // Subject breakdown
        var subjectCounts: [SubjectCategory: Int] = [:]
        for session in sessions {
            let category = SubjectCategory(rawValue: session.subject) ?? .other
            subjectCounts[category, default: 0] += 1
        }
        
        let mostStudiedSubject = subjectCounts.max(by: { $0.value < $1.value })?.key
        
        // Calculate streak and recent activity
        let calendar = Calendar.current
        let today = Date()
        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let thisMonthStart = calendar.dateInterval(of: .month, for: today)?.start ?? today
        
        let thisWeekSessions = sessions.filter { $0.sessionDate >= thisWeekStart }.count
        let thisMonthSessions = sessions.filter { $0.sessionDate >= thisMonthStart }.count
        
        return ArchiveStatistics(
            totalSessions: totalSessions,
            totalQuestions: totalQuestions,
            averageConfidence: averageConfidence,
            mostStudiedSubject: mostStudiedSubject,
            streakDays: 0, // TODO: Implement streak calculation
            thisWeekSessions: thisWeekSessions,
            thisMonthSessions: thisMonthSessions,
            subjectBreakdown: subjectCounts
        )
    }
    
    // MARK: - Helper Methods
    
    private func generateTitle(from result: HomeworkParsingResult, subject: String) -> String {
        let questionCount = result.questionCount
        let date = DateFormatter().string(from: Date())
        
        if questionCount == 1 {
            return "\(subject) - 1 Question"
        } else {
            return "\(subject) - \(questionCount) Questions"
        }
    }
    
    private func convertToDBFormat(_ session: ArchivedSession) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let aiParsingData = try encoder.encode(session.aiParsingResult)
        let aiParsingJSON = try JSONSerialization.jsonObject(with: aiParsingData)
        
        return [
            "id": session.id,
            "user_id": session.userId,
            "subject": session.subject,
            "session_date": ISO8601DateFormatter().string(from: session.sessionDate),
            "title": session.title as Any,
            "original_image_url": session.originalImageUrl,
            "thumbnail_url": session.thumbnailUrl as Any,
            "ai_parsing_result": aiParsingJSON,
            "processing_time": session.processingTime,
            "overall_confidence": session.overallConfidence,
            "student_answers": session.studentAnswers as Any,
            "notes": session.notes as Any,
            "review_count": session.reviewCount,
            "last_reviewed_at": session.lastReviewedAt?.ISO8601Format() as Any,
            "created_at": ISO8601DateFormatter().string(from: session.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: session.updatedAt)
        ]
    }
    
    private func convertFromDBFormat(_ data: [String: Any]) throws -> SessionSummary {
        // Debug: Print all field types and values
        print("🔍 Debug data fields:")
        for (key, value) in data {
            print("  \(key): \(type(of: value)) = \(value)")
        }
        
        // Extract fields with flexible type handling
        guard let subject = data["subject"] as? String ?? data["subject"] as? NSString as String?,
              let sessionDateString = data["session_date"] as? String ?? data["session_date"] as? NSString as String?,
              let title = data["title"] as? String ?? data["title"] as? NSString as String? else {
            print("❌ Failed to extract required string fields")
            throw SupabaseError.invalidData
        }
        
        // ID is optional - generate one if missing
        let id = (data["id"] as? String ?? data["id"] as? NSString as String?) ?? UUID().uuidString
        
        // Parse date - handle both date-only and full datetime formats
        let sessionDate: Date
        if let fullDateTime = ISO8601DateFormatter().date(from: sessionDateString) {
            sessionDate = fullDateTime
        } else {
            // Try parsing date-only format like "2025-09-04"
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            if let dateOnly = dateFormatter.date(from: sessionDateString) {
                sessionDate = dateOnly
            } else {
                print("❌ Failed to parse session_date: \(sessionDateString)")
                throw SupabaseError.invalidData
            }
        }
        
        // Extract question count from ai_parsing_result with flexible handling
        let questionCount: Int
        if let aiParsingResult = data["ai_parsing_result"] as? [String: Any] {
            if let questions = aiParsingResult["questions"] as? [[String: Any]] {
                questionCount = questions.count
            } else if let questions = aiParsingResult["questions"] as? NSArray {
                questionCount = questions.count
            } else {
                print("⚠️ ai_parsing_result exists but no questions array found")
                questionCount = 0
            }
        } else {
            print("⚠️ ai_parsing_result not found or wrong type")
            questionCount = 0
        }
        
        print("✅ Successfully converted session: \(title) with \(questionCount) questions")
        
        // Use simplified SessionSummary with minimal fields
        return SessionSummary(
            id: id,
            subject: subject,
            sessionDate: sessionDate,
            title: title,
            questionCount: questionCount,
            overallConfidence: 1.0, // Default since we don't fetch this anymore
            thumbnailUrl: nil, // Not fetched for list view
            reviewCount: 0 // Not fetched for list view
        )
    }
    
    private func convertFullSessionFromDBFormat(_ data: [String: Any]) throws -> ArchivedSession {
        guard let id = data["id"] as? String,
              let userId = data["user_id"] as? String,
              let subject = data["subject"] as? String,
              let sessionDateString = data["session_date"] as? String,
              let originalImageUrl = data["original_image_url"] as? String,
              let aiParsingData = data["ai_parsing_result"] as? [String: Any],
              let processingTime = data["processing_time"] as? Double,
              let createdAtString = data["created_at"] as? String,
              let createdAt = ISO8601DateFormatter().date(from: createdAtString),
              let updatedAtString = data["updated_at"] as? String,
              let updatedAt = ISO8601DateFormatter().date(from: updatedAtString) else {
            print("❌ Missing required fields for full session conversion")
            throw SupabaseError.invalidData
        }
        
        // Parse date - handle both date-only and full datetime formats
        let sessionDate: Date
        if let fullDateTime = ISO8601DateFormatter().date(from: sessionDateString) {
            sessionDate = fullDateTime
        } else {
            // Try parsing date-only format like "2025-09-04"
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            if let dateOnly = dateFormatter.date(from: sessionDateString) {
                sessionDate = dateOnly
            } else {
                print("❌ Failed to parse session_date: \(sessionDateString)")
                throw SupabaseError.invalidData
            }
        }
        
        // Handle overall_confidence as either Int or Float
        let overallConfidence: Float
        if let floatConfidence = data["overall_confidence"] as? Float {
            overallConfidence = floatConfidence
        } else if let intConfidence = data["overall_confidence"] as? Int {
            overallConfidence = Float(intConfidence)
        } else {
            overallConfidence = 1.0 // Default
        }
        
        // Convert AI parsing result back to HomeworkParsingResult
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let aiParsingJsonData = try JSONSerialization.data(withJSONObject: aiParsingData)
        let aiParsingResult = try decoder.decode(HomeworkParsingResult.self, from: aiParsingJsonData)
        
        // Optional fields
        let title = data["title"] as? String
        let thumbnailUrl = data["thumbnail_url"] as? String
        let studentAnswers = data["student_answers"] as? [String: String]
        let notes = data["notes"] as? String
        let reviewCount = data["review_count"] as? Int ?? 0
        
        var lastReviewedAt: Date?
        if let lastReviewedAtString = data["last_reviewed_at"] as? String {
            lastReviewedAt = ISO8601DateFormatter().date(from: lastReviewedAtString)
        }
        
        return ArchivedSession(
            id: id,
            userId: userId,
            subject: subject,
            sessionDate: sessionDate,
            title: title,
            originalImageUrl: originalImageUrl,
            thumbnailUrl: thumbnailUrl,
            aiParsingResult: aiParsingResult,
            processingTime: processingTime,
            overallConfidence: overallConfidence,
            studentAnswers: studentAnswers,
            notes: notes,
            reviewCount: reviewCount,
            lastReviewedAt: lastReviewedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Supabase Errors

enum SupabaseError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case invalidData
    case archiveFailed(String)
    case fetchFailed(String)
    case updateFailed
    case sessionNotFound
    case notImplemented
    
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
        case .notImplemented:
            return "Feature not implemented"
        }
    }
}
