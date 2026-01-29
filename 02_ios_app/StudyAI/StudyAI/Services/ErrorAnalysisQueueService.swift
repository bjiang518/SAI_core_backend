//
//  ErrorAnalysisQueueService.swift
//  StudyAI
//
//  Manages background error analysis for wrong answers
//  Implements Pass 2 of two-pass grading system
//

import Foundation
import Combine

class ErrorAnalysisQueueService: ObservableObject {
    static let shared = ErrorAnalysisQueueService()

    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0.0

    private let localStorage = QuestionLocalStorage.shared
    private var analysisTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public API

    /// Queue error analysis for newly graded wrong questions
    /// Called immediately after Pass 1 grading completes
    func queueErrorAnalysisAfterGrading(sessionId: String, wrongQuestions: [[String: Any]]) {
        guard !wrongQuestions.isEmpty else {
            print("📊 [ErrorAnalysis] No wrong answers - skipping Pass 2")
            return
        }

        print("📊 [ErrorAnalysis] Queuing Pass 2 for \(wrongQuestions.count) wrong answers")

        // Cancel previous analysis if running
        analysisTask?.cancel()

        // Start background analysis
        analysisTask = Task {
            await analyzeBatch(sessionId: sessionId, questions: wrongQuestions)
        }
    }

    /// Re-analyze failed questions
    func retryFailedAnalyses() async {
        let failedQuestions = localStorage.getLocalQuestions().filter {
            ($0["errorAnalysisStatus"] as? String) == "failed"
        }

        guard !failedQuestions.isEmpty else {
            print("📊 [ErrorAnalysis] No failed analyses to retry")
            return
        }

        print("📊 [ErrorAnalysis] Retrying \(failedQuestions.count) failed analyses")
        await analyzeBatch(sessionId: "retry", questions: failedQuestions)
    }

    // MARK: - Concept Extraction (Bidirectional Status Tracking)

    /// Extract concepts for CORRECT answers to reduce weakness values
    /// Called immediately after grading for correct answers
    func queueConceptExtractionForCorrectAnswers(sessionId: String, correctQuestions: [[String: Any]]) {
        guard !correctQuestions.isEmpty else {
            print("📊 [ConceptExtraction] No correct answers - skipping")
            return
        }

        print("📊 [ConceptExtraction] Queuing concept extraction for \(correctQuestions.count) correct answers")

        Task {
            await extractConceptsBatch(sessionId: sessionId, questions: correctQuestions)
        }
    }

    /// Extract concepts for a batch of correct questions
    private func extractConceptsBatch(sessionId: String, questions: [[String: Any]]) async {
        print("📊 [ConceptExtraction] Starting batch extraction for \(questions.count) questions")

        // Build extraction requests
        let extractionRequests = questions.compactMap { question -> ConceptExtractionRequest? in
            let questionText = question["questionText"] as? String ?? ""
            let subject = question["subject"] as? String ?? "Mathematics"

            print("📝 [ConceptExtraction] Building request for Q: '\(questionText.prefix(50))...'")

            return ConceptExtractionRequest(
                questionText: questionText,
                subject: subject
            )
        }

        do {
            print("📤 [ConceptExtraction] Sending \(extractionRequests.count) requests to backend")

            let concepts = try await NetworkService.shared.extractConceptsBatch(
                questions: extractionRequests
            )

            print("📥 [ConceptExtraction] Received \(concepts.count) concepts from backend")

            // Update ShortTermStatusService with negative values (mastery)
            for (index, concept) in concepts.enumerated() {
                guard index < questions.count else { continue }

                if let baseBranch = concept.baseBranch,
                   let detailedBranch = concept.detailedBranch,
                   !concept.extractionFailed {

                    // Build weakness key: "Subject/Base Branch/Detailed Branch"
                    let weaknessKey = "\(concept.subject)/\(baseBranch)/\(detailedBranch)"
                    let questionId = questions[index]["id"] as? String

                    print("✅ [ConceptExtraction] Correct answer detected:")
                    print("   Key: \(weaknessKey)")
                    print("   Reducing weakness value (mastery bonus)")

                    // ✅ BIDIRECTIONAL TRACKING: Correct answer reduces weakness
                    ShortTermStatusService.shared.recordCorrectAttempt(
                        key: weaknessKey,
                        retryType: .firstTime,
                        questionId: questionId
                    )
                } else {
                    print("⚠️ [ConceptExtraction] Extraction failed for question \(index)")
                }
            }

            print("✅ [ConceptExtraction] Completed extraction for \(concepts.count) questions")

            // Post notification for UI update
            NotificationCenter.default.post(
                name: NSNotification.Name("ConceptExtractionCompleted"),
                object: nil,
                userInfo: ["sessionId": sessionId, "count": concepts.count]
            )

        } catch {
            print("❌ [ConceptExtraction] Batch extraction failed: \(error)")
        }
    }

