//
//  HomeworkResultsView.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import SwiftUI
import os.log

struct HomeworkResultsView: View {
    @State var parsingResult: HomeworkParsingResult
    @State var enhancedResult: EnhancedHomeworkParsingResult?
    let originalImageUrl: String?
    let submittedImage: UIImage?  // NEW: Actual image for local storage
    @State private var expandedQuestions: Set<String> = []
    @State private var showingQuestionArchiveDialog = false
    @State private var isArchiving = false
    @State private var selectedQuestionIndices: Set<Int> = []
    @State private var questionNotes: [String] = []
    @State private var questionTags: [[String]] = []
    @State private var hasMarkedProgress = false
    @State private var hasAlreadySavedImage = false
    @State private var showingNoQuestionsAlert = false
    @State private var showingResultsInfo = false
    @StateObject private var questionArchiveService = QuestionArchiveService.shared

    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @StateObject private var homeworkImageStorage = HomeworkImageStorageService.shared  // NEW: Storage service
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

    // ✅ Logger for debugging
    private let logger = AppLogger.homework

    // Generate unique session ID for this homework session
    private var sessionId: String {
        let questionsContent = parsingResult.allQuestions.map { $0.questionText + $0.answerText }.joined()
        let processingTimeString = String(parsingResult.processingTime)
        let combinedString = questionsContent + processingTimeString
        return String(combinedString.hashValue)
    }

    // Key for storing progress state in UserDefaults
    private var progressMarkedKey: String {
        return "homework_progress_marked_\(sessionId)"
    }

    // Key for storing album save state in UserDefaults
    private var albumSavedKey: String {
        return "homework_album_saved_\(sessionId)"
    }

    // Dynamic navigation title with subject
    private var navigationTitle: String {
        if let subject = enhancedResult?.detectedSubject {
            return String(format: NSLocalizedString("homeworkResults.titleWithSubject", comment: ""), subject)
        }
        return NSLocalizedString("homeworkResults.yourScore", comment: "")
    }

    // Enhanced initializer that can accept either type
    init(parsingResult: HomeworkParsingResult, originalImageUrl: String?, submittedImage: UIImage? = nil) {
        self.parsingResult = parsingResult
        self.enhancedResult = nil
        self.originalImageUrl = originalImageUrl
        self.submittedImage = submittedImage
    }

