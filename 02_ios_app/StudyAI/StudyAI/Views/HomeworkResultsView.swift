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
    @StateObject private var questionArchiveService = QuestionArchiveService.shared
    
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
            rawAIResponse: enhancedResult.rawAIResponse
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
                    
                    // Question Selection Controls
                    questionSelectionSection
                    
                    // Questions List
                    questionsListSection
                    
                    // Debug Section (if needed)
                    if !parsingResult.rawAIResponse.isEmpty {
                        debugSection
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Homework Results")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingQuestionArchiveDialog = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "archivebox")
                            Text("Archive")
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
            }
        }
    }
    
    // MARK: - Results Summary
    
    private var resultsSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Parsing Results")
                    .font(.headline)
                    .foregroundColor(.black)
                Spacer()
                HStack(spacing: 8) {
                    if let enhanced = enhancedResult, enhanced.isReliableParsing {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Text(String(format: "%.1fs", parsingResult.processingTime))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            // Enhanced subject detection display
            if let enhanced = enhancedResult {
                HStack {
                    Text("Subject:")
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
                    
                    Text(String(format: "%.0f%% confidence", enhanced.subjectConfidence * 100))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 4)
            }
            
            HStack(spacing: 16) {
                StatCard(
                    title: "Questions",
                    value: "\(parsingResult.questionCount)",
                    icon: "questionmark.circle.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "Confidence",
                    value: String(format: "%.1f%%", parsingResult.overallConfidence * 100),
                    icon: "checkmark.seal.fill",
                    color: confidenceColor(parsingResult.overallConfidence)
                )
                
                StatCard(
                    title: enhancedResult?.isReliableParsing == true ? "JSON AI" : "AI",
                    value: enhancedResult?.parsingQualityDescription.components(separatedBy: " ").first ?? "Standard",
                    icon: enhancedResult?.isReliableParsing == true ? "cpu.fill" : "brain.head.profile.fill",
                    color: enhancedResult?.isReliableParsing == true ? .green : .purple
                )
            }
            
            // Enhanced parsing method info
            if let enhanced = enhancedResult {
                HStack {
                    Image(systemName: enhanced.isReliableParsing ? "gear.badge.checkmark" : "gear")
                        .font(.caption)
                        .foregroundColor(enhanced.isReliableParsing ? .green : .orange)
                    
                    Text(enhanced.parsingQualityDescription)
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    if let totalFound = enhanced.totalQuestionsFound, totalFound != enhanced.questionCount {
                        Text("Found \(totalFound), Parsed \(enhanced.questionCount)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(enhancedResult?.isReliableParsing == true ? Color.green.opacity(0.05) : Color.gray.opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(enhancedResult?.isReliableParsing == true ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
    
    // MARK: - Questions List
    
    private var questionsListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Questions & Answers")
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
                    
                    Text("Additional Items")
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
                    Text("Debug Info")
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
                Text("Select Questions to Archive")
                    .font(.headline)
                    .foregroundColor(.black)
                Spacer()
                Button(selectedQuestionIndices.count == parsingResult.allQuestions.count ? "Deselect All" : "Select All") {
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
                Text("\(selectedQuestionIndices.count) of \(parsingResult.allQuestions.count) questions selected")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    
    private func initializeQuestionData() {
        let totalQuestions = parsingResult.allQuestions.count
        questionNotes = Array(repeating: "", count: totalQuestions)
        questionTags = Array(repeating: [], count: totalQuestions)
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
                            if question.confidence < 1.0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                        .foregroundColor(confidenceColor(question.confidence))
                                    Text(String(format: "%.0f%%", question.confidence * 100))
                                        .font(.caption2)
                                        .foregroundColor(.gray) // Fixed: explicit gray text
                                }
                            }
                            
                            if question.hasVisualElements {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text("Has Visual")
                                        .font(.caption2)
                                        .foregroundColor(.gray) // Fixed: explicit gray text
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
                    
                    HStack(alignment: .top, spacing: 12) {
                        // Answer indicator
                        VStack {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.top, 2)
                            Spacer()
                        }
                        
                        // Answer text
                        Text(question.answerText)
                            .font(.body)
                            .foregroundColor(.black) // Fixed: explicit black text on white background
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled) // Allow text selection
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .background(Color.blue.opacity(0.05))
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
            } else {
                // Numbered circle for numbered questions
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
            rawAIResponse: "QUESTION_NUMBER: 1\nQUESTION: What is..."
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
            }
        } catch {
            await MainActor.run {
                archiveMessage = "Failed to archive questions: \(error.localizedDescription)"
                isArchiving = false
            }
        }
    }
}