    // MARK: - Private Implementation

    private func analyzeBatch(sessionId: String, questions: [[String: Any]]) async {
        await MainActor.run {
            isAnalyzing = true
            analysisProgress = 0.0
        }

        defer {
            Task { @MainActor in
                isAnalyzing = false
                analysisProgress = 1.0
            }
        }

        print("📊 [ErrorAnalysis] Starting batch analysis for \(questions.count) questions")

        // Mark questions as 'processing' in local storage
        updateLocalStatus(questionIds: questions.compactMap { $0["id"] as? String },
                         status: "processing")

        // Call backend error analysis endpoint (stateless)
        do {
            let analysisRequests = questions.compactMap { question -> ErrorAnalysisRequest? in
                let questionText = question["questionText"] as? String ?? ""
                let studentAnswer = question["studentAnswer"] as? String ?? ""
                let correctAnswer = question["answerText"] as? String ?? ""
                let subject = question["subject"] as? String ?? "General"
                let questionId = question["id"] as? String

                print("📝 [ErrorAnalysis] Building request for Q: '\(questionText.prefix(50))...'")
                print("   Student: '\(studentAnswer.prefix(30))...', Correct: '\(correctAnswer.prefix(30))...'")

                return ErrorAnalysisRequest(
                    questionText: questionText,
                    studentAnswer: studentAnswer,
                    correctAnswer: correctAnswer,
                    subject: subject,
                    questionId: questionId
                )
            }

            print("📤 [ErrorAnalysis] Sending \(analysisRequests.count) requests to backend")

            let analyses = try await NetworkService.shared.analyzeErrorsBatch(
                questions: analysisRequests
            )

            print("📥 [ErrorAnalysis] Received \(analyses.count) analyses from backend")

            // Update local storage with results
            for (index, analysis) in analyses.enumerated() {
                guard index < questions.count,
                      let questionId = questions[index]["id"] as? String else {
                    print("⚠️ [ErrorAnalysis] Skipping analysis \(index) - invalid question ID")
                    continue
                }

                print("📊 [ErrorAnalysis] Analysis \(index + 1)/\(analyses.count):")
                print("   Error Type: \(analysis.error_type ?? "none")")
                print("   Confidence: \(analysis.confidence)")
                print("   Failed: \(analysis.analysis_failed)")

                updateLocalQuestionWithAnalysis(
                    questionId: questionId,
                    analysis: analysis
                )

                // Update progress
                await MainActor.run {
                    analysisProgress = Double(index + 1) / Double(questions.count)
                }
            }

            print("✅ [ErrorAnalysis] Completed Pass 2 for \(analyses.count) questions")

            // Post notification for UI update
            NotificationCenter.default.post(
                name: NSNotification.Name("ErrorAnalysisCompleted"),
                object: nil,
                userInfo: ["sessionId": sessionId, "count": analyses.count]
            )

        } catch {
            print("❌ [ErrorAnalysis] Failed: \(error.localizedDescription)")
            print("❌ [ErrorAnalysis] Error type: \(type(of: error))")
            print("❌ [ErrorAnalysis] Full error: \(error)")

            // Mark all as failed
            updateLocalStatus(
                questionIds: questions.compactMap { $0["id"] as? String },
                status: "failed"
            )
        }
    }

    private func updateLocalQuestionWithAnalysis(questionId: String, analysis: ErrorAnalysisResponse) {
        var allQuestions = localStorage.getLocalQuestions()

        guard let index = allQuestions.firstIndex(where: { ($0["id"] as? String) == questionId }) else {
            print("⚠️ [ErrorAnalysis] Question \(questionId) not found in local storage")
            return
        }

        // NEW: Save hierarchical taxonomy
        allQuestions[index]["baseBranch"] = analysis.base_branch ?? ""
        allQuestions[index]["detailedBranch"] = analysis.detailed_branch ?? ""
        allQuestions[index]["specificIssue"] = analysis.specific_issue ?? ""

        // Save error type (now 3 values)
        allQuestions[index]["errorType"] = analysis.error_type ?? ""
        allQuestions[index]["errorEvidence"] = analysis.evidence ?? ""
        allQuestions[index]["learningSuggestion"] = analysis.learning_suggestion ?? ""
        allQuestions[index]["errorConfidence"] = analysis.confidence

        // ✅ Save status as string (for backwards compatibility with UserDefaults)
        let status: ErrorAnalysisStatus = analysis.analysis_failed ? .failed : .completed
        allQuestions[index]["errorAnalysisStatus"] = status.rawValue
        allQuestions[index]["errorAnalyzedAt"] = ISO8601DateFormatter().string(from: Date())

        // NEW: Generate weakness key using hierarchical path
        if let baseBranch = analysis.base_branch,
           let detailedBranch = analysis.detailed_branch,
           !baseBranch.isEmpty,
           !detailedBranch.isEmpty {

            let subject = allQuestions[index]["subject"] as? String ?? "Mathematics"

            // NEW format: "Mathematics/Algebra - Foundations/Linear Equations - One Variable"
            let weaknessKey = "\(subject)/\(baseBranch)/\(detailedBranch)"

            allQuestions[index]["weaknessKey"] = weaknessKey
            print("   🔑 [WeaknessTracking] Generated weakness key: \(weaknessKey)")
        } else {
            print("   ⚠️ [WeaknessTracking] Could NOT generate weakness key:")
            print("      base_branch: \(analysis.base_branch ?? "nil")")
            print("      detailed_branch: \(analysis.detailed_branch ?? "nil")")
        }

        // Save back to local storage (now includes weaknessKey)
        _ = localStorage.saveQuestions([allQuestions[index]])

        print("✅ [ErrorAnalysis] Updated question \(questionId): \(analysis.error_type ?? "unknown") (branch: \(analysis.detailed_branch ?? "N/A"))")

        // ✅ Update short-term status (use the weaknessKey we just saved)
        if let weaknessKey = allQuestions[index]["weaknessKey"] as? String,
           let errorType = analysis.error_type {

            print("   📊 [WeaknessTracking] Calling recordMistake for key: \(weaknessKey)")
            print("      Error type: \(errorType)")

            Task { @MainActor in
                ShortTermStatusService.shared.recordMistake(
                    key: weaknessKey,
                    errorType: errorType,
                    questionId: questionId
                )
            }
        } else {
            print("   ⚠️ [WeaknessTracking] Skipping recordMistake - no weaknessKey or errorType")
        }
    }

