//
//  WeaknessPracticeView.swift
//  StudyAI
//
//  "Do it again" practice view for weaknesses
//  Created by Claude Code on 1/25/25.
//

import SwiftUI
import Combine

struct WeaknessPracticeView: View {
    let weaknessKey: String
    let weaknessValue: WeaknessValue
    /// Non-nil only in retry mode — assigned to ViewModel in .task to avoid @StateObject re-init race.
    private let preloadedQuestions: [WeaknessPracticeQuestion]?

    @StateObject private var viewModel: WeaknessPracticeViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    @State private var practiceSession: PracticeSession? = nil

    init(weaknessKey: String, weaknessValue: WeaknessValue) {
        self.weaknessKey = weaknessKey
        self.weaknessValue = weaknessValue
        self.preloadedQuestions = nil
        self._viewModel = StateObject(wrappedValue: WeaknessPracticeViewModel(weaknessKey: weaknessKey))
    }

    /// Retry-mode init: re-attempt selected original mistakes directly, no AI generation.
    init(subject: String, preloadedQuestions: [WeaknessPracticeQuestion]) {
        self.weaknessKey = subject
        self.weaknessValue = WeaknessValue(value: 0, firstDetected: Date(), lastAttempt: Date(),
                                           totalAttempts: 0, correctAttempts: 0)
        self.preloadedQuestions = preloadedQuestions
        // ViewModel starts without preloaded questions — they are pushed in .task to survive
        // SwiftUI's @StateObject re-init (which ignores init parameters on re-renders).
        self._viewModel = StateObject(wrappedValue: WeaknessPracticeViewModel(weaknessKey: subject))
    }

