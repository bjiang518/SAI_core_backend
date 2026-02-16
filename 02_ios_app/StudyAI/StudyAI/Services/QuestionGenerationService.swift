//
//  QuestionGenerationService.swift
//  StudyAI
//
//  Created by Claude Code on 12/21/24.
//

import Foundation
import Combine
import SwiftUI
import os.log

// MARK: - Production Logging Safety
// Disable debug print statements in production builds to prevent practice question exposure
#if !DEBUG
private func print(_ items: Any...) { }
private func debugPrint(_ items: Any...) { }
#endif

/// Backend service for generating practice questions using AI
class QuestionGenerationService: ObservableObject {
    static let shared = QuestionGenerationService()

    private let networkService = NetworkService.shared
    private let baseURL: String

    // MARK: - Published State
    @Published var isGenerating = false
    @Published var lastError: String?
    @Published var generationProgress: String?

    // ✅ FIX: Track current session for progress updates
    @Published var currentSessionId: String?

    // MARK: - Cache Management
    private var questionCache: [String: CachedQuestionSet] = [:]
    private let cacheValidityInterval: TimeInterval = 300 // 5 minutes

    // Last generated questions - persists until replaced by new generation
    @Published var lastGeneratedQuestions: [GeneratedQuestion] = []
    @Published var lastGenerationDate: Date?
    @Published var lastGenerationType: String?

    private struct CachedQuestionSet {
        let questions: [GeneratedQuestion]
        let timestamp: Date
        let cacheKey: String
        let generationType: String

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
        let questionType: GeneratedQuestion.QuestionType  // NEW: Question type filter

        enum QuestionDifficulty: String, CaseIterable {
            case beginner = "beginner"
            case intermediate = "intermediate"
            case advanced = "advanced"
            case adaptive = "adaptive"

