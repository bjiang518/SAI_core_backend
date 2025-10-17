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

        // Check for duplicates before archiving
        let deduplicationResult = try await checkForDuplicates(request: request)

        if deduplicationResult.uniqueIndices.isEmpty {
            throw QuestionArchiveError.allQuestionsAreDuplicates(deduplicationResult.duplicateCount)
        }

        guard let url = URL(string: "\(baseURL)/api/archived-questions") else {
            throw QuestionArchiveError.invalidURL
        }

        // Prepare request data with only unique questions
        let uniqueQuestions = deduplicationResult.uniqueIndices.map { index -> [String: Any] in
            let question = request.questions[index]
            return [
                "questionText": question.questionText,
                "rawQuestionText": question.rawQuestionText ?? question.questionText,  // Include raw question
                "answerText": question.correctAnswer ?? question.answerText,  // Prioritize correct answer
                "confidence": question.confidence,
                "hasVisualElements": question.hasVisualElements,
                "studentAnswer": question.studentAnswer ?? "",
                "correctAnswer": question.correctAnswer ?? question.answerText,
                "grade": question.grade ?? "EMPTY",
                "pointsEarned": question.pointsEarned ?? 0.0,
                "pointsPossible": question.pointsPossible ?? 1.0,
                "feedback": question.feedback ?? "",
                "isGraded": question.isGraded
            ]
        }

        let requestData: [String: Any] = [
            "selectedQuestionIndices": deduplicationResult.uniqueIndices,
            "questions": uniqueQuestions,
            "userNotes": deduplicationResult.uniqueNotes,
            "userTags": deduplicationResult.uniqueTags,
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
            throw QuestionArchiveError.archiveFailed(errorMessage)
        }

        // Parse response
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let success = jsonResponse["success"] as? Bool,
              success == true,
              let _ = jsonResponse["data"] as? [[String: Any]] else {
            throw QuestionArchiveError.invalidData
        }

        // Convert response to ArchivedQuestions
        var archivedQuestions: [ArchivedQuestion] = []
        var questionDataForLocalStorage: [[String: Any]] = []

        for (arrayIndex, questionIndex) in deduplicationResult.uniqueIndices.enumerated() {
            guard questionIndex < request.questions.count else { continue }

            let question = request.questions[questionIndex]
            let userNote = arrayIndex < deduplicationResult.uniqueNotes.count ? deduplicationResult.uniqueNotes[arrayIndex] : ""
            let userTag = arrayIndex < deduplicationResult.uniqueTags.count ? deduplicationResult.uniqueTags[arrayIndex] : []

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

            // Build data for local storage
            let questionData: [String: Any] = [
                "id": archivedQuestion.id,
                "subject": request.detectedSubject,
                "questionText": question.questionText,
                "answerText": question.answerText,
                "confidence": question.confidence,
                "hasVisualElements": question.hasVisualElements,
                "archivedAt": ISO8601DateFormatter().string(from: Date()),
                "reviewCount": 0,
                "tags": userTag,
                "notes": userNote,
                "studentAnswer": question.studentAnswer ?? "",
                "grade": question.grade ?? "",
                "points": question.pointsEarned ?? 0.0,
                "maxPoints": question.pointsPossible ?? 1.0,
                "feedback": question.feedback ?? "",
                "isGraded": question.grade != nil
            ]
            questionDataForLocalStorage.append(questionData)
        }

        // Save to local storage immediately for instant access
        QuestionLocalStorage.shared.saveQuestions(questionDataForLocalStorage)

        return archivedQuestions
    }

    // MARK: - Deduplication Helper

    private func checkForDuplicates(request: QuestionArchiveRequest) async throws -> DeduplicationResult {
        // Fetch existing questions for this subject to check for duplicates
        let existingQuestions = try await fetchQuestionsBySubject(request.detectedSubject)

        // Create a set of normalized question texts from existing questions
        let existingQuestionTexts = Set(existingQuestions.map { normalizeQuestionText($0.questionText) })

        var uniqueIndices: [Int] = []
        var duplicateIndices: [Int] = []
        var uniqueNotes: [String] = []
        var uniqueTags: [[String]] = []

        for (arrayIndex, questionIndex) in request.selectedQuestionIndices.enumerated() {
            guard questionIndex < request.questions.count else { continue }

            let question = request.questions[questionIndex]
            let normalizedText = normalizeQuestionText(question.questionText)

            if existingQuestionTexts.contains(normalizedText) {
                // This is a duplicate
                duplicateIndices.append(questionIndex)
            } else {
                // This is unique
                uniqueIndices.append(questionIndex)
                if arrayIndex < request.userNotes.count {
                    uniqueNotes.append(request.userNotes[arrayIndex])
                }
                if arrayIndex < request.userTags.count {
                    uniqueTags.append(request.userTags[arrayIndex])
                }
            }
        }

        return DeduplicationResult(
            uniqueIndices: uniqueIndices,
            duplicateIndices: duplicateIndices,
            duplicateCount: duplicateIndices.count,
            uniqueNotes: uniqueNotes,
            uniqueTags: uniqueTags
        )
    }

    private func normalizeQuestionText(_ text: String) -> String {
        // Normalize by:
        // 1. Converting to lowercase
        // 2. Trimming whitespace
        // 3. Removing extra spaces
        // 4. Removing common punctuation that doesn't affect meaning
        return text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
    }
    
    // MARK: - Enhanced Search Methods
    
    /// Advanced search with comprehensive filtering options
    func searchQuestions(
        searchText: String? = nil,
        subject: String? = nil,
        confidenceRange: ClosedRange<Float>? = nil,
        hasVisualElements: Bool? = nil,
        grade: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [QuestionSummary] {
        guard currentUserId != nil else {
            throw QuestionArchiveError.notAuthenticated
        }

        guard let token = authToken else {
            throw QuestionArchiveError.notAuthenticated
        }

        var urlComponents = URLComponents(string: "\(baseURL)/api/archived-questions")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        
        // Add search filters
        if let searchText = searchText, !searchText.isEmpty {
            queryItems.append(URLQueryItem(name: "searchText", value: searchText))
        }
        
        if let subject = subject, !subject.isEmpty {
            queryItems.append(URLQueryItem(name: "subject", value: subject))
        }
        
        if let confidenceRange = confidenceRange {
            queryItems.append(URLQueryItem(name: "confidenceMin", value: String(confidenceRange.lowerBound)))
            queryItems.append(URLQueryItem(name: "confidenceMax", value: String(confidenceRange.upperBound)))
        }
        
        if let hasVisualElements = hasVisualElements {
            queryItems.append(URLQueryItem(name: "hasVisualElements", value: String(hasVisualElements)))
        }
        
        if let grade = grade, !grade.isEmpty {
            queryItems.append(URLQueryItem(name: "grade", value: grade))
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
    
    // MARK: - Fetch Archived Questions
    
    func fetchArchivedQuestions(limit: Int = 50, offset: Int = 0) async throws -> [QuestionSummary] {
        // ✅ FIX: Implement cache-first loading to show newly archived questions immediately
        // Load from local storage first, then sync with server in background

        // STEP 1: Load from local storage for instant display
        let localStorage = QuestionLocalStorage.shared
        let localQuestions = localStorage.getLocalQuestions()

        // Convert local storage format to QuestionSummary
        var cachedQuestions: [QuestionSummary] = []
        for questionData in localQuestions {
            if let question = try? localStorage.convertLocalQuestionToSummary(questionData) {
                cachedQuestions.append(question)
            }
        }

        // STEP 2: Fetch from server in background (don't throw errors to avoid blocking UI)
        Task {
            await fetchAndUpdateFromServer(limit: limit, offset: offset)
        }

        // Return cached data immediately (may be empty if nothing cached yet)
        return cachedQuestions
    }

    /// Fetch from server and update local storage
    private func fetchAndUpdateFromServer(limit: Int, offset: Int) async {
        guard let userId = currentUserId else {
            return
        }

        guard let token = authToken else {
            return
        }

        var urlComponents = URLComponents(string: "\(baseURL)/api/archived-questions")!
        urlComponents.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        guard let url = urlComponents.url else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("⚠️ [fetchAndUpdateFromServer] Server returned error status")
                return
            }

            guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = jsonResponse["success"] as? Bool,
                  success == true,
                  let questionData = jsonResponse["data"] as? [[String: Any]] else {
                print("⚠️ [fetchAndUpdateFromServer] Invalid server response")
                return
            }

            // Sync server data with local storage
            QuestionLocalStorage.shared.syncWithServer(serverQuestionIds: questionData.compactMap { $0["id"] as? String })

            print("✅ [fetchAndUpdateFromServer] Synced \(questionData.count) questions from server")
        } catch {
            print("⚠️ [fetchAndUpdateFromServer] Failed to fetch from server: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Fetch Questions by Subject
    
    func fetchQuestionsBySubject(_ subject: String) async throws -> [QuestionSummary] {
        guard currentUserId != nil else {
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
        guard currentUserId != nil else {
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
        guard currentUserId != nil else {
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
            totalQuestions: 1, // Each question summary represents 1 question
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
        // Try ISO8601 with fractional seconds first
        let iso8601FormatterWithFractionalSeconds = ISO8601DateFormatter()
        iso8601FormatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601FormatterWithFractionalSeconds.date(from: dateString) {
            return date
        }
        
        // Try ISO8601 without fractional seconds
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }
        
        // Try date-only format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: dateString)
    }
}

// MARK: - Deduplication Result

struct DeduplicationResult {
    let uniqueIndices: [Int]
    let duplicateIndices: [Int]
    let duplicateCount: Int
    let uniqueNotes: [String]
    let uniqueTags: [[String]]
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
    case allQuestionsAreDuplicates(Int)

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
        case .allQuestionsAreDuplicates(let count):
            return "All \(count) question(s) have already been archived"
        }
    }
}