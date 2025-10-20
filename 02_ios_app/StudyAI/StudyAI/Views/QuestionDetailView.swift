//
//  QuestionDetailView.swift
//  StudyAI
//
//  Created by Claude Code on 12/21/24.
//

import SwiftUI
import os.log

struct GeneratedQuestionDetailView: View {
    let question: QuestionGenerationService.GeneratedQuestion
    let onAnswerSubmitted: ((Bool, Int) -> Void)? // Callback with isCorrect and points

    @Environment(\.dismiss) private var dismiss
    @State private var userAnswer = ""
    @State private var selectedOption: String?
    @State private var hasSubmitted = false
    @State private var showingExplanation = false
    @State private var isCorrect = false
    @State private var isArchived = false
    @State private var showingArchiveSuccess = false
    @State private var isArchiving = false

    // Mark progress state
    @State private var hasMarkedProgress = false
    @ObservedObject private var pointsManager = PointsEarningManager.shared

    private let logger = Logger(subsystem: "com.studyai", category: "QuestionDetail")
    private let archiveService = QuestionArchiveService.shared

    // UserDefaults keys
    private var progressMarkedKey: String {
        return "question_progress_marked_\(question.id)"
    }

    private var archivedStateKey: String {
        return "question_archived_\(question.id)"
    }

    private var answerPersistenceKey: String {
        return "question_answer_\(question.id.uuidString)"
    }

    // Default initializer without callback (for backwards compatibility)
    init(question: QuestionGenerationService.GeneratedQuestion, onAnswerSubmitted: ((Bool, Int) -> Void)? = nil) {
        self.question = question
        self.onAnswerSubmitted = onAnswerSubmitted
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Question Header
                    questionHeader

                    // Question Content
                    questionContent

                    // Answer Input Section
                    answerInputSection

                    // Submit Button
                    if !hasSubmitted {
                        submitButton
                    }

                    // Results Section
                    if hasSubmitted {
                        resultsSection
                    }

                    // Explanation Section
                    if showingExplanation {
                        explanationSection
                    }

                    // Question Metadata
                    questionMetadata

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("questionDetail.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: closeButton)
            .onAppear {
                logger.info("📝 Question detail view appeared for: \(question.type.displayName)")
                loadProgressState()
                loadArchivedState()
                loadSavedAnswer()
            }
        }
    }

