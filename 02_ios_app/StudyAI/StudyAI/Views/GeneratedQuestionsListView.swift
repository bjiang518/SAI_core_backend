//
//  GeneratedQuestionsListView.swift
//  StudyAI
//
//  Created by Claude Code on 12/21/24.
//

import SwiftUI
import os.log
import PDFKit

struct GeneratedQuestionsListView: View {
    let questions: [QuestionGenerationService.GeneratedQuestion]
    let subject: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedQuestion: QuestionGenerationService.GeneratedQuestion?
    @State private var showingQuestionDetail = false
    @State private var searchText = ""

    // PDF Generation state
    @State private var selectedQuestions: Set<UUID> = []
    @State private var isSelectionMode = false
    @State private var showingPDFGenerator = false

    // Progress tracking state
    @State private var answeredQuestions: [UUID: QuestionResult] = [:]
    @State private var showingInfoAlert = false

    private let logger = Logger(subsystem: "com.studyai", category: "GeneratedQuestionsList")

    // Track question answer results
    struct QuestionResult {
        let isCorrect: Bool
        let points: Int
    }

    var filteredQuestions: [QuestionGenerationService.GeneratedQuestion] {
        if searchText.isEmpty {
            return questions
        }
        return questions.filter { question in
            question.question.localizedCaseInsensitiveContains(searchText) ||
            question.topic.localizedCaseInsensitiveContains(searchText) ||
            question.type.displayName.localizedCaseInsensitiveContains(searchText)
        }
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
                // PDF Generation button (when not in selection mode)
                if !questions.isEmpty && !isSelectionMode {
                    generatePDFButton
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

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

                // Search Bar
                if questions.count > 3 {
                    searchSection
                }

                // Questions List
                if filteredQuestions.isEmpty {
                    emptyStateView
                } else {
                    questionsListSection
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
                            .foregroundColor(.blue)
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
            }
            .onChange(of: showingQuestionDetail) { _, newValue in
                if !newValue {
                    logger.debug("🔄 Question detail dismissed")
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
            .background(Color.blue)
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
            .background(Color.green)
            .cornerRadius(12)
        }
    }

    private var searchSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundColor(.secondary)

                TextField(NSLocalizedString("generatedQuestions.searchPlaceholder", comment: ""), text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(
                colorScheme == .dark
                    ? Color(.systemGray5)
                    : Color.gray.opacity(0.1)
            )
            .cornerRadius(8)

            // Filter summary
            HStack {
                Text(String.localizedStringWithFormat(NSLocalizedString("generatedQuestions.questionsCount", comment: ""), filteredQuestions.count, questions.count))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !searchText.isEmpty {
                    Text(String.localizedStringWithFormat(NSLocalizedString("generatedQuestions.filteredBy", comment: ""), searchText))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var questionsListSection: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(filteredQuestions.indices, id: \.self) { index in
                    let question = filteredQuestions[index]
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
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contentShape(Rectangle())
                    }
                    .background(DesignTokens.AdaptiveColors.cardBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelectionMode && selectedQuestions.contains(question.id)
                                    ? Color.blue
                                    : DesignTokens.AdaptiveColors.border(colorScheme: colorScheme),
                                lineWidth: isSelectionMode && selectedQuestions.contains(question.id) ? 3 : 2
                            )
                    )
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
                if filteredQuestions.count == questions.count {
                    questionsSummary
                        .padding(.top, 24)
                }
            }
            .padding()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "questionmark.folder")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text(searchText.isEmpty ? NSLocalizedString("generatedQuestions.noQuestions", comment: "") : NSLocalizedString("generatedQuestions.noMatchingQuestions", comment: ""))
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(searchText.isEmpty ?
                     NSLocalizedString("generatedQuestions.noQuestionsMessage", comment: "") :
                     NSLocalizedString("generatedQuestions.noMatchingMessage", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !searchText.isEmpty {
                Button(NSLocalizedString("generatedQuestions.clearSearch", comment: "")) {
                    searchText = ""
                }
                .font(.subheadline)
                .foregroundColor(.blue)
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
                            color: .blue
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
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(
                    colorScheme == .dark
                        ? Color(.systemGray5)
                        : Color.gray.opacity(0.1)
                )
                .cornerRadius(12)
            }
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
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

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
                            String(question.explanation.prefix(80)) + (question.explanation.count > 80 ? "..." : ""),
                            fontSize: 12,
                            colorScheme: colorScheme
                        )
                        .foregroundColor(.secondary)
                        .lineLimit(2)
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
    @State private var pdfURL: URL?
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
            }
            .task {
                await generatePDF()
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
            generationType: generationType
        )

        await MainActor.run {
            self.pdfDocument = document

            // Save PDF to temporary directory for sharing
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