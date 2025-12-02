//
//  ArchivedQuestionsView.swift
//  StudyAI
//
//  Created by Claude Code on 9/4/25.
//

import SwiftUI

struct ArchivedQuestionsView: View {
    @State private var questions: [QuestionSummary] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var selectedSubject: String? = nil
    @State private var searchText = ""
    
    private let subjects = ["Math", "Physics", "Chemistry", "Biology", "English", "History", "Other"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Compact Filter Bar
                if !questions.isEmpty {
                    filterBar
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                // Content
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if questions.isEmpty {
                    emptyState
                } else {
                    questionsList
                }
            }
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadQuestions() }
        }
    }
    
    // MARK: - Compact Filter Bar
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.gray)
                    TextField("Search", text: $searchText)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .frame(width: 100)
                
                // Subject Pills
                ForEach(subjects, id: \.self) { subject in
                    Button(subject) {
                        selectedSubject = selectedSubject == subject ? nil : subject
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(selectedSubject == subject ? Color.blue : Color.gray.opacity(0.1))
                    .foregroundColor(selectedSubject == subject ? .white : .primary)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Questions List
    
    private var questionsList: some View {
        List(filteredQuestions, id: \.id) { question in
            NavigationLink(destination: QuestionDetailView(questionId: question.id)) {
                CompactQuestionCard(question: question)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("No archived questions")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("Archive questions to review later")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Computed Properties
    
    private var filteredQuestions: [QuestionSummary] {
        questions.filter { question in
            let matchesSubject = selectedSubject == nil || question.subject.contains(selectedSubject!)
            let matchesSearch = searchText.isEmpty ||
                question.questionText.localizedCaseInsensitiveContains(searchText) ||
                question.rawQuestionText?.localizedCaseInsensitiveContains(searchText) == true ||
                question.subject.localizedCaseInsensitiveContains(searchText)
            return matchesSubject && matchesSearch
        }
    }
    
    // MARK: - Actions
    
    private func loadQuestions() {
        isLoading = true
        Task {
            do {
                let fetchedQuestions = try await QuestionArchiveService.shared.fetchArchivedQuestions(limit: 100)
                await MainActor.run {
                    self.questions = fetchedQuestions
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Compact Question Card

struct CompactQuestionCard: View {
    let question: QuestionSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row
            HStack {
                // Subject Badge
                Text(shortSubject)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(subjectColor.opacity(0.2))
                    .foregroundColor(subjectColor)
                    .cornerRadius(4)
                
                Spacer()
                
                // Confidence & Visual Indicators
                HStack(spacing: 4) {
                    if question.hasVisualElements {
                        Image(systemName: "photo.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    
                    Circle()
                        .fill(confidenceColor)
                        .frame(width: 6, height: 6)
                }
            }
            
            // Question Text
            // ✅ Use EnhancedMathText for LaTeX/math rendering
            EnhancedMathText(question.rawQuestionText ?? question.questionText, fontSize: 14)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // Footer
            HStack {
                Text(timeAgo)
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                Spacer()
                
                if let tags = question.tags, !tags.isEmpty {
                    Text("• \(tags.count)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }
    
    private var shortSubject: String {
        switch question.subject {
        case "Mathematics": return "Math"
        case "Computer Science": return "CS"
        case "Foreign Language": return "Lang"
        default: return question.subject
        }
    }
    
    private var subjectColor: Color {
        switch question.subject {
        case "Mathematics", "Math": return .blue
        case "Physics": return .purple
        case "Chemistry": return .green
        case "Biology": return .orange
        case "English": return .red
        case "History": return .brown
        default: return .gray
        }
    }
    
    private var confidenceColor: Color {
        guard let confidence = question.confidence else { return .gray }
        return confidence > 0.8 ? .green : confidence > 0.6 ? .orange : .red
    }
    
    private var timeAgo: String {
        let now = Date()
        let interval = now.timeIntervalSince(question.archivedAt)
        
        if interval < 3600 { // < 1 hour
            return "\(Int(interval / 60))m"
        } else if interval < 86400 { // < 1 day
            return "\(Int(interval / 3600))h"
        } else {
            return "\(Int(interval / 86400))d"
        }
    }
}

// MARK: - Minimal Question Detail View

struct QuestionDetailView: View {
    let questionId: String
    @State private var question: ArchivedQuestion?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var proModeImage: UIImage?  // ✅ NEW: For Pro Mode cropped images
    @EnvironmentObject var appState: AppState  // ✅ NEW: For Ask AI navigation

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 100)
            } else if let errorMessage = errorMessage {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Failed to Load Question")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Retry") {
                        loadQuestion()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 100)
            } else if let question = question {
                VStack(alignment: .leading, spacing: 16) {
                    // Check if we should use type-specific renderer
                    if let questionType = question.questionType, !questionType.isEmpty {
                        // Use type-specific renderer
                        typeSpecificQuestionRenderer(for: question)
                    } else {
                        // Use default generic renderer
                        defaultQuestionRenderer(for: question)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadQuestion() }
    }

    // MARK: - Type-Specific Renderer

    @ViewBuilder
    private func typeSpecificQuestionRenderer(for question: ArchivedQuestion) -> some View {
        // Debug logging for data conversion (execute before View body)
        let _ = {
            print("🔄 [QuestionDetail] === CONVERTING TO PARSED QUESTION ===")
            print("🔄 [QuestionDetail] Question ID: \(question.id)")
            print("🔄 [QuestionDetail] Has rawQuestionText in ArchivedQuestion: \(question.rawQuestionText != nil)")
            if let rawText = question.rawQuestionText {
                print("🔄 [QuestionDetail] ArchivedQuestion rawQuestionText length: \(rawText.count) chars")
                print("🔄 [QuestionDetail] ArchivedQuestion rawQuestionText: \(rawText)")
            } else {
                print("🔄 [QuestionDetail] ❌ ArchivedQuestion rawQuestionText is NIL")
            }
            print("🔄 [QuestionDetail] ArchivedQuestion questionText length: \(question.questionText.count) chars")
            print("🔄 [QuestionDetail] ArchivedQuestion questionText: \(question.questionText)")
        }()

        VStack(alignment: .leading, spacing: 16) {
            // Header with subject and grade
            questionHeader(for: question)

            // ✅ NEW: Pro Mode Image Display
            if let image = proModeImage {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Question Image")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            }

            // Convert ArchivedQuestion to ParsedQuestion for renderer
            let parsedQuestion = ParsedQuestion(
                questionNumber: nil,
                rawQuestionText: question.rawQuestionText,
                questionText: question.questionText,
                answerText: question.answerText,
                confidence: question.confidence,
                hasVisualElements: question.hasVisualElements,
                studentAnswer: question.studentAnswer,
                correctAnswer: question.answerText,
                grade: question.grade?.rawValue,
                pointsEarned: question.points,
                pointsPossible: question.maxPoints,
                feedback: question.feedback,
                questionType: question.questionType,
                options: question.options
            )

            // Debug logging for ParsedQuestion (execute before View body)
            let _ = {
                print("🔄 [QuestionDetail] ParsedQuestion has rawQuestionText: \(parsedQuestion.rawQuestionText != nil)")
                if let rawText = parsedQuestion.rawQuestionText {
                    print("🔄 [QuestionDetail] ParsedQuestion rawQuestionText length: \(rawText.count) chars")
                }
            }()

            // Use QuestionTypeRendererSelector to render based on type
            QuestionTypeRendererSelector(
                question: parsedQuestion,
                isExpanded: true,
                onTapAskAI: { askAIForHelp() }  // ✅ NEW: Proper Ask AI implementation
            )

            // User notes and tags
            userNotesAndTags(for: question)
        }
    }

    // MARK: - Default Generic Renderer

    @ViewBuilder
    private func defaultQuestionRenderer(for question: ArchivedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with subject and grade (shared component)
            questionHeader(for: question)

            // ✅ NEW: Pro Mode Image Display (same as type-specific renderer)
            if let image = proModeImage {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Question Image")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
            }

            // Question (Full original text from image)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Q")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.blue)
                        .cornerRadius(4)

                    Text("Question")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Spacer()
                }

                // ✅ Use EnhancedMathText for LaTeX/math rendering
                EnhancedMathText(question.rawQuestionText ?? question.questionText, fontSize: 16)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)

            // Raw Question (Full original text from image)
            if let rawText = question.rawQuestionText, rawText != question.questionText {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("Original Question")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Text(rawText)
                        .font(.callout)
                        .foregroundColor(.black)
                        .textSelection(.enabled)
                }
                .padding()
                .background(Color.gray.opacity(0.03))
                .cornerRadius(12)
            }

            // Student Answer
            if let studentAnswer = question.studentAnswer, !studentAnswer.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("Student Answer")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    // ✅ Use EnhancedMathText for math support in student answers
                    EnhancedMathText(studentAnswer, fontSize: 16)
                        .foregroundColor(.black)
                        .textSelection(.enabled)
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
            }

            // Correct Answer with Feedback
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("A")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.green)
                        .cornerRadius(4)

                    Text("Correct Answer")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                // ✅ Use EnhancedMathText for LaTeX/math rendering in answers
                EnhancedMathText(question.answerText, fontSize: 16)
                    .foregroundColor(.black)
                    .textSelection(.enabled)

                // AI Feedback (if available and not empty)
                if let feedback = question.feedback, !feedback.isEmpty, feedback != "No feedback provided" {
                    Divider()
                        .padding(.vertical, 4)

                    HStack {
                        Image(systemName: "bubble.left.fill")
                            .font(.caption)
                            .foregroundColor(.purple)
                        Text("AI Feedback")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    // ✅ Use EnhancedMathText for math support in feedback
                    EnhancedMathText(feedback, fontSize: 16)
                        .foregroundColor(.black)
                        .textSelection(.enabled)
                }
            }
            .padding()
            .background(Color.green.opacity(0.05))
            .cornerRadius(12)

            // User notes and tags
            userNotesAndTags(for: question)
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func questionHeader(for question: ArchivedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Grading Badge (if graded)
            if question.isGraded, let grade = question.grade {
                HStack(spacing: 8) {
                    Image(systemName: gradeIcon(grade))
                        .foregroundColor(gradeColor(grade))
                    Text(grade.displayName)
                        .font(.headline)
                        .foregroundColor(gradeColor(grade))
                    if let points = question.points, let maxPoints = question.maxPoints {
                        Text("(\(String(format: "%.1f", points))/\(String(format: "%.1f", maxPoints)))")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }
                .padding()
                .background(gradeColor(grade).opacity(0.1))
                .cornerRadius(12)
            }

            // Subject and confidence indicator
            HStack {
                Text(question.subject)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)

                Spacer()

                Circle()
                    .fill(confidenceColor(question.confidence))
                    .frame(width: 8, height: 8)
            }
        }
    }

    @ViewBuilder
    private func userNotesAndTags(for question: ArchivedQuestion) -> some View {
        // Tags (if any)
        if let tags = question.tags, !tags.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
            }
        }

        // Notes (if any)
        if let notes = question.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Your Notes")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Text(notes)
                    .font(.callout)
                    .foregroundColor(.black)
                    .textSelection(.enabled)
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(12)
        }
    }

    // MARK: - Data Loading

    private func loadQuestion() {
        print("🔍 [QuestionDetail] Loading question: \(questionId)")

        Task {
            do {
                let fetchedQuestion = try await QuestionArchiveService.shared.getQuestionDetails(questionId: questionId)
                await MainActor.run {
                    print("✅ [QuestionDetail] Loaded question successfully")
                    print("📋 [QuestionDetail] Question subject: \(fetchedQuestion.subject)")
                    print("📋 [QuestionDetail] Question text length: \(fetchedQuestion.questionText.count) chars")
                    print("📋 [QuestionDetail] Has rawQuestionText: \(fetchedQuestion.rawQuestionText != nil)")
                    if let rawText = fetchedQuestion.rawQuestionText {
                        print("📋 [QuestionDetail] rawQuestionText length: \(rawText.count) chars")
                        print("📋 [QuestionDetail] rawQuestionText value: \(rawText)")
                    } else {
                        print("📋 [QuestionDetail] ❌ rawQuestionText is NIL in loaded question")
                    }
                    print("📋 [QuestionDetail] questionText value: \(fetchedQuestion.questionText)")

                    // ✅ NEW: Load Pro Mode image if available
                    if let imagePath = fetchedQuestion.questionImageUrl, !imagePath.isEmpty {
                        print("🖼️ [QuestionDetail] Found questionImageUrl: \(imagePath)")
                        if let loadedImage = ProModeImageStorage.shared.loadImage(from: imagePath) {
                            print("✅ [QuestionDetail] Successfully loaded Pro Mode image")
                            self.proModeImage = loadedImage
                        } else {
                            print("⚠️ [QuestionDetail] Failed to load Pro Mode image from path")
                        }
                    } else {
                        print("📋 [QuestionDetail] No Pro Mode image path found")
                    }

                    self.question = fetchedQuestion
                    self.isLoading = false
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    print("❌ [QuestionDetail] Failed to load question")
                    print("❌ [QuestionDetail] Question ID: \(questionId)")
                    print("❌ [QuestionDetail] Error: \(error)")
                    print("❌ [QuestionDetail] Error description: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Ask AI for Help

    /// Navigate to chat with question context (similar to Digital Homework implementation)
    private func askAIForHelp() {
        guard let question = question else { return }

        // Build HomeworkQuestionContext from archived question
        let context = HomeworkQuestionContext(
            questionText: question.questionText,
            rawQuestionText: question.rawQuestionText,
            studentAnswer: question.studentAnswer,
            correctAnswer: question.correctAnswer,  // Use correctAnswer field (this is the bug we're tracking)
            currentGrade: question.grade.map { grade in
                // Map GradeResult to string
                switch grade {
                case .correct: return "CORRECT"
                case .incorrect: return "INCORRECT"
                case .empty: return "EMPTY"
                case .partialCredit: return "PARTIAL_CREDIT"
                }
            },
            originalFeedback: question.feedback,
            pointsEarned: question.points,
            pointsPossible: question.maxPoints,
            questionNumber: nil,  // Archived questions don't have question numbers
            subject: question.subject,
            questionImage: proModeImage  // Include Pro Mode cropped image if available
        )

        // Build user message for AI (localized)
        let hasGrade = question.grade != nil
        let gradeText = question.grade.map { grade in
            switch grade {
            case .correct: return NSLocalizedString("homeworkResults.correct", comment: "")
            case .incorrect: return NSLocalizedString("homeworkResults.incorrect", comment: "")
            case .empty: return NSLocalizedString("homeworkResults.empty", comment: "")
            case .partialCredit: return NSLocalizedString("homeworkResults.partialCredit", comment: "")
            }
        } ?? ""

        let message = """
\(NSLocalizedString("proMode.askAIPrompt", comment: "")):

\(NSLocalizedString("homeworkResults.rawQuestion", comment: ""))\(question.rawQuestionText ?? question.questionText)

\(NSLocalizedString("homeworkResults.studentAnswer", comment: ""))\(question.studentAnswer ?? NSLocalizedString("homeworkResults.noAnswerProvided", comment: ""))

\(hasGrade ? "\(NSLocalizedString("homeworkResults.feedback", comment: ""))\(question.feedback ?? NSLocalizedString("proMode.noFeedback", comment: ""))\n\n\(gradeText)" : "")
"""

        // Navigate to chat with homework context
        appState.navigateToChatWithHomeworkQuestion(message: message, context: context)

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }

    private func confidenceColor(_ confidence: Float?) -> Color {
        guard let confidence = confidence else { return .gray }
        return confidence > 0.8 ? .green : confidence > 0.6 ? .orange : .red
    }

    private func gradeIcon(_ grade: GradeResult) -> String {
        switch grade {
        case .correct: return "checkmark.circle.fill"
        case .incorrect: return "xmark.circle.fill"
        case .empty: return "minus.circle.fill"
        case .partialCredit: return "checkmark.circle"
        }
    }

    private func gradeColor(_ grade: GradeResult) -> Color {
        switch grade {
        case .correct: return .green
        case .incorrect: return .red
        case .empty: return .gray
        case .partialCredit: return .orange
        }
    }
}

#Preview {
    ArchivedQuestionsView()
}