    private var questionHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Type and Difficulty Tags
            HStack {
                Label(question.type.displayName, systemImage: question.typeIcon)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(question.difficultyColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(question.difficultyColor.opacity(0.1))
                    .cornerRadius(20)

                Text(question.difficulty.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(question.difficultyColor)
                    .cornerRadius(20)

                Spacer()

                if let points = question.points {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(String(format: NSLocalizedString("questionDetail.pointsValue", comment: ""), points))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                }
            }

            // Topic and Time Estimate
            HStack {
                Label(question.topic, systemImage: "tag.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if let timeEstimate = question.timeEstimate {
                    Label(timeEstimate, systemImage: "clock.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(NSLocalizedString("questionDetail.question", comment: ""))
                .font(.title3)
                .fontWeight(.semibold)

            Text(question.question)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        }
    }

    private var answerInputSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(NSLocalizedString("questionDetail.yourAnswerPrompt", comment: ""))
                .font(.title3)
                .fontWeight(.semibold)

            Group {
                switch question.type {
                case .multipleChoice:
                    multipleChoiceInput
                case .trueFalse:
                    trueFalseInput
                case .shortAnswer, .calculation, .essay:
                    textAnswerInput
                }
            }
            .disabled(hasSubmitted)
        }
    }

    private var multipleChoiceInput: some View {
        VStack(spacing: 12) {
            if let options = question.options {
                ForEach(options, id: \.self) { option in
                    Button(action: { selectedOption = option }) {
                        HStack {
                            Image(systemName: selectedOption == option ? "largecircle.fill.circle" : "circle")
                                .font(.title3)
                                .foregroundColor(selectedOption == option ? .blue : .secondary)

                            Text(option)
                                .font(.body)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                        .padding()
                        .background(selectedOption == option ? Color.blue.opacity(0.05) : Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedOption == option ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var trueFalseInput: some View {
        HStack(spacing: 24) {
            Button(action: { selectedOption = NSLocalizedString("questionDetail.true", comment: "") }) {
                HStack {
                    Image(systemName: selectedOption == NSLocalizedString("questionDetail.true", comment: "") ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(selectedOption == NSLocalizedString("questionDetail.true", comment: "") ? .green : .secondary)

                    Text(NSLocalizedString("questionDetail.true", comment: ""))
                        .font(.body.bold())
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedOption == NSLocalizedString("questionDetail.true", comment: "") ? Color.green.opacity(0.05) : Color.gray.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selectedOption == NSLocalizedString("questionDetail.true", comment: "") ? Color.green : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: { selectedOption = NSLocalizedString("questionDetail.false", comment: "") }) {
                HStack {
                    Image(systemName: selectedOption == NSLocalizedString("questionDetail.false", comment: "") ? "xmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(selectedOption == NSLocalizedString("questionDetail.false", comment: "") ? .red : .secondary)

                    Text(NSLocalizedString("questionDetail.false", comment: ""))
                        .font(.body.bold())
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedOption == NSLocalizedString("questionDetail.false", comment: "") ? Color.red.opacity(0.05) : Color.gray.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selectedOption == NSLocalizedString("questionDetail.false", comment: "") ? Color.red : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var textAnswerInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            if question.type == .essay {
                TextEditor(text: $userAnswer)
                    .frame(minHeight: 120)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            } else {
                TextField(NSLocalizedString("questionDetail.enterAnswer", comment: ""), text: $userAnswer)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            }

            Text(question.type == .essay ? NSLocalizedString("questionDetail.provideDetailedExplanation", comment: "") : NSLocalizedString("questionDetail.typeAnswerAbove", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var submitButton: some View {
        Button(action: submitAnswer) {
            HStack(spacing: 12) {
                Image(systemName: "paperplane.fill")
                    .font(.headline)

                Text(NSLocalizedString("questionDetail.submitAnswer", comment: ""))
                    .font(.body.bold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [.blue, .blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .disabled(!canSubmit())
        }
        .opacity(canSubmit() ? 1.0 : 0.6)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(NSLocalizedString("questionDetail.results", comment: ""))
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 24) {
                // Correctness indicator
                HStack(spacing: 12) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(isCorrect ? .green : .red)

                    Text(isCorrect ? NSLocalizedString("questionDetail.correct", comment: "") : NSLocalizedString("questionDetail.incorrect", comment: ""))
                        .font(.body.bold())
                        .foregroundColor(isCorrect ? .green : .red)
                }

                Spacer()

                Button(action: { showingExplanation.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.body)

                        Text(showingExplanation ? NSLocalizedString("questionDetail.hideExplanation", comment: "") : NSLocalizedString("questionDetail.showExplanation", comment: ""))
                            .font(.subheadline)
                    }
                    .foregroundColor(.blue)
                }
            }

            // Answer comparison
            VStack(alignment: .leading, spacing: 16) {
                // User's answer
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("questionDetail.yourAnswer", comment: ""))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(getCurrentAnswer())
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding()
                        .background(isCorrect ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isCorrect ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
                        )
                }

                // Correct answer
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("questionDetail.correctAnswer", comment: ""))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(question.correctAnswer)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding()
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            // Archive Button
            if !isArchived {
                Button(action: archiveQuestion) {
                    HStack(spacing: 12) {
                        if isArchiving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "archivebox.fill")
                                .font(.headline)
                        }

                        Text(isArchiving ? NSLocalizedString("questionDetail.archiving", comment: "") : NSLocalizedString("questionDetail.archiveQuestion", comment: ""))
                            .font(.body.bold())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [.purple, .purple.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .disabled(isArchiving)
                }
                .opacity(isArchiving ? 0.6 : 1.0)
            } else {
                // Archived indicator
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundColor(.green)

                    Text(NSLocalizedString("questionDetail.archived", comment: ""))
                        .font(.body.bold())
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
            }

            // Mark Progress Button (show after answer submission)
            markProgressButton
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
        .alert(NSLocalizedString("questionDetail.archiveSuccess", comment: ""), isPresented: $showingArchiveSuccess) {
            Button(NSLocalizedString("common.ok", comment: "")) { }
        } message: {
            Text(NSLocalizedString("questionDetail.archiveSuccessMessage", comment: ""))
        }
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.title3)
                    .foregroundColor(.yellow)

                Text(NSLocalizedString("questionDetail.explanation", comment: ""))
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Text(question.explanation)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)

        }
        .padding()
        .background(Color.yellow.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }

    private var questionMetadata: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("questionDetail.questionInfo", comment: ""))
                .font(.title3)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                MetadataRow(label: NSLocalizedString("questionDetail.type", comment: ""), value: question.type.displayName, icon: question.typeIcon)
                MetadataRow(label: NSLocalizedString("questionDetail.topic", comment: ""), value: question.topic, icon: "tag")
                MetadataRow(label: NSLocalizedString("questionDetail.difficulty", comment: ""), value: question.difficulty.capitalized, icon: "chart.bar")

                if let timeEstimate = question.timeEstimate {
                    MetadataRow(label: NSLocalizedString("questionDetail.timeEstimate", comment: ""), value: timeEstimate, icon: "clock")
                }

                if let points = question.points {
                    MetadataRow(label: NSLocalizedString("questionDetail.points", comment: ""), value: "\(points)", icon: "star")
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }

    private var closeButton: some View {
        Button(NSLocalizedString("common.done", comment: "")) {
            dismiss()
        }
        .font(.body.bold())
    }

    private func canSubmit() -> Bool {
        switch question.type {
        case .multipleChoice, .trueFalse:
            return selectedOption != nil
        case .shortAnswer, .calculation, .essay:
            return !userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func getCurrentAnswer() -> String {
        switch question.type {
        case .multipleChoice, .trueFalse:
            return selectedOption ?? ""
        case .shortAnswer, .calculation, .essay:
            return userAnswer
        }
    }

    private func submitAnswer() {
        hasSubmitted = true
        let currentAnswer = getCurrentAnswer()

        // Normalize answers by removing "A)" prefix if present
        let normalizedUserAnswer = normalizeAnswer(currentAnswer)
        let normalizedCorrectAnswer = normalizeAnswer(question.correctAnswer)

        // Compare normalized answers
        isCorrect = normalizedUserAnswer == normalizedCorrectAnswer

        showingExplanation = true
        logger.info("📝 Answer submitted: \(isCorrect ? "Correct" : "Incorrect")")

        // Save answer for persistence
        saveAnswer()

        // Notify parent view about the answer result
        let earnedPoints = isCorrect ? (question.points ?? 1) : 0
        onAnswerSubmitted?(isCorrect, earnedPoints)
    }

    /// Normalize an answer by removing "A)" prefix and trimming whitespace
    private func normalizeAnswer(_ answer: String) -> String {
        var normalized = answer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove "A)" or similar prefixes (A), B), C), etc.)
        let prefixPattern = "^[a-z]\\)\\s*"
        if let regex = try? NSRegularExpression(pattern: prefixPattern, options: []) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
        }

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Mark Progress

    private var markProgressButton: some View {
        VStack(spacing: 16) {
            Button(action: {
                // Only track if not already marked
                if !hasMarkedProgress {
                    trackPracticeProgress()
                    hasMarkedProgress = true
                    saveProgressState()
                }

                // Show success feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
            }) {
                HStack {
                    Image(systemName: hasMarkedProgress ? "checkmark.circle.fill" : "chart.line.uptrend.xyaxis")
                        .font(.title3)
                    Text(hasMarkedProgress ? NSLocalizedString("questionDetail.progressMarked", comment: "") : NSLocalizedString("questionDetail.markProgress", comment: ""))
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: hasMarkedProgress ? [Color.green, Color.green.opacity(0.8)] : [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
                .shadow(color: (hasMarkedProgress ? Color.green : Color.blue).opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(hasMarkedProgress)

            if hasMarkedProgress {
                Text(NSLocalizedString("questionDetail.progressUpdated", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
            } else {
                Text(NSLocalizedString("questionDetail.progressTip", comment: ""))
                    .font(.caption)
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 16)
    }

    private func trackPracticeProgress() {
        let subject = question.topic
        let totalAnswered = 1 // One question
        let correctCount = isCorrect ? 1 : 0

        logger.info("📊 [trackPracticeProgress] Marking progress: \(totalAnswered) question, \(correctCount) correct in \(subject)")

        // Use the same progress marking system as homework
        pointsManager.markHomeworkProgress(
            subject: subject,
            numberOfQuestions: totalAnswered,
            numberOfCorrectQuestions: correctCount
        )

        logger.info("📊 [trackPracticeProgress] ✅ Progress marked successfully")
    }

    // MARK: - Persistence

    private func loadProgressState() {
        hasMarkedProgress = UserDefaults.standard.bool(forKey: progressMarkedKey)
    }

    private func saveProgressState() {
        UserDefaults.standard.set(hasMarkedProgress, forKey: progressMarkedKey)
    }

    private func loadArchivedState() {
        isArchived = UserDefaults.standard.bool(forKey: archivedStateKey)
    }

    private func saveArchivedState() {
        UserDefaults.standard.set(isArchived, forKey: archivedStateKey)
    }

    private func saveAnswer() {
        let answerData: [String: Any] = [
            "userAnswer": userAnswer,
            "selectedOption": selectedOption as Any,
            "hasSubmitted": hasSubmitted,
            "isCorrect": isCorrect,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let data = try? JSONSerialization.data(withJSONObject: answerData) {
            UserDefaults.standard.set(data, forKey: answerPersistenceKey)
            logger.info("💾 Saved answer for question: \(question.id)")
        }
    }

    private func loadSavedAnswer() {
        guard let data = UserDefaults.standard.data(forKey: answerPersistenceKey),
              let answerData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // Restore saved answer
        if let savedUserAnswer = answerData["userAnswer"] as? String {
            userAnswer = savedUserAnswer
        }

        if let savedSelectedOption = answerData["selectedOption"] as? String {
            selectedOption = savedSelectedOption
        }

        if let savedHasSubmitted = answerData["hasSubmitted"] as? Bool {
            hasSubmitted = savedHasSubmitted
        }

        if let savedIsCorrect = answerData["isCorrect"] as? Bool {
            isCorrect = savedIsCorrect
            showingExplanation = hasSubmitted // Show explanation if already submitted
        }

        logger.info("💾 Loaded saved answer for question: \(question.id)")
    }

    /// Archive the answered question to local storage
    private func archiveQuestion() {
        guard hasSubmitted else { return }

        isArchiving = true

        Task {
            do {
                // Build question data for archiving
                let questionData: [String: Any] = [
                    "id": UUID().uuidString,
                    "subject": question.topic,
                    "questionText": question.question,
                    "rawQuestionText": question.question,
                    "answerText": question.correctAnswer,
                    "confidence": 1.0,  // Generated questions have high confidence
                    "hasVisualElements": false,
                    "archivedAt": ISO8601DateFormatter().string(from: Date()),
                    "reviewCount": 0,
                    "tags": question.tags ?? [],  // Inherit tags from generated question
                    "notes": "",
                    "studentAnswer": getCurrentAnswer(),
                    "grade": isCorrect ? "CORRECT" : "INCORRECT",
                    "points": isCorrect ? (question.points ?? 1) : 0,
                    "maxPoints": question.points ?? 1,
                    "feedback": question.explanation,
                    "isGraded": true,
                    "isCorrect": isCorrect
                ]

                // Save to local storage
                QuestionLocalStorage.shared.saveQuestions([questionData])

                await MainActor.run {
                    isArchiving = false
                    isArchived = true
                    saveArchivedState()  // Persist archived state
                    showingArchiveSuccess = true
                    logger.info("📚 [Archive] Practice question archived successfully")
                }
            } catch {
                await MainActor.run {
                    isArchiving = false
                    logger.error("❌ [Archive] Failed to archive question: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    let sampleQuestion = QuestionGenerationService.GeneratedQuestion(
        question: "What is the derivative of the function f(x) = x² + 3x - 5?",
        type: .calculation,
        correctAnswer: "2x + 3",
        explanation: "Using the power rule for derivatives: the derivative of x² is 2x, the derivative of 3x is 3, and the derivative of a constant (-5) is 0. Therefore, f'(x) = 2x + 3.",
        topic: "Calculus - Derivatives",
        difficulty: "intermediate",
        points: 15,
        timeEstimate: "3 min",
        options: nil
    )

    GeneratedQuestionDetailView(question: sampleQuestion)
}