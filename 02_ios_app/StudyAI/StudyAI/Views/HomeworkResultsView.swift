//
//  HomeworkResultsView.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import SwiftUI

struct HomeworkResultsView: View {
    let parsingResult: HomeworkParsingResult
    let enhancedResult: EnhancedHomeworkParsingResult?
    let originalImageUrl: String?
    @State private var expandedQuestions: Set<String> = []
    @State private var showingRawResponse = false
    @State private var showingQuestionArchiveDialog = false
    @State private var isArchiving = false
    @State private var archiveMessage = ""
    @State private var selectedQuestionIndices: Set<Int> = []
    @State private var questionNotes: [String] = []
    @State private var questionTags: [[String]] = []
    @State private var hasMarkedProgress = false
    @StateObject private var questionArchiveService = QuestionArchiveService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared

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

    // Dynamic navigation title with subject
    private var navigationTitle: String {
        if let subject = enhancedResult?.detectedSubject {
            return String(format: NSLocalizedString("homeworkResults.titleWithSubject", comment: ""), subject)
        }
        return NSLocalizedString("homeworkResults.yourScore", comment: "")
    }

    // Enhanced initializer that can accept either type
    init(parsingResult: HomeworkParsingResult, originalImageUrl: String?) {
        self.parsingResult = parsingResult
        self.enhancedResult = nil
        self.originalImageUrl = originalImageUrl
    }
    
