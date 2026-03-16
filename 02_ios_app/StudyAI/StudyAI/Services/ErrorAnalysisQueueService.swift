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

    private let queueLock = NSLock()
    private var analysisTask: Task<Void, Never>?

    // ✅ Queue to accumulate questions while analysis is running
    private var pendingQuestions: [[String: Any]] = []

    // ✅ FIX: Computed property instead of stored let so we always resolve to the
    // current user's singleton instance at call time, not the userId at init time
    // (which could be "anonymous" if the service was first accessed before login).
    private var localStorage: QuestionLocalStorage { currentUserQuestionStorage() }

    private init() {}

    // MARK: - Public API

    /// Queue error analysis for newly graded wrong questions
    /// Called immediately after Pass 1 grading completes
    /// ✅ ACCUMULATES questions if analysis is already running (prevents cancellation)
    func queueErrorAnalysisAfterGrading(sessionId: String, wrongQuestions: [[String: Any]]) {
        guard !wrongQuestions.isEmpty else {
            debugPrint("📊 [ErrorAnalysis] No wrong answers - skipping Pass 2")
            return
        }

        // Guest users have 0 error_analysis quota — skip entirely without a network round-trip
        if AuthenticationService.shared.currentUser?.isAnonymous == true {
            debugPrint("📊 [ErrorAnalysis] Guest account — error analysis not available, skipping")
            return
        }

        // Opportunistically retry any permanently-failed analyses from previous sessions.
        // Runs in background — does not block the current batch or create a lock conflict.
        Task {
            await retryFailedAnalyses()
        }

        debugPrint("📊 [ErrorAnalysis] Received \(wrongQuestions.count) wrong answers for Pass 2")
        debugPrint("🔬 [EA-DBG] ── queueErrorAnalysisAfterGrading entry ──")
        for (i, q) in wrongQuestions.enumerated() {
            let qid = (q["id"] as? String) ?? "NO-ID"
            let qt  = (q["questionText"] as? String) ?? ""
            let sa  = (q["studentAnswer"] as? String) ?? ""
            let sub = (q["subject"] as? String) ?? ""
            let preBase = (q["baseBranch"] as? String) ?? ""
            let preKey  = (q["weaknessKey"] as? String) ?? ""
            debugPrint("🔬 [EA-DBG]   [\(i)] id=\(qid.prefix(12)) sub=\(sub) baseBranch='\(preBase.prefix(20))' wk='\(preKey.prefix(30))'")
            debugPrint("🔬 [EA-DBG]       q='\(qt.prefix(40))' sa='\(sa.prefix(30))'")
        }

        // Always route all wrong questions through the analysis pipeline.
        // Deduplication of displayed mistakes is handled in getMistakeQuestions().
        let unanalyzedWrongQuestions = wrongQuestions.filter { question in
            guard question["id"] as? String != nil else {
                debugPrint("⚠️ [ErrorAnalysis] Question has no ID - skipping")
                return false
            }
            return true
        }

        guard !unanalyzedWrongQuestions.isEmpty else {
            debugPrint("✅ [ErrorAnalysis] No valid wrong answers to analyze")
            return
        }

        debugPrint("📊 [ErrorAnalysis] Queuing Pass 2 for \(unanalyzedWrongQuestions.count) wrong answers")

        // ✅ SPLIT: questions that already have Gemini-pre-filled error keys (from mistake-based
        // question generation) vs. questions that need backend AI analysis (random/archive context).
        // Pre-filled keys must NOT be overwritten by a second analysis pass.
        let questionsWithPrefilledKeys = unanalyzedWrongQuestions.filter { q in
            let base     = q["baseBranch"]     as? String ?? ""
            let detailed = q["detailedBranch"] as? String ?? ""
            let errType  = q["errorType"]      as? String ?? ""
            return !base.isEmpty && !detailed.isEmpty && !errType.isEmpty
        }
        let questionsNeedingAnalysis = unanalyzedWrongQuestions.filter { q in
            let base     = q["baseBranch"]     as? String ?? ""
            let detailed = q["detailedBranch"] as? String ?? ""
            let errType  = q["errorType"]      as? String ?? ""
            return base.isEmpty || detailed.isEmpty || errType.isEmpty
        }

        // For questions with pre-filled keys: record mistake immediately for instant active status,
        // but also write taxonomy fields to local storage so updateLocalQuestionWithAnalysis
        // preserves them. Do NOT mark as completed yet — backend will do that after populating
        // errorEvidence and learningSuggestion.
        if !questionsWithPrefilledKeys.isEmpty {
            debugPrint("📊 [ErrorAnalysis] \(questionsWithPrefilledKeys.count) questions have pre-filled error keys — recording mistakes immediately, then routing to backend for narratives")
            Task {
                for q in questionsWithPrefilledKeys {
                    guard let questionId  = q["id"]          as? String,
                          let weaknessKey = q["weaknessKey"] as? String,
                          let errorType   = q["errorType"]   as? String,
                          !weaknessKey.isEmpty else {
                        debugPrint("⚠️ [ErrorAnalysis] Pre-keyed question missing id/weaknessKey/errorType — skipping")
                        continue
                    }
                    // Write taxonomy to local storage (status stays pending so backend fills narratives)
                    var fields: [String: Any] = ["errorType": errorType]
                    if let baseBranch = q["baseBranch"] as? String { fields["baseBranch"] = baseBranch }
                    if let detailedBranch = q["detailedBranch"] as? String { fields["detailedBranch"] = detailedBranch }
                    // Store weaknessKey using canonical format (resolved by ShortTermStatusService)
                    await MainActor.run {
                        ShortTermStatusService.shared.recordMistake(
                            key: weaknessKey,
                            errorType: errorType,
                            questionId: questionId
                        )
                        let canonicalKey = ShortTermStatusService.shared.resolveWeaknessKey(weaknessKey)
                        fields["weaknessKey"] = canonicalKey
                    }
                    localStorage.updateQuestion(id: questionId, fields: fields)
                    debugPrint("✅ [ErrorAnalysis] Recorded mistake for pre-keyed Q \(questionId.prefix(8))… key=\(weaknessKey)")
                }
            }
        }

        // Send ALL unanalyzed questions (pre-filled + needs-analysis) to backend.
        // updateLocalQuestionWithAnalysis will preserve existing taxonomy for pre-filled ones
        // and only update errorEvidence / learningSuggestion.
        let allForBackend = questionsWithPrefilledKeys + questionsNeedingAnalysis
        guard !allForBackend.isEmpty else {
            debugPrint("📊 [ErrorAnalysis] No questions need backend analysis — done")
            return
        }

        // ✅ NEW: If analysis is already running, add to pending queue
        queueLock.lock()
        let currentlyAnalyzing = isAnalyzing
        if currentlyAnalyzing {
            debugPrint("⏳ [ErrorAnalysis] Analysis already running - adding \(allForBackend.count) questions to pending queue")
            pendingQuestions.append(contentsOf: allForBackend)
            queueLock.unlock()
            return
        }
        queueLock.unlock()

        // Start background analysis
        analysisTask = Task {
            await analyzeBatch(sessionId: sessionId, questions: allForBackend)

            // ✅ NEW: Process pending questions after completion
            await processPendingQuestions()
        }
    }

    /// Force-categorize a specific set of questions immediately, awaiting the result.
    /// Called by the "Categorize Mistakes" button in MistakeReviewView.
    /// Bypasses the dedup filter — questions are always re-analyzed even if previously stuck.
    func categorizeQuestions(_ questions: [[String: Any]]) async {
        guard !questions.isEmpty else { return }
        // Strip any status that would confuse the patch-back logic, then analyze
        await analyzeBatch(sessionId: "ui-categorize", questions: questions)
    }

    /// Re-analyze failed questions
    func retryFailedAnalyses() async {
        let failedQuestions = localStorage.getLocalQuestions().filter {
            ($0["errorAnalysisStatus"] as? String) == "failed"
        }

        guard !failedQuestions.isEmpty else {
            debugPrint("📊 [ErrorAnalysis] No failed analyses to retry")
            return
        }

        debugPrint("📊 [ErrorAnalysis] Retrying \(failedQuestions.count) failed analyses")
        await analyzeBatch(sessionId: "retry", questions: failedQuestions)
    }

    // MARK: - Concept Extraction (Bidirectional Status Tracking)

    /// Extract concepts for CORRECT answers to reduce weakness values
    /// Called immediately after grading for correct answers
    /// ✅ FILTER: Skip questions that have already been ANALYZED (not just archived)
    func queueConceptExtractionForCorrectAnswers(sessionId: String, correctQuestions: [[String: Any]]) {
        guard !correctQuestions.isEmpty else {
            debugPrint("📊 [ConceptExtraction] No correct answers - skipping")
            return
        }

        debugPrint("📊 [ConceptExtraction] Received \(correctQuestions.count) correct answers for concept extraction")

        // ✅ FIXED: Filter by analysis status, not just existence in storage
        let analyzedQuestionIds = Set(getAnalyzedQuestionIds())
        debugPrint("📊 [ConceptExtraction] Found \(analyzedQuestionIds.count) already-analyzed question IDs")

        let unanalyzedCorrectQuestions = correctQuestions.filter { question in
            guard let questionId = question["id"] as? String else {
                debugPrint("⚠️ [ConceptExtraction] Question has no ID - skipping")
                return false
            }

            let isAnalyzed = analyzedQuestionIds.contains(questionId)
            if isAnalyzed {
                debugPrint("  ✓ [ConceptExtraction] Question \(questionId.prefix(8))... already analyzed - SKIP")
                return false
            } else {
                debugPrint("  ✓ [ConceptExtraction] Question \(questionId.prefix(8))... needs analysis - QUEUE")
                return true
            }
        }

        guard !unanalyzedCorrectQuestions.isEmpty else {
            debugPrint("✅ [ConceptExtraction] All correct answers already analyzed - skipping concept extraction")
            return
        }

        debugPrint("📊 [ConceptExtraction] Queuing concept extraction for \(unanalyzedCorrectQuestions.count) unanalyzed correct answers (filtered from \(correctQuestions.count) total)")

        // ✅ FAST PATH: questions that already carry a weaknessKey (e.g. from weakness-based
        // practice) skip backend AI extraction entirely. The key is already known, so we record
        // the correct attempt directly with an explicit-practice bonus.
        let preKeyedCorrect = unanalyzedCorrectQuestions.filter {
            !($0["weaknessKey"] as? String ?? "").isEmpty
        }
        let unknownKeyCorrect = unanalyzedCorrectQuestions.filter {
            ($0["weaknessKey"] as? String ?? "").isEmpty
        }

        if !preKeyedCorrect.isEmpty {
            debugPrint("📊 [ConceptExtraction] \(preKeyedCorrect.count) questions have pre-filled weakness key — recording correct attempts directly (no backend call)")
            Task {
                for q in preKeyedCorrect {
                    guard let weaknessKey = q["weaknessKey"] as? String, !weaknessKey.isEmpty else { continue }
                    let questionId = q["id"] as? String
                    debugPrint("✅ [WeaknessTracking] Fast-path correct: key='\(weaknessKey)' qid=\(questionId?.prefix(8) ?? "?")")
                    await MainActor.run {
                        ShortTermStatusService.shared.recordCorrectAttempt(
                            key: weaknessKey,
                            retryType: .explicitPractice,
                            questionId: questionId
                        )
                    }
                    // Mark as analyzed so this question isn't reprocessed
                    if let qId = questionId {
                        localStorage.updateQuestion(id: qId, fields: [
                            "errorAnalysisStatus": ErrorAnalysisStatus.completed.rawValue,
                            "errorAnalyzedAt": ISO8601DateFormatter().string(from: Date())
                        ])
                    }
                }
            }
        }

        guard !unknownKeyCorrect.isEmpty else {
            debugPrint("📊 [ConceptExtraction] No questions need backend extraction — done")
            return
        }

        debugPrint("📊 [ConceptExtraction] \(unknownKeyCorrect.count) questions need backend concept extraction")
        Task {
            await extractConceptsBatch(sessionId: sessionId, questions: unknownKeyCorrect)
        }
    }

    /// Extract concepts for a batch of correct questions
    private func extractConceptsBatch(sessionId: String, questions: [[String: Any]]) async {
        debugPrint("📊 [ConceptExtraction] Starting batch extraction for \(questions.count) questions")

        // Build extraction requests
        let extractionRequests = questions.compactMap { question -> ConceptExtractionRequest? in
            let questionText = question["questionText"] as? String ?? ""
            let subject = question["subject"] as? String ?? "Mathematics"

            debugPrint("📝 [ConceptExtraction] Building request for Q: '\(questionText.prefix(50))...'")

            return ConceptExtractionRequest(
                questionText: questionText,
                subject: subject
            )
        }

        do {
            debugPrint("📤 [ConceptExtraction] Sending \(extractionRequests.count) requests to backend")

            let concepts = try await NetworkService.shared.extractConceptsBatch(
                questions: extractionRequests
            )

            debugPrint("📥 [ConceptExtraction] Received \(concepts.count) concepts from backend")

            // Update ShortTermStatusService with negative values (mastery)
            for (index, concept) in concepts.enumerated() {
                guard index < questions.count else { continue }

                if let baseBranch = concept.baseBranch,
                   let detailedBranch = concept.detailedBranch,
                   !concept.extractionFailed {

                    // ✅ Normalize subject (AI may return "Mathematics", iOS uses "Math")
                    // ✅ EXCEPT for "Others: XX" - preserve full string for specificity
                    // ✅ Unknown subjects wrapped as "Others: X" rather than silently becoming "Math"
                    let normalizedSubject: String
                    if concept.subject.hasPrefix("Others:") {
                        // Keep "Others: French", "Others: Economics" as-is
                        normalizedSubject = concept.subject
                    } else if let known = Subject.normalize(concept.subject) {
                        // Known standard subject: normalize variant → canonical name
                        normalizedSubject = known.rawValue
                    } else {
                        // Unrecognized subject (e.g. "Science"): wrap as Others to avoid Math mislabel
                        normalizedSubject = "Others: \(concept.subject)"
                    }

                    // Build weakness key: "Subject/Base Branch/Detailed Branch"
                    let weaknessKey = "\(normalizedSubject)/\(baseBranch)/\(detailedBranch)"
                    let questionId = questions[index]["id"] as? String

                    debugPrint("✅ [ConceptExtraction] Correct answer detected:")
                    debugPrint("   Key: \(weaknessKey)")
                    debugPrint("   Reducing weakness value (mastery bonus)")

                    // ✅ BIDIRECTIONAL TRACKING: Correct answer reduces weakness
                    ShortTermStatusService.shared.recordCorrectAttempt(
                        key: weaknessKey,
                        retryType: .firstTime,
                        questionId: questionId
                    )
                } else {
                    debugPrint("⚠️ [ConceptExtraction] Extraction failed for question \(index)")
                }
            }

            debugPrint("✅ [ConceptExtraction] Completed extraction for \(concepts.count) questions")

            // Post notification for UI update
            NotificationCenter.default.post(
                name: NSNotification.Name("ConceptExtractionCompleted"),
                object: nil,
                userInfo: ["sessionId": sessionId, "count": concepts.count]
            )

        } catch {
            debugPrint("❌ [ConceptExtraction] Batch extraction failed: \(error)")
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

        debugPrint("📊 [ErrorAnalysis] Processing \(questionsToProcess.count) pending questions from queue")

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

        debugPrint("📊 [ErrorAnalysis] Starting batch analysis for \(questions.count) questions")
        debugPrint("🔬 [EA-DBG] ── analyzeBatch: IDs being sent to backend ──")
        for (i, q) in questions.enumerated() {
            let qid = (q["id"] as? String) ?? "NO-ID"
            let qt  = (q["questionText"] as? String) ?? ""
            let sa  = (q["studentAnswer"] as? String) ?? ""
            debugPrint("🔬 [EA-DBG]   [\(i)] id=\(qid.prefix(12)) q='\(qt.prefix(40))' sa='\(sa.prefix(30))'")
        }

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
                        debugPrint("   📸 [ErrorAnalysis] Including image for Q: '\(questionText.prefix(30))...'")
                        return jpegData.base64EncodedString()
                    }

                    return nil
                }()

                debugPrint("📝 [ErrorAnalysis] Building request for Q: '\(questionText.prefix(50))...'")
                debugPrint("   Student: '\(studentAnswer.prefix(30))...', Correct: '\(correctAnswer.prefix(30))...'")
                if questionImageBase64 != nil {
                    debugPrint("   📸 Image: YES (base64 encoded)")
                } else {
                    debugPrint("   📸 Image: NO")
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

            debugPrint("📤 [ErrorAnalysis] Sending \(analysisRequests.count) requests to backend")

            let analyses = try await NetworkService.shared.analyzeErrorsBatch(
                questions: analysisRequests
            )

            debugPrint("📥 [ErrorAnalysis] Received \(analyses.count) analyses from backend")
            debugPrint("🔬 [EA-DBG] ── analyzeBatch: backend response pairing ──")
            for (i, analysis) in analyses.enumerated() {
                let qid = (i < questions.count) ? ((questions[i]["id"] as? String) ?? "NO-ID") : "OUT-OF-RANGE"
                debugPrint("🔬 [EA-DBG]   [\(i)] qid=\(qid.prefix(12)) errType=\(analysis.error_type ?? "nil") base='\(analysis.base_branch ?? "nil")' detailed='\((analysis.detailed_branch ?? "nil").prefix(30))' failed=\(analysis.analysis_failed)")
            }

            // Update local storage with results
            for (index, analysis) in analyses.enumerated() {
                guard index < questions.count,
                      let questionId = questions[index]["id"] as? String else {
                    debugPrint("⚠️ [ErrorAnalysis] Skipping analysis \(index) - invalid question ID")
                    continue
                }

                debugPrint("📊 [ErrorAnalysis] Analysis \(index + 1)/\(analyses.count):")
                debugPrint("   Error Type: \(analysis.error_type ?? "none")")
                debugPrint("   Confidence: \(analysis.confidence)")
                debugPrint("   Failed: \(analysis.analysis_failed)")

                updateLocalQuestionWithAnalysis(
                    questionId: questionId,
                    analysis: analysis
                )

                // Update progress
                await MainActor.run {
                    analysisProgress = Double(index + 1) / Double(questions.count)
                }
            }

            debugPrint("✅ [ErrorAnalysis] Completed Pass 2 for \(analyses.count) questions")

            // Post notification for UI update
            NotificationCenter.default.post(
                name: NSNotification.Name("ErrorAnalysisCompleted"),
                object: nil,
                userInfo: ["sessionId": sessionId, "count": analyses.count]
            )

        } catch NetworkService.NetworkError.rateLimited {
            // Backend returned 403 (UPGRADE_REQUIRED) or 429 (MONTHLY_LIMIT_REACHED).
            // Leave questions in their current state — do NOT mark as "failed" or they
            // would be picked up by retryFailedAnalyses() on every subsequent grading call.
            debugPrint("⚠️ [ErrorAnalysis] Tier limit reached — questions left pending until quota renews or plan upgrades")

        } catch {
            debugPrint("❌ [ErrorAnalysis] Failed: \(error.localizedDescription)")
            debugPrint("❌ [ErrorAnalysis] Error type: \(type(of: error))")
            debugPrint("❌ [ErrorAnalysis] Full error: \(error)")

            // Mark all as failed
            updateLocalStatus(
                questionIds: questions.compactMap { $0["id"] as? String },
                status: "failed"
            )
        }
    }

    private func updateLocalQuestionWithAnalysis(questionId: String, analysis: ErrorAnalysisResponse) {
        var allQuestions = localStorage.getLocalQuestions()

        debugPrint("🔬 [EA-DBG] updateLocalQuestionWithAnalysis: searching for id=\(questionId.prefix(12)) in \(allQuestions.count) local questions")

        guard let index = allQuestions.firstIndex(where: { ($0["id"] as? String) == questionId }) else {
            debugPrint("⚠️ [ErrorAnalysis] Question \(questionId) not found in local storage")
            debugPrint("🔬 [EA-DBG] ── PATCH-BACK FAILED: id not found. First 5 local IDs:")
            for q in allQuestions.prefix(5) {
                debugPrint("🔬 [EA-DBG]   local id=\((q["id"] as? String ?? "nil").prefix(12))")
            }
            return
        }

        debugPrint("🔬 [EA-DBG] FOUND at index=\(index). Existing keys: base='\((allQuestions[index]["baseBranch"] as? String ?? "").prefix(20))' detailed='\((allQuestions[index]["detailedBranch"] as? String ?? "").prefix(20))' errType='\(allQuestions[index]["errorType"] as? String ?? "")'")

        // ✅ PRESERVE pre-existing error keys (set by Gemini at question-generation time for
        // mistake-based sessions). Only update taxonomy fields from backend analysis when the
        // stored question has NO prior classification.
        let existingBase     = allQuestions[index]["baseBranch"]     as? String ?? ""
        let existingDetailed = allQuestions[index]["detailedBranch"] as? String ?? ""
        let existingErrType  = allQuestions[index]["errorType"]      as? String ?? ""
        let existingWK       = allQuestions[index]["weaknessKey"]    as? String ?? ""
        let hasPrefilledKeys = !existingBase.isEmpty && !existingDetailed.isEmpty && !existingErrType.isEmpty

        if hasPrefilledKeys {
            // Preserve taxonomy; update status + narrative fields
            var updatedFields: [String: Any] = [
                "errorAnalysisStatus": ErrorAnalysisStatus.completed.rawValue,
                "errorAnalyzedAt": ISO8601DateFormatter().string(from: Date())
            ]
            if let suggestion = analysis.learning_suggestion, !suggestion.isEmpty {
                updatedFields["learningSuggestion"] = suggestion
            }
            if let evidence = analysis.evidence, !evidence.isEmpty {
                updatedFields["errorEvidence"] = evidence
            }
            // Normalise the stored weaknessKey to the canonical format so the active filter finds it
            if !existingWK.isEmpty {
                Task { @MainActor in
                    ShortTermStatusService.shared.recordMistake(
                        key: existingWK,
                        errorType: existingErrType,
                        questionId: questionId
                    )
                    let canonical = ShortTermStatusService.shared.resolveWeaknessKey(existingWK)
                    if canonical != existingWK {
                        self.localStorage.updateQuestion(id: questionId, fields: ["weaknessKey": canonical])
                    }
                }
            }
            localStorage.updateQuestion(id: questionId, fields: updatedFields)
            debugPrint("✅ [ErrorAnalysis] Preserved pre-filled keys for Q \(questionId.prefix(8))… — only updated narratives")
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

            let subject = allQuestions[index]["subject"] as? String ?? "Others: General"

            // ✅ Normalize subject (AI may return "Mathematics", iOS uses "Math")
            // ✅ EXCEPT for "Others: XX" - preserve full string for specificity
            // ✅ Unknown subjects wrapped as "Others: X" rather than silently becoming "Math"
            let normalizedSubject: String
            if subject.hasPrefix("Others:") {
                // Keep "Others: French", "Others: Economics" as-is
                normalizedSubject = subject
            } else if let known = Subject.normalize(subject) {
                // Known standard subject: normalize variant → canonical name
                normalizedSubject = known.rawValue
            } else {
                // Unrecognized subject (e.g. "Science"): wrap as Others to avoid Math mislabel
                normalizedSubject = "Others: \(subject)"
            }

            // NEW format: "Math/Algebra - Foundations/Linear Equations - One Variable"
            let weaknessKey = "\(normalizedSubject)/\(baseBranch)/\(detailedBranch)"

            allQuestions[index]["weaknessKey"] = weaknessKey
            debugPrint("   🔑 [WeaknessTracking] Generated weakness key: \(weaknessKey)")
        } else {
            debugPrint("   ⚠️ [WeaknessTracking] Could NOT generate weakness key:")
            debugPrint("      base_branch: \(analysis.base_branch ?? "nil")")
            debugPrint("      detailed_branch: \(analysis.detailed_branch ?? "nil")")
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
        debugPrint("🔬 [EA-DBG] PATCH-BACK id=\(questionId.prefix(12)): base='\((analysis.base_branch ?? "").prefix(20))' detailed='\((analysis.detailed_branch ?? "").prefix(20))' errType='\(analysis.error_type ?? "nil")' wk='\((updatedFields["weaknessKey"] as? String ?? "").prefix(30))'")
        localStorage.updateQuestion(id: questionId, fields: updatedFields)

        debugPrint("✅ [ErrorAnalysis] Updated question \(questionId): \(analysis.error_type ?? "unknown") (branch: \(analysis.detailed_branch ?? "N/A"))")

        // ✅ Update short-term status (use the weaknessKey we just saved)
        if let weaknessKey = allQuestions[index]["weaknessKey"] as? String,
           let errorType = analysis.error_type {

            debugPrint("   📊 [WeaknessTracking] Calling recordMistake for key: \(weaknessKey)")
            debugPrint("      Error type: \(errorType)")

            Task { @MainActor in
                ShortTermStatusService.shared.recordMistake(
                    key: weaknessKey,
                    errorType: errorType,
                    questionId: questionId
                )
            }
        } else {
            debugPrint("   ⚠️ [WeaknessTracking] Skipping recordMistake - no weaknessKey or errorType")
        }
    }

    private func updateLocalStatus(questionIds: [String], status: String) {
        for questionId in questionIds {
            localStorage.updateQuestion(id: questionId, fields: ["errorAnalysisStatus": status])
        }
    }

    /// Get question IDs that have already been analyzed AND classified.
    /// Only skips questions where status == "completed" AND baseBranch is non-empty.
    /// - "processing" questions are NOT skipped — they may be permanently stuck if the
    ///   app was killed mid-analysis. They will be re-queued and re-analyzed.
    /// - "failed" questions are NOT skipped — they will be retried on the next submission.
    /// - "completed" with empty baseBranch are NOT skipped — taxonomy write may have failed
    ///   silently, so re-analysis ensures the question gets classified.
    private func getAnalyzedQuestionIds() -> [String] {
        let allQuestions = localStorage.getLocalQuestions()
        return allQuestions.compactMap { question in
            guard let questionId = question["id"] as? String else {
                return nil
            }

            let status = question["errorAnalysisStatus"] as? String ?? ""
            let baseBranch = question["baseBranch"] as? String ?? ""
            // Only truly done when analysis completed AND taxonomy is present
            if status == "completed" && !baseBranch.isEmpty {
                return questionId
            }

            return nil
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
