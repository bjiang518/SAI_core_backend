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
private func debugPrint(_ items: Any...) { }
#endif

/// Backend service for generating practice questions using AI
class QuestionGenerationService: ObservableObject {
    static let shared = QuestionGenerationService()

    private let networkService = NetworkService.shared
    private let baseURL: String
    @AppStorage("appLanguage") private var appLanguage: String = "en"

    private var effectiveLanguage: String {
        UserDefaults.standard.string(forKey: "childSessionLanguage") ?? appLanguage
    }

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
    @Published var lastDetectedSubject: String? = nil  // set by backend auto-detection

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

        // Tag context for distractor-aware generation
        let errorMicroTags: [String]        // e.g. ["sign_error", "arithmetic_slip"]
        let skillTags: [String]             // e.g. ["algebraic_manipulation"]

        init(originalQuestion: String, userAnswer: String, correctAnswer: String,
             errorType: String? = nil, baseBranch: String? = nil, detailedBranch: String? = nil,
             specificIssue: String? = nil, questionImageUrl: String? = nil,
             errorMicroTags: [String] = [], skillTags: [String] = []) {
            self.originalQuestion = originalQuestion
            self.userAnswer = userAnswer
            self.correctAnswer = correctAnswer
            self.errorType = errorType
            self.baseBranch = baseBranch
            self.detailedBranch = detailedBranch
            self.specificIssue = specificIssue
            self.questionImageUrl = questionImageUrl
            self.errorMicroTags = errorMicroTags
            self.skillTags = skillTags
        }

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
            if !errorMicroTags.isEmpty { dict["error_micro_tags"] = errorMicroTags }
            if !skillTags.isEmpty      { dict["skill_tags"] = skillTags }

