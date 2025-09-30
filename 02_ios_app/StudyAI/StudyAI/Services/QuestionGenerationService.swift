//
//  QuestionGenerationService.swift
//  StudyAI
//
//  Created by Claude Code on 12/21/24.
//

import Foundation
import Combine
import SwiftUI

/// Backend service for generating practice questions using AI
class QuestionGenerationService: ObservableObject {
    static let shared = QuestionGenerationService()

    private let networkService = NetworkService.shared
    private let baseURL: String

    // MARK: - Published State
    @Published var isGenerating = false
    @Published var lastError: String?
    @Published var generationProgress: String?

    // MARK: - Cache Management
    private var questionCache: [String: CachedQuestionSet] = [:]
    private let cacheValidityInterval: TimeInterval = 300 // 5 minutes

    private struct CachedQuestionSet {
        let questions: [GeneratedQuestion]
        let timestamp: Date
        let cacheKey: String

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 300 // 5 minutes
        }
    }

    // MARK: - Request Models
    struct RandomQuestionsConfig {
        let topics: [String]
        let focusNotes: String?
        let difficulty: QuestionDifficulty
        let questionCount: Int

        enum QuestionDifficulty: String, CaseIterable {
            case beginner = "beginner"
            case intermediate = "intermediate"
            case advanced = "advanced"
            case adaptive = "adaptive"

            var displayName: String {
                switch self {
                case .beginner: return "Beginner"
                case .intermediate: return "Intermediate"
                case .advanced: return "Advanced"
                case .adaptive: return "Adaptive"
                }
            }

            var color: Color {
                switch self {
                case .beginner: return .green
                case .intermediate: return .orange
                case .advanced: return .red
                case .adaptive: return .purple
                }
            }
        }
    }

    struct UserProfile {
        let grade: String
        let location: String
        let preferences: [String: Any]

        var dictionary: [String: Any] {
            return [
                "grade": grade,
                "location": location,
                "preferences": preferences
            ]
        }
    }

    struct MistakeData {
        let originalQuestion: String
        let userAnswer: String
        let correctAnswer: String
        let mistakeType: String
        let topic: String
        let date: String

        var dictionary: [String: Any] {
            return [
                "original_question": originalQuestion,
                "user_answer": userAnswer,
                "correct_answer": correctAnswer,
                "mistake_type": mistakeType,
                "topic": topic,
                "date": date
            ]
        }
    }

    struct ConversationData {
        let date: String
        let topics: [String]
        let studentQuestions: String
        let difficultyLevel: String
        let strengths: [String]
        let weaknesses: [String]
        let keyConcepts: String
        let engagement: String

        var dictionary: [String: Any] {
            return [
                "date": date,
                "topics": topics,
                "student_questions": studentQuestions,
                "difficulty_level": difficultyLevel,
                "strengths": strengths,
                "weaknesses": weaknesses,
                "key_concepts": keyConcepts,
                "engagement": engagement
            ]
        }
    }

    // MARK: - Response Models
    struct GeneratedQuestion: Identifiable, Codable {
        var id: UUID
        let question: String
        let type: QuestionType
        let correctAnswer: String
        let explanation: String
        let topic: String
        let difficulty: String
        let points: Int?
        let timeEstimate: String?
        let options: [String]? // For multiple choice

        // Custom initializer for JSON decoding - generates UUID if not provided
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Generate UUID for id since it's not in JSON
            self.id = UUID()
            self.question = try container.decode(String.self, forKey: .question)
            self.type = try container.decode(QuestionType.self, forKey: .type)
            self.correctAnswer = try container.decode(String.self, forKey: .correctAnswer)
            self.explanation = try container.decode(String.self, forKey: .explanation)
            self.topic = try container.decode(String.self, forKey: .topic)
            self.difficulty = try container.decode(String.self, forKey: .difficulty)
            self.points = try container.decodeIfPresent(Int.self, forKey: .points)
            self.timeEstimate = try container.decodeIfPresent(String.self, forKey: .timeEstimate)
            self.options = try container.decodeIfPresent([String].self, forKey: .options)
        }

        // Regular initializer for programmatic creation
        init(id: UUID = UUID(), question: String, type: QuestionType, correctAnswer: String, explanation: String, topic: String, difficulty: String, points: Int? = nil, timeEstimate: String? = nil, options: [String]? = nil) {
            self.id = id
            self.question = question
            self.type = type
            self.correctAnswer = correctAnswer
            self.explanation = explanation
            self.topic = topic
            self.difficulty = difficulty
            self.points = points
            self.timeEstimate = timeEstimate
            self.options = options
        }

        // Coding keys for JSON encoding/decoding (excludes id since it's generated)
        enum CodingKeys: String, CodingKey {
            case question, type, correctAnswer, explanation, topic, difficulty, points, timeEstimate, options
        }

        enum QuestionType: String, Codable, CaseIterable {
            case multipleChoice = "multiple_choice"
            case shortAnswer = "short_answer"
            case calculation = "calculation"
            case essay = "essay"
            case trueFalse = "true_false"

            var displayName: String {
                switch self {
                case .multipleChoice: return "Multiple Choice"
                case .shortAnswer: return "Short Answer"
                case .calculation: return "Calculation"
                case .essay: return "Essay"
                case .trueFalse: return "True/False"
                }
            }

            var icon: String {
                switch self {
                case .multipleChoice: return "checklist"
                case .shortAnswer: return "text.cursor"
                case .calculation: return "function"
                case .essay: return "doc.text"
                case .trueFalse: return "checkmark.circle"
                }
            }
        }
    }

    struct QuestionGenerationResponse {
        let success: Bool
        let questions: [GeneratedQuestion]
        let generationType: String
        let subject: String
        let tokensUsed: Int?
        let questionCount: Int
        let processingDetails: [String: Any]?
        let error: String?
    }

    private init() {
        self.baseURL = "https://sai-backend-production.up.railway.app"

    }

    // MARK: - Public API Methods

    /// Generate random practice questions for a subject
    func generateRandomQuestions(
        subject: String,
        config: RandomQuestionsConfig,
        userProfile: UserProfile
    ) async -> Result<[GeneratedQuestion], QuestionGenerationError> {

        // Check cache first
        let cacheKey = "random_\(subject)_\(config.difficulty.rawValue)_\(config.questionCount)"
        if let cached = questionCache[cacheKey], !cached.isExpired {

            return .success(cached.questions)
        }

        await MainActor.run {
            self.isGenerating = true
            self.lastError = nil
            self.generationProgress = "Generating random questions for \(subject)..."
        }

        defer {
            Task { @MainActor in
                self.isGenerating = false
                self.generationProgress = nil
            }
        }


        print("📚 Subject: \(subject)")


        print("🏷️ Topics: \(config.topics)")
        print("👤 User Grade: \(userProfile.grade)")

        let endpoint = "/api/ai/generate-questions/random"

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            await MainActor.run { self.lastError = "Invalid URL" }
            return .failure(.invalidURL)
        }

        let requestBody: [String: Any] = [
            "subject": subject,
            "config": [
                "topics": config.topics,
                "focus_notes": config.focusNotes ?? "",
                "difficulty": config.difficulty.rawValue,
                "question_count": config.questionCount
            ],
            "user_profile": userProfile.dictionary
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90.0 // AI processing can take time

        // Add authentication
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            await MainActor.run { self.lastError = "Authentication required" }
            return .failure(.authenticationRequired)
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            print("📤 Sending random questions request to AI engine...")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {


                if httpResponse.statusCode == 200 {
                    let responseResult = try parseQuestionResponse(data: data, generationType: "random")

                    if responseResult.success {
                        // Cache successful results
                        let cachedSet = CachedQuestionSet(
                            questions: responseResult.questions,
                            timestamp: Date(),
                            cacheKey: cacheKey
                        )
                        questionCache[cacheKey] = cachedSet

                        print("🎉 Generated \(responseResult.questions.count) random questions successfully")
                        return .success(responseResult.questions)
                    } else {
                        let errorMsg = responseResult.error ?? "Unknown error from AI engine"
                        await MainActor.run { self.lastError = errorMsg }
                        return .failure(.aiProcessingError(errorMsg))
                    }
                } else {
                    let errorMsg = "Server error: HTTP \(httpResponse.statusCode)"
                    await MainActor.run { self.lastError = errorMsg }
                    return .failure(.serverError(httpResponse.statusCode))
                }
            }

            await MainActor.run { self.lastError = "No response from server" }
            return .failure(.networkError("No response from server"))

        } catch {
            let errorMsg = "Network error: \(error.localizedDescription)"
            await MainActor.run { self.lastError = errorMsg }

            return .failure(.networkError(error.localizedDescription))
        }
    }

    /// Generate questions based on previous mistakes
    func generateMistakeBasedQuestions(
        subject: String,
        mistakes: [MistakeData],
        config: RandomQuestionsConfig,
        userProfile: UserProfile
    ) async -> Result<[GeneratedQuestion], QuestionGenerationError> {

        await MainActor.run {
            self.isGenerating = true
            self.lastError = nil
            self.generationProgress = "Analyzing \(mistakes.count) mistakes and generating remedial questions..."
        }

        defer {
            Task { @MainActor in
                self.isGenerating = false
                self.generationProgress = nil
            }
        }


        print("📚 Subject: \(subject)")



        let endpoint = "/api/ai/generate-questions/mistakes"

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            await MainActor.run { self.lastError = "Invalid URL" }
            return .failure(.invalidURL)
        }

        let requestBody: [String: Any] = [
            "subject": subject,
            "mistakes_data": mistakes.map { $0.dictionary },
            "config": [
                "question_count": config.questionCount
            ],
            "user_profile": userProfile.dictionary
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90.0

        // Add authentication
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            await MainActor.run { self.lastError = "Authentication required" }
            return .failure(.authenticationRequired)
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            print("📤 Sending mistake-based questions request to AI engine...")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {


                if httpResponse.statusCode == 200 {
                    let responseResult = try parseQuestionResponse(data: data, generationType: "mistake_based")

                    if responseResult.success {
                        print("🎉 Generated \(responseResult.questions.count) mistake-based questions successfully")
                        return .success(responseResult.questions)
                    } else {
                        let errorMsg = responseResult.error ?? "Unknown error from AI engine"

                        // Check for specific field validation bugs (addresses_mistake, builds_on, etc.)
                        if errorMsg.contains("missing required field: addresses_mistake") ||
                           errorMsg.contains("addresses_mistake") ||
                           errorMsg.contains("missing required field:") {

                            // Check if this is the text parsing fallback scenario
                            // Look for evidence that text parsing actually worked
                            if let rawString = String(data: data, encoding: .utf8),
                               (rawString.contains("Text parsing completed") ||
                                rawString.contains("questions extracted") ||
                                rawString.contains("Parsed question")) {



                                // Try to extract questions from the error response that might contain parsed data
                                if let extractedQuestions = tryExtractQuestionsFromErrorResponse(data: data) {

                                    return .success(extractedQuestions)
                                }
                            }

                            let friendlyMsg = "There's a temporary issue with mistake-based question generation. The system is having trouble processing the generated questions. Please try using 'Random Practice' instead, or try again later."
                            print("🐛 Detected field validation bug in mistake-based generation: \(errorMsg)")
                            await MainActor.run { self.lastError = friendlyMsg }
                            return .failure(.backendValidationBug(friendlyMsg))
                        }

                        await MainActor.run { self.lastError = errorMsg }
                        return .failure(.aiProcessingError(errorMsg))
                    }
                } else {
                    // Check for validation errors in non-200 responses too
                    let errorMsg = "Server error: HTTP \(httpResponse.statusCode)"

                    // Parse error response to check for validation issues
                    if let errorString = String(data: data, encoding: .utf8) {
                        if errorString.contains("missing required field: addresses_mistake") ||
                           errorString.contains("addresses_mistake") ||
                           errorString.contains("missing required field:") {
                            let friendlyMsg = "There's a temporary issue with mistake-based question generation. The system is having trouble processing the generated questions. Please try using 'Random Practice' instead, or try again later."
                            print("🐛 Detected field validation bug in error response: \(errorString)")
                            await MainActor.run { self.lastError = friendlyMsg }
                            return .failure(.backendValidationBug(friendlyMsg))
                        }
                    }

                    await MainActor.run { self.lastError = errorMsg }
                    return .failure(.serverError(httpResponse.statusCode))
                }
            }

            await MainActor.run { self.lastError = "No response from server" }
            return .failure(.networkError("No response from server"))

        } catch {
            let errorMsg = "Network error: \(error.localizedDescription)"
            await MainActor.run { self.lastError = errorMsg }

            return .failure(.networkError(error.localizedDescription))
        }
    }

    /// Generate questions based on conversation history
    func generateConversationBasedQuestions(
        subject: String,
        conversations: [ConversationData],
        config: RandomQuestionsConfig,
        userProfile: UserProfile
    ) async -> Result<[GeneratedQuestion], QuestionGenerationError> {

        await MainActor.run {
            self.isGenerating = true
            self.lastError = nil
            self.generationProgress = "Analyzing \(conversations.count) conversations and generating personalized questions..."
        }

        defer {
            Task { @MainActor in
                self.isGenerating = false
                self.generationProgress = nil
            }
        }


        print("📚 Subject: \(subject)")
        print("💬 Conversations Count: \(conversations.count)")


        let endpoint = "/api/ai/generate-questions/conversations"

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            await MainActor.run { self.lastError = "Invalid URL" }
            return .failure(.invalidURL)
        }

        let requestBody: [String: Any] = [
            "subject": subject,
            "conversation_data": conversations.map { $0.dictionary },
            "config": [
                "question_count": config.questionCount
            ],
            "user_profile": userProfile.dictionary
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90.0

        // Add authentication
        if let token = AuthenticationService.shared.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            await MainActor.run { self.lastError = "Authentication required" }
            return .failure(.authenticationRequired)
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            print("📤 Sending conversation-based questions request to AI engine...")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {


                // UNIVERSAL PARSING: Always try to parse response data regardless of status code
                // The backend might include valid questions even in error responses
                do {
                    let responseResult = try parseQuestionResponse(data: data, generationType: "conversation_based")

                    // If we successfully parsed questions, return them regardless of status code or success flag
                    if !responseResult.questions.isEmpty {
                        print("🎉 Generated \(responseResult.questions.count) conversation-based questions successfully (Status: \(httpResponse.statusCode))")
                        return .success(responseResult.questions)
                    }

                    // If no questions but successful response
                    if httpResponse.statusCode == 200 && responseResult.success {
                        print("⚠️ Successful response but no questions generated")
                        await MainActor.run { self.lastError = "No questions were generated" }
                        return .failure(.aiProcessingError("No questions were generated"))
                    }

                } catch {
                    print("⚠️ Failed to parse JSON response: \(error)")
                }

                // FALLBACK: If JSON parsing failed, try raw extraction from any response


                if let rawString = String(data: data, encoding: .utf8) {
                    print("📄 Raw response for extraction (Status \(httpResponse.statusCode)):")
                    print("--- START RESPONSE ---")
                    print(String(rawString.prefix(1000))) // Show first 1000 chars for debugging
                    print("--- END RESPONSE ---")

                    // Try to extract questions using the intelligent recovery system
                    if let extractedQuestions = tryExtractQuestionsFromErrorResponse(data: data) {

                        return .success(extractedQuestions)
                    }
                }

                // If all parsing attempts failed
                let errorMsg = httpResponse.statusCode == 200 ? "Failed to parse response" : "Server error: HTTP \(httpResponse.statusCode)"
                await MainActor.run { self.lastError = errorMsg }
                return .failure(httpResponse.statusCode == 200 ? .invalidResponse(errorMsg) : .serverError(httpResponse.statusCode))
            }

            await MainActor.run { self.lastError = "No response from server" }
            return .failure(.networkError("No response from server"))

        } catch {
            let errorMsg = "Network error: \(error.localizedDescription)"
            await MainActor.run { self.lastError = errorMsg }

            return .failure(.networkError(error.localizedDescription))
        }
    }

    // MARK: - Utility Methods

    /// Clear all cached questions
    func clearCache() {
        questionCache.removeAll()
        print("🗑️ Question generation cache cleared")
    }

    /// Get cache statistics
    func getCacheStats() -> (count: Int, totalSize: Int) {
        var totalQuestions = 0
        for (_, cachedSet) in questionCache {
            totalQuestions += cachedSet.questions.count
        }
        return (count: questionCache.count, totalSize: totalQuestions)
    }

    // MARK: - Private Helper Methods

    private func parseQuestionResponse(data: Data, generationType: String) throws -> QuestionGenerationResponse {
        // First, let's see what we got
        if let rawString = String(data: data, encoding: .utf8) {
            print("📄 Raw Response (\(generationType)): \(String(rawString.prefix(500)))...")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuestionGenerationError.invalidResponse("Invalid JSON format")
        }



        let success = json["success"] as? Bool ?? false
        let subject = json["subject"] as? String ?? ""
        let tokensUsed = json["tokens_used"] as? Int
        let questionCount = json["question_count"] as? Int ?? 0
        let processingDetails = json["processing_details"] as? [String: Any]
        let error = json["error"] as? String

        var questions: [GeneratedQuestion] = []

        // AGGRESSIVE PARSING: Try to extract questions even if backend reports success=false
        // This handles the case where backend generates valid JSON but has validation bugs
        if let questionsArray = json["questions"] as? [[String: Any]], !questionsArray.isEmpty {
            print("📝 Found questions array with \(questionsArray.count) questions, attempting to parse regardless of success flag...")

            for (index, questionDict) in questionsArray.enumerated() {
                do {
                    let question = try parseGeneratedQuestion(from: questionDict)
                    questions.append(question)

                } catch {
                    print("⚠️ Failed to parse question \(index + 1): \(error)")
                }
            }

            // If we successfully parsed questions, ignore the backend success flag
            if !questions.isEmpty {
                print("🎉 Successfully parsed \(questions.count) questions despite backend success=false")
                return QuestionGenerationResponse(
                    success: true, // Override backend success flag
                    questions: questions,
                    generationType: generationType,
                    subject: subject,
                    tokensUsed: tokensUsed,
                    questionCount: questions.count,
                    processingDetails: processingDetails,
                    error: nil // Clear the error since we successfully parsed
                )
            }
        }

        // Fallback to original logic only if no questions were found
        if success, let questionsArray = json["questions"] as? [[String: Any]] {
            print("📝 Parsing \(questionsArray.count) questions with success=true...")

            for (index, questionDict) in questionsArray.enumerated() {
                do {
                    let question = try parseGeneratedQuestion(from: questionDict)
                    questions.append(question)

                } catch {
                    print("⚠️ Failed to parse question \(index + 1): \(error)")
                }
            }
        }

        return QuestionGenerationResponse(
            success: success,
            questions: questions,
            generationType: generationType,
            subject: subject,
            tokensUsed: tokensUsed,
            questionCount: questionCount,
            processingDetails: processingDetails,
            error: error
        )
    }

    /// Attempts to extract questions from backend error responses that contain text parsing fallback data
    private func tryExtractQuestionsFromErrorResponse(data: Data) -> [GeneratedQuestion]? {
        guard let rawString = String(data: data, encoding: .utf8) else {

            return nil
        }


        print("📄 Raw response length: \(rawString.count) characters")

        // Strategy 1: Look for complete JSON objects with questions array
        let jsonPattern = #"\{[^{}]*"questions"\s*:\s*\[[^\]]*\][^{}]*\}"#
        if let extractedQuestions = tryExtractWithPattern(jsonPattern, from: rawString, strategy: "Complete JSON") {
            return extractedQuestions
        }

        // Strategy 2: Look for just the questions array and reconstruct the object
        let questionsArrayPattern = #""questions"\s*:\s*\[[\s\S]*?\]"#
        if let extractedQuestions = tryExtractQuestionsArray(from: rawString, pattern: questionsArrayPattern) {
            return extractedQuestions
        }

        // Strategy 3: Look for individual question objects in array format
        let individualQuestionsPattern = #"\[\s*\{[\s\S]*?"question"\s*:[\s\S]*?\}\s*(?:,\s*\{[\s\S]*?"question"\s*:[\s\S]*?\}\s*)*\]"#
        if let extractedQuestions = tryExtractWithPattern(individualQuestionsPattern, from: rawString, strategy: "Questions Array Only") {
            return extractedQuestions
        }


        return nil
    }

    private func tryExtractWithPattern(_ pattern: String, from rawString: String, strategy: String) -> [GeneratedQuestion]? {
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: rawString.count)

        if let match = regex?.firstMatch(in: rawString, options: [], range: range),
           let jsonRange = Range(match.range, in: rawString) {
            let jsonString = String(rawString[jsonRange])
            print("📄 Found JSON block using \(strategy) strategy, attempting to parse...")

            // If it's not a complete object, wrap it in one
            let finalJsonString = jsonString.hasPrefix("{") ? jsonString : "{\(jsonString)}"

            // Try to parse the extracted JSON
            if let jsonData = finalJsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let questionsArray = json["questions"] as? [[String: Any]] {


                return parseQuestionsArray(questionsArray, strategy: strategy)
            }
        }
        return nil
    }

    private func tryExtractQuestionsArray(from rawString: String, pattern: String) -> [GeneratedQuestion]? {
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: rawString.count)

        if let match = regex?.firstMatch(in: rawString, options: [], range: range),
           let jsonRange = Range(match.range, in: rawString) {
            let questionsString = String(rawString[jsonRange])
            print("📄 Found questions array, attempting to parse...")

            // Wrap in a JSON object
            let jsonString = "{\(questionsString)}"

            if let jsonData = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let questionsArray = json["questions"] as? [[String: Any]] {


                return parseQuestionsArray(questionsArray, strategy: "Questions Array Extraction")
            }
        }
        return nil
    }

    private func parseQuestionsArray(_ questionsArray: [[String: Any]], strategy: String) -> [GeneratedQuestion]? {
        var questions: [GeneratedQuestion] = []
        for (index, questionDict) in questionsArray.enumerated() {
            do {
                let question = try parseGeneratedQuestion(from: questionDict)
                questions.append(question)

            } catch {
                print("⚠️ Failed to parse \(strategy) question \(index + 1): \(error)")
                // Continue with other questions instead of failing completely
            }
        }

        if !questions.isEmpty {
            print("🎉 Successfully recovered \(questions.count) questions using \(strategy)")
            return questions
        }
        return nil
    }

    private func parseGeneratedQuestion(from dict: [String: Any]) throws -> GeneratedQuestion {
        // Required fields with fallbacks
        guard let question = dict["question"] as? String else {
            throw QuestionGenerationError.invalidResponse("Missing 'question' field")
        }

        let typeString = dict["type"] as? String ?? "short_answer"
        let type = GeneratedQuestion.QuestionType(rawValue: typeString) ?? .shortAnswer

        let correctAnswer = dict["correct_answer"] as? String ?? ""
        let explanation = dict["explanation"] as? String ?? "No explanation provided"
        let topic = dict["topic"] as? String ?? "General"

        // Optional fields with fallbacks (this is where the robustness improvement happens)
        let difficulty = dict["difficulty"] as? String ?? "intermediate"
        let points = dict["points"] as? Int
        let timeEstimate = dict["time_estimate"] as? String ?? dict["estimated_time"] as? String
        let options = dict["options"] as? [String]

        // These fields are optional and not required for question generation
        // Removed addresses_mistake and builds_on - they're not necessary for the iOS app

        // No need to log missing fields anymore since they're truly optional
        if dict["difficulty"] == nil {
            print("⚠️ Question parsing: Using fallback difficulty 'intermediate'")
        }
        if dict["time_estimate"] == nil && dict["estimated_time"] == nil {
            print("⚠️ Question parsing: No time estimate provided")
        }

        return GeneratedQuestion(
            question: question,
            type: type,
            correctAnswer: correctAnswer,
            explanation: explanation,
            topic: topic,
            difficulty: difficulty,
            points: points,
            timeEstimate: timeEstimate,
            options: options
        )
    }
}