    init(enhancedResult: EnhancedHomeworkParsingResult, originalImageUrl: String?, submittedImage: UIImage? = nil) {
        // Convert enhanced result to basic result for compatibility
        self.parsingResult = HomeworkParsingResult(
            questions: enhancedResult.questions,
            processingTime: enhancedResult.processingTime,
            overallConfidence: enhancedResult.overallConfidence,
            parsingMethod: enhancedResult.parsingMethod,
            rawAIResponse: enhancedResult.rawAIResponse,
            performanceSummary: enhancedResult.performanceSummary
        )
        self.enhancedResult = enhancedResult
        self.originalImageUrl = originalImageUrl
        self.submittedImage = submittedImage
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Results Summary
                    resultsSummarySection
                    
                    // Performance Summary
                    if let enhanced = enhancedResult, let summary = enhanced.performanceSummary {
                        performanceSummarySection(summary)
                    } else if parsingResult.performanceSummary != nil {
                        performanceSummarySection(parsingResult.performanceSummary!)
                    }

                    // ✅ Handwriting Evaluation (Pro Mode only)
                    if let enhanced = enhancedResult,
                       let handwriting = enhanced.handwritingEvaluation,
                       handwriting.hasHandwriting {
                        HandwritingEvaluationView(evaluation: handwriting)
                    }

                    // Question Selection Controls
                    questionSelectionSection
                    
                    // Questions List
                    questionsListSection

                    // Mark Progress Button
                    markProgressButton
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingResultsInfo = true }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // ✅ Validate that questions are selected
                        if selectedQuestionIndices.isEmpty {
                            showingNoQuestionsAlert = true
                        } else {
                            showingQuestionArchiveDialog = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "books.vertical.fill")
                            Text(NSLocalizedString("homeworkResults.archive", comment: ""))
                        }
                        .foregroundColor(.blue)
                    }
                    .disabled(isArchiving)
                }
            }
            .alert(NSLocalizedString("homeworkResults.info.title", comment: ""), isPresented: $showingResultsInfo) {
                Button(NSLocalizedString("common.ok", comment: "")) { }
            } message: {
                Text(NSLocalizedString("homeworkResults.info.message", comment: ""))
            }
            .sheet(isPresented: $showingQuestionArchiveDialog) {
                QuestionArchiveView(
                    questions: parsingResult.allQuestions,
                    selectedIndices: $selectedQuestionIndices,
                    questionNotes: $questionNotes,
                    questionTags: $questionTags,
                    originalImageUrl: originalImageUrl ?? "",
                    processingTime: parsingResult.processingTime,
                    initialDetectedSubject: enhancedResult?.detectedSubject,
                    initialSubjectConfidence: enhancedResult?.subjectConfidence,
                    onArchive: { detectedSubject, subjectConfidence, userNotes, userTags in
                        let archiveRequest = QuestionArchiveRequest(
                            questions: parsingResult.allQuestions,
                            selectedQuestionIndices: Array(selectedQuestionIndices),
                            detectedSubject: enhancedResult?.detectedSubject ?? detectedSubject,
                            subjectConfidence: enhancedResult?.subjectConfidence ?? subjectConfidence,
                            originalImageUrl: originalImageUrl,
                            processingTime: parsingResult.processingTime,
                            userNotes: userNotes,
                            userTags: userTags
                        )
                        Task {
                            await archiveSelectedQuestions(archiveRequest)
                        }
                    }
                )
            }
            .alert(NSLocalizedString("homeworkResults.noQuestionsSelected", comment: "No Questions Selected"), isPresented: $showingNoQuestionsAlert) {
                Button(NSLocalizedString("common.ok", comment: "OK"), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("homeworkResults.selectQuestionsToArchiveMessage", comment: "Please select at least one question to archive."))
            }
            .onAppear {
                initializeQuestionData()
                loadProgressState()

                // ❌ REMOVED: Auto-save moved to Mark Progress button
                // saveHomeworkImageToStorage()
            }
            .onDisappear {
            }
        }
    }
    
    // MARK: - Results Summary
    
    private var resultsSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Enhanced subject detection display
            if let enhanced = enhancedResult {
                HStack {
                    Text(NSLocalizedString("homeworkResults.subject", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(DesignTokens.AdaptiveColors.secondaryText)
                    Text(enhanced.detectedSubject)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(DesignTokens.AdaptiveColors.primaryText)

                    if enhanced.isHighConfidenceSubject {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Spacer()
                }
                .padding(.bottom, 4)
            }

            HStack(spacing: 16) {
                StatCard(
                    title: NSLocalizedString("homeworkResults.questions", comment: ""),
                    value: "\(parsingResult.questionCount)",
                    icon: "questionmark.circle.fill",
                    color: .blue
                )

                StatCard(
                    title: NSLocalizedString("homeworkResults.accuracy", comment: ""),
                    value: String(format: "%.0f%%",
                        (enhancedResult?.calculatedAccuracy ?? parsingResult.calculatedAccuracy) * 100),
                    icon: "target",
                    color: accuracyColor(enhancedResult?.calculatedAccuracy ?? parsingResult.calculatedAccuracy)
                )
            }
        }
        .padding()
        .background(DesignTokens.AdaptiveColors.summaryBackground(colorScheme: colorScheme))
        .cornerRadius(16)
    }
    
    // MARK: - Performance Summary

    private func performanceSummarySection(_ summary: PerformanceSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with icon
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.title3)
                    .foregroundColor(.white)

                Text(NSLocalizedString("homeworkResults.performanceSummary", comment: ""))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()
            }

            // AI Summary Text with enhanced styling
            Text(summary.summaryText)
                .font(.body)
                .foregroundColor(.white.opacity(0.95))
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .padding(.vertical, 4)

            // Score breakdown (if there are incorrect answers)
            if summary.totalIncorrect > 0 || summary.totalEmpty > 0 || summary.totalPartialCredit > 0 {
                VStack(spacing: 12) {
                    Divider()
                        .background(Color.white.opacity(0.3))

                    HStack(spacing: 12) {
                        if summary.totalCorrect > 0 {
                            EnhancedScoreBreakdownItem(
                                count: summary.totalCorrect,
                                label: NSLocalizedString("homeworkResults.correct", comment: ""),
                                color: .green,
                                icon: "checkmark.circle.fill"
                            )
                        }

                        if summary.totalIncorrect > 0 {
                            EnhancedScoreBreakdownItem(
                                count: summary.totalIncorrect,
                                label: NSLocalizedString("homeworkResults.incorrect", comment: ""),
                                color: .red,
                                icon: "xmark.circle.fill"
                            )
                        }

                        if summary.totalPartialCredit > 0 {
                            EnhancedScoreBreakdownItem(
                                count: summary.totalPartialCredit,
                                label: NSLocalizedString("homeworkResults.partialCredit", comment: ""),
                                color: .orange,
                                icon: "checkmark.circle"
                            )
                        }

                        if summary.totalEmpty > 0 {
                            EnhancedScoreBreakdownItem(
                                count: summary.totalEmpty,
                                label: NSLocalizedString("homeworkResults.empty", comment: ""),
                                color: .gray,
                                icon: "minus.circle.fill"
                            )
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(
            ZStack {
                // Adaptive gradient background
                DesignTokens.AdaptiveColors.performanceGradient(colorScheme: colorScheme)

                // Adaptive shimmer overlay
                DesignTokens.AdaptiveColors.shimmerOverlay(colorScheme: colorScheme)
            }
        )
        .cornerRadius(20)
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.3) : Color.blue.opacity(0.4),
            radius: 20,
            x: 0,
            y: 10
        )
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.2) : Color.blue.opacity(0.3),
            radius: 10,
            x: 0,
            y: 5
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }
    
    // MARK: - Questions List
    
    private var questionsListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("homeworkResults.questionsAndAnswers", comment: ""))
                .font(.headline)
                .foregroundColor(DesignTokens.AdaptiveColors.primaryText)
                .padding(.horizontal)

            // Numbered Questions
            if !parsingResult.numberedQuestions.isEmpty {
                ForEach(Array(parsingResult.numberedQuestions.enumerated()), id: \.element.id) { index, question in
                    QuestionAnswerCard(
                        question: question,
                        isExpanded: expandedQuestions.contains(question.id),
                        isSelected: selectedQuestionIndices.contains(index),
                        onToggle: {
                            toggleQuestion(question.id)
                        },
                        onSelectionToggle: {
                            toggleQuestionSelection(index)
                        },
                        showSelection: true,
                        onDismissParent: {
                            dismiss()
                        },
                        enhancedResult: enhancedResult
                    )
                }
            }

            // Unnumbered Questions (as bullet points)
            if !parsingResult.unnumberedQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if !parsingResult.numberedQuestions.isEmpty {
                        Divider()
                            .padding(.vertical, 8)
                    }

                    Text(NSLocalizedString("homeworkResults.additionalItems", comment: ""))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(DesignTokens.AdaptiveColors.secondaryText)
                        .padding(.horizontal)

                    ForEach(Array(parsingResult.unnumberedQuestions.enumerated()), id: \.element.id) { index, question in
                        let adjustedIndex = parsingResult.numberedQuestions.count + index
                        QuestionAnswerCard(
                            question: question,
                            isExpanded: expandedQuestions.contains(question.id),
                            isSelected: selectedQuestionIndices.contains(adjustedIndex),
                            onToggle: {
                                toggleQuestion(question.id)
                            },
                            onSelectionToggle: {
                                toggleQuestionSelection(adjustedIndex)
                            },
                            showAsBullet: true,
                            showSelection: true,
                            onDismissParent: {
                                dismiss()
                            },
                            enhancedResult: enhancedResult
                        )
                    }
                }
            }
        }
    }

    // MARK: - Question Selection Section
    
    private var questionSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("homeworkResults.selectQuestionsToArchive", comment: ""))
                    .font(.headline)
                    .foregroundColor(DesignTokens.AdaptiveColors.primaryText)
                Spacer()
                Button(selectedQuestionIndices.count == parsingResult.allQuestions.count ? NSLocalizedString("common.deselectAll", comment: "") : NSLocalizedString("common.selectAll", comment: "")) {
                    if selectedQuestionIndices.count == parsingResult.allQuestions.count {
                        selectedQuestionIndices.removeAll()
                    } else {
                        selectedQuestionIndices = Set(0..<parsingResult.allQuestions.count)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }

            HStack {
                Text("\(selectedQuestionIndices.count) \(NSLocalizedString("common.of", comment: "")) \(parsingResult.allQuestions.count) \(NSLocalizedString("homeworkResults.questionsSelected", comment: ""))")
                    .font(.caption)
                    .foregroundColor(DesignTokens.AdaptiveColors.secondaryText)
                Spacer()
            }
        }
        .padding()
        .background(DesignTokens.AdaptiveColors.selectionBackground(colorScheme: colorScheme))
        .cornerRadius(12)
    }
    
    // MARK: - Mark Progress Button

    private var markProgressButton: some View {
        VStack(spacing: 16) {
            SlideToConfirmButton(
                text: NSLocalizedString("homeworkResults.slideToMarkProgress", comment: ""),
                confirmedText: NSLocalizedString("homeworkResults.progressMarked", comment: ""),
                icon: "arrow.right",
                confirmedIcon: "checkmark",
                color: .blue,
                confirmedColor: .green,
                isConfirmed: hasMarkedProgress
            ) {
                // Only track if not already marked
                if !hasMarkedProgress {
                    trackHomeworkUsage()
                    hasMarkedProgress = true
                    saveProgressState() // Persist the state

                    // ✅ NEW: Save to album when marking progress
                    saveHomeworkImageToStorage()
                }
            }

            if hasMarkedProgress {
                Text(NSLocalizedString("homeworkResults.progressUpdated", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
            } else {
                Text(String(format: NSLocalizedString("homeworkResults.tapToAddQuestions", comment: ""), parsingResult.allQuestions.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Helper Methods
    
    private func initializeQuestionData() {
        let totalQuestions = parsingResult.allQuestions.count
        questionNotes = Array(repeating: "", count: totalQuestions)
        questionTags = Array(repeating: [], count: totalQuestions)
    }

    /// Load the progress state from UserDefaults based on session ID
    private func loadProgressState() {
        hasMarkedProgress = UserDefaults.standard.bool(forKey: progressMarkedKey)
        hasAlreadySavedImage = UserDefaults.standard.bool(forKey: albumSavedKey)
    }

    /// Save the progress state to UserDefaults
    private func saveProgressState() {
        UserDefaults.standard.set(hasMarkedProgress, forKey: progressMarkedKey)
        UserDefaults.standard.set(hasAlreadySavedImage, forKey: albumSavedKey)
    }
    
    private func toggleQuestion(_ questionId: String) {
        if expandedQuestions.contains(questionId) {
            expandedQuestions.remove(questionId)
        } else {
            expandedQuestions.insert(questionId)
        }
    }
    
    private func toggleQuestionSelection(_ index: Int) {
        if selectedQuestionIndices.contains(index) {
            selectedQuestionIndices.remove(index)
        } else {
            selectedQuestionIndices.insert(index)
        }
    }
    
    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.6 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func accuracyColor(_ accuracy: Float) -> Color {
        if accuracy >= 0.9 {
            return .green
        } else if accuracy >= 0.7 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Question Answer Card

struct QuestionAnswerCard: View {
    let question: ParsedQuestion
    let isExpanded: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    let onSelectionToggle: (() -> Void)?
    let showAsBullet: Bool
    let showSelection: Bool
    let onDismissParent: (() -> Void)?
    let enhancedResult: EnhancedHomeworkParsingResult?
    @ObservedObject private var appState = AppState.shared
    @State private var expandedSubquestions: Set<String> = []
    @Environment(\.colorScheme) var colorScheme

    init(question: ParsedQuestion, isExpanded: Bool, isSelected: Bool = false, onToggle: @escaping () -> Void, onSelectionToggle: (() -> Void)? = nil, showAsBullet: Bool = false, showSelection: Bool = false, onDismissParent: (() -> Void)? = nil, enhancedResult: EnhancedHomeworkParsingResult? = nil) {
        self.question = question
        self.isExpanded = isExpanded
        self.isSelected = isSelected
        self.onToggle = onToggle
        self.onSelectionToggle = onSelectionToggle
        self.showAsBullet = showAsBullet
        self.showSelection = showSelection
        self.onDismissParent = onDismissParent
        self.enhancedResult = enhancedResult
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Check if this is a parent question with subquestions
            if question.isParent == true && question.hasSubquestions == true {
                parentQuestionView
            } else {
                regularQuestionView
            }
        }
        .background(isSelected ? DesignTokens.AdaptiveColors.selectionBackground(colorScheme: colorScheme) : DesignTokens.AdaptiveColors.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : DesignTokens.AdaptiveColors.border(colorScheme: colorScheme), lineWidth: isSelected ? 2 : 1)
        )
    }

    // MARK: - Parent Question View
    private var parentQuestionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Parent Question Header
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 12) {
                    // Selection checkbox (if enabled)
                    if showSelection {
                        VStack {
                            Button(action: {
                                onSelectionToggle?()
                            }) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .font(.title3)
                                    .foregroundColor(isSelected ? .blue : .gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.top, 2)
                            Spacer()
                        }
                    }

                    // Parent Question Number
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.purple.opacity(0.2))
                            .frame(width: 36, height: 28)

                        Text(question.questionNumber?.description ?? "?")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                    }

                    // Parent Content
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(question.parentContent ?? "Parent Question")
                                .font(.body)
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.leading)
                                .foregroundColor(DesignTokens.AdaptiveColors.primaryText)

                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }

                        // Subquestion count
                        Text("\(question.subquestions?.count ?? 0) subquestions")
                            .font(.caption2)
                            .foregroundColor(.gray)

                        // Parent summary score if available
                        if let summary = question.parentSummary {
                            Text(summary.scoreText)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                    }

                    Spacer()

                    // Expand/Collapse Icon
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.title3)
                        .foregroundColor(.purple)
                }
                .padding()
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded Subquestions
            if isExpanded, let subquestions = question.subquestions {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .padding(.horizontal)

                    // Parent summary feedback
                    if let summary = question.parentSummary, let feedback = summary.overallFeedback, !feedback.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Overall Feedback")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.gray)

                                Text(feedback)
                                    .font(.body)
                                    .foregroundColor(DesignTokens.AdaptiveColors.primaryText)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(Color.orange.opacity(0.05))
                    }

                    // Subquestions List
                    ForEach(Array(subquestions.enumerated()), id: \.element.id) { index, subquestion in
                        VStack(alignment: .leading, spacing: 0) {
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 48)
                            }

                            SubquestionCard(
                                subquestion: subquestion,
                                isExpanded: expandedSubquestions.contains(subquestion.id),
                                onToggle: {
                                    toggleSubquestion(subquestion.id)
                                }
                            )
                        }
                    }
                }
                .background(Color.purple.opacity(0.02))
            }
        }
    }

    // MARK: - Regular Question View
    private var regularQuestionView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Question Header
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 12) {
                    // Selection checkbox (if enabled)
                    if showSelection {
                        VStack {
                            Button(action: {
                                onSelectionToggle?()
                            }) {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .font(.title3)
                                    .foregroundColor(isSelected ? .blue : .gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.top, 2)
                            Spacer()
                        }
                    }
                    
                    // Question Number or Bullet
                    questionIndicator
                    
                    // Question Text
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question.questionText)
                            .font(.body)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(DesignTokens.AdaptiveColors.primaryText)
                        
                        // Metadata
                        HStack(spacing: 12) {
                            // Show grading info if available
                            if question.isGraded {
                                HStack(spacing: 4) {
                                    Image(systemName: question.gradeIcon)
                                        .font(.caption2)
                                        .foregroundColor(question.gradeColor)
                                    Text(question.grade ?? "")
                                        .font(.caption2)
                                        .foregroundColor(question.gradeColor)
                                    
                                    if !question.scoreText.isEmpty {
                                        Text("(\(question.scoreText))")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                            } else if let confidence = question.confidence, confidence < 1.0 {
                                // Legacy confidence display
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                        .foregroundColor(confidenceColor(confidence))
                                    Text(String(format: "%.0f%%", confidence * 100))
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            if question.hasVisualElements {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text(NSLocalizedString("homeworkResults.hasVisual", comment: ""))
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Expand/Collapse Icon
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(DesignTokens.AdaptiveColors.secondaryText)
                }
                .padding()
            }
            .buttonStyle(PlainButtonStyle())

            // Answer Content (Collapsible)
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    // Use type-specific renderer
                    QuestionTypeRendererSelector(
                        question: question,
                        isExpanded: true,
                        onTapAskAI: {
                            // Dismiss the parent report view first
                            onDismissParent?()

                            // Small delay to ensure view is dismissed before navigation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                // Detect subject from question or use enhanced result
                                let detectedSubject = enhancedResult?.detectedSubject ?? detectSubjectFromQuestion(question.questionText)

                                // Build comprehensive homework context
                                let homeworkContext = HomeworkQuestionContext(
                                    questionText: question.questionText,
                                    rawQuestionText: question.rawQuestionText,
                                    studentAnswer: question.studentAnswer,
                                    correctAnswer: question.correctAnswer,
                                    currentGrade: question.grade,  // CORRECT, INCORRECT, EMPTY, PARTIAL_CREDIT
                                    originalFeedback: question.feedback,
                                    pointsEarned: question.pointsEarned,
                                    pointsPossible: question.pointsPossible,
                                    questionNumber: question.questionNumber,
                                    subject: detectedSubject,
                                    questionImage: nil  // QuestionAnswerCard doesn't have access to the homework image
                                )

                                // Construct user message for AI with explicit context
                                var userMessage = """
I need help understanding this question from my homework:

Question: \(question.rawQuestionText ?? question.questionText)
"""

                                // Add student answer if available
                                if question.isGraded, let studentAnswer = question.studentAnswer, !studentAnswer.isEmpty {
                                    userMessage += "\n\nMy answer was: \(studentAnswer)"
                                }

                                // IMPORTANT: Explicitly include the correct answer and current grade
                                // This helps the AI detect if there was a grading error
                                if let correctAnswer = question.correctAnswer, !correctAnswer.isEmpty {
                                    userMessage += "\n\nThe AI grader said the correct answer is: \(correctAnswer)"
                                }

                                if let grade = question.grade {
                                    userMessage += "\nMy current grade for this question is: \(grade)"
                                    if let pointsEarned = question.pointsEarned, let pointsPossible = question.pointsPossible {
                                        userMessage += " (\(String(format: "%.1f", pointsEarned))/\(String(format: "%.1f", pointsPossible)) points)"
                                    }
                                }

                                userMessage += "\n\nI'm unclear about how to approach this problem. Can you help me understand it better?"

                                // Enhanced logging for debugging
                                print("📚 === ASK AI FOR HELP - CONTEXT ===")
                                print("Question #\(question.questionNumber ?? 0)")
                                print("Grade: \(question.grade ?? "None")")
                                print("Student Answer: \(question.studentAnswer ?? "None")")
                                print("Correct Answer: \(question.correctAnswer ?? "None")")
                                print("Points: \(question.pointsEarned ?? 0)/\(question.pointsPossible ?? 0)")
                                print("===================================")

                                // Navigate to chat with full homework context
                                appState.navigateToChatWithHomeworkQuestion(
                                    message: userMessage,
                                    context: homeworkContext
                                )

                                // Haptic feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                            }
                        }
                    )
                    .padding(.horizontal)

                    // Bottom padding
                    Color.clear.frame(height: 4)
                }
                .background(question.isGraded ? question.gradeColor.opacity(0.05) : DesignTokens.AdaptiveColors.cardBackgroundElevated)
            }
        }
        .background(isSelected ? DesignTokens.AdaptiveColors.selectionBackground(colorScheme: colorScheme) : DesignTokens.AdaptiveColors.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : DesignTokens.AdaptiveColors.border(colorScheme: colorScheme), lineWidth: isSelected ? 2 : 1)
        )
    }

    // MARK: - Helper Methods
    private func toggleSubquestion(_ subquestionId: String) {
        if expandedSubquestions.contains(subquestionId) {
            expandedSubquestions.remove(subquestionId)
        } else {
            expandedSubquestions.insert(subquestionId)
        }
    }

    private var questionIndicator: some View {
        Group {
            if showAsBullet {
                // Bullet point for unnumbered questions
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .padding(.top, 8)
            } else if question.isGraded {
                // Grade indicator for graded questions
                ZStack {
                    Circle()
                        .fill(question.gradeColor)
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: question.gradeIcon)
                        .font(.caption)
                        .foregroundColor(.white)
                }
            } else {
                // Numbered circle for numbered questions (legacy)
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 28, height: 28)
                    
                    Text(question.questionNumber?.description ?? "?")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.6 {
            return .orange
        } else {
            return .red
        }
    }

    /// Simple subject detection from question text
    private func detectSubjectFromQuestion(_ questionText: String) -> String {
        let lowercaseText = questionText.lowercased()

        // Math keywords
        if lowercaseText.contains("equation") || lowercaseText.contains("solve") ||
           lowercaseText.contains("calculate") || lowercaseText.contains("algebra") ||
           lowercaseText.contains("geometry") || lowercaseText.contains("integral") ||
           lowercaseText.contains("derivative") || lowercaseText.contains("function") {
            return "Math"
        }

        // Physics keywords
        if lowercaseText.contains("force") || lowercaseText.contains("velocity") ||
           lowercaseText.contains("acceleration") || lowercaseText.contains("energy") ||
           lowercaseText.contains("momentum") || lowercaseText.contains("wave") ||
           lowercaseText.contains("electric") || lowercaseText.contains("magnetic") {
            return "Physics"
        }

        // Chemistry keywords
        if lowercaseText.contains("element") || lowercaseText.contains("compound") ||
           lowercaseText.contains("reaction") || lowercaseText.contains("molecule") ||
           lowercaseText.contains("atom") || lowercaseText.contains("chemical") ||
           lowercaseText.contains("periodic") || lowercaseText.contains("bond") {
            return "Chemistry"
        }

        // Biology keywords
        if lowercaseText.contains("cell") || lowercaseText.contains("organism") ||
           lowercaseText.contains("dna") || lowercaseText.contains("gene") ||
           lowercaseText.contains("evolution") || lowercaseText.contains("ecosystem") ||
           lowercaseText.contains("species") || lowercaseText.contains("protein") {
            return "Biology"
        }

        // Default to General if no specific subject detected
        return "General"
    }
}