            var displayName: String {
                switch self {
                case .beginner: return NSLocalizedString("difficulty.beginner", comment: "")
                case .intermediate: return NSLocalizedString("difficulty.intermediate", comment: "")
                case .advanced: return NSLocalizedString("difficulty.advanced", comment: "")
                case .adaptive: return NSLocalizedString("difficulty.adaptive", comment: "")
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
        // Core question data (required)
        let originalQuestion: String
        let userAnswer: String
        let correctAnswer: String

        // Error analysis (required for targeting)
        let errorType: String?              // "execution_error", "conceptual_gap", "needs_refinement"
        let baseBranch: String?             // "Algebra - Foundations"
        let detailedBranch: String?         // "Linear Equations - One Variable"

        // Optional context (send only if available)
        let specificIssue: String?          // "Arithmetic calculation error"
        let questionImageUrl: String?       // Image URL for visual context

        var dictionary: [String: Any] {
            var dict: [String: Any] = [
                "original_question": originalQuestion,
                "user_answer": userAnswer,
                "correct_answer": correctAnswer
            ]

            // Add error analysis if available
            if let errorType = errorType {
                dict["error_type"] = errorType
            }
            if let baseBranch = baseBranch {
                dict["base_branch"] = baseBranch
            }
            if let detailedBranch = detailedBranch {
                dict["detailed_branch"] = detailedBranch
            }
            if let specificIssue = specificIssue {
                dict["specific_issue"] = specificIssue
            }
            if let questionImageUrl = questionImageUrl {
                dict["question_image_url"] = questionImageUrl
            }

            return dict
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
        let tags: [String]? // Tags inherited from source questions

        // ✅ CRITICAL: Error keys for short-term status tracking
        // These fields allow graded answers to update bidirectional status
        let errorType: String?         // "execution_error", "conceptual_gap", "needs_refinement"
        let baseBranch: String?        // "Algebra - Foundations"
        let detailedBranch: String?    // "Linear Equations - One Variable"
        let weaknessKey: String?       // Combined key for status lookup

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

            // Handle difficulty - can be Int or String
            if let difficultyInt = try? container.decode(Int.self, forKey: .difficulty) {
                self.difficulty = String(difficultyInt)
            } else {
                self.difficulty = try container.decode(String.self, forKey: .difficulty)
            }

            self.points = try container.decodeIfPresent(Int.self, forKey: .points)
            self.timeEstimate = try container.decodeIfPresent(String.self, forKey: .timeEstimate)

            // Parse multiple_choice_options - backend sends array of objects with {label, text, is_correct}
            if let multipleChoiceOptions = try? container.decode([MultipleChoiceOption].self, forKey: .options) {
                // Extract just the text from each option
                self.options = multipleChoiceOptions.map { "\($0.label). \($0.text)" }
            } else if let simpleOptions = try? container.decode([String].self, forKey: .options) {
                // Fallback: if backend sends simple string array
                self.options = simpleOptions
            } else {
                self.options = nil
            }

            self.tags = try container.decodeIfPresent([String].self, forKey: .tags)

            // ✅ NEW: Decode error keys for short-term status tracking
            self.errorType = try container.decodeIfPresent(String.self, forKey: .errorType)
            self.baseBranch = try container.decodeIfPresent(String.self, forKey: .baseBranch)
            self.detailedBranch = try container.decodeIfPresent(String.self, forKey: .detailedBranch)
            self.weaknessKey = try container.decodeIfPresent(String.self, forKey: .weaknessKey)

            // ✅ DEBUG: Log error keys if present
            if let errorType = self.errorType {
                DebugSettings.shared.logErrorKeys("Decoded question with error keys: \(errorType)")
                DebugSettings.shared.prettyPrintErrorKeys(
                    errorType: self.errorType,
                    baseBranch: self.baseBranch,
                    detailedBranch: self.detailedBranch,
                    weaknessKey: self.weaknessKey
                )
            } else {
                DebugSettings.shared.logErrorKeys("Question has NO error keys (likely random generation)")
            }
        }

        // Helper struct for parsing backend multiple choice options
        private struct MultipleChoiceOption: Codable {
            let label: String
            let text: String
            let isCorrect: Bool

            enum CodingKeys: String, CodingKey {
                case label
                case text
                case isCorrect = "is_correct"
            }
        }

        // Regular initializer for programmatic creation
        init(id: UUID = UUID(), question: String, type: QuestionType, correctAnswer: String, explanation: String, topic: String, difficulty: String, points: Int? = nil, timeEstimate: String? = nil, options: [String]? = nil, tags: [String]? = nil, errorType: String? = nil, baseBranch: String? = nil, detailedBranch: String? = nil, weaknessKey: String? = nil) {
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
            self.tags = tags
            self.errorType = errorType
            self.baseBranch = baseBranch
            self.detailedBranch = detailedBranch
            self.weaknessKey = weaknessKey
        }

        // Coding keys for JSON encoding/decoding (excludes id since it's generated)
        // Maps iOS camelCase property names to backend snake_case JSON fields
        enum CodingKeys: String, CodingKey {
            case question
            case type = "question_type"              // Backend: question_type
            case correctAnswer = "correct_answer"     // Backend: correct_answer
            case explanation
            case topic
            case difficulty
            case points
            case timeEstimate = "estimated_time_minutes"  // Backend: estimated_time_minutes
            case options = "multiple_choice_options"      // Backend: multiple_choice_options
            case tags
            case errorType = "error_type"                 // ✅ NEW: Backend: error_type
            case baseBranch = "base_branch"               // ✅ NEW: Backend: base_branch
            case detailedBranch = "detailed_branch"       // ✅ NEW: Backend: detailed_branch
            case weaknessKey = "weakness_key"             // ✅ NEW: Backend: weakness_key
        }

        enum QuestionType: String, Codable, CaseIterable {
            case multipleChoice = "multiple_choice"
            case trueFalse = "true_false"
            case fillBlank = "fill_blank"
            case shortAnswer = "short_answer"
            case longAnswer = "long_answer"
            case calculation = "calculation"
            case matching = "matching"
            case any = "any"  // Allow AI to choose type dynamically

            var displayName: String {
                switch self {
                case .multipleChoice: return NSLocalizedString("questionType.multipleChoice", comment: "")
                case .trueFalse: return NSLocalizedString("questionType.trueFalse", comment: "")
                case .fillBlank: return NSLocalizedString("questionType.fillBlank", comment: "")
                case .shortAnswer: return NSLocalizedString("questionType.shortAnswer", comment: "")
                case .longAnswer: return NSLocalizedString("questionType.longAnswer", comment: "")
                case .calculation: return NSLocalizedString("questionType.calculation", comment: "")
                case .matching: return NSLocalizedString("questionType.matching", comment: "")
                case .any: return NSLocalizedString("questionType.mixedTypes", comment: "")
                }
            }

            var icon: String {
                switch self {
                case .multipleChoice: return "checklist"
                case .trueFalse: return "checkmark.circle"
                case .fillBlank: return "text.cursor"
                case .shortAnswer: return "text.alignleft"
                case .longAnswer: return "doc.text"
                case .calculation: return "function"
                case .matching: return "arrow.left.arrow.right"
                case .any: return "sparkles"
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

        // Build comprehensive cache key including all configuration parameters
        let topicsString = config.topics.sorted().joined(separator: ",")
        let focusNotesHash = (config.focusNotes ?? "").isEmpty ? "none" : String((config.focusNotes ?? "").hashValue)
        let cacheKey = "random_\(subject)_\(topicsString)_\(config.difficulty.rawValue)_\(config.questionCount)_\(config.questionType.rawValue)_\(focusNotesHash)"

        if let cached = questionCache[cacheKey], !cached.isExpired {
            print("✅ Using cached questions (generated \(Int(Date().timeIntervalSince(cached.timestamp)))s ago)")
            return .success(cached.questions)
        } else if let cached = questionCache[cacheKey] {
            print("⏰ Cache expired (generated \(Int(Date().timeIntervalSince(cached.timestamp)))s ago), generating new questions...")
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

        // NEW: Use Assistants API endpoint
        let endpoint = "/api/ai/generate-questions/practice"

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            await MainActor.run { self.lastError = "Invalid URL" }
            return .failure(.invalidURL)
        }

        // NEW: Simplified request format for Assistants API
        var requestBody: [String: Any] = [
            "subject": subject,
            "topic": config.topics.joined(separator: ", "), // Combine topics
            "count": config.questionCount,
            "difficulty": mapDifficultyToNumber(config.difficulty) as Any, // Convert to 1-5
            "question_type": config.questionType.rawValue, // Send question type filter
            "language": "en"
        ]

        // ✅ FIX 1: Include personalized focus notes if available
        if let focusNotes = config.focusNotes, !focusNotes.isEmpty {
            requestBody["focus_notes"] = focusNotes
            print("📝 [QuestionGen] Sending personalized focus notes to backend (\(focusNotes.count) chars)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 150.0 // Increased for mistake/archive generation (was 90s)

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
                            cacheKey: cacheKey,
                            generationType: "random"
                        )
                        questionCache[cacheKey] = cachedSet

                        // Update last generated questions (replaces previous)
                        await MainActor.run {
                            self.lastGeneratedQuestions = responseResult.questions
                            self.lastGenerationDate = Date()
                            self.lastGenerationType = "Random Practice"
                        }

                        // ✅ FIX 2: Save session for persistence and capture session ID
                        let sessionId = PracticeSessionManager.shared.saveSession(
                            questions: responseResult.questions,
                            generationType: "Random Practice",
                            subject: subject,
                            config: config
                        )

                        // ✅ Store session ID for progress tracking
                        await MainActor.run {
                            self.currentSessionId = sessionId
                        }

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



        let endpoint = "/api/ai/generate-questions/mistakes"  // V2 standardized endpoint

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            await MainActor.run { self.lastError = "Invalid URL" }
            return .failure(.invalidURL)
        }

        // ✅ FIXED: Nested config structure matching backend expectations
        // Backend expects: subject, mistakes_data, config { question_count, question_type, difficulty }
        let requestBody: [String: Any] = [
            "subject": subject,
            "mistakes_data": mistakes.map { $0.dictionary },
            "config": [
                "question_count": config.questionCount,
                "question_type": config.questionType.rawValue,
                "difficulty": config.difficulty.rawValue,
                "topics": config.topics,
                "focus_notes": config.focusNotes ?? ""
            ] as [String: Any],
            "user_profile": userProfile.dictionary
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 150.0 // Increased for mistake/archive generation (was 90s)

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
                        // Update last generated questions (replaces previous)
                        await MainActor.run {
                            self.lastGeneratedQuestions = responseResult.questions
                            self.lastGenerationDate = Date()
                            self.lastGenerationType = "Mistake-Based Practice"
                        }

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
        questions: [[String: Any]],
        config: RandomQuestionsConfig,
        userProfile: UserProfile
    ) async -> Result<[GeneratedQuestion], QuestionGenerationError> {

        await MainActor.run {
            self.isGenerating = true
            self.lastError = nil
            self.generationProgress = "Analyzing \(conversations.count) conversations and \(questions.count) questions and generating personalized questions..."
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
            "question_data": questions,
            "config": [
                "question_count": config.questionCount,
                "question_type": config.questionType.rawValue
            ],
            "user_profile": userProfile.dictionary
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 150.0 // Increased for mistake/archive generation (was 90s)

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
                        // Update last generated questions (replaces previous)
                        await MainActor.run {
                            self.lastGeneratedQuestions = responseResult.questions
                            self.lastGenerationDate = Date()
                            self.lastGenerationType = "Conversation-Based Practice"
                        }

                        // ✅ FIX 2: Save session for persistence and capture session ID
                        let sessionId = PracticeSessionManager.shared.saveSession(
                            questions: responseResult.questions,
                            generationType: "Conversation-Based Practice",
                            subject: subject,
                            config: config
                        )

                        // ✅ Store session ID for progress tracking
                        await MainActor.run {
                            self.currentSessionId = sessionId
                        }

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
                        // Update last generated questions (replaces previous)
                        await MainActor.run {
                            self.lastGeneratedQuestions = extractedQuestions
                            self.lastGenerationDate = Date()
                            self.lastGenerationType = "Conversation-Based Practice"
                        }

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
        // First, let's see what we got - SHOW FULL RESPONSE
        if let rawString = String(data: data, encoding: .utf8) {
            print("📄 Raw Response (\(generationType)) - FULL VERSION:")
            print("--- START RESPONSE ---")
            print(rawString)
            print("--- END RESPONSE ---")
            print("📏 Total response length: \(rawString.count) characters")
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

        print("✅ Success: \(success)")
        print("📚 Subject: \(subject)")
        print("🔢 Question Count: \(questionCount)")
        if let error = error {
            print("❌ Error from backend: \(error)")
        }

        var questions: [GeneratedQuestion] = []

        // AGGRESSIVE PARSING: Try to extract questions even if backend reports success=false
        // This handles the case where backend generates valid JSON but has validation bugs
        if let questionsArray = json["questions"] as? [[String: Any]], !questionsArray.isEmpty {
            print("📝 Found questions array with \(questionsArray.count) questions, attempting to parse regardless of success flag...")

            for (index, questionDict) in questionsArray.enumerated() {
                print("\n🔍 Parsing Question #\(index + 1):")
                print("  - question_type: \(questionDict["question_type"] ?? "MISSING")")
                print("  - question: \(String(describing: questionDict["question"] ?? "MISSING").prefix(100))...")
                print("  - correct_answer: \(questionDict["correct_answer"] ?? "MISSING")")
                print("  - multiple_choice_options: \(questionDict["multiple_choice_options"] ?? "null")")

                do {
                    let question = try parseGeneratedQuestion(from: questionDict)
                    print("  ✅ Parsed as type: \(question.type.rawValue)")
                    questions.append(question)
                } catch {
                    print("  ❌ Failed to parse question \(index + 1): \(error)")
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

        // CRITICAL FIX: Backend sends "question_type" not "type"!
        let typeString = dict["question_type"] as? String ?? "short_answer"
        let type = GeneratedQuestion.QuestionType(rawValue: typeString) ?? .shortAnswer

        // Backend sends "correct_answer" (snake_case)
        let correctAnswer = dict["correct_answer"] as? String ?? ""
        let explanation = dict["explanation"] as? String ?? "No explanation provided"
        let topic = dict["topic"] as? String ?? "General"

        // Handle difficulty - can be Int or String
        var difficulty = "intermediate"
        if let difficultyInt = dict["difficulty"] as? Int {
            difficulty = String(difficultyInt)
        } else if let difficultyString = dict["difficulty"] as? String {
            difficulty = difficultyString
        }

        let points = dict["points"] as? Int

        // Backend sends "estimated_time_minutes"
        let timeEstimate = dict["estimated_time_minutes"] as? String ?? dict["time_estimate"] as? String ?? dict["estimated_time"] as? String

        // Parse multiple_choice_options from backend
        var options: [String]?
        if let multipleChoiceOptions = dict["multiple_choice_options"] as? [[String: Any]] {
            // Backend format: [{"label": "A", "text": "...", "is_correct": true}]
            options = multipleChoiceOptions.map { option in
                let label = option["label"] as? String ?? ""
                let text = option["text"] as? String ?? ""
                return "\(label). \(text)"
            }
            print("  ✅ Parsed \(options?.count ?? 0) multiple choice options (object format)")
        } else if let simpleOptions = dict["multiple_choice_options"] as? [String] {
            // ✅ NEW: Handle simple string array format from backend
            options = simpleOptions
            print("  ✅ Parsed \(options?.count ?? 0) multiple choice options (string array format)")
        } else if let simpleOptions = dict["options"] as? [String] {
            options = simpleOptions
            print("  ✅ Parsed \(options?.count ?? 0) multiple choice options (legacy format)")
        }

        let tags = dict["tags"] as? [String]

        // ✅ NEW: Extract error taxonomy fields for short-term status tracking
        let errorType = dict["error_type"] as? String
        let baseBranch = dict["base_branch"] as? String
        let detailedBranch = dict["detailed_branch"] as? String
        let weaknessKey = dict["weakness_key"] as? String

        // Debug logging
        print("  📝 Parsed Question:")
        print("     - Type: \(typeString) → \(type.rawValue)")
        print("     - Has options: \(options != nil)")
        if let opts = options {
            print("     - Options count: \(opts.count)")
        }
        // ✅ NEW: Log error keys if present
        if let errorType = errorType {
            print("     - Error Type: \(errorType)")
            print("     - Base Branch: \(baseBranch ?? "nil")")
            print("     - Detailed Branch: \(detailedBranch ?? "nil")")
            print("     - Weakness Key: \(weaknessKey ?? "nil")")
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
            options: options,
            tags: tags,
            // ✅ NEW: Pass error taxonomy fields for status tracking
            errorType: errorType,
            baseBranch: baseBranch,
            detailedBranch: detailedBranch,
            weaknessKey: weaknessKey
        )
    }

    // MARK: - Difficulty Mapping for Assistants API

    /// Maps difficulty enum to 1-5 scale for Assistants API
    private func mapDifficultyToNumber(_ difficulty: RandomQuestionsConfig.QuestionDifficulty) -> Int? {
        switch difficulty {
        case .beginner:
            return 2
        case .intermediate:
            return 3
        case .advanced:
            return 4
        case .adaptive:
            return nil // Let backend auto-adjust
        }
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