    init(enhancedResult: EnhancedHomeworkParsingResult, originalImageUrl: String?) {
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
                    
                    // Question Selection Controls
                    questionSelectionSection
                    
                    // Questions List
                    questionsListSection
                    
                    // Debug Section (if needed)
                    if !parsingResult.rawAIResponse.isEmpty {
                        debugSection
                    }
                    
                    // Mark Progress Button
                    markProgressButton
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingQuestionArchiveDialog = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "archivebox")
                            Text(NSLocalizedString("homeworkResults.archive", comment: ""))
                        }
                        .foregroundColor(.blue)
                    }
                    .disabled(isArchiving || selectedQuestionIndices.isEmpty)
                }
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
            .alert("Archive Status", isPresented: .constant(!archiveMessage.isEmpty)) {
                Button("OK") {
                    archiveMessage = ""
                }
            } message: {
                Text(archiveMessage)
            }
            .onAppear {
                initializeQuestionData()
                loadProgressState()
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
                        .foregroundColor(.gray)
                    Text(enhanced.detectedSubject)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.black)

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
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Performance Summary
    
    private func performanceSummarySection(_ summary: PerformanceSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3)
                    .foregroundColor(.blue)

                Text(NSLocalizedString("homeworkResults.performanceSummary", comment: ""))
                    .font(.headline)
                    .foregroundColor(.black)

                Spacer()
            }

            // AI Summary Text
            Text(summary.summaryText)
                .font(.body)
                .foregroundColor(.black)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)

            // Score breakdown (if there are incorrect answers)
            if summary.totalIncorrect > 0 || summary.totalEmpty > 0 {
                HStack(spacing: 16) {
                    if summary.totalCorrect > 0 {
                        ScoreBreakdownItem(
                            count: summary.totalCorrect,
                            label: NSLocalizedString("homeworkResults.correct", comment: ""),
                            color: .green,
                            icon: "checkmark.circle.fill"
                        )
                    }

                    if summary.totalIncorrect > 0 {
                        ScoreBreakdownItem(
                            count: summary.totalIncorrect,
                            label: NSLocalizedString("homeworkResults.incorrect", comment: ""),
                            color: .red,
                            icon: "xmark.circle.fill"
                        )
                    }

                    if summary.totalEmpty > 0 {
                        ScoreBreakdownItem(
                            count: summary.totalEmpty,
                            label: NSLocalizedString("homeworkResults.empty", comment: ""),
                            color: .gray,
                            icon: "minus.circle.fill"
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(16)
    }
    
    // MARK: - Questions List
    
    private var questionsListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("homeworkResults.questionsAndAnswers", comment: ""))
                .font(.headline)
                .foregroundColor(.black) // Fixed: explicit black text
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
                        showSelection: true
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
                        .foregroundColor(.gray) // Fixed: explicit gray text
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
                            showSelection: true
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Debug Section
    
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                showingRawResponse.toggle()
            }) {
                HStack {
                    Text(NSLocalizedString("homeworkResults.debugInfo", comment: ""))
                        .font(.caption)
                        .foregroundColor(.gray) // Fixed: explicit gray text
                    Spacer()
                    Image(systemName: showingRawResponse ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.gray) // Fixed: explicit gray text
                }
            }

            if showingRawResponse {
                ScrollView {
                    Text(parsingResult.rawAIResponse)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.black) // Fixed: explicit black text
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Question Selection Section
    
    private var questionSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("homeworkResults.selectQuestionsToArchive", comment: ""))
                    .font(.headline)
                    .foregroundColor(.black)
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
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Mark Progress Button
    
    private var markProgressButton: some View {
        VStack(spacing: 16) {
            Button(action: {
                print("🎯 DEBUG: Mark Progress button tapped!")
                print("🎯 DEBUG: Current todayProgress BEFORE: \(pointsManager.todayProgress?.totalQuestions ?? 0) questions, \(pointsManager.todayProgress?.correctAnswers ?? 0) correct")

                trackHomeworkUsage()

                print("🎯 DEBUG: Current todayProgress AFTER: \(pointsManager.todayProgress?.totalQuestions ?? 0) questions, \(pointsManager.todayProgress?.correctAnswers ?? 0) correct")

                hasMarkedProgress = true
                saveProgressState() // Persist the state

                // Show success feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
            }) {
                HStack {
                    Image(systemName: hasMarkedProgress ? "checkmark.circle.fill" : "chart.line.uptrend.xyaxis")
                        .font(.title3)
                    Text(hasMarkedProgress ? NSLocalizedString("homeworkResults.progressMarked", comment: "") : NSLocalizedString("homeworkResults.markProgress", comment: ""))
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
                Text(NSLocalizedString("homeworkResults.progressUpdated", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 4) {
                    Text(NSLocalizedString("homeworkResults.progressTip", comment: ""))
                        .font(.caption)
                        .foregroundColor(.blue)
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("homeworkResults.manuallyAddPrefix", comment: "") + "\(parsingResult.allQuestions.count)" + NSLocalizedString("homeworkResults.manuallyAddSuffix", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
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
        print("🎯 DEBUG: Loaded progress state for session \(sessionId): \(hasMarkedProgress)")
    }

    /// Save the progress state to UserDefaults
    private func saveProgressState() {
        UserDefaults.standard.set(hasMarkedProgress, forKey: progressMarkedKey)
        print("🎯 DEBUG: Saved progress state for session \(sessionId): \(hasMarkedProgress)")
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
    @StateObject private var appState = AppState.shared

    init(question: ParsedQuestion, isExpanded: Bool, isSelected: Bool = false, onToggle: @escaping () -> Void, onSelectionToggle: (() -> Void)? = nil, showAsBullet: Bool = false, showSelection: Bool = false) {
        self.question = question
        self.isExpanded = isExpanded
        self.isSelected = isSelected
        self.onToggle = onToggle
        self.onSelectionToggle = onSelectionToggle
        self.showAsBullet = showAsBullet
        self.showSelection = showSelection
    }
    
    var body: some View {
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
                            .foregroundColor(.black) // Fixed: explicit black text on white background
                        
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
                            } else if question.confidence < 1.0 {
                                // Legacy confidence display
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                        .foregroundColor(confidenceColor(question.confidence))
                                    Text(String(format: "%.0f%%", question.confidence * 100))
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
                        .foregroundColor(.gray) // Fixed: explicit gray color
                }
                .padding()
            }
            .buttonStyle(PlainButtonStyle())
            
            // Answer Content (Collapsible)
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    // Raw Question Section (if available)
                    if let rawQuestion = question.rawQuestionText, !rawQuestion.isEmpty && rawQuestion != question.questionText {
                        HStack(alignment: .top, spacing: 12) {
                            VStack {
                                Image(systemName: "doc.text.fill")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .padding(.top, 2)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("homeworkResults.rawQuestion", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.gray)

                                Text(rawQuestion)
                                    .font(.body)
                                    .foregroundColor(.black)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                            }

                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    
                    if question.isGraded {
                        // Grading Mode: Show student answer, correct answer, and feedback
                        
                        // Student Answer Section
                        if let studentAnswer = question.studentAnswer, !studentAnswer.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                VStack {
                                    Image(systemName: "person.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                        .padding(.top, 2)
                                    Spacer()
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("homeworkResults.studentAnswer", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.gray)
                                    
                                    Text(studentAnswer)
                                        .font(.body)
                                        .foregroundColor(.black)
                                        .multilineTextAlignment(.leading)
                                        .textSelection(.enabled)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                        } else {
                            // Empty answer
                            HStack(alignment: .top, spacing: 12) {
                                VStack {
                                    Image(systemName: "person.fill")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .padding(.top, 2)
                                    Spacer()
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("homeworkResults.studentAnswer", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.gray)

                                    Text(NSLocalizedString("homeworkResults.noAnswerProvided", comment: ""))
                                        .font(.body)
                                        .italic()
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.leading)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                        
                        // Correct Answer Section
                        if let correctAnswer = question.correctAnswer, !correctAnswer.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                VStack {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .padding(.top, 2)
                                    Spacer()
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("homeworkResults.correctAnswer", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.gray)
                                    
                                    Text(correctAnswer)
                                        .font(.body)
                                        .foregroundColor(.black)
                                        .multilineTextAlignment(.leading)
                                        .textSelection(.enabled)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                        
                        // Feedback Section
                        if let feedback = question.feedback, !feedback.isEmpty && feedback != "No feedback provided" {
                            HStack(alignment: .top, spacing: 12) {
                                VStack {
                                    Image(systemName: "bubble.left.fill")
                                        .font(.caption)
                                        .foregroundColor(.purple)
                                        .padding(.top, 2)
                                    Spacer()
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("homeworkResults.feedback", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.gray)
                                    
                                    Text(feedback)
                                        .font(.body)
                                        .foregroundColor(.black)
                                        .multilineTextAlignment(.leading)
                                        .textSelection(.enabled)
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                        
                    } else {
                        // Legacy Mode: Show AI answer only
                        HStack(alignment: .top, spacing: 12) {
                            VStack {
                                Image(systemName: "lightbulb.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.top, 2)
                                Spacer()
                            }
                            
                            Text(question.answerText)
                                .font(.body)
                                .foregroundColor(.black)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                    }

                    // Follow Up Button - Navigate to chat with this question
                    Button(action: {
                        // Construct prompt for chat
                        let chatPrompt = """
I need help understanding this question from my homework:

Question: \(question.questionText)

\(question.isGraded && question.studentAnswer != nil && !question.studentAnswer!.isEmpty ? "My answer was: \(question.studentAnswer!)\n\n" : "")I'm unclear about how to approach this problem. Can you help me understand it better?
"""
                        // Detect subject from question or use default
                        let detectedSubject = detectSubjectFromQuestion(question.questionText)

                        // Navigate to chat with the question
                        appState.navigateToChatWithMessage(chatPrompt, subject: detectedSubject)

                        // Haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 14, weight: .medium))

                            Text(NSLocalizedString("homeworkResults.askAiForHelp", comment: ""))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Bottom padding
                    Color.clear.frame(height: 4)
                }
                .background(question.isGraded ? question.gradeColor.opacity(0.05) : Color.blue.opacity(0.05))
            }
        }
        .background(isSelected ? Color.blue.opacity(0.05) : Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
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
            return "Mathematics"
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

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black) // Fixed: explicit black text
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray) // Fixed: explicit gray text
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Score Breakdown Item

struct ScoreBreakdownItem: View {
    let count: Int
    let label: String
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            
            Text("\(count)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.black)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .cornerRadius(8)
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
            let archivedQuestions = try await questionArchiveService.archiveQuestions(request)

            await MainActor.run {
                archiveMessage = "Successfully archived \(archivedQuestions.count) question(s) to your Mistake Notebook!"
                isArchiving = false
                showingQuestionArchiveDialog = false
                selectedQuestionIndices.removeAll()

                // Automatically track progress for archived questions
                print("🎯 DEBUG: Auto-tracking progress for archived questions")
                trackHomeworkUsage()
                hasMarkedProgress = true
                saveProgressState() // Persist the state
            }
        } catch {
            await MainActor.run {
                archiveMessage = "Failed to archive questions: \(error.localizedDescription)"
                isArchiving = false
            }
        }
    }
    
    /// Track homework grading usage for points earning system
    private func trackHomeworkUsage() {
        print("🎯 DEBUG: trackHomeworkUsage() called in HomeworkResultsView")
        let questions = parsingResult.allQuestions
        print("🎯 DEBUG: Total questions to track: \(questions.count)")
        
        // Get subject from enhanced result or try to detect from question text
        let subject = enhancedResult?.detectedSubject ?? detectSubjectFromQuestion(questions.first?.questionText ?? "")
        
        // Use enhanced result for accurate statistics if available
        if let enhanced = enhancedResult, let performanceSummary = enhanced.performanceSummary {
            let totalCorrect = performanceSummary.totalCorrect
            print("🎯 DEBUG: Using enhanced result: \(totalCorrect) correct out of \(questions.count)")
            
            // Track correct answers based on enhanced result
            for i in 0..<totalCorrect {
                print("🎯 DEBUG: Tracking correct answer \(i + 1)/\(totalCorrect)")
                pointsManager.trackQuestionAnswered(subject: subject, isCorrect: true)
            }
            
            // Track incorrect answers
            let incorrectCount = questions.count - totalCorrect
            for i in 0..<incorrectCount {
                print("🎯 DEBUG: Tracking incorrect answer \(i + 1)/\(incorrectCount)")
                pointsManager.trackQuestionAnswered(subject: subject, isCorrect: false)
            }
        } else {
            // Fallback to individual question checking
            for (index, question) in questions.enumerated() {
                print("🎯 DEBUG: Processing question \(index + 1)/\(questions.count)")
                // Determine if this was a correct answer based on grading result
                let isCorrect: Bool
                if question.isGraded {
                    // Use the actual grading result
                    isCorrect = question.grade?.lowercased().contains("correct") == true ||
                               question.grade?.lowercased().contains("right") == true ||
                               question.grade == "✓" || question.grade == "A"
                } else {
                    // For non-graded questions, assume they were answered (for goal tracking)
                    // We'll consider them as "attempted" rather than correct/incorrect
                    isCorrect = false // Conservative approach for accuracy calculation
                }
                
                print("🎯 DEBUG: Detected subject: \(subject), isCorrect: \(isCorrect)")
                
                // Track the question for points earning  
                print("🎯 DEBUG: About to call pointsManager.trackQuestionAnswered()")
                pointsManager.trackQuestionAnswered(subject: subject, isCorrect: isCorrect)
                print("🎯 DEBUG: Called pointsManager.trackQuestionAnswered() successfully")
            }
        }
        
        // Track study time (estimate based on number of questions)
        let estimatedStudyTime = max(questions.count * 2, 5) // 2 minutes per question, minimum 5 minutes
        print("🎯 DEBUG: About to track study time: \(estimatedStudyTime) minutes")
        pointsManager.trackStudyTime(estimatedStudyTime)
        
        print("📊 Tracked homework usage: \(questions.count) questions, estimated \(estimatedStudyTime) minutes study time")
        print("🎯 DEBUG: trackHomeworkUsage() completed")
    }
    
    /// Simple subject detection from question text
    private func detectSubjectFromQuestion(_ questionText: String) -> String {
        let lowercaseText = questionText.lowercased()
        
        // Math keywords
        if lowercaseText.contains("equation") || lowercaseText.contains("solve") || 
           lowercaseText.contains("calculate") || lowercaseText.contains("algebra") ||
           lowercaseText.contains("geometry") || lowercaseText.contains("integral") ||
           lowercaseText.contains("derivative") || lowercaseText.contains("function") {
            return "Mathematics"
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