// MARK: - Subquestion Card
struct SubquestionCard: View {
    let subquestion: ParsedQuestion
    let isExpanded: Bool
    let onToggle: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Subquestion Header
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 12) {
                    // Subquestion Number Badge
                    ZStack {
                        Circle()
                            .fill(subquestion.gradeColor.opacity(0.2))
                            .frame(width: 28, height: 28)

                        if let subNum = subquestion.subquestionNumber {
                            Text(subNum)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(subquestion.gradeColor)
                        } else {
                            Image(systemName: subquestion.gradeIcon)
                                .font(.caption)
                                .foregroundColor(subquestion.gradeColor)
                        }
                    }

                    // Subquestion Text
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subquestion.questionText)
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                            .foregroundColor(DesignTokens.AdaptiveColors.primaryText)

                        // Grade and Score
                        HStack(spacing: 12) {
                            if subquestion.isGraded {
                                HStack(spacing: 4) {
                                    Image(systemName: subquestion.gradeIcon)
                                        .font(.caption2)
                                        .foregroundColor(subquestion.gradeColor)
                                    Text(subquestion.grade ?? "")
                                        .font(.caption2)
                                        .foregroundColor(subquestion.gradeColor)

                                    if !subquestion.scoreText.isEmpty {
                                        Text("(\(subquestion.scoreText))")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }

                    Spacer()

                    // Expand/Collapse Icon
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding()
                .padding(.leading, 24)  // Extra indent for subquestions
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded Answer Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .padding(.leading, 48)

                    // Student Answer
                    if let studentAnswer = subquestion.studentAnswer, !studentAnswer.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Student Answer")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.gray)

                                Text(studentAnswer)
                                    .font(.subheadline)
                                    .foregroundColor(DesignTokens.AdaptiveColors.primaryText)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                            }

                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.leading, 48)
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundColor(.gray)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Student Answer")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.gray)

                                Text("No answer provided")
                                    .font(.subheadline)
                                    .italic()
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.leading, 48)
                    }

                    // Correct Answer
                    if let correctAnswer = subquestion.correctAnswer, !correctAnswer.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundColor(.orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Correct Answer")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.gray)

                                Text(correctAnswer)
                                    .font(.subheadline)
                                    .foregroundColor(DesignTokens.AdaptiveColors.primaryText)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                            }

                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.leading, 48)
                    }

                    // Feedback
                    if let feedback = subquestion.feedback, !feedback.isEmpty && feedback != "No feedback provided" {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "bubble.left.fill")
                                .font(.caption)
                                .foregroundColor(.purple)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Feedback")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.gray)

                                Text(feedback)
                                    .font(.subheadline)
                                    .foregroundColor(DesignTokens.AdaptiveColors.primaryText)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                            }

                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.leading, 48)
                    }

                    // Bottom padding
                    Color.clear.frame(height: 4)
                }
                .background(subquestion.gradeColor.opacity(0.03))
            }
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(DesignTokens.AdaptiveColors.primaryText)

            Text(title)
                .font(.caption)
                .foregroundColor(DesignTokens.AdaptiveColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            colorScheme == .dark
                ? color.opacity(0.15)
                : color.opacity(0.1)
        )
        .cornerRadius(12)
    }
}

