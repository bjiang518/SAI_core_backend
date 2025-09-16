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
    
    // Railway Backend Configuration
    private let baseURL = "https://sai-backend-production.up.railway.app"
    
    private init() {}
    
    // Get authentication token from AuthenticationService
    private var authToken: String? {
        return AuthenticationService.shared.getAuthToken()
    }
    
    // Get current user ID from AuthenticationService
    private var currentUserId: String? {
        return AuthenticationService.shared.currentUser?.id
    }
    
    // MARK: - Archive Individual Questions
    
    func archiveQuestions(_ request: QuestionArchiveRequest) async throws -> [ArchivedQuestion] {
        guard let userId = currentUserId else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        guard let token = authToken else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        print("📝 Archiving \(request.selectedQuestionIndices.count) questions for user: \(userId)")
        print("📚 Subject: \(request.detectedSubject)")
        
        guard let url = URL(string: "\(baseURL)/api/archived-questions") else {
            throw QuestionArchiveError.invalidURL
        }
        
        // Prepare request data for Railway API
        let requestData: [String: Any] = [
            "selectedQuestionIndices": request.selectedQuestionIndices,
            "questions": request.questions.map { question in
                [
                    "questionText": question.questionText,
                    "answerText": question.answerText,
                    "confidence": question.confidence,
                    "hasVisualElements": question.hasVisualElements,
                    "studentAnswer": question.studentAnswer ?? "",
                    "correctAnswer": question.correctAnswer ?? question.answerText,
                    "grade": question.grade ?? "EMPTY",
                    "pointsEarned": question.pointsEarned ?? 0.0,
                    "pointsPossible": question.pointsPossible ?? 1.0,
                    "feedback": question.feedback ?? ""
                ]
            },
            "userNotes": request.userNotes,
            "userTags": request.userTags,
            "detectedSubject": request.detectedSubject,
            "originalImageUrl": request.originalImageUrl ?? "",
            "processingTime": request.processingTime
        ]
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestData)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuestionArchiveError.invalidResponse
        }
        
        if httpResponse.statusCode != 201 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Question archive failed: \(errorMessage)")
            throw QuestionArchiveError.archiveFailed(errorMessage)
        }
        
        // Parse response
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = jsonResponse["success"] as? Bool,
              success == true,
              let responseData = jsonResponse["data"] as? [[String: Any]] else {
            throw QuestionArchiveError.invalidData
        }
        
        // Convert response to ArchivedQuestions
        var archivedQuestions: [ArchivedQuestion] = []
        
        for (index, questionIndex) in request.selectedQuestionIndices.enumerated() {
            guard questionIndex < request.questions.count else { continue }
            
            let question = request.questions[questionIndex]
            let userNote = index < request.userNotes.count ? request.userNotes[index] : ""
            let userTag = index < request.userTags.count ? request.userTags[index] : []
            
            // Create ArchivedQuestion from response and original data
            let archivedQuestion = ArchivedQuestion(
                userId: userId,
                subject: request.detectedSubject,
                questionText: question.questionText,
                answerText: question.answerText,
                confidence: question.confidence,
                hasVisualElements: question.hasVisualElements,
                originalImageUrl: request.originalImageUrl,
                processingTime: request.processingTime,
                tags: userTag,
                notes: userNote,
                studentAnswer: question.studentAnswer,
                grade: question.grade.map { GradeResult(rawValue: $0) } ?? nil,
                points: question.pointsEarned,
                maxPoints: question.pointsPossible,
                feedback: question.feedback,
                isGraded: question.grade != nil
            )
            
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
        
        guard let token = authToken else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        print("📚 Fetching archived questions for user: \(userId)")
        
        var urlComponents = URLComponents(string: "\(baseURL)/api/archived-questions")!
        urlComponents.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        
        guard let url = urlComponents.url else {
            throw QuestionArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw QuestionArchiveError.fetchFailed(errorMessage)
        }
        
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = jsonResponse["success"] as? Bool,
              success == true,
              let questionData = jsonResponse["data"] as? [[String: Any]] else {
            throw QuestionArchiveError.invalidData
        }
        
        let questions = try questionData.map { try convertQuestionSummaryFromRailwayFormat($0) }
        
        print("✅ Fetched \(questions.count) questions")
        return questions
    }
    
    // MARK: - Fetch Questions by Subject
    
    func fetchQuestionsBySubject(_ subject: String) async throws -> [QuestionSummary] {
        guard let userId = currentUserId else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        guard let token = authToken else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/api/archived-questions/subject/\(subject)") else {
            throw QuestionArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw QuestionArchiveError.fetchFailed(errorMessage)
        }
        
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = jsonResponse["success"] as? Bool,
              success == true,
              let questionData = jsonResponse["data"] as? [[String: Any]] else {
            throw QuestionArchiveError.invalidData
        }
        
        let questions = try questionData.map { try convertQuestionSummaryFromRailwayFormat($0) }
        
        return questions
    }
    
    // MARK: - Get Full Question Details
    
    func getQuestionDetails(questionId: String) async throws -> ArchivedQuestion {
        guard let userId = currentUserId else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        guard let token = authToken else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        guard let url = URL(string: "\(baseURL)/api/archived-questions/\(questionId)") else {
            throw QuestionArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw QuestionArchiveError.fetchFailed(errorMessage)
        }
        
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = jsonResponse["success"] as? Bool,
              success == true,
              let questionData = jsonResponse["data"] as? [String: Any] else {
            throw QuestionArchiveError.invalidData
        }
        
        return try convertFullQuestionFromRailwayFormat(questionData)
    }
    
    // MARK: - Search Questions
    
    func searchQuestions(filter: QuestionSearchFilter) async throws -> [QuestionSummary] {
        guard let userId = currentUserId else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        guard let token = authToken else {
            throw QuestionArchiveError.notAuthenticated
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)/api/archived-questions")!
        var queryItems: [URLQueryItem] = []
        
        // Add filters
        if let subjects = filter.subjects, !subjects.isEmpty {
            // For multiple subjects, we'll use the first one for now
            // The API could be enhanced to support multiple subjects
            queryItems.append(URLQueryItem(name: "subject", value: subjects.first))
        }
        
        if let confidenceRange = filter.confidenceRange {
            queryItems.append(URLQueryItem(name: "confidenceMin", value: String(confidenceRange.lowerBound)))
            queryItems.append(URLQueryItem(name: "confidenceMax", value: String(confidenceRange.upperBound)))
        }
        
        if let hasVisualElements = filter.hasVisualElements {
            queryItems.append(URLQueryItem(name: "hasVisualElements", value: String(hasVisualElements)))
        }
        
        if let searchText = filter.searchText, !searchText.isEmpty {
            queryItems.append(URLQueryItem(name: "searchText", value: searchText))
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw QuestionArchiveError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw QuestionArchiveError.fetchFailed(errorMessage)
        }
        
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = jsonResponse["success"] as? Bool,
              success == true,
              let questionData = jsonResponse["data"] as? [[String: Any]] else {
            throw QuestionArchiveError.invalidData
        }
        
        let questions = try questionData.map { try convertQuestionSummaryFromRailwayFormat($0) }
        
        return questions
    }
    
    // MARK: - Helper Methods
    
    private func convertQuestionSummaryFromRailwayFormat(_ data: [String: Any]) throws -> QuestionSummary {
        guard let id = data["id"] as? String,
              let subject = data["subject"] as? String,
              let questionText = data["questionText"] as? String,
              let archivedAtString = data["archivedAt"] as? String,
              let archivedAt = parseDate(archivedAtString) else {
            throw QuestionArchiveError.invalidData
        }
        
        let confidence = (data["confidence"] as? Float) ?? (data["confidence"] as? Double).map(Float.init) ?? 0.0
        let hasVisualElements = (data["hasVisualElements"] as? Bool) ?? false
        let reviewCount = (data["reviewCount"] as? Int) ?? 0
        let tags = data["tags"] as? [String]
        
        // Grading fields
        let gradeString = data["grade"] as? String
        let grade = gradeString != nil ? GradeResult(rawValue: gradeString!) : nil
        let points = (data["points"] as? Float) ?? (data["points"] as? Double).map(Float.init)
        let maxPoints = (data["maxPoints"] as? Float) ?? (data["maxPoints"] as? Double).map(Float.init)
        let isGraded = (data["isGraded"] as? Bool) ?? false
        
        return QuestionSummary(
            id: id,
            subject: subject,
            questionText: questionText,
            confidence: confidence,
            hasVisualElements: hasVisualElements,
            archivedAt: archivedAt,
            reviewCount: reviewCount,
            tags: tags,
            grade: grade,
            points: points,
            maxPoints: maxPoints,
            isGraded: isGraded
        )
    }
    
    private func convertFullQuestionFromRailwayFormat(_ data: [String: Any]) throws -> ArchivedQuestion {
        guard let id = data["id"] as? String,
              let userId = data["userId"] as? String,
              let subject = data["subject"] as? String,
              let questionText = data["questionText"] as? String,
              let answerText = data["answerText"] as? String,
              let archivedAtString = data["archivedAt"] as? String,
              let archivedAt = parseDate(archivedAtString) else {
            throw QuestionArchiveError.invalidData
        }
        
        let confidence = (data["confidence"] as? Float) ?? (data["confidence"] as? Double).map(Float.init) ?? 0.0
        let hasVisualElements = (data["hasVisualElements"] as? Bool) ?? false
        let processingTime = (data["processingTime"] as? Double) ?? 0.0
        let reviewCount = (data["reviewCount"] as? Int) ?? 0
        let originalImageUrl = data["originalImageUrl"] as? String
        let questionImageUrl = data["questionImageUrl"] as? String
        let tags = data["tags"] as? [String]
        let notes = data["notes"] as? String
        
        // Grading fields
        let studentAnswer = data["studentAnswer"] as? String
        let gradeString = data["grade"] as? String
        let grade = gradeString != nil ? GradeResult(rawValue: gradeString!) : nil
        let points = (data["pointsEarned"] as? Float) ?? (data["pointsEarned"] as? Double).map(Float.init)
        let maxPoints = (data["pointsPossible"] as? Float) ?? (data["pointsPossible"] as? Double).map(Float.init)
        let feedback = data["feedback"] as? String
        let isGraded = (data["isGraded"] as? Bool) ?? false
        
        var lastReviewedAt: Date?
        if let lastReviewedAtString = data["lastReviewedAt"] as? String {
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
            notes: notes,
            studentAnswer: studentAnswer,
            grade: grade,
            points: points,
            maxPoints: maxPoints,
            feedback: feedback,
            isGraded: isGraded
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