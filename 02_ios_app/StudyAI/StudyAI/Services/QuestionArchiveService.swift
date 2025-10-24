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

        print("📚 [Archive] Archiving \(request.selectedQuestionIndices.count) questions to LOCAL storage only")

        // ✅ LOCAL-ONLY: No server POST, no deduplication check against server
        // Deduplication will be handled by StorageSyncService when syncing to server

        var archivedQuestions: [ArchivedQuestion] = []
        var questionDataForLocalStorage: [[String: Any]] = []

        for (arrayIndex, questionIndex) in request.selectedQuestionIndices.enumerated() {
            guard questionIndex < request.questions.count else { continue }

            let question = request.questions[questionIndex]
            let userNote = arrayIndex < request.userNotes.count ? request.userNotes[arrayIndex] : ""
            let userTag = arrayIndex < request.userTags.count ? request.userTags[arrayIndex] : []

            // Generate local UUID for this question
            let questionId = UUID().uuidString

            // ✅ NORMALIZE: Ensure grade is in uppercase format for enum compatibility
            // AI server may send "Correct"/"Incorrect" but enum expects "CORRECT"/"INCORRECT"
            let normalizedGrade: String? = {
                guard let grade = question.grade else { return nil }
                let uppercased = grade.uppercased()
                // Map common variations to enum values
                switch uppercased {
                case "CORRECT": return "CORRECT"
                case "INCORRECT": return "INCORRECT"
                case "EMPTY": return "EMPTY"
                case "PARTIAL_CREDIT", "PARTIAL CREDIT", "PARTIALCREDIT": return "PARTIAL_CREDIT"
                default: return uppercased  // Try to use as-is if unknown
                }
            }()

            // ✅ CRITICAL: Calculate isCorrect for mistake tracking
            // This field is required for the mistake notes feature to work
            // LOGIC: Only grade == .correct results in isCorrect = true
            //        All other grades (.incorrect, .empty, .partialCredit) result in isCorrect = false
            //        This ensures PARTIAL_CREDIT questions appear in Mistake Notes
            let isCorrect: Bool = {
                // Check grade first (most reliable)
                if let gradeString = normalizedGrade,
                   let grade = GradeResult(rawValue: gradeString) {
                    // Only CORRECT grade counts as correct
                    // INCORRECT, EMPTY, and PARTIAL_CREDIT all count as mistakes for review
                    return grade == .correct
                }

                // Fallback: If no grade but has points, check if score >= 80%
                if let points = question.pointsEarned,
                   let maxPoints = question.pointsPossible,
                   maxPoints > 0 {
                    return points >= (maxPoints * 0.8)
                }

                // Default to false (treat as mistake for review if uncertain)
                return false
            }()

            // Create ArchivedQuestion with local ID
            let archivedQuestion = ArchivedQuestion(
                id: questionId,
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
                grade: normalizedGrade.flatMap { GradeResult(rawValue: $0) },
                points: question.pointsEarned,
                maxPoints: question.pointsPossible,
                feedback: question.feedback,
                isGraded: normalizedGrade != nil,
                isCorrect: isCorrect,
                questionType: question.questionType,
                options: question.options
            )

            archivedQuestions.append(archivedQuestion)

            // Build data for local storage
            let questionData: [String: Any] = [
                "id": questionId,
                "subject": request.detectedSubject,
                "questionText": question.questionText,
                "rawQuestionText": question.rawQuestionText ?? question.questionText,
                "answerText": question.answerText,
                "confidence": question.confidence ?? 0.0,
                "hasVisualElements": question.hasVisualElements,
                "archivedAt": ISO8601DateFormatter().string(from: Date()),
                "reviewCount": 0,
                "tags": userTag,
                "notes": userNote,
                "studentAnswer": question.studentAnswer ?? "",
                "grade": normalizedGrade ?? "",  // ✅ Store normalized grade for filtering
                "points": question.pointsEarned ?? 0.0,
                "maxPoints": question.pointsPossible ?? 1.0,
                "feedback": question.feedback ?? "",
                "isGraded": normalizedGrade != nil,
                "isCorrect": isCorrect,  // ✅ CRITICAL: Store for mistake tracking
                "questionType": question.questionType ?? "",
                "options": question.options ?? []
            ]
            questionDataForLocalStorage.append(questionData)

            print("   📝 [Archive] Question \(arrayIndex + 1): \(question.questionText.prefix(50))... (ID: \(questionId))")
            print("      ✓ Original grade: \(question.grade ?? "N/A") → Normalized: \(normalizedGrade ?? "N/A")")
            print("      ✓ isCorrect: \(isCorrect) \(isCorrect ? "✅" : "❌ MISTAKE")")
        }

        // ✅ Save to local storage ONLY - no server request
        QuestionLocalStorage.shared.saveQuestions(questionDataForLocalStorage)

        // ✅ DEBUG: Verify what was saved
        print("\n🔍 [DEBUG] === VERIFYING SAVED DATA ===")
        let savedQuestions = QuestionLocalStorage.shared.getLocalQuestions()
        print("🔍 [DEBUG] Total questions in storage after save: \(savedQuestions.count)")

        if let firstSaved = savedQuestions.first {
            print("🔍 [DEBUG] First saved question:")
            print("   - ID: \(firstSaved["id"] ?? "nil")")
            print("   - Grade: \(firstSaved["grade"] ?? "nil")")
            print("   - isCorrect: \(firstSaved["isCorrect"] ?? "nil")")
            print("   - Subject: \(firstSaved["subject"] ?? "nil")")
            print("   - Question: \(String(describing: firstSaved["questionText"] ?? "nil").prefix(50))...")
        }

        // Check how many mistakes are in storage
        let mistakes = QuestionLocalStorage.shared.getMistakeQuestions()
        print("🔍 [DEBUG] Total mistakes in storage: \(mistakes.count)")
        print("🔍 [DEBUG] === END VERIFICATION ===\n")

        print("✅ [Archive] Saved \(archivedQuestions.count) questions to LOCAL storage only")
        print("   💡 [Archive] Use 'Sync with Server' to upload to backend")

        return archivedQuestions
    }

    // MARK: - Fetch Questions from Server

    /// Fetch archived questions list (summaries) - LOCAL ONLY
    func fetchArchivedQuestions(limit: Int = 50, offset: Int = 0, subject: String? = nil) async throws -> [QuestionSummary] {
        print("🔍 [Archive] Fetching questions from LOCAL storage only")

        // ✅ Get local questions only (no server fetch)
        let localStorage = QuestionLocalStorage.shared
        let localQuestions = localStorage.getLocalQuestions()
        print("   💾 [Archive] Found \(localQuestions.count) questions in local storage")

        // Convert to QuestionSummary
        var summaries: [QuestionSummary] = []
        for questionData in localQuestions {
            do {
                let summary = try convertQuestionSummaryFromRailwayFormat(questionData)
                summaries.append(summary)
            } catch {
                print("   ⚠️ [Archive] Failed to convert question: \(error)")
            }
        }

        print("   ✅ [Archive] Converted \(summaries.count) questions to summaries")
        return summaries
    }

    /// Fetch full question details by ID - LOCAL ONLY
    func getQuestionDetails(questionId: String) async throws -> ArchivedQuestion {
        print("🔍 [Archive] Fetching question details from LOCAL storage: \(questionId)")

        // ✅ Get from local storage only (no server fetch)
        guard let localQuestion = QuestionLocalStorage.shared.getQuestionById(questionId) else {
            print("   ❌ [Archive] Question not found in local storage")
            throw QuestionArchiveError.questionNotFound
        }

        print("   💾 [Archive] Found in local storage")
        let question = try convertFullQuestionFromRailwayFormat(localQuestion)
        print("   ✅ [Archive] Loaded from local storage: \(question.subject)")

        return question
    }

    // MARK: - Upload Question to Server

    /// Upload a single question directly to server (used by StorageSyncService)
    func uploadQuestionToServer(_ questionData: [String: Any]) async throws -> String {
        guard let authToken = authToken else {
            throw QuestionArchiveError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)/api/archived-questions") else {
            throw QuestionArchiveError.invalidURL
        }

        // ✅ NORMALIZE: Ensure grade is in uppercase format before sending to server
        let rawGrade = questionData["grade"] as? String ?? ""
        let normalizedGrade: String = {
            guard !rawGrade.isEmpty else { return "" }
            let uppercased = rawGrade.uppercased()
            switch uppercased {
            case "CORRECT": return "CORRECT"
            case "INCORRECT": return "INCORRECT"
            case "EMPTY": return "EMPTY"
            case "PARTIAL_CREDIT", "PARTIAL CREDIT", "PARTIALCREDIT": return "PARTIAL_CREDIT"
            default: return uppercased
            }
        }()

        // Build request body - ensure isCorrect is included
        var requestBody: [String: Any] = [
            "subject": questionData["subject"] as? String ?? "Unknown",
            "questionText": questionData["questionText"] as? String ?? "",
            "rawQuestionText": questionData["rawQuestionText"] as? String ?? questionData["questionText"] as? String ?? "",
            "answerText": questionData["answerText"] as? String ?? "",
            "confidence": questionData["confidence"] as? Float ?? 0.0,
            "hasVisualElements": questionData["hasVisualElements"] as? Bool ?? false,
            "tags": questionData["tags"] as? [String] ?? [],
            "notes": questionData["notes"] as? String ?? "",
            "studentAnswer": questionData["studentAnswer"] as? String ?? "",
            "grade": normalizedGrade,  // ✅ Send normalized grade
            "points": questionData["points"] as? Float ?? 0.0,
            "maxPoints": questionData["maxPoints"] as? Float ?? 1.0,
            "feedback": questionData["feedback"] as? String ?? "",
            "isCorrect": questionData["isCorrect"] as? Bool ?? false  // ✅ CRITICAL for mistake tracking
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("   📤 [Archive] Uploading question to server: \(url)")
        print("   📝 [Archive] Grade: \(rawGrade) → \(normalizedGrade)")
        print("   📝 [Archive] isCorrect: \(requestBody["isCorrect"] ?? "nil")")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuestionArchiveError.invalidResponse
        }

        guard httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
            print("   ❌ [Archive] Server returned error: \(httpResponse.statusCode)")
            if let errorText = String(data: data, encoding: .utf8) {
                print("   ❌ [Archive] Error response: \(errorText)")
            }
            throw QuestionArchiveError.archiveFailed("Server returned status code \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questionId = json["id"] as? String ?? json["questionId"] as? String else {
            throw QuestionArchiveError.invalidData
        }

        print("   ✅ [Archive] Successfully uploaded question (ID: \(questionId))")

        return questionId
    }

    // MARK: - Helper Methods (kept for StorageSyncService data conversion)

    private func convertQuestionSummaryFromRailwayFormat(_ data: [String: Any]) throws -> QuestionSummary {
        guard let id = data["id"] as? String,
              let subject = data["subject"] as? String,
              let questionText = data["questionText"] as? String,
              let archivedAtString = data["archivedAt"] as? String,
              let archivedAt = parseDate(archivedAtString) else {
            throw QuestionArchiveError.invalidData
        }

        // Extract rawQuestionText from storage
        let rawQuestionText = data["rawQuestionText"] as? String

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

        // Question type fields
        let questionType = data["questionType"] as? String
        let options = data["options"] as? [String]

        return QuestionSummary(
            id: id,
            subject: subject,
            questionText: questionText,
            rawQuestionText: rawQuestionText,  // Include the full question text
            confidence: confidence,
            hasVisualElements: hasVisualElements,
            archivedAt: archivedAt,
            reviewCount: reviewCount,
            tags: tags,
            totalQuestions: 1, // Each question summary represents 1 question
            grade: grade,
            points: points,
            maxPoints: maxPoints,
            isGraded: isGraded,
            questionType: questionType,
            options: options
        )
    }
    
    private func convertFullQuestionFromRailwayFormat(_ data: [String: Any]) throws -> ArchivedQuestion {
        guard let id = data["id"] as? String,
              let subject = data["subject"] as? String,
              let questionText = data["questionText"] as? String,
              let answerText = data["answerText"] as? String,
              let archivedAtString = data["archivedAt"] as? String,
              let archivedAt = parseDate(archivedAtString) else {
            throw QuestionArchiveError.invalidData
        }

        // ✅ userId is optional (local storage doesn't have it, server does)
        let userId = data["userId"] as? String ?? currentUserId ?? "unknown"

        // ✅ Extract rawQuestionText from storage (full original question text)
        let rawQuestionText = data["rawQuestionText"] as? String

        // Debug logging for rawQuestionText extraction
        print("   📊 [Convert] Extracting rawQuestionText from storage:")
        print("      - Has rawQuestionText in data: \(data["rawQuestionText"] != nil)")
        if let rawText = rawQuestionText {
            print("      - rawQuestionText length: \(rawText.count) chars")
            print("      - rawQuestionText preview: \(rawText.prefix(100))...")
        } else {
            print("      - ❌ rawQuestionText is NIL in stored data")
        }

        let confidence = (data["confidence"] as? Float) ?? (data["confidence"] as? Double).map(Float.init) ?? 0.0
        let hasVisualElements = (data["hasVisualElements"] as? Bool) ?? false
        let processingTime = (data["processingTime"] as? Double) ?? 0.0
        let reviewCount = (data["reviewCount"] as? Int) ?? 0
        let originalImageUrl = data["originalImageUrl"] as? String
        let questionImageUrl = data["questionImageUrl"] as? String
        let tags = data["tags"] as? [String]
        let notes = data["notes"] as? String

        // Grading fields - support both local and server formats
        let studentAnswer = data["studentAnswer"] as? String
        let gradeString = data["grade"] as? String
        let grade = gradeString != nil && !gradeString!.isEmpty ? GradeResult(rawValue: gradeString!) : nil
        let points = (data["points"] as? Float) ?? (data["points"] as? Double).map(Float.init) ??
                     (data["pointsEarned"] as? Float) ?? (data["pointsEarned"] as? Double).map(Float.init)
        let maxPoints = (data["maxPoints"] as? Float) ?? (data["maxPoints"] as? Double).map(Float.init) ??
                        (data["pointsPossible"] as? Float) ?? (data["pointsPossible"] as? Double).map(Float.init)
        let feedback = data["feedback"] as? String
        let isGraded = (data["isGraded"] as? Bool) ?? (gradeString != nil && !gradeString!.isEmpty)

        // ✅ CRITICAL: Extract isCorrect for mistake tracking
        // Support both camelCase (local) and snake_case (server) formats
        // LOGIC: Only grade == .correct results in isCorrect = true
        //        All other grades (.incorrect, .empty, .partialCredit) result in isCorrect = false
        //        This ensures PARTIAL_CREDIT questions appear in Mistake Notes
        let isCorrect: Bool? = {
            // First try to get stored value
            if let storedValue = data["isCorrect"] as? Bool ?? data["is_correct"] as? Bool {
                return storedValue
            }

            // Calculate from grade if not stored (backward compatibility)
            if let grade = grade {
                // Only CORRECT grade counts as correct
                // INCORRECT, EMPTY, and PARTIAL_CREDIT all count as mistakes for review
                return grade == .correct
            }

            // Fallback: If no grade but has points, check if score >= 80%
            if let points = points, let maxPoints = maxPoints, maxPoints > 0 {
                return points >= (maxPoints * 0.8)
            }

            // Default to false (treat as mistake for review if uncertain)
            return false
        }()

        var lastReviewedAt: Date?
        if let lastReviewedAtString = data["lastReviewedAt"] as? String {
            lastReviewedAt = parseDate(lastReviewedAtString)
        }

        // Question type fields
        let questionType = data["questionType"] as? String
        let options = data["options"] as? [String]

        // Log the isCorrect value for debugging
        print("   📊 [Convert] Question \(id): grade=\(gradeString ?? "nil"), isCorrect=\(isCorrect?.description ?? "nil")")

        return ArchivedQuestion(
            id: id,
            userId: userId,
            subject: subject,
            questionText: questionText,
            rawQuestionText: rawQuestionText,  // ✅ CRITICAL: Include full original question text
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
            isGraded: isGraded,
            isCorrect: isCorrect,  // ✅ CRITICAL: Include for mistake tracking
            questionType: questionType,
            options: options
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