// MARK: - Score Breakdown Item

struct ScoreBreakdownItem: View {
    let count: Int
    let label: String
    let color: Color
    let icon: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)

            Text("\(count)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(DesignTokens.AdaptiveColors.primaryText)

            Text(label)
                .font(.caption)
                .foregroundColor(DesignTokens.AdaptiveColors.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            colorScheme == .dark
                ? color.opacity(0.2)
                : color.opacity(0.1)
        )
        .cornerRadius(8)
    }
}

// MARK: - Enhanced Score Breakdown Item (for glowing card)

struct EnhancedScoreBreakdownItem: View {
    let count: Int
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview {
    HomeworkResultsView(
        parsingResult: HomeworkParsingResult(
            questions: [
                ParsedQuestion(
                    questionNumber: 1,
                    questionText: "What is the value of x in the equation 2x + 5 = 15?",
                    answerText: "To solve for x: 2x + 5 = 15. Subtract 5 from both sides: 2x = 10. Divide by 2: x = 5.",
                    confidence: 0.95
                ),
                ParsedQuestion(
                    questionNumber: 2,
                    questionText: "Calculate the area of a circle with radius 7 cm.",
                    answerText: "Area = πr² = π × 7² = π × 49 = 49π ≈ 153.94 cm²",
                    confidence: 0.92,
                    hasVisualElements: true
                ),
                ParsedQuestion(
                    questionText: "Additional note: Remember to show all work.",
                    answerText: "This is a general reminder for all problems.",
                    confidence: 0.7
                )
            ],
            processingTime: 2.3,
            overallConfidence: 0.86,
            parsingMethod: "AI-Powered Parsing",
            rawAIResponse: "QUESTION_NUMBER: 1\nQUESTION: What is...",
            performanceSummary: nil
        ),
        originalImageUrl: "test-url"
    )
}

// MARK: - Archive Function Extension

extension HomeworkResultsView {
    private func archiveSelectedQuestions(_ request: QuestionArchiveRequest) async {
        isArchiving = true

        do {
            let _ = try await questionArchiveService.archiveQuestions(request)

            await MainActor.run {
                // ✅ LOCAL-FIRST: Questions are saved locally only
                isArchiving = false
                showingQuestionArchiveDialog = false
                selectedQuestionIndices.removeAll()
            }
        } catch {
            await MainActor.run {
                isArchiving = false
            }
        }
    }
    
