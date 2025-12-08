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
    // ⚠️ REMOVED: @EnvironmentObject var appState (no longer needed after removing "Ask AI" button)
    @State private var question: ArchivedQuestion?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var proModeImage: UIImage?  // ✅ For Pro Mode cropped images

    var body: some View {
        // 🔍 DEBUG: Log when QuestionDetailView body is evaluated
        let _ = print("🔍 [QuestionDetailView] Body evaluated for question ID: \(questionId)")

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
                    // 🎨 DEBUG: Log renderer selection
                    let _ = {
                        print("")
                        print("🎨 [QuestionDetailView] ========================================")
                        print("🎨 [QuestionDetailView] RENDERER SELECTION")
                        print("🎨 [QuestionDetailView] ========================================")
                        print("🎨 [QuestionDetailView] Question Type: \(question.questionType ?? "nil")")
                        print("🎨 [QuestionDetailView] Is Empty: \(question.questionType?.isEmpty ?? true)")
                        if let questionType = question.questionType, !questionType.isEmpty {
                            print("🎨 [QuestionDetailView] ✅ Using TYPE-SPECIFIC renderer for type: \(questionType)")
                        } else {
                            print("🎨 [QuestionDetailView] ⚠️ Using DEFAULT GENERIC renderer (no question type)")
                        }
                        print("🎨 [QuestionDetailView] ========================================")
                        print("")
                    }()

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
        // Debug logging for data conversion and rendering decisions
        let _ = {
            print("")
            print("🎨 [TypeSpecificRenderer] ========================================")
            print("🎨 [TypeSpecificRenderer] RENDERING TYPE-SPECIFIC QUESTION")
            print("🎨 [TypeSpecificRenderer] ========================================")
            print("🎨 [TypeSpecificRenderer] Question ID: \(question.id)")
            print("🎨 [TypeSpecificRenderer] Question Type: \(question.questionType ?? "nil")")

            // Pro Mode Image
            print("")
            print("🖼️ [TypeSpecificRenderer] === PRO MODE IMAGE DISPLAY ===")
            if proModeImage != nil {
                print("🖼️ [TypeSpecificRenderer] ✅ WILL DISPLAY Pro Mode image")
            } else {
                print("🖼️ [TypeSpecificRenderer] ⚠️ WILL NOT DISPLAY Pro Mode image (image is nil)")
            }

            // Question Section
            print("")
            print("📝 [TypeSpecificRenderer] === QUESTION SECTION ===")
            print("📝 [TypeSpecificRenderer] ✅ WILL DISPLAY question section")
            print("📝 [TypeSpecificRenderer] Using text: \(question.rawQuestionText != nil ? "rawQuestionText" : "questionText")")
            let displayText = question.rawQuestionText ?? question.questionText
            print("📝 [TypeSpecificRenderer] Text length: \(displayText.count) chars")

            // Student Answer
            print("")
            print("👤 [TypeSpecificRenderer] === STUDENT ANSWER SECTION ===")
            if let studentAnswer = question.studentAnswer, !studentAnswer.isEmpty {
                print("👤 [TypeSpecificRenderer] ✅ WILL DISPLAY student answer")
                print("👤 [TypeSpecificRenderer] Student answer length: \(studentAnswer.count) chars")
                print("👤 [TypeSpecificRenderer] Student answer: '\(studentAnswer)'")
            } else {
                print("👤 [TypeSpecificRenderer] ⚠️ WILL NOT DISPLAY student answer (nil or empty)")
                print("👤 [TypeSpecificRenderer] Is nil: \(question.studentAnswer == nil)")
                print("👤 [TypeSpecificRenderer] Is empty: \(question.studentAnswer?.isEmpty ?? true)")
            }

            // Correct Answer + Feedback
            print("")
            print("✅ [TypeSpecificRenderer] === CORRECT ANSWER + FEEDBACK SECTION ===")
            print("✅ [TypeSpecificRenderer] ✅ WILL DISPLAY correct answer section")
            print("✅ [TypeSpecificRenderer] Answer text length: \(question.answerText.count) chars")
            print("✅ [TypeSpecificRenderer] Answer text: '\(question.answerText)'")

            if let feedback = question.feedback, !feedback.isEmpty, feedback != "No feedback provided" {
                print("💬 [TypeSpecificRenderer] ✅ WILL DISPLAY feedback inside answer section")
                print("💬 [TypeSpecificRenderer] Feedback length: \(feedback.count) chars")
                print("💬 [TypeSpecificRenderer] Feedback: '\(feedback)'")
            } else {
                print("💬 [TypeSpecificRenderer] ⚠️ WILL NOT DISPLAY feedback (nil, empty, or 'No feedback provided')")
                print("💬 [TypeSpecificRenderer] Is nil: \(question.feedback == nil)")
                print("💬 [TypeSpecificRenderer] Is empty: \(question.feedback?.isEmpty ?? true)")
                print("💬 [TypeSpecificRenderer] Is 'No feedback provided': \(question.feedback == "No feedback provided")")
            }

            print("🎨 [TypeSpecificRenderer] ========================================")
            print("")
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
        // Debug logging for rendering decisions
        let _ = {
            print("")
            print("🎨 [DefaultRenderer] ========================================")
            print("🎨 [DefaultRenderer] RENDERING DEFAULT GENERIC QUESTION")
            print("🎨 [DefaultRenderer] ========================================")
            print("🎨 [DefaultRenderer] Question ID: \(question.id)")

            // Pro Mode Image
            print("")
            print("🖼️ [DefaultRenderer] === PRO MODE IMAGE DISPLAY ===")
            if proModeImage != nil {
                print("🖼️ [DefaultRenderer] ✅ WILL DISPLAY Pro Mode image")
            } else {
                print("🖼️ [DefaultRenderer] ⚠️ WILL NOT DISPLAY Pro Mode image (image is nil)")
            }

            // Question Section
            print("")
            print("📝 [DefaultRenderer] === QUESTION SECTION ===")
            print("📝 [DefaultRenderer] ✅ WILL DISPLAY question section")
            print("📝 [DefaultRenderer] Using text: \(question.rawQuestionText != nil ? "rawQuestionText" : "questionText")")
            let displayText = question.rawQuestionText ?? question.questionText
            print("📝 [DefaultRenderer] Text length: \(displayText.count) chars")

            // Raw Question (Original) Section
            print("")
            print("📄 [DefaultRenderer] === RAW QUESTION (ORIGINAL) SECTION ===")
            if let rawText = question.rawQuestionText, rawText != question.questionText {
                print("📄 [DefaultRenderer] ✅ WILL DISPLAY 'Original Question' section")
                print("📄 [DefaultRenderer] rawQuestionText differs from questionText")
                print("📄 [DefaultRenderer] Raw text length: \(rawText.count) chars")
            } else {
                print("📄 [DefaultRenderer] ⚠️ WILL NOT DISPLAY 'Original Question' section")
                print("📄 [DefaultRenderer] Reason: rawQuestionText is nil or same as questionText")
                print("📄 [DefaultRenderer] rawQuestionText is nil: \(question.rawQuestionText == nil)")
                if question.rawQuestionText != nil {
                    print("📄 [DefaultRenderer] rawQuestionText == questionText: \(question.rawQuestionText == question.questionText)")
                }
            }

            // Student Answer
            print("")
            print("👤 [DefaultRenderer] === STUDENT ANSWER SECTION ===")
            if let studentAnswer = question.studentAnswer, !studentAnswer.isEmpty {
                print("👤 [DefaultRenderer] ✅ WILL DISPLAY student answer")
                print("👤 [DefaultRenderer] Student answer length: \(studentAnswer.count) chars")
                print("👤 [DefaultRenderer] Student answer: '\(studentAnswer)'")
            } else {
                print("👤 [DefaultRenderer] ⚠️ WILL NOT DISPLAY student answer (nil or empty)")
                print("👤 [DefaultRenderer] Is nil: \(question.studentAnswer == nil)")
                print("👤 [DefaultRenderer] Is empty: \(question.studentAnswer?.isEmpty ?? true)")
            }

            // Correct Answer + Feedback
            print("")
            print("✅ [DefaultRenderer] === CORRECT ANSWER + FEEDBACK SECTION ===")
            print("✅ [DefaultRenderer] ✅ WILL DISPLAY correct answer section")
            print("✅ [DefaultRenderer] Answer text length: \(question.answerText.count) chars")
            print("✅ [DefaultRenderer] Answer text: '\(question.answerText)'")

            if let feedback = question.feedback, !feedback.isEmpty, feedback != "No feedback provided" {
                print("💬 [DefaultRenderer] ✅ WILL DISPLAY feedback inside answer section")
                print("💬 [DefaultRenderer] Feedback length: \(feedback.count) chars")
                print("💬 [DefaultRenderer] Feedback: '\(feedback)'")
            } else {
                print("💬 [DefaultRenderer] ⚠️ WILL NOT DISPLAY feedback (nil, empty, or 'No feedback provided')")
                print("💬 [DefaultRenderer] Is nil: \(question.feedback == nil)")
                print("💬 [DefaultRenderer] Is empty: \(question.feedback?.isEmpty ?? true)")
                print("💬 [DefaultRenderer] Is 'No feedback provided': \(question.feedback == "No feedback provided")")
            }

            print("🎨 [DefaultRenderer] ========================================")
            print("")
        }()

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
        print("")
        print("🔍 [QuestionDetail] ========================================")
        print("🔍 [QuestionDetail] LOADING QUESTION DETAILS")
        print("🔍 [QuestionDetail] ========================================")
        print("🔍 [QuestionDetail] Question ID: \(questionId)")

        Task {
            do {
                let fetchedQuestion = try await QuestionArchiveService.shared.getQuestionDetails(questionId: questionId)
                await MainActor.run {
                    print("")
                    print("✅ [QuestionDetail] ========================================")
                    print("✅ [QuestionDetail] QUESTION LOADED SUCCESSFULLY")
                    print("✅ [QuestionDetail] ========================================")

                    // BASIC INFO
                    print("")
                    print("📋 [QuestionDetail] === BASIC INFO ===")
                    print("📋 [QuestionDetail] ID: \(fetchedQuestion.id)")
                    print("📋 [QuestionDetail] Subject: \(fetchedQuestion.subject)")
                    print("📋 [QuestionDetail] Confidence: \(fetchedQuestion.confidence ?? 0.0)")
                    print("📋 [QuestionDetail] Has Visual Elements: \(fetchedQuestion.hasVisualElements)")
                    print("📋 [QuestionDetail] Question Type: \(fetchedQuestion.questionType ?? "nil")")

                    // PARENT-CHILD RELATIONSHIP
                    print("")
                    print("🌳 [QuestionDetail] === PARENT-CHILD RELATIONSHIP ===")
                    print("🌳 [QuestionDetail] Parent Question ID: \(fetchedQuestion.parentQuestionId?.description ?? "nil")")
                    print("🌳 [QuestionDetail] Subquestion ID: \(fetchedQuestion.subquestionId ?? "nil")")
                    print("🌳 [QuestionDetail] Is this a parent question: \(fetchedQuestion.parentQuestionId == nil && fetchedQuestion.subquestionId == nil)")
                    print("🌳 [QuestionDetail] Is this a subquestion: \(fetchedQuestion.parentQuestionId != nil)")

                    // QUESTION TEXT
                    print("")
                    print("📝 [QuestionDetail] === QUESTION TEXT ===")
                    print("📝 [QuestionDetail] questionText length: \(fetchedQuestion.questionText.count) chars")
                    print("📝 [QuestionDetail] questionText: '\(fetchedQuestion.questionText)'")
                    print("📝 [QuestionDetail] Has rawQuestionText: \(fetchedQuestion.rawQuestionText != nil)")
                    if let rawText = fetchedQuestion.rawQuestionText {
                        print("📝 [QuestionDetail] rawQuestionText length: \(rawText.count) chars")
                        print("📝 [QuestionDetail] rawQuestionText: '\(rawText)'")
                    } else {
                        print("📝 [QuestionDetail] ❌ rawQuestionText is NIL")
                    }

                    // STUDENT ANSWER
                    print("")
                    print("👤 [QuestionDetail] === STUDENT ANSWER ===")
                    if let studentAnswer = fetchedQuestion.studentAnswer {
                        print("👤 [QuestionDetail] Has student answer: YES")
                        print("👤 [QuestionDetail] Student answer length: \(studentAnswer.count) chars")
                        print("👤 [QuestionDetail] Student answer: '\(studentAnswer)'")
                        print("👤 [QuestionDetail] Is empty: \(studentAnswer.isEmpty)")
                    } else {
                        print("👤 [QuestionDetail] ❌ Student answer is NIL")
                    }

                    // CORRECT ANSWER
                    print("")
                    print("✅ [QuestionDetail] === CORRECT ANSWER ===")
                    print("✅ [QuestionDetail] answerText length: \(fetchedQuestion.answerText.count) chars")
                    print("✅ [QuestionDetail] answerText: '\(fetchedQuestion.answerText)'")
                    print("✅ [QuestionDetail] Is empty: \(fetchedQuestion.answerText.isEmpty)")

                    // FEEDBACK
                    print("")
                    print("💬 [QuestionDetail] === FEEDBACK ===")
                    if let feedback = fetchedQuestion.feedback {
                        print("💬 [QuestionDetail] Has feedback: YES")
                        print("💬 [QuestionDetail] Feedback length: \(feedback.count) chars")
                        print("💬 [QuestionDetail] Feedback: '\(feedback)'")
                        print("💬 [QuestionDetail] Is empty: \(feedback.isEmpty)")
                        print("💬 [QuestionDetail] Is 'No feedback provided': \(feedback == "No feedback provided")")
                    } else {
                        print("💬 [QuestionDetail] ❌ Feedback is NIL")
                    }

                    // GRADING INFO
                    print("")
                    print("📊 [QuestionDetail] === GRADING INFO ===")
                    print("📊 [QuestionDetail] Is Graded: \(fetchedQuestion.isGraded)")
                    if let grade = fetchedQuestion.grade {
                        print("📊 [QuestionDetail] Grade: \(grade.displayName)")
                        print("📊 [QuestionDetail] Grade raw value: \(grade.rawValue)")
                    } else {
                        print("📊 [QuestionDetail] ❌ Grade is NIL")
                    }
                    if let points = fetchedQuestion.points {
                        print("📊 [QuestionDetail] Points earned: \(points)")
                    } else {
                        print("📊 [QuestionDetail] ❌ Points is NIL")
                    }
                    if let maxPoints = fetchedQuestion.maxPoints {
                        print("📊 [QuestionDetail] Max points: \(maxPoints)")
                    } else {
                        print("📊 [QuestionDetail] ❌ Max points is NIL")
                    }

                    // OPTIONS (for multiple choice)
                    print("")
                    print("🔘 [QuestionDetail] === OPTIONS (Multiple Choice) ===")
                    if let options = fetchedQuestion.options {
                        print("🔘 [QuestionDetail] Has options: YES")
                        print("🔘 [QuestionDetail] Options count: \(options.count)")
                        for (index, option) in options.enumerated() {
                            print("🔘 [QuestionDetail] Option \(index): '\(option)'")
                        }
                    } else {
                        print("🔘 [QuestionDetail] ❌ Options is NIL (not a multiple choice question)")
                    }

                    // METADATA
                    print("")
                    print("🏷️ [QuestionDetail] === METADATA ===")
                    if let tags = fetchedQuestion.tags {
                        print("🏷️ [QuestionDetail] Tags count: \(tags.count)")
                        print("🏷️ [QuestionDetail] Tags: \(tags)")
                    } else {
                        print("🏷️ [QuestionDetail] ❌ Tags is NIL")
                    }
                    if let notes = fetchedQuestion.notes {
                        print("🏷️ [QuestionDetail] Notes length: \(notes.count) chars")
                        print("🏷️ [QuestionDetail] Notes: '\(notes)'")
                    } else {
                        print("🏷️ [QuestionDetail] ❌ Notes is NIL")
                    }
                    print("🏷️ [QuestionDetail] Archived At: \(fetchedQuestion.archivedAt)")

                    // PRO MODE IMAGE
                    print("")
                    print("🖼️ [QuestionDetail] === PRO MODE IMAGE ===")
                    if let imagePath = fetchedQuestion.questionImageUrl, !imagePath.isEmpty {
                        print("🖼️ [QuestionDetail] Has questionImageUrl: YES")
                        print("🖼️ [QuestionDetail] Image path: \(imagePath)")
                        if let loadedImage = ProModeImageStorage.shared.loadImage(from: imagePath) {
                            print("✅ [QuestionDetail] Successfully loaded Pro Mode image")
                            print("🖼️ [QuestionDetail] Image size: \(loadedImage.size.width) x \(loadedImage.size.height)")
                            self.proModeImage = loadedImage
                        } else {
                            print("⚠️ [QuestionDetail] Failed to load Pro Mode image from path")
                        }
                    } else {
                        print("🖼️ [QuestionDetail] ❌ No Pro Mode image path found")
                    }

                    print("")
                    print("✅ [QuestionDetail] ========================================")
                    print("✅ [QuestionDetail] DATA LOADING COMPLETE")
                    print("✅ [QuestionDetail] ========================================")
                    print("")

                    self.question = fetchedQuestion
                    self.isLoading = false
                    self.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    print("")
                    print("❌ [QuestionDetail] ========================================")
                    print("❌ [QuestionDetail] FAILED TO LOAD QUESTION")
                    print("❌ [QuestionDetail] ========================================")
                    print("❌ [QuestionDetail] Question ID: \(questionId)")
                    print("❌ [QuestionDetail] Error: \(error)")
                    print("❌ [QuestionDetail] Error description: \(error.localizedDescription)")
                    print("❌ [QuestionDetail] ========================================")
                    print("")
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