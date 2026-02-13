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

    @StateObject private var viewModel: WeaknessPracticeViewModel
    @Environment(\.dismiss) private var dismiss

    init(weaknessKey: String, weaknessValue: WeaknessValue) {
        self.weaknessKey = weaknessKey
        self.weaknessValue = weaknessValue
        self._viewModel = StateObject(wrappedValue: WeaknessPracticeViewModel(weaknessKey: weaknessKey))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Practice questions
                    if viewModel.isLoading {
                        ProgressView("Loading practice questions...")
                            .padding()
                    } else if let error = viewModel.error {
                        WeaknessPracticeErrorView(message: error, onRetry: {
                            Task { await viewModel.loadPracticeQuestions() }
                        })
                    } else if viewModel.questions.isEmpty {
                        Text("No questions available")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(viewModel.questions.enumerated()), id: \.offset) { index, question in
                            WeaknessPracticeQuestionCard(
                                question: question,
                                questionNumber: index + 1,
                                weaknessKey: weaknessKey
                            )
                        }

                        // ✅ "Generate More" button with loading state
                        if !viewModel.questions.isEmpty {
                            Button {
                                Task {
                                    await viewModel.generateMoreQuestions()
                                }
                            } label: {
                                HStack {
                                    if viewModel.isGenerating {
                                        ProgressView()
                                            .tint(.blue)
                                        Text("Generating...")
                                            .font(.headline)
                                    } else {
                                        Label("Generate More Questions", systemImage: "plus.circle.fill")
                                            .font(.headline)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(viewModel.isGenerating ? Color.gray.opacity(0.1) : Color.blue.opacity(0.1))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isGenerating)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            // ✅ DEBUG: Print short-term status for debugging bidirectional tracking
            printShortTermStatusDebugInfo()

            await viewModel.loadPracticeQuestions()
        }
    }

    /// DEBUG: Print comprehensive short-term status for bidirectional tracking verification
    private func printShortTermStatusDebugInfo() {
        let statusService = ShortTermStatusService.shared
        let status = statusService.status

        print("\n" + String(repeating: "=", count: 80))
        print("🔍 SHORT-TERM STATUS DEBUG INFO (Bidirectional Tracking)")
        print(String(repeating: "=", count: 80))

        // Overall statistics
        let totalKeys = status.activeWeaknesses.count
        let weaknessKeys = status.activeWeaknesses.filter { $0.value.value > 0 }
        let masteryKeys = status.activeWeaknesses.filter { $0.value.value < 0 }
        let neutralKeys = status.activeWeaknesses.filter { $0.value.value == 0 }

        print("📊 OVERALL STATISTICS:")
        print("   Total Keys: \(totalKeys)")
        print("   Weaknesses (value > 0): \(weaknessKeys.count)")
        print("   Mastery (value < 0): \(masteryKeys.count)")
        print("   Neutral (value = 0): \(neutralKeys.count)")

        // Group by subject
        var keysBySubject: [String: [(key: String, weakness: WeaknessValue)]] = [:]
        for (key, weakness) in status.activeWeaknesses {
            let components = key.split(separator: "/").map(String.init)
            guard let subject = components.first else { continue }
            keysBySubject[subject, default: []].append((key, weakness))
        }

        // Print subject-by-subject breakdown
        for (subject, keys) in keysBySubject.sorted(by: { $0.key < $1.key }) {
            print("\n" + String(repeating: "-", count: 80))
            print("📚 SUBJECT: \(subject) (\(keys.count) keys)")
            print(String(repeating: "-", count: 80))

            // Sort by value (most negative first, then most positive)
            let sortedKeys = keys.sorted { $0.weakness.value < $1.weakness.value }

            for (key, weakness) in sortedKeys {
                let statusEmoji = weakness.value > 0 ? "⚠️" : (weakness.value < 0 ? "✅" : "➖")
                let statusLabel = weakness.value > 0 ? "WEAKNESS" : (weakness.value < 0 ? "MASTERY" : "NEUTRAL")

                print("\n\(statusEmoji) [\(statusLabel)] Key: \(key)")
                print("   Value: \(String(format: "%.2f", weakness.value)) (Attempts: \(weakness.totalAttempts), Correct: \(weakness.correctAttempts))")
                print("   First Detected: \(formatDate(weakness.firstDetected))")
                print("   Last Attempt: \(formatDate(weakness.lastAttempt))")

                // Conditional tracking data
                if weakness.value > 0 {
                    // Weakness tracking
                    if !weakness.recentErrorTypes.isEmpty {
                        print("   Error Types: \(weakness.recentErrorTypes.joined(separator: ", "))")
                    }
                    if !weakness.recentQuestionIds.isEmpty {
                        print("   Recent Questions: \(weakness.recentQuestionIds.prefix(3).joined(separator: ", "))...")
                    }
                } else if weakness.value < 0 {
                    // Mastery tracking
                    if !weakness.masteryQuestions.isEmpty {
                        print("   Mastery Questions: \(weakness.masteryQuestions.prefix(3).joined(separator: ", "))...")
                    }
                }
            }
        }

        print("\n" + String(repeating: "=", count: 80))
        print("🔍 END OF SHORT-TERM STATUS DEBUG INFO")
        print(String(repeating: "=", count: 80) + "\n")
    }

    /// Helper: Format date for debug output
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Error View

struct WeaknessPracticeErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Error Loading Questions")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                onRetry()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Practice Question Card (Using Question Rendering System)

struct WeaknessPracticeQuestionCard: View {
    let question: WeaknessPracticeQuestion
    let questionNumber: Int
    let weaknessKey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Question number header
            Text("Original Mistake #\(questionNumber)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange)
                .cornerRadius(8)

            // ✅ RAW QUESTION Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                    Text("Raw Question")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                }

                // ✅ Use shared SubquestionAwareTextView for consistent rendering
                SubquestionAwareTextView(
                    text: question.rawQuestionText ?? question.questionText,
                    fontSize: 16
                )

                // ✅ Display question image if available
                #if DEBUG
                let _ = print("🔍 [WeaknessPractice-Render] Evaluating image conditional for Q\(questionNumber)")
                let _ = print("   question.questionImageUrl = '\(question.questionImageUrl ?? "nil")'")
                let _ = print("   isEmpty check = \(question.questionImageUrl?.isEmpty ?? true)")
                #endif

                if let imageUrl = question.questionImageUrl, !imageUrl.isEmpty {
                    #if DEBUG
                    let _ = print("✅ [WeaknessPractice-Render] IF branch - imageUrl has value: '\(imageUrl)'")
                    #endif

                    QuestionImageView(imageUrl: imageUrl)
                        .onAppear {
                            #if DEBUG
                            print("🖼️ [WeaknessPractice-Render] QuestionImageView.onAppear - imageUrl: '\(imageUrl)'")
                            #endif
                        }
                } else {
                    // No image for this question - render nothing
                    EmptyView()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.05))
            )

            // ✅ ANSWER SUBMISSION Section
            WeaknessPracticeAnswerInput(
                question: question,
                questionNumber: questionNumber,
                weaknessKey: weaknessKey,
                onAnswerSubmitted: { /* Handle answer submission */ }
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Input Components

struct MultipleChoiceInput: View {
    let options: [String]
    @Binding var selectedOption: String

    var body: some View {
        VStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    selectedOption = option
                } label: {
                    HStack {
                        Image(systemName: selectedOption == option ? "circle.fill" : "circle")
                        Text(option)
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedOption == option ? Color.blue.opacity(0.1) : Color(.systemGray6))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct TrueFalseInput: View {
    @Binding var selectedOption: String

    var body: some View {
        HStack(spacing: 16) {
            Button {
                selectedOption = "True"
            } label: {
                HStack {
                    Image(systemName: selectedOption == "True" ? "circle.fill" : "circle")
                    Text("True")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedOption == "True" ? Color.green.opacity(0.1) : Color(.systemGray6))
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedOption = "False"
            } label: {
                HStack {
                    Image(systemName: selectedOption == "False" ? "circle.fill" : "circle")
                    Text("False")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedOption == "False" ? Color.red.opacity(0.1) : Color(.systemGray6))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

struct WeaknessPracticeResultView: View {
    let result: WeaknessPracticeQuestionResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: result.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(result.isCorrect ? .green : .red)

                Text(result.isCorrect ? "Correct!" : "Incorrect")
                    .font(.headline)
                    .foregroundColor(result.isCorrect ? .green : .red)
            }

            if !result.isCorrect {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Answer:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(result.userAnswer)
                        .font(.body)

                    Text("Correct Answer:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(result.correctAnswer)
                        .font(.body)
                        .foregroundColor(.green)
                }
            }

            Text(result.feedback)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(result.isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
    }
}

// MARK: - Answer Input and Grading

struct WeaknessPracticeAnswerInput: View {
    let question: WeaknessPracticeQuestion
    let questionNumber: Int
    let weaknessKey: String
    let onAnswerSubmitted: () -> Void

    @State private var studentAnswer = ""
    @State private var selectedOption = ""
    @State private var isSubmitting = false
    @State private var gradeResult: ProgressiveGradeResult?
    @State private var gradingError: String?

    private let networkService = NetworkService.shared
    private let logger = AppLogger.forFeature("WeaknessPractice")

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Answer input section - styled as a card
            if gradeResult == nil {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with icon
                    HStack(spacing: 6) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                            .foregroundColor(.blue)
                        Text("Your Answer")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.blue)
                    }

                    // Answer input based on question type
                    switch question.questionType.lowercased() {
                    case "multiple_choice":
                        if let options = question.options {
                            MultipleChoiceInput(options: options, selectedOption: $selectedOption)
                        } else {
                            TextEditor(text: $studentAnswer)
                                .frame(minHeight: 120)
                                .padding(12)
                                .background(Color.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                .onChange(of: studentAnswer) { oldValue, newValue in
                                    // ✅ Dismiss keyboard when whitespace is typed
                                    if newValue.last == " " && oldValue.count < newValue.count {
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    }
                                }
                        }

                    case "true_false":
                        TrueFalseInput(selectedOption: $selectedOption)

                    default:
                        // Text input for other types - white background with border
                        TextEditor(text: $studentAnswer)
                            .frame(minHeight: 120)
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .onChange(of: studentAnswer) { oldValue, newValue in
                                // ✅ Dismiss keyboard when whitespace is typed
                                if newValue.last == " " && oldValue.count < newValue.count {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }
                            }
                    }

                    // Submit button only
                    Button {
                        Task {
                            await submitAnswer()
                        }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(height: 20)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Submit Answer")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isSubmitDisabled ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isSubmitDisabled)

                    // Error display
                    if let error = gradingError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                )
            } else {
                // Show grading result
                WeaknessPracticeResultView(
                    result: WeaknessPracticeQuestionResult(
                        isCorrect: gradeResult!.isCorrect,
                        userAnswer: currentAnswer,
                        correctAnswer: gradeResult!.correctAnswer ?? "",
                        feedback: gradeResult!.feedback
                    )
                )

                // Try Again button
                Button {
                    resetAnswer()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            }
        }
    }

    private var currentAnswer: String {
        if question.questionType.lowercased() == "multiple_choice" ||
           question.questionType.lowercased() == "true_false" {
            return selectedOption
        }
        return studentAnswer
    }

    private var isSubmitDisabled: Bool {
        if isSubmitting {
            return true
        }

        if question.questionType.lowercased() == "multiple_choice" ||
           question.questionType.lowercased() == "true_false" {
            return selectedOption.isEmpty
        }

        return studentAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitAnswer() async {
        isSubmitting = true
        gradingError = nil

        logger.info("Submitting answer for practice question")

        do {
            // ✅ FIX: Try client-side matching first to avoid unnecessary API calls
            if question.questionType.lowercased() == "multiple_choice" ||
               question.questionType.lowercased() == "true_false" {

                let matchResult = AnswerMatchingService.shared.matchAnswer(
                    userAnswer: currentAnswer,
                    correctAnswer: question.correctAnswer,
                    questionType: question.questionType,
                    options: nil  // Options dict not needed with our fix
                )

                logger.info("✅ Client-side match: score=\(matchResult.matchScore), shouldSkip=\(matchResult.shouldSkipAIGrading)")

                if matchResult.shouldSkipAIGrading {
                    // Instant grading - no API call needed!
                    let instantGrade = ProgressiveGradeResult(
                        score: matchResult.isCorrect ? 1.0 : 0.0,
                        isCorrect: matchResult.isCorrect,
                        feedback: matchResult.isCorrect ?
                            "Correct! Well done." :
                            "Incorrect. The correct answer is: \(question.correctAnswer)",
                        confidence: Float(matchResult.matchScore),
                        correctAnswer: question.correctAnswer
                    )

                    gradeResult = instantGrade

                    // Update weakness tracking
                    if matchResult.isCorrect {
                        ShortTermStatusService.shared.recordCorrectAttempt(
                            key: weaknessKey,
                            retryType: .explicitPractice,
                            questionId: question.id.uuidString
                        )
                        logger.info("✅ Correct answer (instant graded) - weakness value decreased")
                    } else {
                        ShortTermStatusService.shared.recordMistake(
                            key: weaknessKey,
                            errorType: "practice_error",
                            questionId: question.id.uuidString
                        )
                        logger.info("❌ Incorrect answer (instant graded) - weakness value increased")
                    }

                    onAnswerSubmitted()
                    isSubmitting = false
                    return
                }
            }

            // If not a multiple choice or match failed, use AI grading
            let response = try await networkService.gradeSingleQuestion(
                questionText: question.questionText,
                studentAnswer: currentAnswer,
                subject: nil,  // Can be extracted from weaknessKey if needed
                questionType: question.questionType,
                contextImageBase64: nil,
                parentQuestionContent: nil,
                useDeepReasoning: true,  // Use Pro Mode
                modelProvider: "gemini"
            )

            if let grade = response.grade {
                gradeResult = grade

                // Update weakness tracking
                if grade.isCorrect {
                    ShortTermStatusService.shared.recordCorrectAttempt(
                        key: weaknessKey,
                        retryType: .explicitPractice,
                        questionId: question.id.uuidString
                    )
                    logger.info("✅ Correct answer - weakness value decreased")
                } else {
                    ShortTermStatusService.shared.recordMistake(
                        key: weaknessKey,
                        errorType: "practice_error",
                        questionId: question.id.uuidString
                    )
                    logger.info("❌ Incorrect answer - weakness value increased")
                }

                onAnswerSubmitted()
            } else if let error = response.error {
                gradingError = error
            }

        } catch {
            logger.error("Failed to grade answer: \(error.localizedDescription)")
            gradingError = "Failed to grade answer. Please try again."
        }

        isSubmitting = false
    }

    private func resetAnswer() {
        studentAnswer = ""
        selectedOption = ""
        gradeResult = nil
        gradingError = nil
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

    private let logger = AppLogger.forFeature("WeaknessPractice")

    init(weaknessKey: String) {
        self.weaknessKey = weaknessKey
    }

    func loadPracticeQuestions() async {
        isLoading = true
        error = nil

        print("📚 [WeaknessPractice] Loading questions for weakness key: \(weaknessKey)")

        do {
            // Parse weakness key: "Math/algebra/calculation"
            let parts = weaknessKey.split(separator: "/")
            guard parts.count >= 2 else {
                throw PracticeError.invalidWeaknessKey
            }

            // ✅ Load original mistake questions from local storage
            let localStorage = QuestionLocalStorage.shared
            let allQuestions = localStorage.getLocalQuestions()

            print("   📊 Total questions in storage: \(allQuestions.count)")

            // Filter for questions with matching weakness key
            let mistakeQuestions = allQuestions.filter { question in
                guard let questionWeaknessKey = question["weaknessKey"] as? String else {
                    return false
                }
                return questionWeaknessKey == weaknessKey
            }

            print("   🎯 Found \(mistakeQuestions.count) original mistake questions for '\(weaknessKey)'")
            #if DEBUG
            // Show IDs of all matching questions
            print("   📋 Question IDs with this weakness key:")
            for (idx, q) in mistakeQuestions.enumerated() {
                let qId = q["id"] as? String ?? "unknown"
                let hasRaw = q["rawQuestionText"] != nil
                let rawLength = (q["rawQuestionText"] as? String)?.count ?? 0
                print("      \(idx + 1). ID: \(qId), hasRawQuestionText: \(hasRaw), length: \(rawLength)")
            }
            #endif

            // Convert to WeaknessPracticeQuestion format
            var practiceQuestions: [WeaknessPracticeQuestion] = []

            for (index, questionData) in mistakeQuestions.enumerated() {
                guard let questionText = questionData["questionText"] as? String,
                      let correctAnswer = questionData["answerText"] as? String else {
                    print("   ⚠️ Skipping question \(index) - missing required fields")
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
                print("📦 [WeaknessPractice-Storage] Question \(index + 1) data from local storage:")
                print("   Question ID: \(questionId)")
                print("   weaknessKey: \(weaknessKey)")
                print("   questionText length: \(questionText.count)")
                print("   questionText: '\(questionText.prefix(100))'...")
                print("   rawQuestionText from storage: \(rawFromStorage != nil ? "EXISTS (\(rawFromStorage!.count) chars)" : "NIL/MISSING")")
                if let raw = rawFromStorage {
                    print("   rawQuestionText content: '\(raw.prefix(100))'...")
                    if raw.isEmpty {
                        print("   ⚠️ rawQuestionText is EMPTY STRING - will fallback to questionText")
                    }
                } else {
                    print("   ⚠️ rawQuestionText is NIL - will fallback to questionText")
                }
                print("   All keys in questionData: \(questionData.keys.sorted())")
                #endif

                // ✅ FIX: Add fallback to questionText if rawQuestionText is nil OR empty (same as MistakeReviewService)
                let rawQuestionTextFromStorage = questionData["rawQuestionText"] as? String
                let rawQuestionText = (rawQuestionTextFromStorage?.isEmpty == false) ? rawQuestionTextFromStorage! : questionText

                #if DEBUG
                // Only log image-related data
                if let imageUrl = questionImageUrl {
                    let fileExists = FileManager.default.fileExists(atPath: imageUrl)
                    print("🖼️ [WeaknessPractice] Question \(index + 1) - Image file exists: \(fileExists)")
                    if fileExists {
                        print("   📍 Image path: \(imageUrl)")
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
                    rawQuestionText: rawQuestionText  // ✅ Include raw text
                )

                practiceQuestions.append(practiceQuestion)
            }

            questions = practiceQuestions

            #if DEBUG
            // Only log image-related info
            if !questions.isEmpty {
                print("   🖼️ [WeaknessPractice] Loaded \(questions.count) questions with images:")
                for (idx, q) in questions.enumerated() {
                    if let imageUrl = q.questionImageUrl, !imageUrl.isEmpty {
                        print("      Question \(idx + 1): has image at '\(imageUrl)'")
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

    func submitAnswer(questionIndex: Int, answer: String) async {
        guard questionIndex < questions.count else { return }

        var question = questions[questionIndex]

        // Simple grading (exact match)
        let isCorrect = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == question.correctAnswer.lowercased()

        question.result = WeaknessPracticeQuestionResult(
            isCorrect: isCorrect,
            userAnswer: answer,
            correctAnswer: question.correctAnswer,
            feedback: generateFeedback(isCorrect: isCorrect)
        )

        questions[questionIndex] = question

        // Update short-term status
        if isCorrect {
            ShortTermStatusService.shared.recordCorrectAttempt(
                key: weaknessKey,
                retryType: .explicitPractice,  // ✅ Full bonus for practice button
                questionId: question.id.uuidString
            )
            logger.info("Correct practice answer for '\(weaknessKey)'")
        } else {
            ShortTermStatusService.shared.recordMistake(
                key: weaknessKey,
                errorType: "practice_error",
                questionId: question.id.uuidString
            )
            logger.info("Incorrect practice answer for '\(weaknessKey)'")
        }
    }

    private func generateFeedback(isCorrect: Bool) -> String {
        if isCorrect {
            return "Great job! Keep practicing to master this weakness."
        } else {
            return "Not quite. Review the correct answer and try similar questions."
        }
    }

    // ✅ Generate additional practice questions using error analysis
    func generateMoreQuestions() async {
        isGenerating = true

        print("🔨 [WeaknessPractice] Generating more questions for: \(weaknessKey)")

        do {
            // Parse weakness key to extract subject and concept
            let parts = weaknessKey.split(separator: "/")
            guard parts.count >= 3 else {
                throw PracticeError.generationFailed
            }

            let subject = String(parts[0])
            let baseBranch = String(parts[1])
            let detailedBranch = String(parts[2])

            print("   📚 Subject: \(subject), Base: \(baseBranch), Detail: \(detailedBranch)")

            // ✅ Load original mistake questions with error analysis from local storage
            let localStorage = QuestionLocalStorage.shared
            let allQuestions = localStorage.getLocalQuestions()

            // Filter for questions matching this weakness key
            let mistakeQuestions = allQuestions.filter { question in
                guard let questionWeaknessKey = question["weaknessKey"] as? String else {
                    return false
                }
                return questionWeaknessKey == weaknessKey
            }

            print("   📊 Found \(mistakeQuestions.count) original mistakes for this weakness")

            // Build mistakes data with error analysis
            let mistakesData: [[String: Any]] = mistakeQuestions.compactMap { question in
                guard let questionText = question["questionText"] as? String,
                      let studentAnswer = question["studentAnswer"] as? String,
                      let correctAnswer = question["answerText"] as? String else {
                    return nil
                }

                var data: [String: Any] = [
                    "question_text": questionText,
                    "student_answer": studentAnswer,
                    "correct_answer": correctAnswer,
                    "subject": subject
                ]

                // ✅ Add error analysis if available
                if let errorType = question["errorType"] as? String {
                    data["error_type"] = errorType
                    print("   ✓ Including error type: \(errorType)")
                }
                if let errorEvidence = question["errorEvidence"] as? String {
                    data["error_evidence"] = errorEvidence
                }
                if let baseBranch = question["baseBranch"] as? String {
                    data["base_branch"] = baseBranch
                    print("   ✓ Including base branch: \(baseBranch)")
                }
                if let detailedBranch = question["detailedBranch"] as? String {
                    data["detailed_branch"] = detailedBranch
                    print("   ✓ Including detailed branch: \(detailedBranch)")
                }

                return data
            }

            guard !mistakesData.isEmpty else {
                print("   ⚠️ No mistake data available - generating generic questions")
                throw PracticeError.generationFailed
            }

            print("   🎯 Calling backend with \(mistakesData.count) mistakes (with error analysis)")

            // Call backend endpoint
            guard let url = URL(string: "https://sai-backend-production.up.railway.app/api/ai/generate-questions/mistakes") else {
                throw URLError(.badURL)
            }

            guard let token = AuthenticationService.shared.getAuthToken() else {
                throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let requestBody: [String: Any] = [
                "subject": subject,
                "mistakes_data": mistakesData,
                "count": 3  // Generate 3 new questions
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw NSError(domain: "API", code: (response as? HTTPURLResponse)?.statusCode ?? 500)
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let generatedQuestions = json["questions"] as? [[String: Any]] {

                print("   ✅ Received \(generatedQuestions.count) AI-generated questions")

                // Convert to WeaknessPracticeQuestion format
                for (index, questionData) in generatedQuestions.enumerated() {
                    guard let questionText = questionData["question"] as? String,
                          let correctAnswer = questionData["correct_answer"] as? String else {
                        print("   ⚠️ Skipping question \(index) - missing fields")
                        continue
                    }

                    let questionType = questionData["question_type"] as? String ?? "open_ended"
                    let options = questionData["options"] as? [String]

                    let practiceQuestion = WeaknessPracticeQuestion(
                        id: UUID(),
                        questionText: questionText,
                        questionType: questionType,
                        options: options,
                        correctAnswer: correctAnswer,
                        isOriginalMistake: false,  // AI-generated, not original
                        originalQuestionId: nil
                    )

                    questions.append(practiceQuestion)
                    print("   ✅ Added AI-generated question \(index + 1): \(questionText.prefix(50))...")
                }

                logger.info("Generated \(generatedQuestions.count) additional practice questions for '\(weaknessKey)'")
            }

        } catch {
            logger.error("Failed to generate questions: \(error)")
            print("   ❌ Generation failed: \(error.localizedDescription)")
            self.error = "Failed to generate questions: \(error.localizedDescription)"
        }

        isGenerating = false
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
    var result: WeaknessPracticeQuestionResult?

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

struct WeaknessPracticeQuestionResult {
    let isCorrect: Bool
    let userAnswer: String
    let correctAnswer: String
    let feedback: String
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
