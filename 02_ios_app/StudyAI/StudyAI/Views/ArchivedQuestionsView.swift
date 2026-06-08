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
                    TextField(NSLocalizedString("common.search", value: "Search", comment: ""), text: $searchText)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .frame(width: 100)
                
                // Subject Pills
                ForEach(subjects, id: \.self) { subject in
                    Button(action: {
                        selectedSubject = selectedSubject == subject ? nil : subject
                    }) {
                        Text(NSLocalizedString("subject.\(subject.lowercased())", value: subject, comment: ""))
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

// MARK: - Notebook Highlighter Mark (organic felt-tip highlight shape)

private struct NotebookHighlighterMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let top = rect.height * 0.18
        let bot = rect.height * 0.88
        let l   = rect.minX - 3
        let r   = rect.maxX + 4
        p.move(to: CGPoint(x: l, y: top + 1.5))
        p.addCurve(
            to: CGPoint(x: r, y: top - 0.5),
            control1: CGPoint(x: rect.width * 0.32, y: top - 2.5),
            control2: CGPoint(x: rect.width * 0.70, y: top + 2.0)
        )
        p.addLine(to: CGPoint(x: r, y: bot + 0.5))
        p.addCurve(
            to: CGPoint(x: l, y: bot - 0.5),
            control1: CGPoint(x: rect.width * 0.65, y: bot + 2.5),
            control2: CGPoint(x: rect.width * 0.28, y: bot - 2.0)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Question Detail View (Library)

struct QuestionDetailView: View {
    let questionId: String
    var preloadedSummary: QuestionSummary? = nil

    @Environment(\.colorScheme) private var colorScheme
    private let appState = AppState.shared

    @State private var question: ArchivedQuestion?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var proModeImage: UIImage?
    @State private var hasStartedLoading = false

    // MARK: - Theme (matches SuggestedTodosSection notebook paper)

    private var paperColor: Color {
        colorScheme == .dark ? Color(hex: "27251F") : Color(hex: "FAF6EE")
    }
    private var lineColor: Color {
        colorScheme == .dark
            ? Color(hex: "4A4640").opacity(0.55)
            : Color(hex: "B8C4C0").opacity(0.55)
    }
    private var primaryText: Color {
        colorScheme == .dark ? Color(hex: "E8E8E8") : Color(hex: "2A2A2A")
    }
    private var secondaryText: Color {
        colorScheme == .dark ? Color(hex: "909098") : Color(hex: "888888")
    }

    // MARK: - Handwriting font (matches SuggestedTodosSection)

    private func handwritingFont(size: CGFloat, for text: String) -> Font {
        let hasCJK = text.unicodeScalars.contains {
            (0x4E00...0x9FFF ~= $0.value) || (0x3400...0x4DBF ~= $0.value)
        }
        return hasCJK
            ? Font.custom("ZCOOLKuaiLe-Regular", size: size)
            : Font.custom("IndieFlower", size: size)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().padding(.top, 100)
            } else if let err = errorMessage {
                errorView(err)
            } else if let q = question {
                ZStack(alignment: .topLeading) {
                    notebookBackground
                    contentView(for: q)
                }
            }
        }
        .background(paperColor.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !hasStartedLoading else { return }
            hasStartedLoading = true
            loadQuestion()
        }
    }

    // MARK: - Notebook paper background (grid lines)

    private var notebookBackground: some View {
        GeometryReader { geo in
            ZStack {
                paperColor
                Canvas { ctx, size in
                    let spacing: CGFloat = 24
                    let style = StrokeStyle(lineWidth: 0.5, lineCap: .round)
                    var y: CGFloat = spacing
                    while y < size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(p, with: .color(lineColor), style: style)
                        y += spacing
                    }
                    var x: CGFloat = spacing
                    while x < size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(p, with: .color(lineColor), style: style)
                        x += spacing
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private func contentView(for q: ArchivedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 24) {

            // Subject tag — top right
            HStack {
                Spacer()
                Text(q.subject)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(subjectColor(q.subject))
                    .cornerRadius(12)
            }

            // Question
            questionSection(for: q)

            // Student answer (left) + Grade (right, floating)
            studentAnswerAndGradeRow(for: q)

            // Correct answer
            correctAnswerSection(for: q)

            // AI Feedback
            if let feedback = q.feedback, !feedback.isEmpty, feedback != "No feedback provided" {
                aiFeedbackSection(feedback)
            }

            // Tags & notes (if any)
            userNotesAndTags(for: q)

            // Follow Up with AI
            followUpButton(for: q)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Question section (no box — content lives directly on paper)

    private func containsLaTeX(_ text: String) -> Bool {
        text.contains("$") || text.contains("\\(") || text.contains("\\[") ||
        text.contains("\\frac") || text.contains("\\sqrt") || text.contains("\\sum") ||
        text.contains("\\int") || text.contains("\\alpha") || text.contains("\\beta") ||
        text.contains("\\pi") || text.contains("\\theta")
    }

    private func questionDisplayText(_ q: ArchivedQuestion) -> String {
        let hasSeparateOptions = !(q.options ?? []).isEmpty
        if q.questionType == "multiple_choice" && hasSeparateOptions {
            return q.questionText  // stem only — options rendered separately below
        }
        return q.rawQuestionText ?? q.questionText
    }

    @ViewBuilder
    private func questionSection(for q: ArchivedQuestion) -> some View {
        let qType = q.questionType ?? ""
        let separateOptions = q.options ?? []
        let letters = ["A", "B", "C", "D", "E", "F"]

        VStack(alignment: .leading, spacing: 10) {
            highlightedLabel("Question", highlightColor: Color(hex: "7EC8E3").opacity(0.50))

            EnhancedMathText(questionDisplayText(q), fontSize: 17)

            // Multiple choice — separate options array
            if qType == "multiple_choice" && !separateOptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(separateOptions.enumerated()), id: \.offset) { i, option in
                        HStack(alignment: .top, spacing: 8) {
                            Text(i < letters.count ? letters[i] : "\(i + 1)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(secondaryText)
                                .frame(width: 18, alignment: .leading)
                            EnhancedMathText(option, fontSize: 15)
                        }
                    }
                }
                .padding(.top, 4)
            }

            // True / False — show the two choices explicitly
            if qType == "true_false" {
                HStack(spacing: 24) {
                    ForEach(["True", "False"], id: \.self) { label in
                        HStack(spacing: 5) {
                            Image(systemName: "circle")
                                .font(.system(size: 12))
                                .foregroundColor(secondaryText)
                            Text(label)
                                .font(.system(size: 15))
                                .foregroundColor(secondaryText)
                        }
                    }
                }
                .padding(.top, 4)
            }

            if let image = proModeImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(6)
            }
        }
    }

    // MARK: - Student answer (3/4) + Grade (1/4, floating on paper)

    @ViewBuilder
    private func studentAnswerAndGradeRow(for q: ArchivedQuestion) -> some View {
        let answerText = q.studentAnswer ?? "—"
        let hasAnswer = !(q.studentAnswer ?? "").isEmpty
        let hColor = q.grade.map { answerHighlightColor($0) } ?? Color(hex: "FFE066")
        let gColor = q.grade.map { gradeColor($0) } ?? Color.gray

        HStack(alignment: .top, spacing: 0) {

            // Student answer — takes ~3/4, no box
            VStack(alignment: .leading, spacing: 8) {
                highlightedLabel("Your Answer", highlightColor: hColor.opacity(0.50))

                if hasAnswer && containsLaTeX(answerText) {
                    EnhancedMathText(answerText, fontSize: 17)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(NotebookHighlighterMark().fill(hColor.opacity(0.32)))
                } else {
                    Text(hasAnswer ? answerText : "—")
                        .font(handwritingFont(size: 22, for: answerText))
                        .foregroundColor(primaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(NotebookHighlighterMark().fill(hColor.opacity(0.32)))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Grade indicator — ~1/4 width, just icon + text, no box
            VStack(spacing: 4) {
                Image(systemName: gradeIconName(q.grade))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(gColor)

                if let grade = q.grade {
                    Text(grade.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(gColor)
                        .multilineTextAlignment(.center)
                }

                if let pts = q.points, let max = q.maxPoints {
                    Text("\(formatScore(pts))/\(formatScore(max))")
                        .font(.caption2)
                        .foregroundColor(secondaryText)
                }
            }
            .frame(width: 72)
        }
    }

    // MARK: - Correct answer section (no box)

    @ViewBuilder
    private func correctAnswerSection(for q: ArchivedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            highlightedLabel("Correct Answer", highlightColor: Color.green.opacity(0.40))

            EnhancedMathText(q.answerText, fontSize: 16)
                .foregroundColor(primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - AI Feedback section (no box)

    @ViewBuilder
    private func aiFeedbackSection(_ feedback: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            highlightedLabel("AI Feedback", highlightColor: Color.purple.opacity(0.30))

            EnhancedMathText(feedback, fontSize: 16)
                .foregroundColor(primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Notes & Tags (no box)

    @ViewBuilder
    private func userNotesAndTags(for q: ArchivedQuestion) -> some View {
        if let tags = q.tags, !tags.isEmpty {
            FlowLayout(items: tags) { tag in
                Text(tag)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
        }

        if let notes = q.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                highlightedLabel("Your Notes", highlightColor: Color(hex: "FFE066").opacity(0.55))
                if containsLaTeX(notes) {
                    EnhancedMathText(notes, fontSize: 15)
                } else {
                    Text(notes)
                        .font(handwritingFont(size: 17, for: notes))
                        .foregroundColor(primaryText)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Follow Up button

    @ViewBuilder
    private func followUpButton(for q: ArchivedQuestion) -> some View {
        Button {
            // Build a rich message with full question content so AI has complete context
            var parts: [String] = []
            parts.append("I need help understanding this \(q.subject) question from my study archive.\n")

            // Use rawQuestionText (full original from image) when available, else clean text
            let raw = q.rawQuestionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let questionContent = raw.isEmpty ? q.questionText : raw
            parts.append("**Question:**\n\(questionContent)")

            if let options = q.options, !options.isEmpty {
                parts.append("\n**Options:**\n" + options.joined(separator: "\n"))
            }
            if let studentAnswer = q.studentAnswer, !studentAnswer.isEmpty {
                if studentAnswer == ProgressiveQuestion.answerInImageSentinel {
                    parts.append("\n**My answer:** (shown visually in the homework image — not extracted as text)")
                } else {
                    parts.append("\n**My answer:** \(studentAnswer)")
                }
            }
            if !q.answerText.isEmpty {
                parts.append("**Correct answer:** \(q.answerText)")
            }
            if let grade = q.grade {
                parts.append("**Grade:** \(grade.rawValue)")
            }
            if let feedback = q.feedback, !feedback.isEmpty,
               feedback != "No feedback provided" {
                parts.append("\n**Feedback I received:**\n\(feedback)")
            }
            parts.append("\nPlease explain the solution step by step and help me understand where I went wrong.")

            let msg = parts.joined(separator: "\n")

            let context = HomeworkQuestionContext(
                questionText: q.questionText,
                rawQuestionText: q.rawQuestionText,
                studentAnswer: q.studentAnswer,
                correctAnswer: q.answerText,
                currentGrade: q.grade?.rawValue,
                originalFeedback: q.feedback,
                pointsEarned: q.points,
                pointsPossible: q.maxPoints,
                questionNumber: nil,
                subject: q.subject,
                questionImage: nil
            )
            appState.navigateToChatWithHomeworkQuestion(message: msg, context: context)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "message.fill")
                Text(NSLocalizedString("archive.followUpWithAI", value: "Follow Up with AI", comment: ""))
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color(hex: "FFB6A3"), Color(hex: "FF85C1")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
            .shadow(color: Color(hex: "FFB6A3").opacity(0.40), radius: 6, x: 0, y: 3)
        }
    }

    // MARK: - Highlighted subtitle label

    @ViewBuilder
    private func highlightedLabel(_ text: String, highlightColor: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(secondaryText)
            .background(NotebookHighlighterMark().fill(highlightColor))
    }

    // MARK: - Error view

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle).foregroundColor(.red)
            Text("Failed to Load Question").font(.headline)
            Text(message).font(.subheadline).foregroundColor(.gray)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button("Retry") { loadQuestion() }.buttonStyle(.bordered)
        }
        .padding(.top, 100)
    }

    // MARK: - Data loading

    private func loadQuestion() {
        if let summary = preloadedSummary {
            // Quick path: show immediately from summary data
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
            if let path = summary.questionImageUrl, !path.isEmpty,
               let img = ProModeImageStorage.shared.loadImage(from: path) {
                self.proModeImage = img
            }

            // Background fetch to get full details including AI feedback
            Task {
                if let full = try? await QuestionArchiveService.shared.getQuestionDetails(questionId: questionId) {
                    await MainActor.run {
                        self.question = full
                        if let path = full.questionImageUrl, !path.isEmpty,
                           let img = ProModeImageStorage.shared.loadImage(from: path) {
                            self.proModeImage = img
                        }
                    }
                }
            }
            return
        }

        Task {
            do {
                let q = try await QuestionArchiveService.shared.getQuestionDetails(questionId: questionId)
                await MainActor.run {
                    if let path = q.questionImageUrl, !path.isEmpty,
                       let img = ProModeImageStorage.shared.loadImage(from: path) {
                        self.proModeImage = img
                    }
                    self.question = q
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func subjectColor(_ subject: String) -> Color {
        switch subject {
        case "Mathematics", "Math": return .blue
        case "Physics": return .purple
        case "Chemistry": return Color(hex: "27AE60")
        case "Biology": return .orange
        case "English": return .red
        case "History": return Color(hex: "8B6914")
        default: return .gray
        }
    }

    private func gradeColor(_ grade: GradeResult) -> Color {
        switch grade {
        case .correct: return .green
        case .incorrect: return .red
        case .partialCredit: return .orange
        case .empty: return .gray
        }
    }

    private func answerHighlightColor(_ grade: GradeResult) -> Color {
        switch grade {
        case .correct: return Color(hex: "7FDBCA")       // mint
        case .incorrect: return Color(hex: "FFB6A3")     // peach-red
        case .partialCredit: return Color(hex: "FFE066") // yellow
        case .empty: return Color(hex: "FFE066")
        }
    }

    private func gradeIconName(_ grade: GradeResult?) -> String {
        switch grade {
        case .correct: return "checkmark.circle.fill"
        case .incorrect: return "xmark.circle.fill"
        case .partialCredit: return "circle.lefthalf.filled"
        case .empty, nil: return "minus.circle"
        }
    }

    private func formatScore(_ value: Float) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

#Preview {
    ArchivedQuestionsView()
}