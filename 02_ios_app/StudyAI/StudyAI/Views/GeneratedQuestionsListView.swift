//
//  GeneratedQuestionsListView.swift
//  StudyAI
//
//  Created by Claude Code on 12/21/24.
//

import SwiftUI
import os.log
import PDFKit
import AudioToolbox

struct GeneratedQuestionsListView: View {
    let questions: [QuestionGenerationService.GeneratedQuestion]
    let subject: String
    /// When set (resume path), pre-populate answered state from the saved session.
    var resumeSessionId: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedQuestion: QuestionGenerationService.GeneratedQuestion?
    @State private var showingQuestionDetail = false

    // PDF Generation state
    @State private var selectedQuestions: Set<UUID> = []
    @State private var isSelectionMode = false
    @State private var showingPDFGenerator = false

    // Progress tracking state
    @State private var answeredQuestions: [UUID: QuestionResult] = [:]
    @State private var archivedQuestions: Set<UUID> = []
    @State private var showingInfoAlert = false

    // Smart Organize state
    @State private var hasSmartOrganized = false
    @State private var slideOffset: CGFloat = 0
    @State private var isSliding = false
    @State private var hasTriggeredSlide = false
    @State private var isOrganizing = false

    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @StateObject private var themeManager = ThemeManager.shared

    private let logger = Logger(subsystem: "com.studyai", category: "GeneratedQuestionsList")

    // Track question answer results
    struct QuestionResult {
        let isCorrect: Bool
        let points: Int
    }