    /// Track homework grading usage for points earning system
    /// ⚠️ IMPORTANT: This function ALWAYS tracks ALL questions from the homework report,
    /// regardless of which questions are selected. Selection only affects archiving, not progress tracking.
    private func trackHomeworkUsage() {
        // ✅ ALWAYS use ALL questions from the report, not just selected ones
        let questions = parsingResult.allQuestions

        // Get subject from enhanced result or try to detect from question text
        let subject = enhancedResult?.detectedSubject ?? detectSubjectFromQuestion(questions.first?.questionText ?? "")

        // ✅ FIX: Always use actual question grades, not AI's initial performance summary
        // This ensures we track the user's manual grading, not the AI's initial assessment

        // Count correct and incorrect based on actual grades
        var correctCount = 0
        var incorrectCount = 0

        for question in questions {
            // Determine if this was a correct answer based on grading result
            let isCorrect: Bool
            if question.isGraded {
                // Use the actual grading result (user's manual grading)
                isCorrect = question.grade == "CORRECT" ||
                           question.grade?.lowercased().contains("correct") == true ||
                           question.grade?.lowercased().contains("right") == true ||
                           question.grade == "✓" || question.grade == "A"
            } else {
                // For non-graded questions, assume incorrect for conservative accuracy
                isCorrect = false
            }

            if isCorrect {
                correctCount += 1
            } else {
                incorrectCount += 1
            }
        }

        // ✅ FIX: Use new counter-based markHomeworkProgress() method
        // Call once with aggregated counts instead of looping through each question
        let totalQuestions = correctCount + incorrectCount
        pointsManager.markHomeworkProgress(
            subject: subject,
            numberOfQuestions: totalQuestions,
            numberOfCorrectQuestions: correctCount
        )

        print("📊 [trackHomeworkUsage] ✅ Marked progress: \(totalQuestions) total questions, \(correctCount) correct, \(incorrectCount) incorrect")
    }
    
