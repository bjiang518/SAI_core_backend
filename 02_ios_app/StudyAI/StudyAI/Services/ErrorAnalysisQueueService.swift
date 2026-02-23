//
//  ErrorAnalysisQueueService.swift
//  StudyAI
//
//  Manages background error analysis for wrong answers
//  Implements Pass 2 of two-pass grading system
//

import Foundation
import Combine
import UIKit  // ✅ Required for UIImage operations

class ErrorAnalysisQueueService: ObservableObject {
    static let shared = ErrorAnalysisQueueService()

    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0.0

    private let localStorage = QuestionLocalStorage.shared
    private var analysisTask: Task<Void, Never>?

    // ✅ NEW: Queue to accumulate questions while analysis is running
    private var pendingQuestions: [[String: Any]] = []
    private let queueLock = NSLock()

    private init() {}

    // MARK: - Public API

    /// Queue error analysis for newly graded wrong questions
    /// Called immediately after Pass 1 grading completes
    /// ✅ ACCUMULATES questions if analysis is already running (prevents cancellation)
    func queueErrorAnalysisAfterGrading(sessionId: String, wrongQuestions: [[String: Any]]) {
        guard !wrongQuestions.isEmpty else {
            print("📊 [ErrorAnalysis] No wrong answers - skipping Pass 2")
            return
        }

        print("📊 [ErrorAnalysis] Received \(wrongQuestions.count) wrong answers for Pass 2")

        // ✅ FIXED: Filter by analysis status, not just existence in storage
        let analyzedQuestionIds = Set(getAnalyzedQuestionIds())
        print("📊 [ErrorAnalysis] Found \(analyzedQuestionIds.count) already-analyzed question IDs")

        let unanalyzedWrongQuestions = wrongQuestions.filter { question in
            guard let questionId = question["id"] as? String else {
                print("⚠️ [ErrorAnalysis] Question has no ID - skipping")
                return false
            }

            let isAnalyzed = analyzedQuestionIds.contains(questionId)
            if isAnalyzed {
                print("  ✓ [ErrorAnalysis] Question \(questionId.prefix(8))... already analyzed - SKIP")
                return false
            } else {
                print("  ✓ [ErrorAnalysis] Question \(questionId.prefix(8))... needs analysis - QUEUE")
                return true
            }
        }

        guard !unanalyzedWrongQuestions.isEmpty else {
            print("✅ [ErrorAnalysis] All wrong answers already analyzed - skipping Pass 2")
            return
        }

        print("📊 [ErrorAnalysis] Queuing Pass 2 for \(unanalyzedWrongQuestions.count) unanalyzed wrong answers (filtered from \(wrongQuestions.count) total)")

        // ✅ NEW: If analysis is already running, add to pending queue
        queueLock.lock()
        let currentlyAnalyzing = isAnalyzing
        if currentlyAnalyzing {
            print("⏳ [ErrorAnalysis] Analysis already running - adding \(unanalyzedWrongQuestions.count) questions to pending queue")
            pendingQuestions.append(contentsOf: unanalyzedWrongQuestions)
            queueLock.unlock()
            return
        }
        queueLock.unlock()

        // Start background analysis
        analysisTask = Task {
            await analyzeBatch(sessionId: sessionId, questions: unanalyzedWrongQuestions)

            // ✅ NEW: Process pending questions after completion
            await processPendingQuestions()
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
    /// ✅ FILTER: Skip questions that have already been ANALYZED (not just archived)
    func queueConceptExtractionForCorrectAnswers(sessionId: String, correctQuestions: [[String: Any]]) {
        guard !correctQuestions.isEmpty else {
            print("📊 [ConceptExtraction] No correct answers - skipping")
            return
        }

        print("📊 [ConceptExtraction] Received \(correctQuestions.count) correct answers for concept extraction")

        // ✅ FIXED: Filter by analysis status, not just existence in storage
        let analyzedQuestionIds = Set(getAnalyzedQuestionIds())
        print("📊 [ConceptExtraction] Found \(analyzedQuestionIds.count) already-analyzed question IDs")

        let unanalyzedCorrectQuestions = correctQuestions.filter { question in
            guard let questionId = question["id"] as? String else {
                print("⚠️ [ConceptExtraction] Question has no ID - skipping")
                return false
            }

            let isAnalyzed = analyzedQuestionIds.contains(questionId)
            if isAnalyzed {
                print("  ✓ [ConceptExtraction] Question \(questionId.prefix(8))... already analyzed - SKIP")
                return false
            } else {
                print("  ✓ [ConceptExtraction] Question \(questionId.prefix(8))... needs analysis - QUEUE")
                return true
            }
        }

        guard !unanalyzedCorrectQuestions.isEmpty else {
            print("✅ [ConceptExtraction] All correct answers already analyzed - skipping concept extraction")
            return
        }

        print("📊 [ConceptExtraction] Queuing concept extraction for \(unanalyzedCorrectQuestions.count) unanalyzed correct answers (filtered from \(correctQuestions.count) total)")

        Task {
            await extractConceptsBatch(sessionId: sessionId, questions: unanalyzedCorrectQuestions)
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

                    // ✅ Normalize subject (AI may return "Mathematics", iOS uses "Math")
                    // ✅ EXCEPT for "Others: XX" - preserve full string for specificity
                    let normalizedSubject: String
                    if concept.subject.hasPrefix("Others:") {
                        // Keep "Others: French", "Others: Economics" as-is
                        normalizedSubject = concept.subject
                    } else {
                        // Normalize standard subjects: "Mathematics" → "Math"
                        normalizedSubject = Subject.normalizeWithFallback(concept.subject).rawValue
                    }

                    // Build weakness key: "Subject/Base Branch/Detailed Branch"
                    let weaknessKey = "\(normalizedSubject)/\(baseBranch)/\(detailedBranch)"
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

    /// Process pending questions that accumulated during analysis
    private func processPendingQuestions() async {
        queueLock.lock()
        guard !pendingQuestions.isEmpty else {
            queueLock.unlock()
            return
        }

        let questionsToProcess = pendingQuestions
        pendingQuestions = []  // Clear the queue
        queueLock.unlock()

        print("📊 [ErrorAnalysis] Processing \(questionsToProcess.count) pending questions from queue")

        // Process the accumulated questions
        await analyzeBatch(sessionId: "queued-batch", questions: questionsToProcess)

        // Recursively check for more pending questions (in case more were added during this batch)
        await processPendingQuestions()
    }

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

                // ✅ NEW: Extract and encode image if present
                let questionImageBase64: String? = {
                    guard let imageUrl = question["questionImageUrl"] as? String,
                          !imageUrl.isEmpty else {
                        return nil
                    }

                    // Load image from file system
                    if let image = ProModeImageStorage.shared.loadImage(from: imageUrl),
                       let jpegData = image.jpegData(compressionQuality: 0.85) {
                        print("   📸 [ErrorAnalysis] Including image for Q: '\(questionText.prefix(30))...'")
                        return jpegData.base64EncodedString()
                    }

                    return nil
                }()

                print("📝 [ErrorAnalysis] Building request for Q: '\(questionText.prefix(50))...'")
                print("   Student: '\(studentAnswer.prefix(30))...', Correct: '\(correctAnswer.prefix(30))...'")
                if questionImageBase64 != nil {
                    print("   📸 Image: YES (base64 encoded)")
                } else {
                    print("   📸 Image: NO")
                }

                return ErrorAnalysisRequest(
                    questionText: questionText,
                    studentAnswer: studentAnswer,
                    correctAnswer: correctAnswer,
                    subject: subject,
                    questionId: questionId,
                    questionImageBase64: questionImageBase64,
                    language: UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
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

            let subject = allQuestions[index]["subject"] as? String ?? "Math"

            // ✅ Normalize subject (AI may return "Mathematics", iOS uses "Math")
            // ✅ EXCEPT for "Others: XX" - preserve full string for specificity
            let normalizedSubject: String
            if subject.hasPrefix("Others:") {
                // Keep "Others: French", "Others: Economics" as-is
                normalizedSubject = subject
            } else {
                // Normalize standard subjects: "Mathematics" → "Math"
                normalizedSubject = Subject.normalizeWithFallback(subject).rawValue
            }

            // NEW format: "Math/Algebra - Foundations/Linear Equations - One Variable"
            let weaknessKey = "\(normalizedSubject)/\(baseBranch)/\(detailedBranch)"

            allQuestions[index]["weaknessKey"] = weaknessKey
            print("   🔑 [WeaknessTracking] Generated weakness key: \(weaknessKey)")
        } else {
            print("   ⚠️ [WeaknessTracking] Could NOT generate weakness key:")
            print("      base_branch: \(analysis.base_branch ?? "nil")")
            print("      detailed_branch: \(analysis.detailed_branch ?? "nil")")
        }

        // Patch fields back using updateQuestion (bypasses dedup — this is an update, not a new insert)
        var updatedFields: [String: Any] = [
            "baseBranch": analysis.base_branch ?? "",
            "detailedBranch": analysis.detailed_branch ?? "",
            "specificIssue": analysis.specific_issue ?? "",
            "errorType": analysis.error_type ?? "",
            "errorEvidence": analysis.evidence ?? "",
            "learningSuggestion": analysis.learning_suggestion ?? "",
            "errorConfidence": analysis.confidence as Any,
            "errorAnalysisStatus": (analysis.analysis_failed ? ErrorAnalysisStatus.failed : .completed).rawValue,
            "errorAnalyzedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let wk = allQuestions[index]["weaknessKey"] as? String {
            updatedFields["weaknessKey"] = wk
        }
        localStorage.updateQuestion(id: questionId, fields: updatedFields)

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
        for questionId in questionIds {
            localStorage.updateQuestion(id: questionId, fields: ["errorAnalysisStatus": status])
        }
    }

    /// Get question IDs that have already been analyzed (status = "completed" or "processing")
    /// Used to prevent duplicate error analysis for the same question
    private func getAnalyzedQuestionIds() -> [String] {
        let allQuestions = localStorage.getLocalQuestions()
        return allQuestions.compactMap { question in
            guard let questionId = question["id"] as? String else {
                return nil
            }

            // Check if question has already been analyzed
            let status = question["errorAnalysisStatus"] as? String ?? ""
            if status == "completed" || status == "processing" {
                return questionId  // Already analyzed or being analyzed
            }

            return nil  // Needs analysis (status is nil, "", or "failed")
        }
    }

    // MARK: - Correct Answer Processing
    // NOTE: Correct answer processing is now handled by queueConceptExtractionForCorrectAnswers()
    // which uses the new hierarchical taxonomy (baseBranch/detailedBranch) instead of the old
    // single-concept approach. The old processCorrectAnswer() method has been removed.
}

// MARK: - Models

struct ErrorAnalysisRequest: Codable {
    let questionText: String
    let studentAnswer: String
    let correctAnswer: String
    let subject: String
    let questionId: String?
    let questionImageBase64: String?
    let language: String
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