    @ViewBuilder
    private var questionDetailView: some View {
        if let selectedQuestion = selectedQuestion,
           let questionIndex = questions.firstIndex(where: { $0.id == selectedQuestion.id }) {
            GeneratedQuestionDetailView(
                question: selectedQuestion,
                subject: subject,
                sessionId: QuestionGenerationService.shared.currentSessionId,
                onAnswerSubmitted: { isCorrect, points in
                    answeredQuestions[selectedQuestion.id] = QuestionResult(isCorrect: isCorrect, points: points)
                    logger.info("📝 Question answered: \(selectedQuestion.id), correct: \(isCorrect)")
                },
                allQuestions: questions,
                currentIndex: questionIndex
            )
        } else {
            VStack {
                Text("Error: Question not found")
                    .font(.headline)
                    .foregroundColor(.red)
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Selection controls (when in selection mode)
                if isSelectionMode {
                    selectionControls
                        .padding()
                }

                // Generate PDF button (when in selection mode with selections)
                if isSelectionMode && !selectedQuestions.isEmpty {
                    confirmPDFButton
                        .padding(.horizontal)
                }

                // Questions List
                if questions.isEmpty {
                    emptyStateView
                } else {
                    questionsListSection
                }

                // Bottom bar: Smart Organize + Export PDF (pinned outside scroll)
                if !questions.isEmpty && !isSelectionMode {
                    bottomBar
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .padding(.top, 8)
                        .background(themeManager.cardBackground)
                }
            }
            .navigationTitle(NSLocalizedString("generatedQuestions.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingInfoAlert = true
                    }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : .blue)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    closeButton
                }
            }
            // .adaptiveNavigationBar() // iOS 18+ liquid glass / iOS < 18 solid background - DISABLED: modifier not found
            // ✅ CHANGED: Use fullScreenCover instead of sheet for fixed view
            .fullScreenCover(isPresented: $showingQuestionDetail) {
                questionDetailView
            }
            .sheet(isPresented: $showingPDFGenerator) {
                if !selectedQuestions.isEmpty {
                    let selected = questions.filter { selectedQuestions.contains($0.id) }
                    PracticePDFPreviewView(
                        questions: selected,
                        subject: getSubject(),
                        generationType: "Custom Practice"
                    )
                }
            }
            .alert(NSLocalizedString("generatedQuestions.howToUse.title", comment: ""), isPresented: $showingInfoAlert) {
                Button(NSLocalizedString("common.ok", comment: "")) { }
            } message: {
                Text(NSLocalizedString("generatedQuestions.howToUse.message", comment: ""))
            }
            .onAppear {
                logger.info("📝 Generated questions list appeared with \(questions.count) questions")

                let questionsWithErrorKeys = questions.filter { $0.errorType != nil }
                logger.debug("🎯 Questions with error keys: \(questionsWithErrorKeys.count)/\(questions.count)")

                // Pre-populate answered state from UserDefaults (per-question persistence).
                // Covers both the resume path (resumeSessionId set) and re-entry after navigating
                // away — any question that was submitted will have saved state in UserDefaults.
                let uid = AuthenticationService.shared.currentUser?.id ?? "anonymous"
                for question in questions {
                    let key = "question_answer_\(question.id.uuidString)_\(uid)"
                    guard let data = UserDefaults.standard.data(forKey: key),
                          let answerData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let hasSubmitted = answerData["hasSubmitted"] as? Bool,
                          hasSubmitted else { continue }

                    let isCorrect = answerData["isCorrect"] as? Bool ?? false
                    let points = isCorrect ? (question.points ?? 10) : 0
                    answeredQuestions[question.id] = QuestionResult(isCorrect: isCorrect, points: points)
                    logger.debug("♻️ Restored answer for question \(question.id.uuidString.prefix(8)): correct=\(isCorrect)")
                }

                if !answeredQuestions.isEmpty {
                    logger.info("✅ Restored \(answeredQuestions.count)/\(questions.count) answered questions from saved state")
                }

                loadArchivedState()
                loadSmartOrganizedState()
            }
            .onChange(of: showingQuestionDetail) { _, newValue in
                if !newValue {
                    logger.debug("🔄 Question detail dismissed")
                    // Re-read per-question answer data to pick up newly graded questions
                    let uid = AuthenticationService.shared.currentUser?.id ?? "anonymous"
                    for question in questions {
                        let key = "question_answer_\(question.id.uuidString)_\(uid)"
                        guard let data = UserDefaults.standard.data(forKey: key),
                              let answerData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let hasSubmitted = answerData["hasSubmitted"] as? Bool,
                              hasSubmitted else { continue }

                        let isCorrect = answerData["isCorrect"] as? Bool ?? false
                        let points = isCorrect ? (question.points ?? 10) : 0
                        answeredQuestions[question.id] = QuestionResult(isCorrect: isCorrect, points: points)
                    }
                }
            }
        }
    }

    private var generatePDFButton: some View {
        Button(action: {
            isSelectionMode = true
        }) {
            HStack {
                Image(systemName: "doc.text.fill")
                Text(NSLocalizedString("generatedQuestions.generatePDF", comment: ""))
                    .font(.body)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                themeManager.currentTheme == .cute
                    ? DesignTokens.Colors.Cute.blue
                    : Color.blue
            )
            .cornerRadius(12)
        }
    }

    private var selectionControls: some View {
        HStack {
            Button(action: {
                if selectedQuestions.count == questions.count {
                    selectedQuestions.removeAll()
                } else {
                    selectedQuestions = Set(questions.map { $0.id })
                }
            }) {
                Text(selectedQuestions.count == questions.count ? NSLocalizedString("common.deselectAll", comment: "") : NSLocalizedString("common.selectAll", comment: ""))
                    .font(.subheadline)
            }

            Spacer()

            Text(String.localizedStringWithFormat(NSLocalizedString("generatedQuestions.questionsSelected", comment: ""), selectedQuestions.count))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Button(NSLocalizedString("common.cancel", comment: "")) {
                isSelectionMode = false
                selectedQuestions.removeAll()
            }
            .font(.subheadline)
        }
    }

    private var confirmPDFButton: some View {
        Button(action: {
            showingPDFGenerator = true
        }) {
            HStack {
                Image(systemName: "doc.badge.plus")
                Text(String.localizedStringWithFormat(NSLocalizedString("generatedQuestions.generatePDFCount", comment: ""), selectedQuestions.count))
                    .font(.body)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                themeManager.currentTheme == .cute
                    ? DesignTokens.Colors.Cute.mint
                    : Color.green
            )
            .cornerRadius(12)
        }
    }

    private var questionsListSection: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(questions.indices, id: \.self) { index in
                    let question = questions[index]
                    let questionIndex = index + 1

                    // Wrap renderer in selection container
                    VStack(spacing: 0) {
                        // Selection header (when in selection mode)
                        if isSelectionMode {
                            HStack {
                                Button(action: {
                                    if selectedQuestions.contains(question.id) {
                                        selectedQuestions.remove(question.id)
                                    } else {
                                        selectedQuestions.insert(question.id)
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: selectedQuestions.contains(question.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundColor(selectedQuestions.contains(question.id) ? .blue : .gray)

                                        Text(selectedQuestions.contains(question.id) ? NSLocalizedString("generatedQuestions.selected", comment: "") : NSLocalizedString("generatedQuestions.select", comment: ""))
                                            .font(.subheadline)
                                            .foregroundColor(selectedQuestions.contains(question.id) ? .blue : .gray)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())

                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.top, 12)
                        }

                        // Use QuestionTypeRenderer based on question type
                        Button(action: {
                            if !isSelectionMode {
                                selectedQuestion = question
                                showingQuestionDetail = true
                            } else {
                                if selectedQuestions.contains(question.id) {
                                    selectedQuestions.remove(question.id)
                                } else {
                                    selectedQuestions.insert(question.id)
                                }
                            }
                        }) {
                            HStack(spacing: 0) {
                                // Question content - disable hit testing so taps pass through to button
                                renderQuestion(question, at: questionIndex)
                                    .allowsHitTesting(false)
                                    .padding()

                                // Chevron indicator - makes it clear this is tappable
                                if !isSelectionMode {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.5))
                                        .padding(.trailing, 16)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contentShape(Rectangle())
                    }
                    .background(
                        archivedQuestions.contains(question.id)
                            ? themeManager.cardBackground.opacity(0.6)
                            : themeManager.cardBackground
                    )
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                archivedQuestions.contains(question.id)
                                    ? Color.green.opacity(0.5)
                                    : (isSelectionMode && selectedQuestions.contains(question.id)
                                        ? Color.blue
                                        : DesignTokens.AdaptiveColors.border(colorScheme: colorScheme)),
                                lineWidth: (archivedQuestions.contains(question.id) || (isSelectionMode && selectedQuestions.contains(question.id))) ? 2 : 2
                            )
                    )
                    .overlay(
                        // Archived badge — bottom-right corner
                        Group {
                            if archivedQuestions.contains(question.id) {
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        HStack(spacing: 4) {
                                            Image(systemName: "books.vertical.fill")
                                                .font(.caption2)
                                            Text("Archived")
                                                .font(.caption2)
                                                .fontWeight(.medium)
                                        }
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.12))
                                        .cornerRadius(8)
                                        .padding(8)
                                    }
                                }
                            }
                        }
                    )
                    .opacity(archivedQuestions.contains(question.id) ? 0.75 : 1.0)
                    .shadow(
                        color: isSelectionMode && selectedQuestions.contains(question.id)
                            ? Color.blue.opacity(0.3)
                            : (colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.1)),
                        radius: isSelectionMode && selectedQuestions.contains(question.id) ? 8 : 4,
                        x: 0,
                        y: isSelectionMode && selectedQuestions.contains(question.id) ? 4 : 2
                    )
                }

                // Stats Summary at bottom
                questionsSummary
                    .padding(.top, 24)
            }
            .padding()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "questionmark.folder")
                .font(.system(size: 60))
                .foregroundColor(themeManager.secondaryText)

            VStack(spacing: 8) {
                Text(NSLocalizedString("generatedQuestions.noQuestions", comment: ""))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.primaryText)

                Text(NSLocalizedString("generatedQuestions.noQuestionsMessage", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(themeManager.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }

    private var questionsSummary: some View {
        VStack(spacing: 20) {
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text(NSLocalizedString("generatedQuestions.summary", comment: ""))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.primaryText)

                // Type breakdown
                let typeBreakdown = Dictionary(grouping: questions) { $0.type }
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(Array(typeBreakdown.keys), id: \.self) { type in
                        SummaryCard(
                            title: type.displayName,
                            count: typeBreakdown[type]?.count ?? 0,
                            icon: type.icon,
                            color: themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.blue : .blue
                        )
                    }
                }

                // Difficulty breakdown
                let difficultyBreakdown = Dictionary(grouping: questions) { $0.difficulty }
                HStack(spacing: 20) {
                    ForEach(Array(difficultyBreakdown.keys.sorted()), id: \.self) { difficulty in
                        VStack(spacing: 4) {
                            Text("\(difficultyBreakdown[difficulty]?.count ?? 0)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(difficultyColor(difficulty))

                            Text(difficulty.capitalized)
                                .font(.caption)
                                .foregroundColor(themeManager.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(themeManager.cardBackground)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Smart Organize

    private var smartOrganizeSection: some View {
        VStack(spacing: 12) {
            if hasSmartOrganized {
                // Done state
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.mint : .green)
                    Text(NSLocalizedString("questionDetail.marked", comment: ""))
                        .font(.headline)
                        .foregroundColor(themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.mint : .green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background((themeManager.currentTheme == .cute ? DesignTokens.Colors.Cute.mint : Color.green).opacity(0.1))
                .cornerRadius(12)
            } else {
                slideToSmartOrganizeTrack
            }
        }
    }

    private var slideToSmartOrganizeTrack: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let sliderWidth: CGFloat = 60
            let maxOffset = trackWidth - sliderWidth - 8

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .frame(height: 60)

                // Progress fill
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: slideOffset + sliderWidth + 4, height: 60)
                    .opacity(slideOffset > 0 ? 1.0 : 0.0)

                // Instruction text (fades as slider moves)
                HStack {
                    Spacer()
                    Text(NSLocalizedString("questionDetail.markProgress", comment: ""))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary.opacity(0.6))
                        .opacity(1.0 - (slideOffset / maxOffset))
                    Spacer()
                }
                .frame(height: 60)

                // Sliding thumb - frosted glass circle
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: sliderWidth, height: sliderWidth)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundColor(.primary.opacity(0.6))
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundColor(.primary.opacity(0.3))
                    }
                }
                .offset(x: slideOffset + 4, y: 0)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newOffset = max(0, min(value.translation.width, maxOffset))
                            withAnimation(.interactiveSpring()) {
                                slideOffset = newOffset
                                isSliding = true
                            }
                            if newOffset >= maxOffset * 1.0 && !hasTriggeredSlide {
                                hasTriggeredSlide = true
                                smartOrganizeMistakes()
                                AudioServicesPlaySystemSound(1100)
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                                withAnimation(.spring()) {
                                    slideOffset = 0
                                    isSliding = false
                                }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring()) {
                                slideOffset = 0
                                isSliding = false
                            }
                            hasTriggeredSlide = false
                        }
                )
            }
        }
        .frame(height: 60)
    }

    /// Archive only mistake questions; run concept extraction for correct ones.
    private func smartOrganizeMistakes() {
        guard !isOrganizing else { return }
        isOrganizing = true

        let uid = AuthenticationService.shared.currentUser?.id ?? "anonymous"
        let sessionId = QuestionGenerationService.shared.currentSessionId ?? UUID().uuidString

        var mistakeData: [[String: Any]] = []
        var correctData: [[String: Any]] = []
        var totalAnswered = 0
        var totalCorrect = 0

        for question in questions {
            guard let result = answeredQuestions[question.id] else { continue }
            totalAnswered += 1

            // Load student answer from UserDefaults
            let answerKey = "question_answer_\(question.id.uuidString)_\(uid)"
            var studentAnswer = ""
            if let data = UserDefaults.standard.data(forKey: answerKey),
               let answerData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let saved = answerData["selectedOption"] as? String, !saved.isEmpty {
                    studentAnswer = saved
                } else if let saved = answerData["userAnswer"] as? String {
                    studentAnswer = saved
                }
            }

            let questionData: [String: Any] = [
                "id": UUID().uuidString,
                "subject": subject,
                "questionText": question.question,
                "rawQuestionText": question.question,
                "answerText": question.correctAnswer,
                "confidence": 1.0,
                "hasVisualElements": false,
                "archivedAt": ISO8601DateFormatter().string(from: Date()),
                "reviewCount": 0,
                "tags": question.tags ?? [],
                "notes": "",
                "studentAnswer": studentAnswer,
                "grade": result.isCorrect ? "CORRECT" : "INCORRECT",
                "points": result.isCorrect ? (question.points ?? 1) : 0,
                "maxPoints": question.points ?? 1,
                "feedback": question.explanation,
                "isGraded": true,
                "isCorrect": result.isCorrect,
                "errorType": question.errorType as Any,
                "baseBranch": question.baseBranch as Any,
                "detailedBranch": question.detailedBranch as Any,
                "weaknessKey": question.weaknessKey as Any
            ]

            if result.isCorrect {
                totalCorrect += 1
                correctData.append(questionData)
            } else {
                mistakeData.append(questionData)
            }
        }

        // Save only mistakes to local storage
        if !mistakeData.isEmpty {
            let idMappings = currentUserQuestionStorage().saveQuestions(mistakeData)
            // Remap IDs for deduplication
            for (index, mapping) in idMappings.enumerated() {
                if mapping.savedId != mapping.originalId {
                    mistakeData[index]["id"] = mapping.savedId
                }
            }

            ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
                sessionId: sessionId,
                wrongQuestions: mistakeData
            )

            // Mark mistake questions with archived badges
            for question in questions {
                if let result = answeredQuestions[question.id], !result.isCorrect {
                    archivedQuestions.insert(question.id)
                    // Persist per-question archived state
                    let key = "question_archived_\(question.id)_\(uid)"
                    UserDefaults.standard.set(true, forKey: key)
                }
            }
        }

        // Concept extraction for correct answers (NOT saved to storage)
        if !correctData.isEmpty {
            ErrorAnalysisQueueService.shared.queueConceptExtractionForCorrectAnswers(
                sessionId: sessionId,
                correctQuestions: correctData
            )
        }

        // Mark progress
        pointsManager.markHomeworkProgress(
            subject: subject,
            numberOfQuestions: totalAnswered,
            numberOfCorrectQuestions: totalCorrect
        )

        hasSmartOrganized = true
        isOrganizing = false
        saveSmartOrganizedState()

        logger.info("📚 Smart Organize complete: \(mistakeData.count) mistakes archived, \(correctData.count) correct for concept extraction")
    }

    // MARK: - Smart Organize Persistence

    private var smartOrganizedKey: String {
        let sessionId = QuestionGenerationService.shared.currentSessionId ?? "unknown"
        return "smart_organized_\(sessionId)"
    }

    private func loadSmartOrganizedState() {
        hasSmartOrganized = UserDefaults.standard.bool(forKey: smartOrganizedKey)
    }

    private func saveSmartOrganizedState() {
        UserDefaults.standard.set(hasSmartOrganized, forKey: smartOrganizedKey)
    }

    // MARK: - Bottom Bar (Smart Organize + Export PDF)

    private var bottomBar: some View {
        VStack(spacing: 12) {
            // Smart Organize — visible only when all questions are answered
            if answeredQuestions.count == questions.count && !questions.isEmpty {
                smartOrganizeSection
            }

            // Export to PDF button
            generatePDFButton
        }
    }

    private var closeButton: some View {
        Button(NSLocalizedString("common.done", comment: "")) {
            dismiss()
        }
        .font(.body)
        .fontWeight(.semibold)
    }

    private func difficultyColor(_ difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "beginner": return .green
        case "intermediate": return .orange
        case "advanced": return .red
        default: return .gray
        }
    }

    private func getSubject() -> String {
        // Get the most common topic as the subject
        let topicCounts = Dictionary(grouping: questions) { $0.topic }
        let mostCommonTopic = topicCounts.max(by: { $0.value.count < $1.value.count })?.key ?? "Practice"
        return mostCommonTopic
    }

    /// Reload which questions have been archived from UserDefaults.
    /// Called on appear and whenever the question detail sheet closes.
    private func loadArchivedState() {
        let uid = AuthenticationService.shared.currentUser?.id ?? "anonymous"
        var updated: Set<UUID> = []
        for question in questions {
            let key = "question_archived_\(question.id)_\(uid)"
            if UserDefaults.standard.bool(forKey: key) {
                updated.insert(question.id)
            }
        }
        archivedQuestions = updated
    }

    @ViewBuilder
    private func renderQuestion(_ question: QuestionGenerationService.GeneratedQuestion, at index: Int) -> some View {
        // Convert GeneratedQuestion to ParsedQuestion format for renderers
        let parsedQuestion = ParsedQuestion(
            questionNumber: index,
            rawQuestionText: question.question,  // ✅ Include full question text for math rendering
            questionText: question.question,
            answerText: question.correctAnswer,
            confidence: nil,
            hasVisualElements: false,
            studentAnswer: "",  // No student answer yet (practice mode)
            correctAnswer: question.correctAnswer,
            grade: nil,  // No grading yet
            pointsEarned: nil,
            pointsPossible: Float(question.points ?? 10),
            feedback: question.explanation,
            questionType: question.type.rawValue,
            options: question.options,
            isParent: nil,
            hasSubquestions: nil,
            parentContent: nil,
            subquestions: nil,
            subquestionNumber: nil,
            parentSummary: nil
        )

        // Render based on question type
        switch question.type {
        case .multipleChoice:
            MultipleChoiceRenderer(question: parsedQuestion, isExpanded: false, onTapAskAI: {})
        case .trueFalse:
            TrueFalseRenderer(question: parsedQuestion, isExpanded: false, onTapAskAI: {})
        case .fillBlank:
            FillInBlankRenderer(question: parsedQuestion, isExpanded: false, onTapAskAI: {})
        case .shortAnswer:
            ShortAnswerRenderer(question: parsedQuestion, isExpanded: false, onTapAskAI: {})
        case .longAnswer:
            LongAnswerRenderer(question: parsedQuestion, isExpanded: false, onTapAskAI: {})
        case .calculation:
            CalculationRenderer(question: parsedQuestion, isExpanded: false, onTapAskAI: {})
        case .matching:
            MatchingRenderer(question: parsedQuestion, isExpanded: false, onTapAskAI: {})
        case .any:
            // Fallback to generic renderer for "any" type
            ShortAnswerRenderer(question: parsedQuestion, isExpanded: false, onTapAskAI: {})
        }
    }

}