    /// Simple subject detection from question text
    private func detectSubjectFromQuestion(_ questionText: String) -> String {
        let lowercaseText = questionText.lowercased()

        // Math keywords
        if lowercaseText.contains("equation") || lowercaseText.contains("solve") ||
           lowercaseText.contains("calculate") || lowercaseText.contains("algebra") ||
           lowercaseText.contains("geometry") || lowercaseText.contains("integral") ||
           lowercaseText.contains("derivative") || lowercaseText.contains("function") {
            return "Math"
        }

        // Physics keywords
        if lowercaseText.contains("force") || lowercaseText.contains("velocity") ||
           lowercaseText.contains("acceleration") || lowercaseText.contains("energy") ||
           lowercaseText.contains("momentum") || lowercaseText.contains("wave") ||
           lowercaseText.contains("electric") || lowercaseText.contains("magnetic") {
            return "Physics"
        }

        // Chemistry keywords
        if lowercaseText.contains("element") || lowercaseText.contains("compound") ||
           lowercaseText.contains("reaction") || lowercaseText.contains("molecule") ||
           lowercaseText.contains("atom") || lowercaseText.contains("chemical") ||
           lowercaseText.contains("periodic") || lowercaseText.contains("bond") {
            return "Chemistry"
        }

        // Biology keywords
        if lowercaseText.contains("cell") || lowercaseText.contains("organism") ||
           lowercaseText.contains("dna") || lowercaseText.contains("gene") ||
           lowercaseText.contains("evolution") || lowercaseText.contains("ecosystem") ||
           lowercaseText.contains("species") || lowercaseText.contains("protein") {
            return "Biology"
        }

        // Default to General if no specific subject detected
        return "General"
    }

