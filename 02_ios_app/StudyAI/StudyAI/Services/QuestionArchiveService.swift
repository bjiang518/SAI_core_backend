//
//  QuestionArchiveService.swift
//  StudyAI
//
//  Created by Claude Code on 9/4/25.
//

import Foundation
import Combine

class QuestionArchiveService: ObservableObject {
    static let shared = QuestionArchiveService()
    
    // Supabase Configuration (reuse from SupabaseService)
    private let supabaseURL = "https://zfrjpqmhezfcxzqbkivg.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpmcmpwcW1oZXpmY3h6cWJraXZnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTYzOTUxMTUsImV4cCI6MjA3MTk3MTExNX0._ePT9qbKj0-MjzXPjofLKBbYLZWQGsLyqNx6H4FgJ7c"
    
    private init() {}
    
    // Get current user ID from AuthenticationService
    private var currentUserId: String? {
        return AuthenticationService.shared.currentUser?.id
    }
    
    // MARK: - Archive Individual Questions
    
    func archiveQuestions(_ request: QuestionArchiveRequest) async throws -> [ArchivedQuestion] {
        guard let userId = currentUserId else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        print("📝 Archiving \(request.selectedQuestionIndices.count) questions for user: \(userId)")
        print("📚 Subject: \(request.detectedSubject)")
        
        var archivedQuestions: [ArchivedQuestion] = []
        
        // Process each selected question
        for (arrayIndex, questionIndex) in request.selectedQuestionIndices.enumerated() {
            guard questionIndex < request.questions.count else { continue }
            
            let question = request.questions[questionIndex]
            let userNotes = arrayIndex < request.userNotes.count ? request.userNotes[arrayIndex] : ""
            let userTags = arrayIndex < request.userTags.count ? request.userTags[arrayIndex] : []
            
            let archivedQuestion = ArchivedQuestion(
                userId: userId,
                subject: request.detectedSubject,
                questionText: question.questionText,
                answerText: question.answerText,
                confidence: question.confidence,
                hasVisualElements: question.hasVisualElements,
                originalImageUrl: request.originalImageUrl,
                processingTime: request.processingTime,
                tags: userTags,
                notes: userNotes
            )
            
            // Convert to database format
            let dbData = try convertQuestionToDBFormat(archivedQuestion)
            
            // Insert into Supabase
            try await insertQuestionToDB(dbData)
            
            archivedQuestions.append(archivedQuestion)
        }
        
        print("✅ Successfully archived \(archivedQuestions.count) questions")
        return archivedQuestions
    }
    
    // MARK: - Fetch Archived Questions
    
    func fetchArchivedQuestions(limit: Int = 50, offset: Int = 0) async throws -> [QuestionSummary] {
        guard let userId = currentUserId else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        print("📚 Fetching archived questions for user: \(userId)")
        
        let queryParams = [
            "select=id,subject,question_text,confidence,has_visual_elements,archived_at,review_count,tags",
            "user_id=eq.\(userId)",
            "order=archived_at.desc",
            "limit=\(limit)",
            "offset=\(offset)"
        ].joined(separator: "&")
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/archived_questions?\(queryParams)") else {
            throw QuestionArchiveError.invalidURL
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
            throw QuestionArchiveError.fetchFailed(errorMessage)
        }
        
        let questionData = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        let questions = try questionData.map { try convertQuestionSummaryFromDBFormat($0) }
        