// MARK: - Error Types

enum QuestionGenerationError: LocalizedError {
    case invalidURL
    case authenticationRequired
    case networkError(String)
    case serverError(Int)
    case aiProcessingError(String)
    case invalidResponse(String)
    case cacheError(String)
    case backendValidationBug(String) // New case for the builds_on validation bug

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL"
        case .authenticationRequired:
            return "Please sign in to generate questions"
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let code):
            return "Server error (HTTP \(code))"
        case .aiProcessingError(let message):
            return "AI processing error: \(message)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .cacheError(let message):
            return "Cache error: \(message)"
        case .backendValidationBug(let message):
            return message // Use the friendly message directly
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .authenticationRequired:
            return "Please sign in with your account to continue."
        case .networkError:
            return "Check your internet connection and try again."
        case .serverError:
            return "The server is temporarily unavailable. Please try again later."
        case .aiProcessingError:
            return "The AI service encountered an error. Please try generating questions again."
        case .invalidResponse:
            return "There was an issue with the server response. Please try again."
        case .backendValidationBug:
            return "This is a known temporary issue with the backend. Try using other question generation methods like 'Random Practice' or 'From Mistakes'."
        default:
            return "Please try again. If the problem persists, contact support."
        }
    }
}

// MARK: - Extensions for View Integration

extension QuestionGenerationService.GeneratedQuestion {
    /// Preview text for display in lists
    var previewText: String {
        let maxLength = 100
        if question.count <= maxLength {
            return question
        } else {
            return String(question.prefix(maxLength)) + "..."
        }
    }

    /// Formatted difficulty display
    var difficultyColor: Color {
        switch difficulty.lowercased() {
        case "beginner": return .green
        case "intermediate": return .orange
        case "advanced": return .red
        default: return .gray
        }
    }

    /// Question type icon with SF Symbols
    var typeIcon: String {
        return type.icon
    }
}