    var body: some View {
        ZStack {
            themeManager.backgroundColor.ignoresSafeArea()

            if let session = practiceSession {
                // Hand off to the unified question sheet used by PracticeLibraryView
                QuestionSheetView(session: session)
            } else if let error = viewModel.error {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button(action: {
                        Task { await viewModel.loadPracticeQuestions() }
                    }) {
                        Text("Retry")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(themeManager.accentColor)
                            .cornerRadius(10)
                    }
                    Button("Done", action: { dismiss() })
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(viewModel.isGenerating
                         ? NSLocalizedString("weaknessPractice.generating", value: "Generating questions…", comment: "")
                         : NSLocalizedString("weaknessPractice.loading",    value: "Loading questions…",    comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .task {
            if let questions = preloadedQuestions {
                viewModel.loadPreloadedQuestions(questions)
            } else {
                await viewModel.loadPracticeQuestions()
            }
            buildSession()
        }
    }

    /// Convert loaded `WeaknessPracticeQuestion`s into a `PracticeSession` and persist it.
    private func buildSession() {
        guard !viewModel.questions.isEmpty else { return }
        let parts = weaknessKey.split(separator: "/")
        let subject = String(parts.first ?? Substring(weaknessKey))
        let topic   = parts.count >= 2 ? parts[1...].joined(separator: "/") : weaknessKey

        let generated = viewModel.questions.map { $0.toGeneratedQuestion(topic: topic) }
        let session = PracticeSession(
            id: UUID().uuidString,
            questions: generated,
            generationType: "Feynman-Based",
            subject: subject,
            difficulty: "adaptive",
            questionType: "any",
            createdDate: Date(),
            lastAccessedDate: Date(),
            completedQuestionIds: [],
            answers: [:],
            isOrganized: false
        )
        practiceSession = PracticeSessionManager.shared.saveSession(session)
    }
}

// MARK: - Weakness Practice ViewModel

@MainActor
class WeaknessPracticeViewModel: ObservableObject {
    let weaknessKey: String

    @Published var questions: [WeaknessPracticeQuestion] = []
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published var error: String?
    @Published var isRetryMode = false

    private let logger = AppLogger.forFeature("WeaknessPractice")

    init(weaknessKey: String) {
        self.weaknessKey = weaknessKey
    }

    /// Retry-mode init: skip local-storage loading, use preloaded questions directly.
    init(weaknessKey: String, preloadedQuestions: [WeaknessPracticeQuestion]) {
        self.weaknessKey = weaknessKey
        self.questions = preloadedQuestions
        self.isRetryMode = true
    }

    /// Called from the view's .task when in retry mode — guaranteed to run after @StateObject is live.
    func loadPreloadedQuestions(_ questions: [WeaknessPracticeQuestion]) {
        self.questions = questions
        self.isRetryMode = true
    }

    func loadPracticeQuestions() async {
        isLoading = true
        error = nil

        debugPrint("📚 [WeaknessPractice] Loading questions for weakness key: \(weaknessKey)")

        do {
            // Parse weakness key: "Math/algebra/calculation"
            let parts = weaknessKey.split(separator: "/")
            guard parts.count >= 2 else {
                throw PracticeError.invalidWeaknessKey
            }

            // ✅ Load original mistake questions from local storage
            let localStorage = currentUserQuestionStorage()
            let allQuestions = localStorage.getLocalQuestions()

            debugPrint("   📊 Total questions in storage: \(allQuestions.count)")

            // Filter for questions with matching weakness key
            let mistakeQuestions = allQuestions.filter { question in
                guard let questionWeaknessKey = question["weaknessKey"] as? String else {
                    return false
                }
                return questionWeaknessKey == weaknessKey
            }

            debugPrint("   🎯 Found \(mistakeQuestions.count) original mistake questions for '\(weaknessKey)'")
            #if DEBUG
            // Show IDs of all matching questions
            debugPrint("   📋 Question IDs with this weakness key:")
            for (idx, q) in mistakeQuestions.enumerated() {
                let qId = q["id"] as? String ?? "unknown"
                let hasRaw = q["rawQuestionText"] != nil
                let rawLength = (q["rawQuestionText"] as? String)?.count ?? 0
                debugPrint("      \(idx + 1). ID: \(qId), hasRawQuestionText: \(hasRaw), length: \(rawLength)")
            }
            #endif

            // Convert to WeaknessPracticeQuestion format
            var practiceQuestions: [WeaknessPracticeQuestion] = []

            for (index, questionData) in mistakeQuestions.enumerated() {
                guard let questionText = questionData["questionText"] as? String,
                      let correctAnswer = questionData["answerText"] as? String else {
                    debugPrint("   ⚠️ Skipping question \(index) - missing required fields")
                    continue
                }

                let questionType = questionData["questionType"] as? String ?? "open_ended"
                let options = questionData["options"] as? [String]
                let questionId = questionData["id"] as? String ?? UUID().uuidString
                let studentAnswer = questionData["studentAnswer"] as? String  // ✅ Original answer
                let questionImageUrl = questionData["questionImageUrl"] as? String  // ✅ Image

                #if DEBUG
                // Log what's in local storage BEFORE fallback
                let rawFromStorage = questionData["rawQuestionText"] as? String
                debugPrint("📦 [WeaknessPractice-Storage] Question \(index + 1) data from local storage:")
                debugPrint("   Question ID: \(questionId)")
                debugPrint("   weaknessKey: \(weaknessKey)")
                debugPrint("   questionText length: \(questionText.count)")
                debugPrint("   questionText: '\(questionText.prefix(100))'...")
                debugPrint("   rawQuestionText from storage: \(rawFromStorage != nil ? "EXISTS (\(rawFromStorage!.count) chars)" : "NIL/MISSING")")
                if let raw = rawFromStorage {
                    debugPrint("   rawQuestionText content: '\(raw.prefix(100))'...")
                    if raw.isEmpty {
                        debugPrint("   ⚠️ rawQuestionText is EMPTY STRING - will fallback to questionText")
                    }
                } else {
                    debugPrint("   ⚠️ rawQuestionText is NIL - will fallback to questionText")
                }
                debugPrint("   All keys in questionData: \(questionData.keys.sorted())")
                #endif

                // ✅ FIX: Add fallback to questionText if rawQuestionText is nil OR empty (same as MistakeReviewService)
                let rawQuestionTextFromStorage = questionData["rawQuestionText"] as? String
                let rawQuestionText = (rawQuestionTextFromStorage?.isEmpty == false) ? rawQuestionTextFromStorage! : questionText

                #if DEBUG
                // Only log image-related data
                if let imageUrl = questionImageUrl {
                    let fileExists = FileManager.default.fileExists(atPath: imageUrl)
                    debugPrint("🖼️ [WeaknessPractice] Question \(index + 1) - Image file exists: \(fileExists)")
                    if fileExists {
                        debugPrint("   📍 Image path: \(imageUrl)")
                    }
                }
                #endif

                let practiceQuestion = WeaknessPracticeQuestion(
                    id: UUID(uuidString: questionId) ?? UUID(),
                    questionText: questionText,
                    questionType: questionType,
                    options: options,
                    correctAnswer: correctAnswer,
                    isOriginalMistake: true,  // Mark as original
                    originalQuestionId: questionId,
                    studentAnswer: studentAnswer,  // ✅ Include student answer
                    questionImageUrl: questionImageUrl,  // ✅ Include image URL
                    rawQuestionText: rawQuestionText,  // ✅ Include raw text
                    weaknessKey: weaknessKey  // ✅ FIX: propagate so QuestionSheetView can record mastery
                )

                practiceQuestions.append(practiceQuestion)
            }

            questions = practiceQuestions

            #if DEBUG
            // Only log image-related info
            if !questions.isEmpty {
                debugPrint("   🖼️ [WeaknessPractice] Loaded \(questions.count) questions with images:")
                for (idx, q) in questions.enumerated() {
                    if let imageUrl = q.questionImageUrl, !imageUrl.isEmpty {
                        debugPrint("      Question \(idx + 1): has image at '\(imageUrl)'")
                    }
                }
            }
            #endif

            logger.info("Loaded \(questions.count) original mistake questions for '\(weaknessKey)'")

        } catch {
            self.error = error.localizedDescription
            logger.error("Failed to load practice questions: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Practice Question Models

struct WeaknessPracticeQuestion: Identifiable {
    let id: UUID
    let questionText: String
    let questionType: String
    let options: [String]?
    let correctAnswer: String
    var isOriginalMistake: Bool = false  // True if this is an original mistake question
    var originalQuestionId: String? = nil  // ID of the original question in storage
    var studentAnswer: String? = nil  // Original student answer (for mistakes)
    var questionImageUrl: String? = nil  // Image URL if present
    var rawQuestionText: String? = nil  // Full raw question text
    var weaknessKey: String? = nil  // Per-question weakness key for retry mode

    /// Convert to the unified `GeneratedQuestion` type so it can be placed in a `PracticeSession`
    /// and displayed by `QuestionSheetView`.
    func toGeneratedQuestion(topic: String) -> QuestionGenerationService.GeneratedQuestion {
        let qType: QuestionGenerationService.GeneratedQuestion.QuestionType
        switch questionType.lowercased() {
        case "multiple_choice": qType = .multipleChoice
        case "true_false":      qType = .trueFalse
        case "fill_blank":      qType = .fillBlank
        case "short_answer":    qType = .shortAnswer
        case "long_answer":     qType = .longAnswer
        default:                qType = .shortAnswer
        }
        return QuestionGenerationService.GeneratedQuestion(
            id: id,
            question: questionText,
            type: qType,
            correctAnswer: correctAnswer,
            explanation: "",
            topic: topic,
            difficulty: "adaptive",
            options: options,
            weaknessKey: weaknessKey
        )
    }

    // ✅ Convert to ParsedQuestion for use with question rendering system
    // ⚠️ IMPORTANT: Do NOT include studentAnswer or correctAnswer - we only want to show the raw question
    func toParsedQuestion() -> ParsedQuestion? {
        // Use rawQuestionText if available, otherwise use questionText
        let displayText = rawQuestionText ?? questionText

        return ParsedQuestion(
            questionNumber: nil,
            rawQuestionText: rawQuestionText,
            questionText: displayText,
            answerText: "",  // ❌ Empty string - don't show correct answer
            confidence: nil,
            hasVisualElements: questionImageUrl != nil,
            studentAnswer: nil,  // ❌ Don't show student's original answer
            correctAnswer: nil,  // ❌ Don't show correct answer
            grade: nil,  // ❌ Don't show grade
            pointsEarned: nil,
            pointsPossible: nil,
            feedback: nil,
            questionType: questionType,
            options: options,
            isParent: nil,
            hasSubquestions: nil,
            parentContent: nil,
            subquestions: nil,
            subquestionNumber: nil,
            parentSummary: nil
        )
    }
}

enum PracticeError: LocalizedError {
    case invalidWeaknessKey
    case weaknessNotFound
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .invalidWeaknessKey: return "Invalid weakness key format"
        case .weaknessNotFound: return "Weakness not found in active weaknesses"
        case .generationFailed: return "Failed to generate practice questions"
        }
    }
}