struct QuestionListCard: View {
    let question: QuestionGenerationService.GeneratedQuestion
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: {
            if isSelectionMode {
                onToggleSelection()
            } else {
                onTap()
            }
        }) {
            VStack(alignment: .leading, spacing: 16) {
                // Selection checkbox header (when in selection mode)
                if isSelectionMode {
                    HStack {
                        Button(action: onToggleSelection) {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundColor(isSelected ? .blue : .gray)

                                Text(isSelected ? NSLocalizedString("generatedQuestions.selected", comment: "") : NSLocalizedString("generatedQuestions.select", comment: ""))
                                    .font(.subheadline)
                                    .foregroundColor(isSelected ? .blue : .gray)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())

                        Spacer()
                    }
                }

                // Header with type and difficulty
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: question.typeIcon)
                            .font(.body)
                            .foregroundColor(question.difficultyColor)

                        Text(question.type.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(question.difficultyColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(question.difficultyColor.opacity(0.1))
                    .cornerRadius(6)

                    Spacer()

                    Text(question.difficulty.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            colorScheme == .dark
                                ? Color(.systemGray5)
                                : Color.gray.opacity(0.1)
                        )
                        .cornerRadius(6)
                }

                // Question text - ✅ Use SmartLaTeXView for proper LaTeX/MathJax rendering
                SmartLaTeXView(question.question, fontSize: 14, colorScheme: colorScheme)
                    .frame(maxHeight: 80)
                    .clipped()

                // Topic and metadata
                HStack {
                    Label(question.topic, systemImage: "tag.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let timeEstimate = question.timeEstimate {
                        Label(timeEstimate, systemImage: "clock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let points = question.points {
                        Label(String(format: NSLocalizedString("generatedQuestions.points", comment: ""), points), systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                // Preview of answer/explanation - ✅ Use SmartLaTeXView for proper LaTeX support
                if !question.explanation.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)

                        SmartLaTeXView(
                            String(question.explanation.prefix(120)) + (question.explanation.count > 120 ? "..." : ""),
                            fontSize: 12,
                            colorScheme: colorScheme
                        )
                        .frame(maxHeight: 50)
                        .clipped()
                    }
                    .padding(.top, 4)
                }

                // Footer
                HStack {
                    Spacer()

                    HStack(spacing: 4) {
                        Text(NSLocalizedString("generatedQuestions.viewDetails", comment: ""))
                            .font(.caption)
                            .foregroundColor(.blue)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding()
            .background(DesignTokens.AdaptiveColors.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DesignTokens.AdaptiveColors.border(colorScheme: colorScheme), lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.05),
                radius: 2,
                x: 0,
                y: 1
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SummaryCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.body.bold())
                    .foregroundColor(.primary)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            colorScheme == .dark
                ? color.opacity(0.15)
                : color.opacity(0.05)
        )
        .cornerRadius(8)
    }
}

// MARK: - Practice PDF Preview View

struct PracticePDFPreviewView: View {
    let questions: [QuestionGenerationService.GeneratedQuestion]
    let subject: String
    let generationType: String

    @StateObject private var pdfGenerator = PDFGeneratorService()
    @State private var pdfDocument: PDFDocument?
    @State private var showingPrintOptions = false
    @State private var showingEmailComposer = false
    @State private var showingShareSheet = false
    @State private var showingOptions = false
    @State private var pdfURL: URL?
    @State private var options = PDFExportOptions()
    @Environment(\.dismiss) private var dismiss

    var isLoading: Bool {
        pdfDocument == nil || pdfGenerator.isGenerating
    }

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    // Loading state
                    VStack(spacing: 20) {
                        ProgressView(value: pdfGenerator.generationProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding(.horizontal, 40)

                        Text(pdfGenerator.isGenerating ? NSLocalizedString("generatedQuestions.generatingPDF", comment: "") : NSLocalizedString("generatedQuestions.loading", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("\(Int(pdfGenerator.generationProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let document = pdfDocument {
                    VStack(spacing: 0) {
                        // PDF Preview
                        PDFKitView(document: document)

                        // Action buttons
                        HStack(spacing: 16) {
                            Button {
                                handlePrint()
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "printer.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)

                                    Text(NSLocalizedString("generatedQuestions.print", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                            }

                            Button {
                                showingEmailComposer = true
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "envelope.fill")
                                        .font(.title2)
                                        .foregroundColor(.green)

                                    Text(NSLocalizedString("generatedQuestions.email", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)
                            }

                            Button {
                                showingShareSheet = true
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up.fill")
                                        .font(.title2)
                                        .foregroundColor(.orange)

                                    Text(NSLocalizedString("generatedQuestions.share", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 5, y: -2)
                    }
                } else {
                    // Error state
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)

                        Text(NSLocalizedString("generatedQuestions.pdfError", comment: ""))
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text(NSLocalizedString("generatedQuestions.tryAgain", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Button(NSLocalizedString("generatedQuestions.retry", comment: "")) {
                            Task {
                                await generatePDF()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("generatedQuestions.pdfPreview", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.close", comment: "")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingOptions = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await generatePDF()
            }
            .sheet(isPresented: $showingOptions) {
                // Practice questions are text-only — no image section
                PDFOptionsSheet(options: $options, hasImages: false) {
                    Task { await generatePDF() }
                }
            }
            .sheet(isPresented: $showingEmailComposer) {
                if let url = pdfURL {
                    PDFMailComposeView(
                        subject: "Practice Questions - \(subject)",
                        messageBody: createEmailBody(),
                        attachmentURL: url,
                        attachmentName: "practice-questions.pdf"
                    )
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = pdfURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    // MARK: - PDF Generation

    private func generatePDF() async {
        let document = await pdfGenerator.generatePracticePDF(
            questions: questions,
            subject: subject,
            generationType: generationType,
            options: options
        )

        await MainActor.run {
            self.pdfDocument = document
            if let document = document {
                savePDFForSharing(document)
            }
        }
    }

    private func savePDFForSharing(_ document: PDFDocument) {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("practice-questions-\(Date().timeIntervalSince1970).pdf")

        if document.write(to: fileURL) {
            self.pdfURL = fileURL
        }
    }

    // MARK: - Actions

    private func handlePrint() {
        guard let document = pdfDocument else { return }

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = "Practice Questions - \(subject)"
        printInfo.outputType = .general
        printController.printInfo = printInfo
        printController.printingItem = document.dataRepresentation()

        printController.present(animated: true) { _, completed, error in
            if let error = error {
                print("❌ Print error: \(error.localizedDescription)")
            } else if completed {
                print("✅ Print job completed")
            }
        }
    }

    private func createEmailBody() -> String {
        let greeting = NSLocalizedString("generatedQuestions.emailGreeting", comment: "")
        let body = String(format: NSLocalizedString("generatedQuestions.emailBody", comment: ""), questions.count, subject)
        let generatedBy = NSLocalizedString("generatedQuestions.emailGeneratedBy", comment: "")
        let closing = NSLocalizedString("generatedQuestions.emailClosing", comment: "")

        return """
        \(greeting)

        \(body)

        \(generatedBy)

        \(closing)
        """
    }
}

#Preview {
    let sampleQuestions = [
        QuestionGenerationService.GeneratedQuestion(
            question: "What is the derivative of x² + 3x - 5?",
            type: .calculation,
            correctAnswer: "2x + 3",
            explanation: "Using the power rule, the derivative of x² is 2x, and the derivative of 3x is 3.",
            topic: "Calculus",
            difficulty: "intermediate",
            points: 10,
            timeEstimate: "2 min",
            options: nil
        ),
        QuestionGenerationService.GeneratedQuestion(
            question: "Which of the following is a prime number?",
            type: .multipleChoice,
            correctAnswer: "17",
            explanation: "17 is only divisible by 1 and itself, making it a prime number.",
            topic: "Number Theory",
            difficulty: "beginner",
            points: 5,
            timeEstimate: "1 min",
            options: ["15", "16", "17", "18"]
        )
    ]

    GeneratedQuestionsListView(questions: sampleQuestions, subject: "Mathematics")
}