//
//  ArchivedQuestionsView.swift
//  StudyAI
//
//  Created by Claude Code on 9/4/25.
//

import SwiftUI

// MARK: - Grouped Question Structure for Parent-Child Display

struct QuestionGroup: Identifiable {
    let id: String
    let parentQuestion: QuestionSummary?  // nil for standalone questions
    let subquestions: [QuestionSummary]

    var displayQuestion: QuestionSummary {
        return parentQuestion ?? subquestions[0]
    }

    var hasSubquestions: Bool {
        return parentQuestion != nil && subquestions.count > 1
    }
}

struct ArchivedQuestionsView: View {
    // ⚠️ REMOVED: @EnvironmentObject var appState (no longer needed after removing "Ask AI" button)
    @State private var questions: [QuestionSummary] = []
    @State private var questionGroups: [QuestionGroup] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var selectedSubject: String? = nil
    @State private var searchText = ""
    @State private var expandedGroups: Set<String> = []  // Track expanded parent questions

    private let subjects = ["Math", "Physics", "Chemistry", "Biology", "English", "History", "Other"]
    
    var body: some View {
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
        List(filteredQuestionGroups, id: \.id) { group in
            if group.hasSubquestions {
                // Parent question with subquestions - expandable
                parentQuestionRow(group: group)
            } else {
                // Standalone question - navigate directly
                NavigationLink(destination: QuestionDetailView(questionId: group.displayQuestion.id)) {
                    CompactQuestionCard(question: group.displayQuestion)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        }
        .listStyle(PlainListStyle())
    }

    // MARK: - Parent Question Row (Expandable)

    @ViewBuilder
    private func parentQuestionRow(group: QuestionGroup) -> some View {
        let isExpanded = expandedGroups.contains(group.id)

        VStack(spacing: 0) {
            // Parent question header (tappable to expand/collapse)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if isExpanded {
                        expandedGroups.remove(group.id)
                    } else {
                        expandedGroups.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .frame(width: 20)

                    // Parent question card
                    if let parentQuestion = group.parentQuestion {
                        CompactQuestionCard(question: parentQuestion, isParent: true, subquestionCount: group.subquestions.count)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            // Subquestions (shown when expanded)
            if isExpanded {
                ForEach(group.subquestions, id: \.id) { subquestion in
                    NavigationLink(destination: QuestionDetailView(questionId: subquestion.id)) {
                        HStack(spacing: 12) {
                            // Indent to show hierarchy
                            Color.clear.frame(width: 32)

                            VStack(alignment: .leading, spacing: 4) {
                                // Subquestion ID badge (e.g., "1a", "1b")
                                if let subqId = subquestion.subquestionId {
                                    Text(subqId)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                }

                                // Subquestion content
                                CompactQuestionCard(question: subquestion, isSubquestion: true)
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                }
            }
        }
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

    /// Group questions by parent-child relationships
    private var filteredQuestionGroups: [QuestionGroup] {
        let filtered = filteredQuestions

        // Separate subquestions from standalone/parent questions
        var subquestionsByParent: [Int: [QuestionSummary]] = [:]
        var standaloneQuestions: [QuestionSummary] = []

        for question in filtered {
            if let parentId = question.parentQuestionId {
                // This is a subquestion - group by parent ID
                subquestionsByParent[parentId, default: []].append(question)
            } else {
                // Standalone question or parent question
                standaloneQuestions.append(question)
            }
        }

        // Build groups
        var groups: [QuestionGroup] = []

        for question in standaloneQuestions {
            // Check if this question has subquestions
            if let parentId = extractParentIdFromQuestion(question),
               let subquestions = subquestionsByParent[parentId],
               !subquestions.isEmpty {
                // This is a parent question with subquestions
                let sortedSubquestions = subquestions.sorted {
                    ($0.subquestionId ?? "") < ($1.subquestionId ?? "")
                }
                groups.append(QuestionGroup(
                    id: "parent-\(parentId)",
                    parentQuestion: question,
                    subquestions: sortedSubquestions
                ))
            } else {
                // This is a standalone question (no subquestions)
                groups.append(QuestionGroup(
                    id: question.id,
                    parentQuestion: nil,
                    subquestions: [question]
                ))
            }
        }

        // Sort groups by archived date (most recent first)
        return groups.sorted {
            $0.displayQuestion.archivedAt > $1.displayQuestion.archivedAt
        }
    }

    /// Extract parent ID from standalone question (heuristic approach)
    /// Since parent questions aren't explicitly marked, we use question ID matching
    private func extractParentIdFromQuestion(_ question: QuestionSummary) -> Int? {
        // Try to parse the question ID to get a numeric parent ID
        // This is a heuristic - in reality, we'd need the parent to store its own ID
        // For now, we'll use the archived subquestions' parentQuestionId as the source of truth
        return nil  // Will be populated from subquestions' parentQuestionId
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
    var isParent: Bool = false
    var isSubquestion: Bool = false
    var subquestionCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row
            HStack {
                // Subject Badge (for parent questions or standalone)
                if !isSubquestion {
                    Text(shortSubject)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(subjectColor.opacity(0.2))
                        .foregroundColor(subjectColor)
                        .cornerRadius(4)
                }

                // Parent indicator badge
                if isParent && subquestionCount > 0 {
                    Text("\(subquestionCount) parts")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }

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
            EnhancedMathText(question.rawQuestionText ?? question.questionText, fontSize: isSubquestion ? 13 : 14)
                .lineLimit(isParent ? 1 : 2)
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
        .padding(isSubquestion ? 8 : 12)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isParent ? Color.blue.opacity(0.3) : Color.gray.opacity(0.15), lineWidth: isParent ? 1 : 0.5)
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
    var preloadedSummary: QuestionSummary? = nil  // bypass ID lookup for library nav
    // ⚠️ REMOVED: @EnvironmentObject var appState (no longer needed after removing "Ask AI" button)
    @State private var question: ArchivedQuestion?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var proModeImage: UIImage?  // ✅ For Pro Mode cropped images
    @State private var hasStartedLoading = false  // guard against double onAppear

    var body: some View {
        return ScrollView {
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
        .onAppear {
            guard !hasStartedLoading else { return }
            hasStartedLoading = true
            loadQuestion()
        }
    }

    // MARK: - Type-Specific Renderer

    @ViewBuilder
    private func typeSpecificQuestionRenderer(for question: ArchivedQuestion) -> some View {
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

            // ⚠️ SIMPLIFIED: Removed QuestionTypeRendererSelector to avoid "Ask AI" button crash
            // Display question content with student answer, correct answer, and feedback (no interactive buttons)

            // Question section
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

                EnhancedMathText(question.rawQuestionText ?? question.questionText, fontSize: 16)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)

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

                    EnhancedMathText(studentAnswer, fontSize: 16)
                        .foregroundColor(.primary)  // ✅ Adaptive color for dark mode
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

                EnhancedMathText(question.answerText, fontSize: 16)
                    .foregroundColor(.primary)  // ✅ Adaptive color for dark mode
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

                    EnhancedMathText(feedback, fontSize: 16)
                        .foregroundColor(.primary)  // ✅ Adaptive color for dark mode
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
                        .foregroundColor(.primary)  // ✅ Adaptive color for dark mode
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
                        .foregroundColor(.primary)  // ✅ Adaptive color for dark mode
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
                    .foregroundColor(.primary)  // ✅ Adaptive color for dark mode
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
                        .foregroundColor(.primary)  // ✅ Adaptive color for dark mode
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
                    .foregroundColor(.primary)  // ✅ Adaptive color for dark mode
                    .textSelection(.enabled)
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(12)
        }
    }

    // MARK: - Data Loading

    private func loadQuestion() {
        // If we were given the summary directly from the library, convert it
        // without an ID lookup — avoids the ambiguity of bare subquestion IDs
        if let summary = preloadedSummary {
            let converted = ArchivedQuestion(
                id: summary.id,
                userId: "",
                subject: summary.subject,
                questionText: summary.questionText,
                rawQuestionText: summary.rawQuestionText,
                answerText: summary.answerText ?? "",
                confidence: summary.confidence,
                hasVisualElements: summary.hasVisualElements,
                originalImageUrl: nil,
                questionImageUrl: summary.questionImageUrl,
                processingTime: 0,
                archivedAt: summary.archivedAt,
                reviewCount: summary.reviewCount,
                lastReviewedAt: nil,
                tags: summary.tags,
                notes: nil,
                studentAnswer: summary.studentAnswer,
                grade: summary.grade,
                points: summary.points,
                maxPoints: summary.maxPoints,
                feedback: nil,
                isGraded: summary.isGraded,
                isCorrect: nil,
                questionType: summary.questionType,
                options: summary.options,
                parentQuestionId: summary.parentQuestionId,
                subquestionId: summary.subquestionId
            )
            self.question = converted
            self.isLoading = false

            // Load the question image (same logic as the fetch path below)
            if let imagePath = summary.questionImageUrl, !imagePath.isEmpty,
               let loadedImage = ProModeImageStorage.shared.loadImage(from: imagePath) {
                self.proModeImage = loadedImage
            }

            let hash = QuestionLocalStorage.contentHash(
                subject: summary.subject,
                questionText: summary.questionText,
                studentAnswer: summary.studentAnswer ?? ""
            )
            let log = AppLogger(category: "QuestionDetail")
            log.info("📖 [QuestionDetail] ─────────────────────────────────────")
            log.info("📖 [QuestionDetail] id:            \(summary.id)")
            log.info("📖 [QuestionDetail] subject:       \(summary.subject)")
            log.info("📖 [QuestionDetail] questionType:  \(summary.questionType ?? "nil")")
            log.info("📖 [QuestionDetail] grade:         \(summary.grade?.rawValue ?? "nil")")
            log.info("📖 [QuestionDetail] points:        \(summary.points.map { "\($0)" } ?? "nil") / \(summary.maxPoints.map { "\($0)" } ?? "nil")")
            log.info("📖 [QuestionDetail] studentAnswer: \(summary.studentAnswer ?? "nil")")
            log.info("📖 [QuestionDetail] answerText:    \(summary.answerText ?? "nil")")
            log.info("📖 [QuestionDetail] questionText:  \(summary.questionText.prefix(120))")
            log.info("📖 [QuestionDetail] hasImage:      \(summary.questionImageUrl != nil)")
            log.info("📖 [QuestionDetail] parentId:      \(summary.parentQuestionId.map { "\($0)" } ?? "nil")  subId: \(summary.subquestionId ?? "nil")")
            log.info("📖 [QuestionDetail] contentHash:   \(hash)")
            log.info("📖 [QuestionDetail] ─────────────────────────────────────")
            return
        }

        Task {
            do {
                let fetchedQuestion = try await QuestionArchiveService.shared.getQuestionDetails(questionId: questionId)
                await MainActor.run {
                    if let imagePath = fetchedQuestion.questionImageUrl, !imagePath.isEmpty,
                       let loadedImage = ProModeImageStorage.shared.loadImage(from: imagePath) {
                        self.proModeImage = loadedImage
                    }
                    self.question = fetchedQuestion
                    self.isLoading = false
                    self.errorMessage = nil

                    let hash = QuestionLocalStorage.contentHash(
                        subject: fetchedQuestion.subject,
                        questionText: fetchedQuestion.questionText,
                        studentAnswer: fetchedQuestion.studentAnswer ?? ""
                    )
                    let log = AppLogger(category: "QuestionDetail")
                    log.info("📖 [QuestionDetail] ─────────────────────────────────────")
                    log.info("📖 [QuestionDetail] id:            \(fetchedQuestion.id)")
                    log.info("📖 [QuestionDetail] subject:       \(fetchedQuestion.subject)")
                    log.info("📖 [QuestionDetail] questionType:  \(fetchedQuestion.questionType ?? "nil")")
                    log.info("📖 [QuestionDetail] grade:         \(fetchedQuestion.grade?.rawValue ?? "nil")")
                    log.info("📖 [QuestionDetail] points:        \(fetchedQuestion.points.map { "\($0)" } ?? "nil") / \(fetchedQuestion.maxPoints.map { "\($0)" } ?? "nil")")
                    log.info("📖 [QuestionDetail] studentAnswer: \(fetchedQuestion.studentAnswer ?? "nil")")
                    log.info("📖 [QuestionDetail] answerText:    \(fetchedQuestion.answerText)")
                    log.info("📖 [QuestionDetail] questionText:  \(fetchedQuestion.questionText.prefix(120))")
                    log.info("📖 [QuestionDetail] hasImage:      \(fetchedQuestion.questionImageUrl != nil)")
                    log.info("📖 [QuestionDetail] parentId:      \(fetchedQuestion.parentQuestionId.map { "\($0)" } ?? "nil")  subId: \(fetchedQuestion.subquestionId ?? "nil")")
                    log.info("📖 [QuestionDetail] contentHash:   \(hash)")
                    log.info("📖 [QuestionDetail] ─────────────────────────────────────")
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Helper Methods

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