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
    let sessionId: String?  // ✅ FIX P0: Track session for progress updates
    let onAnswerSubmitted: ((Bool, Int) -> Void)? // Callback with isCorrect and points

    // Navigation support
    let allQuestions: [QuestionGenerationService.GeneratedQuestion]?
    let currentIndex: Int?
    @State private var showingNextQuestion = false
    @State private var nextQuestion: QuestionGenerationService.GeneratedQuestion?

    @Environment(\.dismiss) private var dismiss
    @State private var userAnswer = ""
    @State private var selectedOption: String?
    @State private var hasSubmitted = false
    @State private var showingExplanation = false
    @State private var isCorrect = false
    @State private var partialCredit: Double = 0.0  // 0.0 to 1.0 for partial credit
    @State private var isArchived = false
    @State private var showingArchiveSuccess = false
    @State private var isArchiving = false

    // ✅ NEW: Two-tier grading state
    @State private var isGradingWithAI = false
    @State private var wasInstantGraded = false
    @State private var aiFeedback: String? = nil

    // Mark progress state
    @State private var hasMarkedProgress = false
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @ObservedObject private var appState = AppState.shared

    private let logger = Logger(subsystem: "com.studyai", category: "QuestionDetail")
    private let archiveService = QuestionArchiveService.shared

    // Check if there's a next question available
    private var hasNextQuestion: Bool {
        guard let allQuestions = allQuestions,
              let currentIndex = currentIndex else {
            return false
        }
        return currentIndex < allQuestions.count - 1
    }

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
    init(question: QuestionGenerationService.GeneratedQuestion,
         sessionId: String? = nil,  // ✅ FIX P0: Accept session ID
         onAnswerSubmitted: ((Bool, Int) -> Void)? = nil,
         allQuestions: [QuestionGenerationService.GeneratedQuestion]? = nil,
         currentIndex: Int? = nil) {
        self.question = question
        self.sessionId = sessionId
        self.onAnswerSubmitted = onAnswerSubmitted
        self.allQuestions = allQuestions
        self.currentIndex = currentIndex
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Question Content
                    questionContent

                    // Answer Input Section
                    answerInputSection

                    // Submit Button
                    if !hasSubmitted {
                        submitButton
                    }

                    // Results Section with Explanation inside
                    if hasSubmitted {
                        resultsSection
                    }

                    // Action Buttons (outside results card)
                    if hasSubmitted {
                        actionButtonsSection
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
        // ✅ NEW: AI grading loading overlay
        .overlay {
            if isGradingWithAI {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)

                        Text("AI is analyzing your answer...")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                            .multilineTextAlignment(.center)

                        Text("Using Gemini deep mode")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isGradingWithAI)
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(NSLocalizedString("questionDetail.question", comment: ""))
                .font(.title3)
                .fontWeight(.semibold)

            EnhancedMathText(question.question, fontSize: 16)
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
                case .shortAnswer, .calculation, .longAnswer, .fillBlank, .matching, .any:
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
            if question.type == .longAnswer {
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

            Text(question.type == .longAnswer ? NSLocalizedString("questionDetail.provideDetailedExplanation", comment: "") : NSLocalizedString("questionDetail.typeAnswerAbove", comment: ""))
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

            resultsHeader

            answerComparison

            if showingExplanation {
                explanationView
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }

    private var resultsHeader: some View {
        HStack(spacing: 24) {
            correctnessIndicator

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
    }

    private var correctnessIndicator: some View {
        HStack(spacing: 12) {
            let iconName = isCorrect ? "checkmark.circle.fill" : (partialCredit > 0 ? "circle.lefthalf.filled" : "xmark.circle.fill")
            let color = isCorrect ? Color.green : (partialCredit > 0 ? Color.orange : Color.red)

            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 4) {
                let statusText = isCorrect ? NSLocalizedString("questionDetail.correct", comment: "") : (partialCredit > 0 ? "Partial Credit" : NSLocalizedString("questionDetail.incorrect", comment: ""))

                Text(statusText)
                    .font(.body.bold())
                    .foregroundColor(color)

                if partialCredit > 0 && partialCredit < 1.0 {
                    Text("\(Int(partialCredit * 100))% Credit")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var answerComparison: some View {
        VStack(alignment: .leading, spacing: 16) {
            userAnswerView
            correctAnswerView
        }
    }

    private var userAnswerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("questionDetail.yourAnswer", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            let bgColor = isCorrect ? Color.green.opacity(0.05) : (partialCredit > 0 ? Color.orange.opacity(0.05) : Color.red.opacity(0.05))
            let strokeColor = isCorrect ? Color.green.opacity(0.3) : (partialCredit > 0 ? Color.orange.opacity(0.3) : Color.red.opacity(0.3))

            EnhancedMathText(getCurrentAnswer(), fontSize: 14)
                .padding()
                .background(bgColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(strokeColor, lineWidth: 1)
                )
        }
    }

    private var correctAnswerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("questionDetail.correctAnswer", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            EnhancedMathText(question.correctAnswer, fontSize: 14)
                .padding()
                .background(Color.green.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var explanationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            HStack {
                Image(systemName: wasInstantGraded ? "bolt.fill" : "brain.head.profile")
                    .font(.title3)
                    .foregroundColor(wasInstantGraded ? .yellow : .purple)

                Text(NSLocalizedString("questionDetail.explanation", comment: ""))
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                // ✅ NEW: Badge showing grading method
                if wasInstantGraded {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                        Text("Instant")
                            .font(.system(size: 9))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.yellow)
                    )
                } else if aiFeedback != nil {
                    HStack(spacing: 3) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 8))
                        Text("AI Analyzed")
                            .font(.system(size: 9))
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.purple)
                    )
                }
            }

            // Show AI feedback if available, otherwise show question explanation
            if let feedback = aiFeedback {
                EnhancedMathText(feedback, fontSize: 14)
                    .foregroundColor(.primary)
            } else {
                EnhancedMathText(question.explanation, fontSize: 14)
            }
        }
        .padding()
        .background((wasInstantGraded ? Color.yellow : Color.purple).opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke((wasInstantGraded ? Color.yellow : Color.purple).opacity(0.3), lineWidth: 1)
        )
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            // Row 1: Archive and Mark Progress side by side
            HStack(spacing: 12) {
                // Archive Button
                if !isArchived {
                    Button(action: archiveQuestion) {
                        HStack(spacing: 8) {
                            if isArchiving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "books.vertical.fill")
                                    .font(.body)
                            }

                            Text(isArchiving ? "Archiving..." : "Archive")
                                .font(.subheadline)
                                .fontWeight(.semibold)
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
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.body)
                            .foregroundColor(.green)

                        Text("Archived")
                            .font(.subheadline)
                            .fontWeight(.semibold)
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

                // Mark Progress Button
                Button(action: {
                    if !hasMarkedProgress {
                        trackPracticeProgress()
                        hasMarkedProgress = true
                        saveProgressState()
                    }
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: hasMarkedProgress ? "checkmark.circle.fill" : "chart.line.uptrend.xyaxis")
                            .font(.body)
                        Text(hasMarkedProgress ? "Marked" : "Mark Progress")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: hasMarkedProgress ? [Color.green, Color.green.opacity(0.8)] : [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .disabled(hasMarkedProgress)
            }

            // Ask AI Button
            Button(action: askAIForHelp) {
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.body)
                    Text("Ask AI for Follow Up")
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.orange.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
            }

            // Next Question Button (if available)
            if hasNextQuestion {
                Button(action: {
                    if let allQuestions = allQuestions,
                       let currentIndex = currentIndex,
                       currentIndex < allQuestions.count - 1 {
                        nextQuestion = allQuestions[currentIndex + 1]
                        showingNextQuestion = true
                    }
                }) {
                    HStack(spacing: 12) {
                        Text("Next Question")
                            .font(.body)
                            .fontWeight(.semibold)

                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)

                        if let currentIndex = currentIndex,
                           let allQuestions = allQuestions {
                            Text("(\(currentIndex + 2)/\(allQuestions.count))")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
        }
        .alert(NSLocalizedString("questionDetail.archiveSuccess", comment: ""), isPresented: $showingArchiveSuccess) {
            Button(NSLocalizedString("common.ok", comment: "")) { }
        } message: {
            Text(NSLocalizedString("questionDetail.archiveSuccessMessage", comment: ""))
        }
        .sheet(isPresented: $showingNextQuestion) {
            if let nextQuestion = nextQuestion,
               let allQuestions = allQuestions,
               let currentIndex = currentIndex {
                GeneratedQuestionDetailView(
                    question: nextQuestion,
                    sessionId: sessionId,  // ✅ FIX P0: Pass session ID to next question
                    onAnswerSubmitted: onAnswerSubmitted,
                    allQuestions: allQuestions,
                    currentIndex: currentIndex + 1
                )
            }
        }
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
        case .shortAnswer, .calculation, .longAnswer, .fillBlank, .matching, .any:
            return !userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func getCurrentAnswer() -> String {
        switch question.type {
        case .multipleChoice, .trueFalse:
            return selectedOption ?? ""
        case .shortAnswer, .calculation, .longAnswer, .fillBlank, .matching, .any:
            return userAnswer
        }
    }

    // ✅ OPTIMIZED: Two-tier grading system (client-side matching + AI fallback)
    private func submitAnswer() {
        hasSubmitted = true
        let currentAnswer = getCurrentAnswer()

        print("📝 [Generation] Submitting answer for question: \(question.question.prefix(50))...")
        print("📝 [Generation] User answer: \(currentAnswer.prefix(100))")
        print("📝 [Generation] Correct answer: \(question.correctAnswer.prefix(100))")

        // TIER 1: Client-side answer matching (instant grading)
        // Convert options array to dictionary format for matching service
        let optionsDict: [String: String]?
        if let optionsArray = question.options {
            let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
            optionsDict = Dictionary(uniqueKeysWithValues: zip(letters.prefix(optionsArray.count), optionsArray))
        } else {
            optionsDict = nil
        }

        let matchResult = AnswerMatchingService.shared.matchAnswer(
            userAnswer: currentAnswer,
            correctAnswer: question.correctAnswer,
            questionType: question.type.rawValue,
            options: optionsDict
        )

        print("🎯 [Generation] Client-side match score: \(String(format: "%.1f%%", matchResult.matchScore * 100))")
        print("   Should skip AI: \(matchResult.shouldSkipAIGrading)")

        // If match score >= 90%, grade instantly without AI call
        if matchResult.shouldSkipAIGrading {
            print("⚡ [Generation] INSTANT GRADING (score >= 90%)")

            // Instant grade result (curve to 100% correct if >= 90%)
            isCorrect = true
            partialCredit = 1.0
            wasInstantGraded = true
            showingExplanation = true

            let instantFeedback = matchResult.isExactMatch ?
                "Perfect! Your answer is exactly correct." :
                "Correct! Your answer matches the expected solution."
            aiFeedback = instantFeedback

            logger.info("📝 Answer submitted: Instant grade - Correct (100%)")

            // Save and notify
            saveAnswer()
            let maxPoints = question.points ?? 1
            onAnswerSubmitted?(isCorrect, maxPoints)

            return  // Skip AI grading
        }

        // TIER 2: AI grading with specialized prompts (for match score < 90%)
        print("🤖 [Generation] AI GRADING (score < 90%)")
        print("   Sending to Gemini deep mode for analysis...")

        isGradingWithAI = true

        Task {
            await gradeWithAI(userAnswer: currentAnswer)
        }
    }

    // ✅ NEW: AI grading helper with specialized prompts
    private func gradeWithAI(userAnswer: String) async {
        defer { isGradingWithAI = false }

        do {
            // Get subject from question topic or default to "General"
            let subject = question.topic ?? "General"

            // Call backend with specialized prompts
            let response = try await NetworkService.shared.gradeSingleQuestion(
                questionText: question.question,
                studentAnswer: userAnswer,
                subject: subject,
                questionType: question.type.rawValue,
                contextImageBase64: nil,
                parentQuestionContent: nil,
                useDeepReasoning: true,  // Gemini deep mode for nuanced grading
                modelProvider: "gemini"
            )

            print("✅ [Generation] RECEIVED AI GRADING RESPONSE")

            if let grade = response.grade {
                await MainActor.run {
                    isCorrect = grade.isCorrect
                    partialCredit = Double(grade.score)
                    wasInstantGraded = false
                    aiFeedback = grade.feedback
                    showingExplanation = true

                    print("   Is Correct: \(grade.isCorrect ? "✅ YES" : "❌ NO")")
                    print("   Score: \(String(format: "%.1f%%", grade.score * 100))")
                    print("   Feedback: \(grade.feedback)")

                    if isCorrect {
                        logger.info("📝 Answer submitted: AI grade - Correct (100%)")
                    } else if partialCredit > 0 {
                        logger.info("📝 Answer submitted: AI grade - Partial credit (\(Int(partialCredit * 100))%)")
                    } else {
                        logger.info("📝 Answer submitted: AI grade - Incorrect (0%)")
                    }

                    // Save answer for persistence
                    saveAnswer()

                    // Notify parent view about the answer result with partial credit
                    let maxPoints = question.points ?? 1
                    let earnedPoints = Int(Double(maxPoints) * partialCredit)
                    onAnswerSubmitted?(isCorrect, earnedPoints)

                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(isCorrect ? .success : .error)
                }
            }
        } catch {
            print("❌ [Generation] AI grading failed: \(error.localizedDescription)")
            logger.error("AI grading failed: \(error.localizedDescription)")

            await MainActor.run {
                // Fallback to local flexible grading on error
                print("🔄 [Generation] Falling back to local flexible grading")
                let gradingResult = gradeAnswerFlexibly(
                    userAnswer: userAnswer,
                    correctAnswer: question.correctAnswer,
                    questionType: question.type
                )

                isCorrect = gradingResult.isFullyCorrect
                partialCredit = gradingResult.creditPercentage
                wasInstantGraded = false
                aiFeedback = "AI grading unavailable. Using local grading."
                showingExplanation = true

                print("   Fallback result: \(gradingResult.matchMethod), Credit: \(Int(partialCredit * 100))%")

                // Save and notify
                saveAnswer()
                let maxPoints = question.points ?? 1
                let earnedPoints = Int(Double(maxPoints) * partialCredit)
                onAnswerSubmitted?(isCorrect, earnedPoints)
            }
        }
    }

    /// Normalize an answer by removing option prefixes and standardizing format across all question types
    private func normalizeAnswer(_ answer: String) -> String {
        var normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        // Step 1: Remove multiple choice option prefixes BEFORE lowercasing
        // Patterns: "A.", "A)", "(A)", "a.", "a)", "(a)", etc.
        // This must be done BEFORE lowercasing to match uppercase letters
        let prefixPattern = "^[(]?[A-Za-z][.\\)\\]]?\\s*"
        if let regex = try? NSRegularExpression(pattern: prefixPattern, options: []) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "")
        }

        // Step 2: Lowercase for case-insensitive comparison
        normalized = normalized.lowercased()

        // Step 3: True/False normalization - expand abbreviations
        // "t" or "T" → "true", "f" or "F" → "false"
        if normalized == "t" {
            normalized = "true"
        } else if normalized == "f" {
            normalized = "false"
        }

        // Step 4: Remove common filler words and phrases
        let fillerPhrases = ["the answer is", "answer:", "result:", "solution:", "equals"]
        for phrase in fillerPhrases {
            normalized = normalized.replacingOccurrences(of: phrase, with: "")
        }

        // Step 5: Normalize mathematical expressions
        // Remove spaces around operators for consistent comparison
        normalized = normalized.replacingOccurrences(of: " + ", with: "+")
        normalized = normalized.replacingOccurrences(of: " - ", with: "-")
        normalized = normalized.replacingOccurrences(of: " * ", with: "*")
        normalized = normalized.replacingOccurrences(of: " / ", with: "/")
        normalized = normalized.replacingOccurrences(of: " = ", with: "=")

        // Step 6: Normalize fractions (1/2, ½) and common unicode symbols
        let fractionMap: [String: String] = [
            "½": "1/2", "⅓": "1/3", "⅔": "2/3", "¼": "1/4", "¾": "3/4",
            "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5", "⅙": "1/6", "⅚": "5/6",
            "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8"
        ]
        for (unicode, fraction) in fractionMap {
            normalized = normalized.replacingOccurrences(of: unicode, with: fraction)
        }

        // Step 7: Normalize units - remove spaces between number and unit
        // "5 km" → "5km", "10 m/s" → "10m/s"
        let unitPattern = "(\\d)\\s+(km|m|cm|mm|kg|g|mg|l|ml|s|min|h|mph|km/h|m/s|°c|°f)"
        if let regex = try? NSRegularExpression(pattern: unitPattern, options: .caseInsensitive) {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: "$1$2")
        }

        // Step 8: Final cleanup - trim and collapse multiple spaces
        normalized = normalized.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized
    }

    // MARK: - Flexible Grading System

    /// Result of flexible grading
    private struct GradingResult {
        let isFullyCorrect: Bool
        let creditPercentage: Double  // 0.0 to 1.0
        let matchMethod: String  // For debugging/logging
    }

    /// Grade answer using multiple flexible methods with partial credit
    private func gradeAnswerFlexibly(userAnswer: String, correctAnswer: String, questionType: QuestionGenerationService.GeneratedQuestion.QuestionType) -> GradingResult {

        let normalizedUser = normalizeAnswer(userAnswer)
        let normalizedCorrect = normalizeAnswer(correctAnswer)

        // Strategy 1: Exact match (100% credit)
        if normalizedUser == normalizedCorrect {
            return GradingResult(isFullyCorrect: true, creditPercentage: 1.0, matchMethod: "exact")
        }

        // Strategy 2: Multiple choice and True/False - strict matching only
        if questionType == .multipleChoice || questionType == .trueFalse {
            // For MC/TF, only exact match counts
            return GradingResult(isFullyCorrect: false, creditPercentage: 0.0, matchMethod: "strict")
        }

        // Strategy 3: Numerical answer matching (great for math problems)
        if let numericalResult = gradeNumericalAnswer(userAnswer: normalizedUser, correctAnswer: normalizedCorrect) {
            return numericalResult
        }

        // Strategy 4: Substring/containment matching (80% credit)
        // Check if user's answer is contained in correct answer or vice versa
        if normalizedCorrect.contains(normalizedUser) && normalizedUser.count >= 3 {
            // User gave a shorter but correct answer (e.g., "11" vs "11 ducklings")
            return GradingResult(isFullyCorrect: false, creditPercentage: 0.9, matchMethod: "substring-user-in-correct")
        }

        if normalizedUser.contains(normalizedCorrect) && normalizedCorrect.count >= 3 {
            // User gave extra information (e.g., "the answer is 11 ducklings" vs "11 ducklings")
            return GradingResult(isFullyCorrect: false, creditPercentage: 0.85, matchMethod: "substring-correct-in-user")
        }

        // Strategy 5: Keyword matching (70% credit)
        let keywordScore = gradeByKeywords(userAnswer: normalizedUser, correctAnswer: normalizedCorrect)
        if keywordScore >= 0.7 {
            return GradingResult(isFullyCorrect: false, creditPercentage: keywordScore * 0.7, matchMethod: "keyword")
        }

        // Strategy 6: Fuzzy string similarity (50-70% credit based on similarity)
        let similarity = stringSimilarity(normalizedUser, normalizedCorrect)
        if similarity >= 0.7 {
            let credit = 0.5 + (similarity - 0.7) * 1.0  // 50-80% credit for 70-100% similarity
            return GradingResult(isFullyCorrect: false, creditPercentage: min(credit, 0.8), matchMethod: "fuzzy")
        }

        // No match found
        return GradingResult(isFullyCorrect: false, creditPercentage: 0.0, matchMethod: "none")
    }

    /// Extract and compare numerical values from answers
    private func gradeNumericalAnswer(userAnswer: String, correctAnswer: String) -> GradingResult? {
        let userNumbers = extractNumbers(from: userAnswer)
        let correctNumbers = extractNumbers(from: correctAnswer)

        // No numbers found in either answer
        guard !userNumbers.isEmpty || !correctNumbers.isEmpty else {
            return nil
        }

        // If both have numbers, compare them
        if !userNumbers.isEmpty && !correctNumbers.isEmpty {
            // Check if all correct numbers are present in user's answer
            let matchingNumbers = correctNumbers.filter { correctNum in
                userNumbers.contains { userNum in
                    abs(userNum - correctNum) < 0.0001  // Float comparison with tolerance
                }
            }

            let matchPercentage = Double(matchingNumbers.count) / Double(correctNumbers.count)

            if matchPercentage == 1.0 {
                // All numbers match - give 95% credit (very likely correct)
                return GradingResult(isFullyCorrect: false, creditPercentage: 0.95, matchMethod: "numerical")
            } else if matchPercentage >= 0.5 {
                // At least half the numbers match - partial credit
                return GradingResult(isFullyCorrect: false, creditPercentage: 0.5 * matchPercentage, matchMethod: "numerical-partial")
            }
        }

        return nil
    }

    /// Extract all numbers (integers and decimals) from a string
    private func extractNumbers(from text: String) -> [Double] {
        var numbers: [Double] = []

        // Pattern matches integers and decimals (including negative numbers)
        let pattern = "-?\\d+\\.?\\d*"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                let numberString = nsString.substring(with: match.range)
                if let number = Double(numberString) {
                    numbers.append(number)
                }
            }
        }

        return numbers
    }

    /// Grade by comparing keywords (important words)
    private func gradeByKeywords(userAnswer: String, correctAnswer: String) -> Double {
        // Extract keywords (words longer than 2 characters, excluding common words)
        let commonWords = Set(["the", "and", "or", "in", "on", "at", "to", "for", "of", "with", "is", "are", "was", "were", "be", "been", "being"])

        let userWords = Set(userAnswer.split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 && !commonWords.contains($0) })

        let correctWords = Set(correctAnswer.split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 && !commonWords.contains($0) })

        guard !correctWords.isEmpty else { return 0.0 }

        let matchingWords = userWords.intersection(correctWords)
        return Double(matchingWords.count) / Double(correctWords.count)
    }

    /// Calculate string similarity using Levenshtein distance
    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let longer = s1.count > s2.count ? s1 : s2
        let shorter = s1.count > s2.count ? s2 : s1

        let longerLength = longer.count
        if longerLength == 0 { return 1.0 }

        let distance = levenshteinDistance(shorter, longer)
        return (Double(longerLength) - Double(distance)) / Double(longerLength)
    }

    /// Calculate Levenshtein distance between two strings
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2Array.count + 1), count: s1Array.count + 1)

        for i in 0...s1Array.count {
            matrix[i][0] = i
        }
        for j in 0...s2Array.count {
            matrix[0][j] = j
        }

        for i in 1...s1Array.count {
            for j in 1...s2Array.count {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[s1Array.count][s2Array.count]
    }

    // MARK: - AI Follow Up

    private func askAIForHelp() {
        // Dismiss the current view first
        dismiss()

        // Small delay to ensure view is dismissed before navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Construct user message for AI
            let userMessage = """
I need help understanding this question:

Question: \(question.question)

\(hasSubmitted ? "My answer was: \(getCurrentAnswer())\n\n" : "")Can you help me understand this better and explain the solution?
"""

            // ✅ Navigate to chat with question context AND deep mode enabled for first message
            // User can use fast mode for follow-up messages, or activate deep mode manually via long-press
            appState.navigateToChatWithMessage(userMessage, subject: question.topic, useDeepMode: true)

            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
    }

    // MARK: - Progress Tracking

    private func trackPracticeProgress() {
        let subject = question.topic
        let totalAnswered = 1 // One question

        // Use partial credit for correct count
        // If fully correct, count as 1. If partial credit, count proportionally
        let correctCount = partialCredit >= 0.5 ? 1 : 0  // 50% or more counts as correct

        logger.info("📊 [trackPracticeProgress] Marking progress: \(totalAnswered) question, \(correctCount) correct (\(Int(partialCredit * 100))% credit) in \(subject)")

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
            "partialCredit": partialCredit,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let data = try? JSONSerialization.data(withJSONObject: answerData) {
            UserDefaults.standard.set(data, forKey: answerPersistenceKey)
            logger.info("💾 Saved answer for question: \(question.id)")
        }

        // ✅ FIX P0: Update session progress if session ID is available
        if let sessionId = sessionId {
            PracticeSessionManager.shared.updateProgress(
                sessionId: sessionId,
                completedQuestionId: question.id.uuidString,
                answer: getCurrentAnswer(),
                isCorrect: isCorrect
            )
            logger.info("✅ Updated session progress: \(sessionId) - Question \(question.id.uuidString.prefix(8))")
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

        if let savedPartialCredit = answerData["partialCredit"] as? Double {
            partialCredit = savedPartialCredit
        }

        logger.info("💾 Loaded saved answer for question: \(question.id)")
    }

    /// Archive the answered question to local storage
    private func archiveQuestion() {
        guard hasSubmitted else { return }

        isArchiving = true

        // ✅ DEBUG: Log archiving start
        print("📚 [Archive] Starting archive for question: \(question.question.prefix(50))...")
        // DebugSettings.shared.logArchive("Starting archive for question: \(question.question.prefix(50))...")
        // DebugSettings.shared.prettyPrintErrorKeys(
        //     errorType: question.errorType,
        //     baseBranch: question.baseBranch,
        //     detailedBranch: question.detailedBranch,
        //     weaknessKey: question.weaknessKey
        // )

        Task {
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
                "isCorrect": isCorrect,
                // ✅ CRITICAL: Include error keys for short-term status tracking
                "errorType": question.errorType as Any,
                "baseBranch": question.baseBranch as Any,
                "detailedBranch": question.detailedBranch as Any,
                "weaknessKey": question.weaknessKey as Any
            ]

            // ✅ DEBUG: Log archiving data
            print("📚 [Archive] Archive data - Subject: \(question.topic), Correct: \(isCorrect), Has error keys: \(question.errorType != nil)")
            // DebugSettings.shared.logArchive("Archive data - Subject: \(question.topic), Correct: \(isCorrect), Has error keys: \(question.errorType != nil)")

            // Save to local storage
            _ = QuestionLocalStorage.shared.saveQuestions([questionData])

            await MainActor.run {
                isArchiving = false
                isArchived = true
                saveArchivedState()  // Persist archived state
                showingArchiveSuccess = true
                logger.info("📚 [Archive] Practice question archived successfully")

                // ✅ DEBUG: Log completion
                print("📚 [Archive] ✅ Archive completed successfully")
                // DebugSettings.shared.logArchive("✅ Archive completed successfully")
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