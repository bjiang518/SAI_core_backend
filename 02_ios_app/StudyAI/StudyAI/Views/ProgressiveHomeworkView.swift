//
//  ProgressiveHomeworkView.swift
//  StudyAI
//
//  Main view for progressive homework grading
//  Shows electronic paper with animated grading results
//

import SwiftUI

struct ProgressiveHomeworkView: View {

    // MARK: - Properties

    @StateObject private var viewModel: ProgressiveHomeworkViewModel
    let originalImage: UIImage
    let base64Image: String
    let preParsedQuestions: ParseHomeworkQuestionsResponse?  // NEW: Optional pre-parsed questions

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme  // For icon selection

    // AI Model selection (OpenAI vs Gemini)
    @AppStorage("selectedAIModel") private var selectedAIModel: String = "openai"
    @State private var showModelSelection = true  // Show model selection before processing

    // MARK: - Initialization

    init(originalImage: UIImage, base64Image: String, preParsedQuestions: ParseHomeworkQuestionsResponse? = nil) {
        self.originalImage = originalImage
        self.base64Image = base64Image
        self.preParsedQuestions = preParsedQuestions
        self._viewModel = StateObject(wrappedValue: ProgressiveHomeworkViewModel())
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            if showModelSelection {
                // Model selection screen
                modelSelectionView
            } else if viewModel.isLoading && viewModel.state.questions.isEmpty {
                // Loading state - Phase 1 parsing
                loadingView
            } else {
                // Main content
                ScrollView {
                    VStack(spacing: 20) {

                        // Header with subject and stats
                        headerSection

                        // Progress bar (shown during grading)
                        if !viewModel.isComplete && !viewModel.state.questions.isEmpty {
                            progressSection
                        }

                        // Questions list
                        questionsListSection

                        // Collection button (shown when complete)
                        if viewModel.isComplete {
                            collectionButtonSection
                        }

                        // Spacing at bottom
                        Spacer(minLength: 40)
                    }
                    .padding(.vertical)
                }
            }

            // Error overlay
            if viewModel.showError {
                errorOverlay
            }
        }
        .navigationTitle("Homework Grading")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isComplete {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(viewModel.loadingMessage)
                .font(.headline)
                .foregroundColor(.secondary)

            Text("This may take a moment...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Model Selection View

    private var modelSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Title
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)

                Text("Select AI Model")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Choose the AI model for grading")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Model selection card
            VStack(alignment: .leading, spacing: 16) {
                Text("AI Model")
                    .font(.headline)
                    .foregroundColor(.secondary)

                // iOS Native Segmented Control Style
                HStack(spacing: 4) {
                    // OpenAI Option
                    aiModelSegmentButton(
                        model: "openai",
                        icon: colorScheme == .dark ? "openai-dark" : "openai-light",
                        label: "OpenAI",
                        description: "GPT-4o-mini: Proven accuracy"
                    )

                    // Gemini Option
                    aiModelSegmentButton(
                        model: "gemini",
                        icon: "gemini-icon",
                        label: "Gemini",
                        description: "Gemini 2.5: Advanced reasoning"
                    )
                }
                .padding(4)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
            .padding(20)
            .background(Color(UIColor.systemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            .padding(.horizontal)

            // Start grading button
            Button {
                withAnimation {
                    showModelSelection = false
                }
                // Start processing
                Task {
                    await viewModel.processHomework(
                        originalImage: originalImage,
                        base64Image: base64Image,
                        preParsedQuestions: preParsedQuestions,
                        modelProvider: selectedAIModel
                    )
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)

                    Text("Start Grading")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
            }
            .padding(.horizontal)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - AI Model Segment Button

    private func aiModelSegmentButton(model: String, icon: String, label: String, description: String) -> some View {
        let isSelected = selectedAIModel == model

        return Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedAIModel = model
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }) {
            VStack(spacing: 8) {
                Image(icon)
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color(UIColor.systemBackground) : Color.clear)
                    .shadow(color: isSelected ? Color.black.opacity(0.1) : Color.clear, radius: 3, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Subject badge
            if let subject = viewModel.state.subject {
                HStack(spacing: 8) {
                    Image(systemName: subjectIcon(for: subject))
                        .font(.headline)

                    Text(subject)
                        .font(.headline)
                        .fontWeight(.semibold)

                    if viewModel.state.subjectConfidence > 0.8 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(subjectColor(for: subject))
                .cornerRadius(20)
            }

            // Question count
            Text("\(viewModel.totalQuestions) Questions")
                .font(.title2)
                .fontWeight(.bold)

            // Accuracy badge (shown after grading starts)
            if viewModel.gradedCount > 0 {
                AccuracyBadge(
                    correct: viewModel.state.correctCount,
                    total: viewModel.gradedCount
                )
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Grading Progress")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(viewModel.gradedCount)/\(viewModel.totalQuestions)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }

            ProgressView(value: Float(viewModel.gradedCount), total: Float(viewModel.totalQuestions))
                .progressViewStyle(.linear)
                .tint(.blue)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Questions List

    private var questionsListSection: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.state.questions) { questionWithGrade in
                QuestionGradeCard(
                    questionWithGrade: questionWithGrade,
                    croppedImage: getCroppedImage(for: questionWithGrade.id),
                    onAskAI: {
                        viewModel.askAIForHelp(questionId: questionWithGrade.id)
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Collection Button

    private var collectionButtonSection: some View {
        Button {
            viewModel.saveToCollection()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.headline)

                Text("Save to Wrong Answer Book")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.orange, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: .orange.opacity(0.4), radius: 10, y: 5)
        }
        .padding(.horizontal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Error Overlay

    private var errorOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.red)

                Text("Error")
                    .font(.title2)
                    .fontWeight(.bold)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }

                Button("Dismiss") {
                    viewModel.showError = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(30)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(40)
        }
    }

    // MARK: - Helper Methods

    private func getCroppedImage(for questionId: Int) -> UIImage? {
        guard let jpegData = viewModel.state.croppedImages[questionId] else {
            return nil
        }
        return UIImage(data: jpegData)
    }

    private func subjectIcon(for subject: String) -> String {
        switch subject.lowercased() {
        case "mathematics", "math":
            return "function"
        case "physics":
            return "atom"
        case "chemistry":
            return "flask.fill"
        case "biology":
            return "leaf.fill"
        case "english", "language":
            return "book.fill"
        case "history":
            return "clock.fill"
        case "geography":
            return "globe"
        case "computer science", "cs":
            return "laptopcomputer"
        default:
            return "book"
        }
    }

    private func subjectColor(for subject: String) -> Color {
        switch subject.lowercased() {
        case "mathematics", "math":
            return .blue
        case "physics":
            return .purple
        case "chemistry":
            return .green
        case "biology":
            return .mint
        case "english", "language":
            return .orange
        case "history":
            return .brown
        case "geography":
            return .teal
        case "computer science", "cs":
            return .indigo
        default:
            return .gray
        }
    }
}

// MARK: - Question Grade Card Component

struct QuestionGradeCard: View {

    let questionWithGrade: ProgressiveQuestionWithGrade
    let croppedImage: UIImage?
    let onAskAI: () -> Void

    @State private var isExpanded = false
    @State private var showSubquestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Question header with number and grade icon
            HStack {
                Text("Question \(questionWithGrade.id)")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Grade icon or loading indicator
                gradeStatusView
            }

            // Parent or regular question content
            if questionWithGrade.question.isParentQuestion {
                parentQuestionContent
            } else {
                regularQuestionContent
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    // MARK: - Grade Status View

    @ViewBuilder
    private var gradeStatusView: some View {
        if questionWithGrade.isGrading {
            ProgressView()
                .scaleEffect(0.8)
        } else if questionWithGrade.question.isParentQuestion {
            // Parent question: Show overall status
            if questionWithGrade.allSubquestionsGraded {
                ParentGradeIcon(
                    score: questionWithGrade.parentScore ?? 0.0,
                    isCorrect: questionWithGrade.parentIsCorrect ?? false
                )
                .transition(.scale.combined(with: .opacity))
            } else if !questionWithGrade.subquestionErrors.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
            }
        } else {
            // Regular question: Show single grade
            if let grade = questionWithGrade.grade {
                GradeIcon(grade: grade)
                    .transition(.scale.combined(with: .opacity))
            } else if questionWithGrade.gradingError != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
            }
        }
    }

    // MARK: - Parent Question Content

    @ViewBuilder
    private var parentQuestionContent: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Parent instruction text
            Text(questionWithGrade.question.displayText)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Context image (shared by all subquestions)
            if let image = croppedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }

            // Parent score summary (if all subquestions graded)
            if questionWithGrade.allSubquestionsGraded, let score = questionWithGrade.parentScore {
                HStack {
                    Text("Overall Score:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(String(format: "%.1f / 1.0", score))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(scoreColor(for: score, isCorrect: questionWithGrade.parentIsCorrect ?? false))
                }
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(6)
            }

            // Subquestions toggle button
            if let subquestions = questionWithGrade.question.subquestions {
                Button {
                    withAnimation(.spring()) {
                        showSubquestions.toggle()
                    }
                } label: {
                    HStack {
                        Text("View Subquestions (\(subquestions.count))")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        // Progress indicator
                        if questionWithGrade.allSubquestionsGraded {
                            Text("\(questionWithGrade.gradedSubquestionsCount)/\(questionWithGrade.totalSubquestionsCount)")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("\(questionWithGrade.gradedSubquestionsCount)/\(questionWithGrade.totalSubquestionsCount)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }

                        Image(systemName: showSubquestions ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .foregroundColor(.primary)
            }

            // Expanded subquestions list
            if showSubquestions, let subquestions = questionWithGrade.question.subquestions {
                VStack(spacing: 12) {
                    ForEach(subquestions) { subquestion in
                        let _ = {
                            // 🔍 DEBUG: Log dictionary retrieval
                            print("")
                            print("   " + String(repeating: "=", count: 70))
                            print("   🔍 === RETRIEVING GRADE FROM DICTIONARY (View Rendering) ===")
                            print("   " + String(repeating: "=", count: 70))
                            print("   🔑 Dictionary Key (subquestion.id): '\(subquestion.id)'")
                            print("   📚 Available keys in dictionary: \(questionWithGrade.subquestionGrades.keys.sorted())")

                            if let retrievedGrade = questionWithGrade.subquestionGrades[subquestion.id] {
                                print("   ✅ Grade FOUND in dictionary")
                                print("   📊 Score: \(retrievedGrade.score)")
                                print("   ✓ Is Correct: \(retrievedGrade.isCorrect)")
                                print("   💬 Feedback: '\(retrievedGrade.feedback)'")
                                print("   🔍 Feedback length: \(retrievedGrade.feedback.count) chars")
                                print("   🔍 Feedback is empty: \(retrievedGrade.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")
                            } else {
                                print("   ❌ Grade NOT FOUND in dictionary for key: '\(subquestion.id)'")
                                print("   ⚠️ This will cause the ProgressiveSubquestionCard to receive nil grade!")
                            }
                            print("   " + String(repeating: "=", count: 70))
                            print("")
                        }()

                        ProgressiveSubquestionCard(
                            subquestion: subquestion,
                            grade: questionWithGrade.subquestionGrades[subquestion.id],
                            isGrading: questionWithGrade.subquestionGradingStatus[subquestion.id] ?? false,
                            error: questionWithGrade.subquestionErrors[subquestion.id]
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Error messages for parent question
            if !questionWithGrade.subquestionErrors.isEmpty {
                Text("Some subquestions failed to grade")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
            }
        }
    }

    // MARK: - Regular Question Content

    @ViewBuilder
    private var regularQuestionContent: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Question text
            Text(questionWithGrade.question.displayText)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Context image (if exists)
            if let image = croppedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }

            // Student answer
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Answer:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(questionWithGrade.question.displayStudentAnswer.isEmpty ? "No answer" : questionWithGrade.question.displayStudentAnswer)
                    .font(.body)
                    .foregroundColor(questionWithGrade.question.displayStudentAnswer.isEmpty ? .red : .primary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(6)
            }

            // Grade details (if graded)
            if let grade = questionWithGrade.grade {
                gradeDetailsSection(grade: grade)
            }

            // Error message (if failed)
            if let error = questionWithGrade.gradingError {
                Text("Grading error: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
        }
    }

    // MARK: - Grade Details Section

    @ViewBuilder
    private func gradeDetailsSection(grade: ProgressiveGradeResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            // Score display
            HStack {
                Text("Score:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(String(format: "%.1f / 1.0", grade.score))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(scoreColor(for: grade.score, isCorrect: grade.isCorrect))
            }

            // Feedback toggle
            Button {
                withAnimation(.spring()) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("AI Feedback")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            // Expanded feedback
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(grade.feedback)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    // Ask AI button
                    Button {
                        onAskAI()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                            Text("Ask AI for Help")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helper Methods

    private func scoreColor(for score: Float, isCorrect: Bool) -> Color {
        if isCorrect { return .green }
        if score >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - Progressive Subquestion Card Component

struct ProgressiveSubquestionCard: View {

    let subquestion: ProgressiveSubquestion
    let grade: ProgressiveGradeResult?
    let isGrading: Bool
    let error: String?

    @State private var isExpanded = true  // ✅ Changed: Show feedback by default

    var body: some View {
        let _ = {
            // 🔍 DEBUG: Log what the Card component receives
            print("")
            print("   " + String(repeating: "=", count: 70))
            print("   🎴 === PROGRESSIVE SUBQUESTION CARD RENDERING ===")
            print("   " + String(repeating: "=", count: 70))
            print("   🆔 Subquestion ID: '\(subquestion.id)'")
            print("   📝 Question Text: '\(subquestion.questionText.prefix(50))...'")
            print("   📝 Student Answer: '\(subquestion.studentAnswer)'")

            if let grade = grade {
                print("   ✅ Grade parameter: NOT NIL")
                print("   📊 Score: \(grade.score)")
                print("   ✓ Is Correct: \(grade.isCorrect)")
                print("   💬 Feedback: '\(grade.feedback)'")
                print("   🔍 Feedback length: \(grade.feedback.count) chars")
                print("   🔍 Feedback is empty: \(grade.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")
                print("   🔍 isExpanded state: \(isExpanded)")

                // Check if feedback will be displayed
                if isExpanded && !grade.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("   ✅ FEEDBACK SHOULD BE VISIBLE IN UI")
                } else if !isExpanded {
                    print("   ⚠️ FEEDBACK HIDDEN because isExpanded = false")
                } else if grade.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("   ⚠️ FEEDBACK HIDDEN because feedback is empty")
                }
            } else {
                print("   ❌ Grade parameter: NIL (Card will only show question, no grade/feedback)")
            }

            if isGrading {
                print("   🔄 isGrading: true (showing progress spinner)")
            }

            if let error = error {
                print("   ❌ Error: '\(error)'")
            }

            print("   " + String(repeating: "=", count: 70))
            print("")
        }()

        VStack(alignment: .leading, spacing: 8) {

            // Subquestion header
            HStack {
                Text(subquestion.id)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)

                Spacer()

                // Grade status
                if isGrading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if let grade = grade {
                    Circle()
                        .fill(grade.isCorrect ? Color.green : (grade.score >= 0.5 ? Color.orange : Color.red))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: grade.isCorrect ? "checkmark" : (grade.score >= 0.5 ? "minus" : "xmark"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        )
                } else if error != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }

            // Question text
            Text(subquestion.questionText)
                .font(.caption)
                .foregroundColor(.primary)

            // Student answer
            HStack {
                Text("Answer:")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(subquestion.studentAnswer.isEmpty ? "No answer" : subquestion.studentAnswer)
                    .font(.caption)
                    .foregroundColor(subquestion.studentAnswer.isEmpty ? .red : .primary)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.quaternarySystemFill))
            .cornerRadius(4)

            // Grade details (if graded)
            if let grade = grade {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Score:")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(String(format: "%.1f", grade.score))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(grade.isCorrect ? .green : (grade.score >= 0.5 ? .orange : .red))
                    }

                    // Feedback toggle
                    Button {
                        withAnimation(.spring()) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Feedback")
                                .font(.caption2)
                                .fontWeight(.medium)

                            // ✅ NEW: Show badge if feedback exists
                            if !grade.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 6, height: 6)
                            }

                            Spacer()

                            Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }

                    // Expanded feedback
                    if isExpanded {
                        Text(grade.feedback)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            // Error message
            if let error = error {
                Text("Error: \(error)")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Parent Grade Icon Component

struct ParentGradeIcon: View {

    let score: Float
    let isCorrect: Bool

    @State private var scale: CGFloat = 0.1
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 40, height: 40)

            Image(systemName: iconName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1.0
                rotation = 360
            }
        }
    }

    private var backgroundColor: Color {
        if isCorrect { return .green }
        if score >= 0.5 { return .orange }
        return .red
    }

    private var iconName: String {
        if isCorrect { return "checkmark" }
        if score >= 0.5 { return "minus" }
        return "xmark"
    }
}

// MARK: - Grade Icon Component

struct GradeIcon: View {

    let grade: ProgressiveGradeResult

    @State private var scale: CGFloat = 0.1
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 40, height: 40)

            Image(systemName: iconName)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .scaleEffect(scale)
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                scale = 1.0
                rotation = 360
            }
        }
    }

    private var backgroundColor: Color {
        if grade.isCorrect { return .green }
        if grade.score >= 0.5 { return .orange }
        return .red
    }

    private var iconName: String {
        if grade.isCorrect { return "checkmark" }
        if grade.score >= 0.5 { return "minus" }
        return "xmark"
    }
}

// MARK: - Accuracy Badge Component

struct AccuracyBadge: View {

    let correct: Int
    let total: Int

    var accuracy: Float {
        guard total > 0 else { return 0.0 }
        return Float(correct) / Float(total)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Accuracy")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("\(Int(accuracy * 100))%")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(accuracyColor)

            Text("(\(correct)/\(total))")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(accuracyColor.opacity(0.1))
        )
    }

    private var accuracyColor: Color {
        if accuracy >= 0.8 { return .green }
        if accuracy >= 0.6 { return .orange }
        return .red
    }
}

// MARK: - Preview

struct ProgressiveHomeworkView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ProgressiveHomeworkView(
                originalImage: UIImage(systemName: "photo")!,
                base64Image: ""
            )
        }
    }
}