            return dict
        }
    }

    struct ConversationData {
        let date: String
        let topics: [String]
        let studentQuestions: String
        let keyConcepts: String

        var dictionary: [String: Any] {
            return [
                "date": date,
                "topics": topics,
                "student_questions": studentQuestions,
                "key_concepts": keyConcepts
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
        let bankQuestionId: String?    // UUID of the source row in question_bank
        let figureUrl: String?         // Relative path: /api/ai/question-bank/figure/<id>
        let source: String?            // "amc8" | "amc12" | "aime" | "sat" | "mmlu" | "arc" | "gsm8k"
        let sourceId: String?          // e.g. "2023-P5", "1990-I-5"

        // Human-readable label for the question source
        var sourceLabel: String? {
            guard let source else { return nil }
            switch source {
            case "amc8":
                let parts = sourceId?.components(separatedBy: "-") ?? []
                let year = parts.first ?? ""; let num = parts.last?.replacingOccurrences(of: "P", with: "") ?? ""
                return "AMC 8 · \(year) #\(num)"
            case "amc10":
                let year = sourceId.flatMap { String($0.prefix(4)) } ?? ""
                let part = sourceId.flatMap { s -> String? in
                    let c = s.dropFirst(4).prefix(1); return c.isEmpty ? nil : String(c) } ?? ""
                let num = sourceId?.components(separatedBy: "-P").last ?? ""
                return "AMC 10\(part) · \(year) #\(num)"
            case "amc12":
                let year = sourceId.flatMap { String($0.prefix(4)) } ?? ""
                let part = sourceId.flatMap { s -> String? in
                    let c = s.dropFirst(4).prefix(1); return c.isEmpty ? nil : String(c) } ?? ""
                let num = sourceId?.components(separatedBy: "-P").last ?? ""
                return "AMC 12\(part) · \(year) #\(num)"
            case "aime":
                let parts = sourceId?.components(separatedBy: "-") ?? []
                let year = parts.first ?? ""; let part = parts.dropFirst().first ?? ""; let num = parts.last ?? ""
                return "AIME \(part) · \(year) #\(num)"
            case "sat":      return "SAT Math"
            case "mmlu":
                let branch = baseBranch ?? topic
                return branch.isEmpty ? "MMLU" : "MMLU · \(branch)"
            case "arc":      return "ARC Science"
            case "gsm8k":    return "Grade School Math"
            case "openbookqa": return "OpenBookQA Science"
            case "scienceqa":  return "ScienceQA"
            case "mathvista":  return "MathVista"
            case "kangaroo":
                // source_id: "kangaroo_lvl-0_2015_1" → strip prefix → split by "_" → find 4-digit year
                let stripped = sourceId?.replacingOccurrences(of: "kangaroo_", with: "") ?? ""
                let year = stripped.components(separatedBy: "_").first(where: { $0.count == 4 && Int($0) != nil }) ?? ""
                return year.isEmpty ? "Math Kangaroo" : "Math Kangaroo · \(year)"
            case "agieval":
                if sourceId?.contains("sat_en") == true  { return "SAT English" }
                if sourceId?.contains("lsat_lr") == true { return "LSAT · Logical Reasoning" }
                if sourceId?.contains("lsat_rc") == true { return "LSAT · Reading" }
                if sourceId?.contains("lsat_ar") == true { return "LSAT · Analytical Reasoning" }
                return "AGIEval"
            default: return nil
            }
        }

        var isFromBank: Bool { bankQuestionId != nil }

        // Custom initializer for JSON decoding - restores UUID if stored, generates new one otherwise
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Restore persisted UUID (from UserDefaults); fall back to new UUID for backend JSON
            self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
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
            self.bankQuestionId = try container.decodeIfPresent(String.self, forKey: .bankQuestionId)
            self.figureUrl = try container.decodeIfPresent(String.self, forKey: .figureUrl)
            self.source = try container.decodeIfPresent(String.self, forKey: .source)
            self.sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId)
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
        init(id: UUID = UUID(), question: String, type: QuestionType, correctAnswer: String, explanation: String, topic: String, difficulty: String, points: Int? = nil, timeEstimate: String? = nil, options: [String]? = nil, tags: [String]? = nil, errorType: String? = nil, baseBranch: String? = nil, detailedBranch: String? = nil, weaknessKey: String? = nil, bankQuestionId: String? = nil, figureUrl: String? = nil, source: String? = nil, sourceId: String? = nil) {
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
            self.bankQuestionId = bankQuestionId
            self.figureUrl = figureUrl
            self.source = source
            self.sourceId = sourceId
        }

        // Coding keys for JSON encoding/decoding
        // 'id' is included so UUIDs survive UserDefaults round-trips;
        // backend JSON doesn't send 'id' so decoding falls back to UUID() above.
        enum CodingKeys: String, CodingKey {
            case id
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
            case errorType = "error_type"
            case baseBranch = "base_branch"
            case detailedBranch = "detailed_branch"
            case weaknessKey = "weakness_key"
            case bankQuestionId = "bank_question_id"
            case figureUrl = "figure_url"
            case source = "source"
            case sourceId = "source_id"
        }

        enum QuestionType: String, Codable, CaseIterable {
            case multipleChoice = "multiple_choice"
            case trueFalse = "true_false"
            case fillBlank = "fill_blank"
            case shortAnswer = "short_answer"
            case longAnswer = "long_answer"
            case calculation = "calculation"
            case matching = "matching"
            case composition = "composition"
            case any = "any"  // Allow AI to choose type dynamically

            /// Types that can be requested for generation (v2 endpoint).
            /// Excludes longAnswer, calculation, matching — kept for grading/display of existing questions only.
            static let generatableTypes: [QuestionType] = [.any, .multipleChoice, .trueFalse, .shortAnswer]

            var displayName: String {
                switch self {
                case .multipleChoice: return NSLocalizedString("questionType.multipleChoice", comment: "")
                case .trueFalse: return NSLocalizedString("questionType.trueFalse", comment: "")
                case .fillBlank: return NSLocalizedString("questionType.fillBlank", comment: "")
                case .shortAnswer: return NSLocalizedString("questionType.shortAnswer", comment: "")
                case .longAnswer: return NSLocalizedString("questionType.longAnswer", comment: "")
                case .calculation: return NSLocalizedString("questionType.calculation", comment: "")
                case .matching: return NSLocalizedString("questionType.matching", comment: "")
                case .composition: return NSLocalizedString("questionType.composition", comment: "")
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
                case .composition: return "doc.richtext"
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
        userProfile: UserProfile,
        rawMessages: [[String: String]] = []
    ) async -> Result<[GeneratedQuestion], QuestionGenerationError> {

        // Build comprehensive cache key including all configuration parameters
        let topicsString = config.topics.sorted().joined(separator: ",")
        let focusNotesHash = (config.focusNotes ?? "").isEmpty ? "none" : String((config.focusNotes ?? "").hashValue)
        let cacheKey = "random_\(subject)_\(topicsString)_\(config.difficulty.rawValue)_\(config.questionCount)_\(config.questionType.rawValue)_\(focusNotesHash)"

        if let cached = questionCache[cacheKey], !cached.isExpired {
            debugPrint("✅ Using cached questions (generated \(Int(Date().timeIntervalSince(cached.timestamp)))s ago)")
            return .success(cached.questions)
        } else if let cached = questionCache[cacheKey] {
            debugPrint("⏰ Cache expired (generated \(Int(Date().timeIntervalSince(cached.timestamp)))s ago), generating new questions...")
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


        debugPrint("📚 Subject: \(subject)")


        debugPrint("🏷️ Topics: \(config.topics)")
        debugPrint("👤 User Grade: \(userProfile.grade)")

        // NEW: Use Assistants API endpoint
        let endpoint = "/api/ai/generate-questions/practice"

        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            await MainActor.run { self.lastError = "Invalid URL" }
            return .failure(.invalidURL)
        }

        // NEW: Simplified request format for Assistants API
        var requestBody: [String: Any] = [
            "subject": subject,
            "topic": config.topics.joined(separator: ", "),
            "count": config.questionCount,
            "question_type": config.questionType.rawValue,
            "language": effectiveLanguage
        ]
        // Send grade_level so backend generates age-appropriate questions.
        // Without this, backend defaults to "General" and generates content beyond the student's level.
        if !userProfile.grade.isEmpty {
            requestBody["grade_level"] = userProfile.grade
        }
        // Only include difficulty when explicitly set — omit for .adaptive so backend auto-selects
        if let diffNum = mapDifficultyToNumber(config.difficulty) {
            requestBody["difficulty"] = diffNum
        }

        // Pass raw conversation messages when provided (triggers AI subject detection + Mode 3)
        if !rawMessages.isEmpty {
            requestBody["raw_messages"] = rawMessages
        }

        // ✅ FIX 1: Include personalized focus notes if available
        if let focusNotes = config.focusNotes, !focusNotes.isEmpty {
            requestBody["focus_notes"] = focusNotes
            debugPrint("📝 [QuestionGen] Sending personalized focus notes to backend (\(focusNotes.count) chars)")
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

            debugPrint("📤 Sending random questions request to AI engine...")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {


                if httpResponse.statusCode == 200 {
                    // Parse detectedSubject BEFORE parseQuestionResponse, then set synchronously
                    // using await MainActor.run so the caller reads the correct value immediately
                    if let rawJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let ds = rawJson["detectedSubject"] as? String, !ds.isEmpty {
                        await MainActor.run { self.lastDetectedSubject = ds }
                    }

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
                        let savedSession = PracticeSessionManager.shared.saveSession(
                            questions: responseResult.questions,
                            generationType: "Random Practice",
                            subject: subject,
                            config: config
                        )

                        await MainActor.run {
                            self.currentSessionId = savedSession.id
                        }

                        JourneyTracker.shared.track("practice_generated", [
                            "subject": subject,
                            "practice_type": "Random Practice",
                            "count": responseResult.questions.count,
                            "difficulty": config.difficulty.rawValue
                        ])
                        return .success(responseResult.questions)
                    } else {
                        let errorMsg = responseResult.error ?? "Unknown error from AI engine"
                        await MainActor.run { self.lastError = errorMsg }
                        return .failure(.aiProcessingError(errorMsg))
                    }
                } else if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                    // Genuine tier/quota block — show upgrade prompt
                    UsageService.shared.flagLimitReached(feature: "questions", errorCode: httpResponse.statusCode == 403 ? "UPGRADE_REQUIRED" : "MONTHLY_LIMIT_REACHED")
                    await MainActor.run { self.lastError = "Usage limit reached" }
                    return .failure(.serverError(httpResponse.statusCode))
                } else {
                    // Other errors (400 schema, 500 server, etc.) — don't show upgrade page
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


    // MARK: - Utility Methods

    /// Clear all cached questions
    func clearCache() {
        questionCache.removeAll()
        debugPrint("🗑️ Question generation cache cleared")
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
            debugPrint("📄 Raw Response (\(generationType)) - FULL VERSION:")
            debugPrint("--- START RESPONSE ---")
            debugPrint(rawString)
            debugPrint("--- END RESPONSE ---")
            debugPrint("📏 Total response length: \(rawString.count) characters")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuestionGenerationError.invalidResponse("Invalid JSON format")
        }

        let success = json["success"] as? Bool ?? false
        let subject = json["subject"] as? String ?? ""
        let detectedSubject = json["detectedSubject"] as? String  // set by backend auto-detection
        let tokensUsed = json["tokens_used"] as? Int
        let questionCount = json["question_count"] as? Int ?? 0
        let processingDetails = json["processing_details"] as? [String: Any]
        let error = json["error"] as? String

        // detectedSubject is now set synchronously in generateRandomQuestions via await MainActor.run
        // (keeping this as an additional safety net for other callers)
        if let ds = detectedSubject, !ds.isEmpty, Thread.isMainThread {
            self.lastDetectedSubject = ds
        }

        debugPrint("✅ Success: \(success)")
        debugPrint("📚 Subject: \(subject)")
        debugPrint("🔢 Question Count: \(questionCount)")
        if let error = error {
            debugPrint("❌ Error from backend: \(error)")
        }

        var questions: [GeneratedQuestion] = []

        // AGGRESSIVE PARSING: Try to extract questions even if backend reports success=false
        // This handles the case where backend generates valid JSON but has validation bugs
        if let questionsArray = json["questions"] as? [[String: Any]], !questionsArray.isEmpty {
            debugPrint("📝 Found questions array with \(questionsArray.count) questions, attempting to parse regardless of success flag...")

            for (index, questionDict) in questionsArray.enumerated() {
                debugPrint("\n🔍 Parsing Question #\(index + 1):")
                debugPrint("  - question_type: \(questionDict["question_type"] ?? "MISSING")")
                debugPrint("  - question: \(String(describing: questionDict["question"] ?? "MISSING").prefix(100))...")
                debugPrint("  - correct_answer: \(questionDict["correct_answer"] ?? "MISSING")")
                debugPrint("  - multiple_choice_options: \(questionDict["multiple_choice_options"] ?? "null")")

                do {
                    let question = try parseGeneratedQuestion(from: questionDict)
                    debugPrint("  ✅ Parsed as type: \(question.type.rawValue)")
                    questions.append(question)
                } catch {
                    debugPrint("  ❌ Failed to parse question \(index + 1): \(error)")
                }
            }

            // If we successfully parsed questions, ignore the backend success flag
            if !questions.isEmpty {
                debugPrint("🎉 Successfully parsed \(questions.count) questions despite backend success=false")
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
            debugPrint("📝 Parsing \(questionsArray.count) questions with success=true...")

            for (index, questionDict) in questionsArray.enumerated() {
                do {
                    let question = try parseGeneratedQuestion(from: questionDict)
                    questions.append(question)
                } catch {
                    debugPrint("⚠️ Failed to parse question \(index + 1): \(error)")
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


        debugPrint("📄 Raw response length: \(rawString.count) characters")

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
            debugPrint("📄 Found JSON block using \(strategy) strategy, attempting to parse...")

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
            debugPrint("📄 Found questions array, attempting to parse...")

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
                debugPrint("⚠️ Failed to parse \(strategy) question \(index + 1): \(error)")
                // Continue with other questions instead of failing completely
            }
        }

        if !questions.isEmpty {
            debugPrint("🎉 Successfully recovered \(questions.count) questions using \(strategy)")
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
            debugPrint("  ✅ Parsed \(options?.count ?? 0) multiple choice options (object format)")
        } else if let simpleOptions = dict["multiple_choice_options"] as? [String] {
            // ✅ NEW: Handle simple string array format from backend
            options = simpleOptions
            debugPrint("  ✅ Parsed \(options?.count ?? 0) multiple choice options (string array format)")
        } else if let simpleOptions = dict["options"] as? [String] {
            options = simpleOptions
            debugPrint("  ✅ Parsed \(options?.count ?? 0) multiple choice options (legacy format)")
        }

        let tags = dict["tags"] as? [String]

        // ✅ NEW: Extract error taxonomy fields for short-term status tracking
        let errorType = dict["error_type"] as? String
        let baseBranch = dict["base_branch"] as? String
        let detailedBranch = dict["detailed_branch"] as? String
        let weaknessKey = dict["weakness_key"] as? String
        let source = dict["source"] as? String
        let sourceId = dict["source_id"] as? String

        // Debug logging
        debugPrint("  📝 Parsed Question:")
        debugPrint("     - Type: \(typeString) → \(type.rawValue)")
        debugPrint("     - Has options: \(options != nil)")
        if let opts = options {
            debugPrint("     - Options count: \(opts.count)")
        }
        // ✅ NEW: Log error keys if present
        if let errorType = errorType {
            debugPrint("     - Error Type: \(errorType)")
            debugPrint("     - Base Branch: \(baseBranch ?? "nil")")
            debugPrint("     - Detailed Branch: \(detailedBranch ?? "nil")")
            debugPrint("     - Weakness Key: \(weaknessKey ?? "nil")")
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
            weaknessKey: weaknessKey,
            bankQuestionId: dict["bank_question_id"] as? String,
            figureUrl: dict["figure_url"] as? String,
            source: source,
            sourceId: sourceId
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

    // MARK: - V2 Unified Endpoint (Typed Parallel Requests)

    /// Build short-term context from the top active weakness for mode-1 generation.
    /// Returns up to 2 recent wrong questions associated with the strongest active weakness.
    func buildShortTermContext(subject: String) -> [[String: Any]] {
        let allWeaknesses = ShortTermStatusService.shared.getTopActiveWeaknesses(limit: 20)
        let weaknesses = allWeaknesses.filter {
            $0.key.split(separator: "/").first.map { String($0).lowercased() == subject.lowercased() } ?? false
        }.prefix(3)
        guard !weaknesses.isEmpty else { return [] }

        let allLocalQuestions = currentUserQuestionStorage().getLocalQuestions()

        var result: [[String: Any]] = []

        for (weaknessKey, weaknessValue) in weaknesses {
            guard result.count < 2 else { break }

            for questionId in weaknessValue.recentQuestionIds.prefix(2) {
                guard result.count < 2 else { break }

                if let qDict = allLocalQuestions.first(where: { ($0["id"] as? String) == questionId }),
                   let questionText = qDict["questionText"] as? String,
                   !questionText.isEmpty {
                    let entry: [String: Any] = [
                        "question": questionText,
                        "correct_answer": qDict["answerText"] as? String ?? "",
                        "user_answer": qDict["studentAnswer"] as? String ?? "",
                        "branch": weaknessKey
                    ]
                    result.append(entry)
                }
            }
        }

        return result
    }

    /// Generate practice questions using the v2 endpoint (typed parallel requests).
    ///
    /// - Parameters:
    ///   - subject: Subject name
    ///   - mode: 1 = Random, 2 = From Mistakes, 3 = From Archive
    ///   - config: Question count, type, difficulty, topics
    ///   - userProfile: Grade / location
    ///   - shortTermContext: Recent wrong questions for mode 1 (pass `buildShortTermContext(subject:)`)
    ///   - mistakesData: For mode 2
    ///   - conversationData: For mode 3
    ///   - questionData: For mode 3
    func generateQuestionsV2(
        subject: String,
        mode: Int,
        config: RandomQuestionsConfig,
        userProfile: UserProfile,
        shortTermContext: [[String: Any]] = [],
        mistakesData: [MistakeData] = [],
        conversationData: [ConversationData] = [],
        questionData: [[String: Any]] = [],
        bankSource: String? = nil
    ) async -> Result<[GeneratedQuestion], QuestionGenerationError> {

        await MainActor.run {
            self.isGenerating = true
            self.lastError = nil
            self.generationProgress = "Generating questions for \(subject)..."
        }

        defer {
            Task { @MainActor in
                self.isGenerating = false
                self.generationProgress = nil
            }
        }

        let endpoint = "/api/ai/generate-questions/practice/v2"
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            await MainActor.run { self.lastError = "Invalid URL" }
            return .failure(.invalidURL)
        }

        var body: [String: Any] = [
            "subject": subject,
            "mode": mode,
            "count": config.questionCount,
            "question_type": config.questionType.rawValue,
            "language": effectiveLanguage,
            "topic": config.topics.joined(separator: ", ")
        ]

        // Pass local grade so backend generates age-appropriate questions immediately.
        // For child accounts: read ChildLocalProfile.gradeLevel first (no DB lag after switch).
        let localGradeForV2: String? = {
            if UserDefaults.standard.bool(forKey: "isChildSessionActive"),
               let childId = AuthenticationService.shared.currentUser?.id {
                let childData = UserDefaults.standard.data(forKey: "child_local_\(childId)")
                let childLocal = childData.flatMap { try? JSONDecoder().decode(ChildLocalProfile.self, from: $0) }
                if let g = childLocal?.gradeLevel, !g.isEmpty { return g }
            }
            return userProfile.grade.isEmpty ? nil : userProfile.grade
        }()
        if let grade = localGradeForV2 {
            body["grade_level"] = grade
        }

        if let diffNum = mapDifficultyToNumber(config.difficulty) {
            body["difficulty"] = diffNum
        }

        switch mode {
        case 1:
            if !shortTermContext.isEmpty {
                body["short_term_context"] = shortTermContext
            }
        case 2:
            body["mistakes_data"] = mistakesData.map { $0.dictionary }
        case 3:
            body["conversation_data"] = conversationData.map { $0.dictionary }
            body["question_data"] = questionData
        case 4:
            body["short_term_context"] = shortTermContext
            body["mistakes_data"] = mistakesData.map { $0.dictionary }
            if let src = bankSource { body["bank_source"] = src }
            // Include tag weakness context so the bank can boost/de-boost matching questions
            let errorMicroWeakness = ShortTermStatusService.shared.topErrorMicroTags(limit: 3)
            let skillWeakness      = ShortTermStatusService.shared.topSkillWeaknesses(limit: 2)
            let styleWeakness      = ShortTermStatusService.shared.topStyleWeaknesses(limit: 2)
            if !errorMicroWeakness.isEmpty || !skillWeakness.isEmpty || !styleWeakness.isEmpty {
                body["tag_weakness_context"] = [
                    "error_micro_weakness": errorMicroWeakness,
                    "skill_weakness": skillWeakness,
                    "style_weakness": styleWeakness,
                ]
            }
        default:
            break
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 150.0

        guard let token = AuthenticationService.shared.getAuthToken() else {
            await MainActor.run { self.lastError = "Authentication required" }
            return .failure(.authenticationRequired)
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            debugPrint("📤 [V2] Sending request to \(endpoint) (mode=\(mode), type=\(config.questionType.rawValue), count=\(config.questionCount))")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let responseResult = try parseQuestionResponse(data: data, generationType: "v2_mode\(mode)")
                    if responseResult.success {
                        let generationType: String
                        switch mode {
                        case 2: generationType = "Mistake-Based Practice"
                        case 3: generationType = "Conversation-Based Practice"
                        default: generationType = "Random Practice"
                        }
                        let savedSession4 = PracticeSessionManager.shared.saveSession(
                            questions: responseResult.questions,
                            generationType: generationType,
                            subject: subject,
                            config: config
                        )
                        await MainActor.run {
                            self.lastGeneratedQuestions = responseResult.questions
                            self.lastGenerationDate = Date()
                            self.lastGenerationType = generationType
                            self.currentSessionId = savedSession4.id
                        }
                        debugPrint("🎉 [V2] Generated \(responseResult.questions.count) questions successfully")
                        return .success(responseResult.questions)
                    } else {
                        let errorMsg = responseResult.error ?? "Unknown error from v2 endpoint"
                        await MainActor.run { self.lastError = errorMsg }
                        return .failure(.aiProcessingError(errorMsg))
                    }
                } else {
                    let errorMsg = "Server error: HTTP \(httpResponse.statusCode)"
                    await MainActor.run { self.lastError = errorMsg }
                    if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
                        UsageService.shared.flagLimitReached(feature: "questions", errorCode: httpResponse.statusCode == 403 ? "UPGRADE_REQUIRED" : "MONTHLY_LIMIT_REACHED")
                    }
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