    private func updateLocalStatus(questionIds: [String], status: String) {
        var allQuestions = localStorage.getLocalQuestions()

        for questionId in questionIds {
            guard let index = allQuestions.firstIndex(where: { ($0["id"] as? String) == questionId }) else {
                continue
            }

            allQuestions[index]["errorAnalysisStatus"] = status
        }

        _ = localStorage.saveQuestions(allQuestions)
    }

    // MARK: - Correct Answer Processing

    /// Process correct answers to update weakness tracking
    /// Should be called after grading completes for CORRECT answers
    /// This allows natural learning through homework to reduce weaknesses
    func processCorrectAnswer(questionId: String, subject: String, concept: String, questionType: String) {
        print("✅ [WeaknessTracking] processCorrectAnswer called:")
        print("   Question ID: \(questionId)")
        print("   Subject: \(subject), Concept: \(concept), Type: \(questionType)")

        Task { @MainActor in
            let key = ShortTermStatusService.shared.generateKey(
                subject: subject,
                concept: concept,
                questionType: questionType
            )

            print("   Generated weakness key: \(key)")

            // Check if this weakness exists
            guard ShortTermStatusService.shared.status.activeWeaknesses[key] != nil else {
                print("   ℹ️ No existing weakness for this key - skipping")
                return  // No weakness to update
            }

            print("   ✅ Found weakness! Calling recordCorrectAttemptWithAutoDetection...")

            // Record correct attempt with auto-detection
            ShortTermStatusService.shared.recordCorrectAttemptWithAutoDetection(
                key: key,
                questionId: questionId
            )

            print("   ✅ Weakness value decreased")
        }
    }
}

// MARK: - Models

struct ErrorAnalysisRequest: Codable {
    let questionText: String
    let studentAnswer: String
    let correctAnswer: String
    let subject: String
    let questionId: String?
}

struct ErrorAnalysisResponse: Codable {
    // NEW: Hierarchical taxonomy fields
    let base_branch: String?           // "Algebra - Foundations"
    let detailed_branch: String?       // "Linear Equations - One Variable"
    let specific_issue: String?        // AI-generated issue description

    // Updated: Error type (now 3 values instead of 9)
    let error_type: String?            // "execution_error" | "conceptual_gap" | "needs_refinement"

    // Existing fields (unchanged)
    let evidence: String?
    let learning_suggestion: String?
    let confidence: Double
    let analysis_failed: Bool
}

// MARK: - Concept Extraction Models (Bidirectional Status Tracking)

/// Request for lightweight concept extraction (CORRECT answers only)
/// Much simpler than error analysis - only needs question text and subject
struct ConceptExtractionRequest: Codable {
    let questionText: String
    let subject: String

    enum CodingKeys: String, CodingKey {
        case questionText = "question_text"
        case subject
    }
}

/// Response from concept extraction (ONLY taxonomy, no error analysis)
/// Used to reduce weakness values when students answer correctly
struct ConceptExtractionResponse: Codable {
    let subject: String
    let baseBranch: String?
    let detailedBranch: String?
    let extractionFailed: Bool

    enum CodingKeys: String, CodingKey {
        case subject
        case baseBranch = "base_branch"
        case detailedBranch = "detailed_branch"
        case extractionFailed = "extraction_failed"
    }
}