    // MARK: - Homework Image Storage

    /// Automatically save homework image to local storage
    private func saveHomeworkImageToStorage() {
        logger.homeworkAlbum("=== Attempting to Save to Album ===")

        // Guard: Only save once per session (persistent check)
        guard !hasAlreadySavedImage else {
            logger.homeworkAlbum("Image already saved for this session (persistent), skipping")
            return
        }

        // Only save if we have an image
        guard let image = submittedImage else {
            logger.warning("No submitted image to save to album")
            return
        }

        // Extract metadata from results
        let subject = enhancedResult?.detectedSubject ?? detectSubjectFromQuestion(parsingResult.allQuestions.first?.questionText ?? "")
        let accuracy = enhancedResult?.calculatedAccuracy ?? parsingResult.calculatedAccuracy
        let questionCount = parsingResult.allQuestions.count

        logger.homeworkAlbum("Metadata extracted:")
        logger.homeworkAlbum("  Session ID: \(sessionId)")
        logger.homeworkAlbum("  Subject: \(subject)")
        logger.homeworkAlbum("  Accuracy: \(String(format: "%.1f%%", accuracy * 100))")
        logger.homeworkAlbum("  Questions: \(questionCount)")

        // Calculate correct/incorrect counts
        var correctCount = 0
        var incorrectCount = 0
        for question in parsingResult.allQuestions {
            if question.isGraded {
                if question.grade == "CORRECT" ||
                   question.grade?.lowercased().contains("correct") == true {
                    correctCount += 1
                } else {
                    incorrectCount += 1
                }
            }
        }

        logger.homeworkAlbum("  Correct: \(correctCount), Incorrect: \(incorrectCount)")

        // Get total points if available
        let totalPoints = parsingResult.allQuestions.compactMap { $0.pointsEarned }.reduce(0, +)
        let maxPoints = parsingResult.allQuestions.compactMap { $0.pointsPossible }.reduce(0, +)

        if totalPoints > 0 || maxPoints > 0 {
            logger.homeworkAlbum("  Points: \(totalPoints)/\(maxPoints)")
        }

        // Extract raw question texts for PDF generation
        let rawQuestions = parsingResult.allQuestions.compactMap { $0.rawQuestionText }

        logger.homeworkAlbum("Calling HomeworkImageStorageService.saveHomeworkImage()...")

        // Save to storage
        let record = homeworkImageStorage.saveHomeworkImage(
            image,
            subject: subject,
            accuracy: accuracy,
            questionCount: questionCount,
            correctCount: correctCount,
            incorrectCount: incorrectCount,
            totalPoints: totalPoints > 0 ? totalPoints : nil,
            maxPoints: maxPoints > 0 ? maxPoints : nil,
            rawQuestions: rawQuestions.isEmpty ? nil : rawQuestions
        )

        if record != nil {
            logger.info("✅ Homework image saved to album successfully")
            logger.homeworkAlbum("Record ID: \(record!.id)")

            // Mark as saved and persist to prevent duplicates
            hasAlreadySavedImage = true
            UserDefaults.standard.set(true, forKey: albumSavedKey)
            logger.homeworkAlbum("Saved flag set to prevent future duplicates")
        } else {
            logger.warning("⚠️ Failed to save homework image (likely duplicate detected by service)")
        }

        logger.homeworkAlbum("=== Album Save Complete ===")
    }

}