        print("✅ Fetched \(questions.count) questions")
        return questions
    }
    
    // MARK: - Fetch Questions by Subject
    
    func fetchQuestionsBySubject(_ subject: String) async throws -> [QuestionSummary] {
        guard let userId = currentUserId else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        let queryParams = [
            "select=id,subject,question_text,confidence,has_visual_elements,archived_at,review_count,tags",
            "user_id=eq.\(userId)",
            "subject=eq.\(subject)",
            "order=archived_at.desc"
        ].joined(separator: "&")
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/archived_questions?\(queryParams)") else {
            throw QuestionArchiveError.invalidURL
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
            throw QuestionArchiveError.fetchFailed(errorMessage)
        }
        
        let questionData = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        let questions = try questionData.map { try convertQuestionSummaryFromDBFormat($0) }
        
        return questions
    }
    
    // MARK: - Get Full Question Details
    
    func getQuestionDetails(questionId: String) async throws -> ArchivedQuestion {
        guard let userId = currentUserId else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        let queryParams = [
            "select=*",
            "id=eq.\(questionId)",
            "user_id=eq.\(userId)"
        ].joined(separator: "&")
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/archived_questions?\(queryParams)") else {
            throw QuestionArchiveError.invalidURL
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
            throw QuestionArchiveError.fetchFailed(errorMessage)
        }
        
        let questionData = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        guard let firstQuestion = questionData.first else {
            throw QuestionArchiveError.questionNotFound
        }
        
        return try convertFullQuestionFromDBFormat(firstQuestion)
    }
    
    // MARK: - Search Questions
    
    func searchQuestions(filter: QuestionSearchFilter) async throws -> [QuestionSummary] {
        guard let userId = currentUserId else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        var queryParams = [
            "select=id,subject,question_text,confidence,has_visual_elements,archived_at,review_count,tags",
            "user_id=eq.\(userId)",
            "order=archived_at.desc"
        ]
        
        // Add filters
        if let subjects = filter.subjects, !subjects.isEmpty {
            let subjectFilter = subjects.map { "subject.eq.\($0)" }.joined(separator: ",")
            queryParams.append("or=(\(subjectFilter))")
        }
        
        if let confidenceRange = filter.confidenceRange {
            queryParams.append("confidence=gte.\(confidenceRange.lowerBound)")
            queryParams.append("confidence=lte.\(confidenceRange.upperBound)")
        }
        
        if let hasVisualElements = filter.hasVisualElements {
            queryParams.append("has_visual_elements=eq.\(hasVisualElements)")
        }
        
        let queryString = queryParams.joined(separator: "&")
        
        guard let url = URL(string: "\(supabaseURL)/rest/v1/archived_questions?\(queryString)") else {
            throw QuestionArchiveError.invalidURL
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
            throw QuestionArchiveError.fetchFailed(errorMessage)
        }
        
        let questionData = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        var questions = try questionData.map { try convertQuestionSummaryFromDBFormat($0) }
        
        // Apply text search (client-side for now)
        if let searchText = filter.searchText, !searchText.isEmpty {
            questions = questions.filter { question in
                question.questionText.localizedCaseInsensitiveContains(searchText) ||
                question.subject.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return questions
    }
    
    // MARK: - Helper Methods
    
    private func insertQuestionToDB(_ dbData: [String: Any]) async throws {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/archived_questions") else {
            throw QuestionArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: dbData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuestionArchiveError.invalidResponse
        }
        
        if httpResponse.statusCode != 201 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Question archive failed: \(errorMessage)")
            throw QuestionArchiveError.archiveFailed(errorMessage)
        }
    }
    
    private func convertQuestionToDBFormat(_ question: ArchivedQuestion) throws -> [String: Any] {
        return [
            "id": question.id,
            "user_id": question.userId,
            "subject": question.subject,
            "question_text": question.questionText,
            "answer_text": question.answerText,
            "confidence": question.confidence,
            "has_visual_elements": question.hasVisualElements,
            "original_image_url": question.originalImageUrl as Any,
            "question_image_url": question.questionImageUrl as Any,
            "processing_time": question.processingTime,
            "archived_at": ISO8601DateFormatter().string(from: question.archivedAt),
            "review_count": question.reviewCount,
            "last_reviewed_at": question.lastReviewedAt?.ISO8601Format() as Any,
            "tags": question.tags as Any,
            "notes": question.notes as Any
        ]
    }
    
    private func convertQuestionSummaryFromDBFormat(_ data: [String: Any]) throws -> QuestionSummary {
        guard let id = data["id"] as? String,
              let subject = data["subject"] as? String,
              let questionText = data["question_text"] as? String,
              let archivedAtString = data["archived_at"] as? String,
              let archivedAt = parseDate(archivedAtString) else {
            throw QuestionArchiveError.invalidData
        }
        
        let confidence = (data["confidence"] as? Float) ?? (data["confidence"] as? Int).map(Float.init) ?? 0.0
        let hasVisualElements = (data["has_visual_elements"] as? Bool) ?? false
        let reviewCount = (data["review_count"] as? Int) ?? 0
        let tags = data["tags"] as? [String]
        
        return QuestionSummary(
            id: id,
            subject: subject,
            questionText: questionText,
            confidence: confidence,
            hasVisualElements: hasVisualElements,
            archivedAt: archivedAt,
            reviewCount: reviewCount,
            tags: tags
        )
    }
    
    private func convertFullQuestionFromDBFormat(_ data: [String: Any]) throws -> ArchivedQuestion {
        guard let id = data["id"] as? String,
              let userId = data["user_id"] as? String,
              let subject = data["subject"] as? String,
              let questionText = data["question_text"] as? String,
              let answerText = data["answer_text"] as? String,
              let archivedAtString = data["archived_at"] as? String,
              let archivedAt = parseDate(archivedAtString) else {
            throw QuestionArchiveError.invalidData
        }
        
        let confidence = (data["confidence"] as? Float) ?? (data["confidence"] as? Int).map(Float.init) ?? 0.0
        let hasVisualElements = (data["has_visual_elements"] as? Bool) ?? false
        let processingTime = (data["processing_time"] as? Double) ?? 0.0
        let reviewCount = (data["review_count"] as? Int) ?? 0
        let originalImageUrl = data["original_image_url"] as? String
        let questionImageUrl = data["question_image_url"] as? String
        let tags = data["tags"] as? [String]
        let notes = data["notes"] as? String
        
        var lastReviewedAt: Date?
        if let lastReviewedAtString = data["last_reviewed_at"] as? String {
            lastReviewedAt = parseDate(lastReviewedAtString)
        }
        
        return ArchivedQuestion(
            id: id,
            userId: userId,
            subject: subject,
            questionText: questionText,
            answerText: answerText,
            confidence: confidence,
            hasVisualElements: hasVisualElements,
            originalImageUrl: originalImageUrl,
            questionImageUrl: questionImageUrl,
            processingTime: processingTime,
            archivedAt: archivedAt,
            reviewCount: reviewCount,
            lastReviewedAt: lastReviewedAt,
            tags: tags,
            notes: notes
        )
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        // Try ISO8601 first
        if let date = ISO8601DateFormatter().date(from: dateString) {
            return date
        }
        
        // Try date-only format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: dateString)
    }
}

// MARK: - Question Archive Errors

enum QuestionArchiveError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case invalidData
    case archiveFailed(String)
    case fetchFailed(String)
    case questionNotFound
    
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
            return "Failed to archive question: \(message)"
        case .fetchFailed(let message):
            return "Failed to fetch questions: \(message)"
        case .questionNotFound:
            return "Question not found"
        }
    }
}