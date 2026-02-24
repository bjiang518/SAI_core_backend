//
//  QuestionGenerationView.swift
//  StudyAI
//
//  Created by Claude Code on 12/21/24.
//

import SwiftUI
import Foundation
import os.log
import Lottie

struct QuestionGenerationView: View {
    @StateObject private var questionService = QuestionGenerationService.shared
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var profileService = ProfileService.shared
    @StateObject private var archiveService = QuestionArchiveService.shared
    @StateObject private var libraryService = LibraryDataService.shared
    @StateObject private var mistakeService = MistakeReviewService()
    @StateObject private var sessionManager = PracticeSessionManager.shared  // ✅ FIX 2: Session persistence
    @State private var inputSubject = ""
    @State private var selectedTemplate: TemplateType = .randomPractice
    @State private var showingQuestionsList = false
    @State private var generatedQuestions: [QuestionGenerationService.GeneratedQuestion] = []
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var availableConversations: [[String: Any]] = []
    @State private var availableQuestions: [QuestionSummary] = []
    @State private var availableMistakes: [MistakeQuestion] = []
    @State private var selectedConversations: Set<String> = []
    @State private var selectedQuestions: Set<String> = []
    @State private var selectedDifficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty = .intermediate
    @State private var questionCount = 5
    @State private var selectedQuestionType: QuestionGenerationService.GeneratedQuestion.QuestionType = .any
    @State private var selectedArchiveSession = ""
    @State private var isLoadingData = false
    @State private var selectedSubject = ""
    @State private var showingArchiveSelection = false
    @State private var showingInfoAlert = false
    @State private var generatedSubject = ""  // Top-level subject for archiving
    @State private var isRecentExpanded = false  // Recent Questions section collapsed by default
    @State private var resumeSessionId: String? = nil  // Set when user taps Resume
    @Environment(\.dismiss) private var dismiss

    private let logger = Logger(subsystem: "com.studyai", category: "QuestionGeneration")
    private let dataAdapter = QuestionGenerationDataAdapter.shared

    enum TemplateType: String, CaseIterable {
        case randomPractice = "random"
        case fromArchives = "conversation_based"

        var displayName: String {
            switch self {
            case .randomPractice: return NSLocalizedString("questionGeneration.template.randomPractice", comment: "")
            case .fromArchives: return NSLocalizedString("questionGeneration.template.fromArchives", comment: "")
            }
        }

        var description: String {
            switch self {
            case .randomPractice: return NSLocalizedString("questionGeneration.description.randomPractice", comment: "")
            case .fromArchives: return NSLocalizedString("questionGeneration.description.fromArchives", comment: "")
            }
        }

        var iconName: String {
            switch self {
            case .randomPractice: return "dice.fill"
            case .fromArchives: return "books.vertical.fill"
            }
        }

        var color: Color {
            switch self {
            case .randomPractice: return .blue
            case .fromArchives: return .green
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                    // ✅ FIX 2: Resume Session Banner
                    if sessionManager.hasIncompleteSessions,
                       let latestSession = sessionManager.incompleteSessions.first {
                        ResumeSessionBanner(
                            session: latestSession,
                            onResume: {
                                // Load the session questions and record which session we're resuming
                                generatedQuestions = latestSession.questions
                                resumeSessionId = latestSession.id
                                showingQuestionsList = true
                            },
                            onDismiss: {
                                // Delete the session
                                sessionManager.deleteSession(id: latestSession.id)
                            }
                        )
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Generation Type Selection
                    generationTypeSelection

                    // Configuration Section
                    configurationSection

                    // General Configuration Section
                    generalConfigurationSection

                    // Generate Button
                    generateButton

                    // Progress Section
                    if questionService.isGenerating {
                        progressSection
                    }

                    // Recent Questions Preview
                    if !generatedQuestions.isEmpty {
                        recentQuestionsPreview
                    }

                    // Only add spacer when not generating
                    if !questionService.isGenerating {
                        Spacer(minLength: 100)
                    }
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("questionGeneration.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingInfoAlert = true
                    }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                    }
                }
            }
            // ✅ CHANGED: Use fullScreenCover instead of sheet for fixed view
            .fullScreenCover(isPresented: $showingQuestionsList) {
                GeneratedQuestionsListView(
                    questions: generatedQuestions,
                    subject: generatedSubject,
                    resumeSessionId: resumeSessionId
                )
            }
            .sheet(isPresented: $showingArchiveSelection) {
                ArchiveSelectionView(
                    conversations: availableConversations,
                    questions: availableQuestions,
                    selectedConversations: $selectedConversations,
                    selectedQuestions: $selectedQuestions
                )
            }
            .alert(NSLocalizedString("questionGeneration.error.title", comment: ""), isPresented: $showingErrorAlert) {
                Button(NSLocalizedString("common.ok", comment: "")) { }
            } message: {
                Text(errorMessage)
            }
            .alert(NSLocalizedString("questionGeneration.howToUse.title", comment: ""), isPresented: $showingInfoAlert) {
                Button(NSLocalizedString("common.ok", comment: "")) { }
            } message: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("questionGeneration.howToUse.message", comment: ""))
                }
            }
            .onAppear {
                loadInitialData()
            }
    }

    private var generationTypeSelection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 16) {
                ForEach(TemplateType.allCases, id: \.self) { type in
                    GenerationTypeCard(
                        type: type,
                        isSelected: selectedTemplate == type,
                        onTap: { selectedTemplate = type }
                    )
                }
            }
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch selectedTemplate {
            case .randomPractice:
                RandomQuestionConfig(
                    availableSubjects: dataAdapter.getMostCommonSubjects(),
                    selectedSubject: $selectedSubject
                )
            case .fromArchives:
                ArchiveBasedConfig(
                    conversations: availableConversations,
                    questions: availableQuestions,
                    selectedConversations: $selectedConversations,
                    selectedQuestions: $selectedQuestions,
                    isLoading: isLoadingData,
                    onShowSelection: { showingArchiveSelection = true }
                )
            }
        }
    }

    private var generalConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 16) {
                // Difficulty Slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline)
                            .foregroundColor(.purple)
                        Text(NSLocalizedString("questionGeneration.difficultyLevel", comment: ""))
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        Text(selectedDifficulty.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedTemplate.color.opacity(0.1))
                            .cornerRadius(6)
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Text(NSLocalizedString("questionGeneration.difficulty.beginner", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(NSLocalizedString("questionGeneration.difficulty.advanced", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Custom difficulty picker using segmented control style
                        Picker(NSLocalizedString("questionGeneration.difficultyLevel", comment: ""), selection: $selectedDifficulty) {
                            ForEach(QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty.allCases, id: \.self) { difficulty in
                                Text(difficulty.displayName).tag(difficulty)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }

                // Question Count Slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "number.circle")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        Text(NSLocalizedString("questionGeneration.numberOfQuestions", comment: ""))
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(questionCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedTemplate.color.opacity(0.1))
                            .cornerRadius(6)
                    }

                    VStack(spacing: 8) {
                        HStack {
                            Text("1")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("10")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Slider(value: Binding(
                            get: { Double(questionCount) },
                            set: { questionCount = Int($0) }
                        ), in: 1...10, step: 1)
                        .accentColor(selectedTemplate.color)
                    }
                }

                // Question Type Selection
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.subheadline)
                            .foregroundColor(.purple)
                        Text(NSLocalizedString("questionGeneration.questionType", comment: ""))
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        Text(selectedQuestionType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedTemplate.color.opacity(0.1))
                            .cornerRadius(6)
                    }

                    // Visual type grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(QuestionGenerationService.GeneratedQuestion.QuestionType.allCases, id: \.self) { type in
                            Button(action: {
                                selectedQuestionType = type
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: type.icon)
                                        .font(.title3)
                                        .foregroundColor(selectedQuestionType == type ? selectedTemplate.color : .secondary)

                                    Text(type.displayName)
                                        .font(.caption2)
                                        .foregroundColor(selectedQuestionType == type ? selectedTemplate.color : .secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedQuestionType == type ? selectedTemplate.color.opacity(0.1) : Color.gray.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedQuestionType == type ? selectedTemplate.color : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
    }

    private var generateButton: some View {
        Button(action: generateQuestions) {
            HStack(spacing: 8) {
                if questionService.isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles")
                        .font(.headline)
                }

                Text(questionService.isGenerating ? NSLocalizedString("questionGeneration.generating", comment: "") : NSLocalizedString("questionGeneration.generateQuestions", comment: ""))
                    .font(.body.bold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [selectedTemplate.color, selectedTemplate.color.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .disabled(questionService.isGenerating || !canGenerate())
        }
        .opacity(questionService.isGenerating || !canGenerate() ? 0.6 : 1.0)
    }

    private var progressSection: some View {
        GeometryReader { geometry in
            VStack(spacing: -60) {
                LottieView(
                    animationName: "Bubbles x2",
                    loopMode: .loop,
                    animationSpeed: 1.0,
                    powerSavingProgress: 0.7
                )
                .frame(
                    width: min(geometry.size.width, 500),
                    height: min(geometry.size.width - 64, 500) * (500.0 / 370.0)
                )
                .clipped()
                .scaleEffect(1.3)
                .offset(y: -100)
                .frame(height: 300)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 300)
    }

    private var recentQuestionsPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsible header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isRecentExpanded.toggle()
                }
            }) {
                HStack {
                    Text(NSLocalizedString("questionGeneration.recentQuestions", comment: "Recent Questions"))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Spacer()

                    HStack(spacing: 12) {
                        // Question count badge
                        Text("\(generatedQuestions.count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(selectedTemplate.color)
                            .clipShape(Capsule())

                        // View All button
                        Button(NSLocalizedString("questionGeneration.viewAll", comment: "")) {
                            showingQuestionsList = true
                        }
                        .font(.subheadline)
                        .foregroundColor(selectedTemplate.color)

                        // Chevron
                        Image(systemName: isRecentExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expandable preview cards
            if isRecentExpanded {
                VStack(spacing: 8) {
                    ForEach(generatedQuestions.prefix(3)) { question in
                        QuestionGenerationPreviewCard(question: question)
                    }
                }
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func loadInitialData() {
        guard !isLoadingData else { return }

        isLoadingData = true

        Task {
            do {
                // Load mistakes - fetch them properly like MistakeReviewView does
                // Use nil subject to get all mistakes across all subjects
                await mistakeService.fetchMistakes(subject: nil, timeRange: MistakeTimeRange.thisMonth)
                let allMistakes = mistakeService.mistakes

                // Load conversations from LibraryDataService
                let conversations = await libraryService.fetchConversationsOnly()

                // Load archived questions from QuestionArchiveService
                let questions = try await archiveService.fetchArchivedQuestions(limit: 100)

                await MainActor.run {
                    self.availableMistakes = allMistakes
                    self.availableConversations = conversations
                    self.availableQuestions = questions
                    self.isLoadingData = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingData = false
                    self.errorMessage = String.localizedStringWithFormat(NSLocalizedString("questionGeneration.failedToLoadData", comment: ""), error.localizedDescription)
                    self.showingErrorAlert = true
                }
            }
        }
    }

    private func canGenerate() -> Bool {
        guard authService.isAuthenticated else { return false }

        switch selectedTemplate {
        case .randomPractice:
            return true
        case .fromArchives:
            return !selectedConversations.isEmpty || !selectedQuestions.isEmpty
        }
    }

    private func generateQuestions() {

        Task {
            do {
                let (questions, subject) = try await performGeneration()

                await MainActor.run {
                    self.generatedQuestions = questions
                    self.generatedSubject = subject
                    self.showingQuestionsList = true
                }
            } catch {
                await MainActor.run {
                    // Enhanced error handling with better user messages
                    if let generationError = error as? QuestionGenerationError {
                        self.errorMessage = generationError.errorDescription ?? error.localizedDescription

                        // Add recovery suggestion for better UX
                        if let recovery = generationError.recoverySuggestion {
                            self.errorMessage += "\n\n💡 " + recovery
                        }
                    } else {
                        // Fallback for non-QuestionGenerationError types
                        self.errorMessage = error.localizedDescription
                    }

                    self.showingErrorAlert = true
                }
            }
        }
    }

    private func performGeneration() async throws -> ([QuestionGenerationService.GeneratedQuestion], String) {
        let userProfile = dataAdapter.createUserProfile()

        switch selectedTemplate {
        case .randomPractice:
            // ✅ NEW: Determine primary subject
            let mostCommonSubjects = dataAdapter.getMostCommonSubjects()
            let primarySubject = !selectedSubject.isEmpty ? selectedSubject : (mostCommonSubjects.first ?? NSLocalizedString("questionGeneration.defaultSubject.mathematics", comment: ""))

            print("🎯 [QuestionGen] === PERSONALIZED RANDOM GENERATION ===")
            print("   Selected subject: \(primarySubject)")

            // ✅ NEW: Extract weakness topics from short-term status
            let weaknessTopics = dataAdapter.getWeaknessTopics(for: primarySubject)

            // ✅ NEW: Mix 80% weakness + 20% mastery for balanced practice
            let mixedTopics = dataAdapter.getMixedTopicsWithMastery(
                for: primarySubject,
                weaknessTopics: weaknessTopics
            )

            // ✅ NEW: Personalized focus notes from actual student struggles
            let focusNotes = dataAdapter.getPersonalizedFocusNotes(for: primarySubject)

            // ✅ NEW: Adaptive difficulty suggestion (user can still override)
            let adaptiveDifficulty = dataAdapter.getAdaptiveDifficulty(for: primarySubject)

            print("📊 [QuestionGen] Adaptive difficulty recommendation: \(adaptiveDifficulty.rawValue)")
            print("   User-selected difficulty: \(selectedDifficulty.rawValue)")
            print("   Using: \(selectedDifficulty.rawValue) (user preference)")

            let config = QuestionGenerationService.RandomQuestionsConfig(
                topics: mixedTopics.isEmpty ? [primarySubject] : mixedTopics,  // ✅ Dynamic from short-term status
                focusNotes: focusNotes,  // ✅ Personalized focus notes
                difficulty: selectedDifficulty,  // User can override adaptive difficulty
                questionCount: questionCount,
                questionType: selectedQuestionType
            )

            print("✅ [QuestionGen] Final config:")
            print("   Topics: \(config.topics)")
            print("   Focus: \(focusNotes.prefix(100))...")
            print("   Difficulty: \(config.difficulty.rawValue)")
            print("   Count: \(config.questionCount)")
            print("   Type: \(config.questionType.rawValue)")
            print("========================================\n")


            let result = await questionService.generateRandomQuestions(
                subject: primarySubject,
                config: config,
                userProfile: userProfile
            )

            switch result {
            case .success(let questions):
                return (questions, primarySubject)
            case .failure(let error):
                throw error
            }

        case .fromArchives:
            // ✅ FIX: Handle both conversations and questions
            guard !selectedConversations.isEmpty || !selectedQuestions.isEmpty else {
                throw NSError(domain: "QuestionGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("questionGeneration.noArchives", comment: "")])
            }

            // Filter to only selected conversations
            let selectedConversationObjects = availableConversations.filter { conversation in
                if let conversationId = conversation["id"] as? String {
                    return selectedConversations.contains(conversationId)
                }
                return false
            }

            // ✅ NEW: Filter to only selected questions
            let selectedQuestionObjects = availableQuestions.filter { question in
                return selectedQuestions.contains(question.id)
            }

            // Convert real conversation data using backend analysis
            let conversationData = selectedConversationObjects.map { conversation in
                let title = conversation["title"] as? String ?? conversation["summary"] as? String ?? NSLocalizedString("questionGeneration.untitled", comment: "")
                let subject = conversation["subject"] as? String ?? NSLocalizedString("questionGeneration.generalSubject", comment: "")
                let content = conversation["conversationContent"] as? String ?? ""
                let summary = conversation["summary"] as? String ?? ""

                // Use backend-provided keyTopics, fall back to subject
                let keyTopics: [String]
                if let keyTopicsArray = conversation["keyTopics"] as? [String] {
                    keyTopics = keyTopicsArray
                } else if let keyTopicsJSON = conversation["keyTopics"] as? String,
                          let data = keyTopicsJSON.data(using: .utf8),
                          let decoded = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    keyTopics = decoded
                } else {
                    keyTopics = [subject]
                }

                let studentQuestions = extractStudentQuestions(from: content, title: title)

                return QuestionGenerationService.ConversationData(
                    date: conversation["createdAt"] as? String ?? ISO8601DateFormatter().string(from: Date()),
                    topics: keyTopics,
                    studentQuestions: studentQuestions,
                    keyConcepts: summary.isEmpty ? title : summary
                )
            }

            // Convert selected questions to backend format
            let questionData = selectedQuestionObjects.map { question -> [String: Any] in
                var questionDict: [String: Any] = [
                    "question_text": question.questionText,
                    "topic": question.subject,
                    "date": ISO8601DateFormatter().string(from: question.archivedAt),
                    "is_correct": question.grade == .correct || question.grade == .partialCredit
                ]

                if let studentAnswer = question.studentAnswer, !studentAnswer.isEmpty {
                    questionDict["student_answer"] = studentAnswer
                }
                if let answerText = question.answerText, !answerText.isEmpty {
                    questionDict["correct_answer"] = answerText
                }
                if let grade = question.grade {
                    questionDict["grade"] = grade.rawValue
                }
                if let tags = question.tags, !tags.isEmpty {
                    questionDict["tags"] = tags
                }
                if let questionType = question.questionType, !questionType.isEmpty {
                    questionDict["question_type"] = questionType
                }

                return questionDict
            }

            // ✅ FIX: Get the most common subject from BOTH conversations and questions
            var allSubjects: [String] = []

            // Add conversation subjects
            let conversationSubjects = selectedConversationObjects.compactMap { conversation in
                conversation["subject"] as? String
            }.filter { !$0.isEmpty && $0 != NSLocalizedString("questionGeneration.generalDiscussion", comment: "") }
            allSubjects.append(contentsOf: conversationSubjects)

            // Add question subjects
            let questionSubjects = selectedQuestionObjects.map { $0.subject }
            allSubjects.append(contentsOf: questionSubjects)

            // Get unique subjects and determine primary
            let uniqueSubjects = Array(Set(allSubjects))
            let primarySubject = uniqueSubjects.first ?? NSLocalizedString("questionGeneration.defaultSubject.mathematics", comment: "")

            let config = QuestionGenerationService.RandomQuestionsConfig(
                topics: uniqueSubjects.isEmpty ? [primarySubject] : uniqueSubjects,
                focusNotes: NSLocalizedString("questionGeneration.focusNotes.conversationPatterns", comment: ""),
                difficulty: selectedDifficulty,
                questionCount: questionCount,
                questionType: selectedQuestionType
            )

            // ✅ FIX: Call with both conversation data AND question data
            let result = await questionService.generateConversationBasedQuestions(
                subject: primarySubject,
                conversations: conversationData,
                questions: questionData,  // ✅ NEW: Pass question data
                config: config,
                userProfile: userProfile
            )

            switch result {
            case .success(let questions):
                return (questions, primarySubject)
            case .failure(let error):
                throw error
            }
        }
    }

    // MARK: - Helper Functions
}

// MARK: - New Supporting Views

struct TemplateButton: View {
    let template: QuestionGenerationView.TemplateType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(template.color.opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 50, height: 50)

                    Image(systemName: template.iconName)
                        .font(.title3)
                        .foregroundColor(template.color)
                }

                Text(template.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundColor(isSelected ? template.color : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? template.color.opacity(0.08) : Color.clear)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? template.color : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GenerationTypeCard: View {
    let type: QuestionGenerationView.TemplateType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(type.color.opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 50, height: 50)

                    Image(systemName: type.iconName)
                        .font(.title2)
                        .foregroundColor(type.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName)
                        .font(.body.bold())
                        .foregroundColor(.primary)

                    Text(type.description)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(type.color)
                }
            }
            .padding()
            .background(isSelected ? type.color.opacity(0.05) : Color.gray.opacity(0.1))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? type.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct QuestionGenerationPreviewCard: View {
    let question: QuestionGenerationService.GeneratedQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Use SmartMathRenderer for proper math rendering
            SmartMathRenderer(question.question, fontSize: 15)
                .lineLimit(2)

            Text(question.topic)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

struct RandomQuestionConfig: View {
    let availableSubjects: [String]
    @Binding var selectedSubject: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "dice.fill")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                Text(NSLocalizedString("questionGeneration.randomPracticeSettings", comment: ""))
                    .font(.body)
                    .fontWeight(.medium)
            }

            if !availableSubjects.isEmpty {
                Menu {
                    ForEach(availableSubjects, id: \.self) { subject in
                        Button(subject) {
                            selectedSubject = subject
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedSubject.isEmpty ? NSLocalizedString("questionGeneration.chooseSubject", comment: "") : selectedSubject)
                            .foregroundColor(selectedSubject.isEmpty ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            } else {
                Text(NSLocalizedString("questionGeneration.usingGeneralMath", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .onAppear {
            if selectedSubject.isEmpty && !availableSubjects.isEmpty {
                selectedSubject = availableSubjects.first ?? ""
            }
        }
    }
}

struct MistakeBasedConfig: View {
    let mistakes: [MistakeQuestion]
    let isLoading: Bool
    @Binding var selectedMistakes: Set<String>
    let onShowSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                Text(NSLocalizedString("questionGeneration.mistakeBasedSettings", comment: ""))
                    .font(.body)
                    .fontWeight(.medium)
            }

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(NSLocalizedString("questionGeneration.loadingMistakes", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !mistakes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(mistakes.count) \(NSLocalizedString("questionGeneration.mistakesAvailable", comment: ""))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if selectedMistakes.isEmpty {
                                Text(NSLocalizedString("questionGeneration.tapToSelectMistakes", comment: ""))
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .italic()
                            } else {
                                Text("\(selectedMistakes.count) \(NSLocalizedString("questionGeneration.mistakesSelected", comment: ""))")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .fontWeight(.medium)
                            }
                        }

                        Spacer()

                        Button(action: onShowSelection) {
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet")
                                    .font(.caption)
                                Text(NSLocalizedString("common.select", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Show breakdown by subject if available and mistakes are selected
                    if !selectedMistakes.isEmpty {
                        let selectedMistakeObjects = mistakes.filter { selectedMistakes.contains($0.id) }
                        let subjectCounts = Dictionary(grouping: selectedMistakeObjects, by: { $0.subject })
                            .mapValues { $0.count }
                            .sorted(by: { $0.value > $1.value })

                        if subjectCounts.count > 0 {
                            Text("\(NSLocalizedString("common.selected", comment: "")): \(subjectCounts.prefix(3).map { "\($0.key) (\($0.value))" }.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                }
            } else {
                Text(NSLocalizedString("questionGeneration.noMistakes", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ArchiveBasedConfig: View {
    let conversations: [[String: Any]]
    let questions: [QuestionSummary]
    @Binding var selectedConversations: Set<String>
    @Binding var selectedQuestions: Set<String>
    let isLoading: Bool
    let onShowSelection: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
                Text(NSLocalizedString("questionGeneration.archiveBasedSettings", comment: ""))
                    .font(.body)
                    .fontWeight(.medium)
            }

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(NSLocalizedString("questionGeneration.loadingArchiveData", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(conversations.count) \(NSLocalizedString("questionGeneration.conversationsCount", comment: ""))\(questions.count) \(NSLocalizedString("questionGeneration.questionsAvailable", comment: ""))")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if selectedConversations.isEmpty && selectedQuestions.isEmpty {
                                Text(NSLocalizedString("questionGeneration.tapToSelectArchives", comment: ""))
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .italic()
                            } else {
                                Text("\(selectedConversations.count) \(NSLocalizedString("questionGeneration.conversationsCount", comment: ""))\(selectedQuestions.count) \(NSLocalizedString("questionGeneration.questionsSelected", comment: ""))")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                    .fontWeight(.medium)
                            }
                        }

                        Spacer()

                        Button(action: onShowSelection) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                Text(NSLocalizedString("common.select", comment: ""))
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 0.0, green: 0.5, blue: 0.0), Color(red: 0.0, green: 0.4, blue: 0.0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                            .shadow(color: Color(red: 0.0, green: 0.5, blue: 0.0).opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    if conversations.isEmpty && questions.isEmpty {
                        Text(NSLocalizedString("questionGeneration.noArchives", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ConversationSelectionCard: View {
    let conversationTitle: String // Temporary: using String instead of Conversation
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversationTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(NSLocalizedString("questionGeneration.conversation", comment: "")) // Temporary placeholder for subject
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(width: 120, height: 60)
            .background(isSelected ? Color.green.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct QuestionSelectionCard: View {
    let question: QuestionSummary
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 4) {
                Text(question.subject)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("\(question.totalQuestions) \(NSLocalizedString("questionGeneration.questions", comment: ""))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .frame(width: 100, height: 50)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ConversationBasedConfig: View {
    let conversations: [String]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
                Text(NSLocalizedString("questionGeneration.archiveBasedSettings", comment: ""))
                    .font(.body)
                    .fontWeight(.medium)
            }

            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(NSLocalizedString("questionGeneration.loadingConversations", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !conversations.isEmpty {
                Text(String.localizedStringWithFormat(NSLocalizedString("questionGeneration.conversationsAvailable", comment: ""), conversations.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(NSLocalizedString("questionGeneration.noConversationsFound", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    QuestionGenerationView()
}

// MARK: - Selection Views

struct MistakeSelectionView: View {
    let mistakes: [MistakeQuestion]
    @Binding var selectedMistakes: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack {
                if mistakes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)

                        Text(NSLocalizedString("questionGeneration.noMistakesFound", comment: ""))
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(NSLocalizedString("questionGeneration.completeHomeworkToCreateMistakes", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    // Selection Controls
                    HStack {
                        Button(action: {
                            if selectedMistakes.count == mistakes.count {
                                selectedMistakes.removeAll()
                            } else {
                                selectedMistakes = Set(mistakes.map { $0.id })
                            }
                        }) {
                            Text(selectedMistakes.count == mistakes.count ? NSLocalizedString("common.deselectAll", comment: "") : NSLocalizedString("common.selectAll", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }

                        Spacer()

                        Text("\(selectedMistakes.count) \(NSLocalizedString("common.selected", comment: ""))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    // Mistakes List
                    List {
                        ForEach(mistakes) { mistake in
                            MistakeSelectionCard(
                                mistake: mistake,
                                isSelected: selectedMistakes.contains(mistake.id),
                                onToggle: {
                                    if selectedMistakes.contains(mistake.id) {
                                        selectedMistakes.remove(mistake.id)
                                    } else {
                                        selectedMistakes.insert(mistake.id)
                                    }
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(NSLocalizedString("questionGeneration.selectMistakes", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedMistakes.isEmpty)
                }
            }
        }
    }
}

struct ArchiveSelectionView: View {
    let conversations: [[String: Any]]
    let questions: [QuestionSummary]
    @Binding var selectedConversations: Set<String>
    @Binding var selectedQuestions: Set<String>
    @Environment(\.dismiss) private var dismiss

    // ✅ NEW: Filter state for switching between conversations and questions
    enum ArchiveFilter: String, CaseIterable {
        case all = "All"
        case conversations = "Conversations"
        case questions = "Questions"

        var localizedName: String {
            switch self {
            case .all: return NSLocalizedString("questionGeneration.filter.all", value: "All", comment: "")
            case .conversations: return NSLocalizedString("questionGeneration.filter.conversations", value: "Conversations", comment: "")
            case .questions: return NSLocalizedString("questionGeneration.filter.questions", value: "Questions", comment: "")
            }
        }
    }

    @State private var selectedFilter: ArchiveFilter = .all
    @State private var selectedSubject: String = "All"
    @State private var selectedTimeFilter: TimeFilter = .allTime

    enum TimeFilter: String, CaseIterable {
        case thisWeek  = "This Week"
        case thisMonth = "This Month"
        case thisYear  = "This Year"
        case allTime   = "All Time"
    }

    // All distinct subjects across both conversations and questions
    private var availableSubjects: [String] {
        var subjects = Set<String>()
        for conv in conversations {
            if let s = conv["subject"] as? String, !s.isEmpty { subjects.insert(s) }
        }
        for q in questions {
            if !q.subject.isEmpty { subjects.insert(q.subject) }
        }
        return ["All"] + subjects.sorted()
    }

    // Date cutoff derived from time filter
    private var dateCutoff: Date? {
        let cal = Calendar.current
        let now = Date()
        switch selectedTimeFilter {
        case .allTime:   return nil
        case .thisWeek:  return cal.date(byAdding: .day,   value: -7,   to: now)
        case .thisMonth: return cal.date(byAdding: .month, value: -1,   to: now)
        case .thisYear:  return cal.date(byAdding: .year,  value: -1,   to: now)
        }
    }

    private func conversationDate(_ conv: [String: Any]) -> Date? {
        let keys = ["archived_date", "archivedDate", "archived_at", "sessionDate", "created_at"]
        for key in keys {
            if let s = conv[key] as? String {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = fmt.date(from: s) { return d }
                fmt.formatOptions = [.withInternetDateTime]
                if let d = fmt.date(from: s) { return d }
                // Try yyyy-MM-dd
                let simple = DateFormatter()
                simple.dateFormat = "yyyy-MM-dd"
                if let d = simple.date(from: s) { return d }
            }
        }
        return nil
    }

    private var filteredConversations: [[String: Any]] {
        conversations.filter { conv in
            let subjectOK = selectedSubject == "All" || (conv["subject"] as? String) == selectedSubject
            let dateOK: Bool
            if let cutoff = dateCutoff, let d = conversationDate(conv) {
                dateOK = d >= cutoff
            } else {
                dateOK = dateCutoff == nil
            }
            return subjectOK && dateOK
        }
    }

    private var filteredQuestions: [QuestionSummary] {
        questions.filter { q in
            let subjectOK = selectedSubject == "All" || q.subject == selectedSubject
            let dateOK: Bool
            if let cutoff = dateCutoff {
                dateOK = q.archivedAt >= cutoff
            } else {
                dateOK = true
            }
            return subjectOK && dateOK
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                if conversations.isEmpty && questions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)

                        Text(NSLocalizedString("questionGeneration.noArchivesFound", comment: ""))
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(NSLocalizedString("questionGeneration.createArchivesMessage", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    // Row 1: Content type segmented control
                    Picker("Archive Type", selection: $selectedFilter) {
                        ForEach(ArchiveFilter.allCases, id: \.self) { filter in
                            Text(filter.localizedName).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Row 2: Subject + Time dropdown filters
                    HStack(spacing: 12) {
                        // Subject filter
                        Menu {
                            ForEach(availableSubjects, id: \.self) { subject in
                                Button(action: { selectedSubject = subject }) {
                                    HStack {
                                        Text(subject)
                                        if selectedSubject == subject {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "book.closed")
                                    .font(.caption)
                                Text(selectedSubject == "All" ? "Subject" : selectedSubject)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selectedSubject == "All" ? Color(.systemGray6) : Color.green.opacity(0.15))
                            .foregroundColor(selectedSubject == "All" ? .primary : .green)
                            .cornerRadius(8)
                        }

                        // Time filter
                        Menu {
                            ForEach(TimeFilter.allCases, id: \.self) { tf in
                                Button(action: { selectedTimeFilter = tf }) {
                                    HStack {
                                        Text(tf.rawValue)
                                        if selectedTimeFilter == tf {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                Text(selectedTimeFilter.rawValue)
                                    .font(.subheadline)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selectedTimeFilter == .allTime ? Color(.systemGray6) : Color.green.opacity(0.15))
                            .foregroundColor(selectedTimeFilter == .allTime ? .primary : .green)
                            .cornerRadius(8)
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)

                    // Selection Controls
                    HStack {
                        Button(action: {
                            let totalItems = filteredConversations.count + filteredQuestions.count
                            let selectedItems = selectedConversations.count + selectedQuestions.count

                            if selectedItems == totalItems {
                                selectedConversations.removeAll()
                                selectedQuestions.removeAll()
                            } else {
                                let conversationIds = filteredConversations.compactMap { $0["id"] as? String }
                                selectedConversations = Set(conversationIds)
                                selectedQuestions = Set(filteredQuestions.map { $0.id })
                            }
                        }) {
                            let totalItems = filteredConversations.count + filteredQuestions.count
                            let selectedItems = selectedConversations.count + selectedQuestions.count
                            Text(selectedItems == totalItems && totalItems > 0 ? NSLocalizedString("common.deselectAll", comment: "") : NSLocalizedString("common.selectAll", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }

                        Spacer()

                        Text("\(selectedConversations.count + selectedQuestions.count) \(NSLocalizedString("common.selected", comment: ""))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    // Archive List
                    List {
                        // Show conversations only if filter allows
                        if (selectedFilter == .all || selectedFilter == .conversations) && !filteredConversations.isEmpty {
                            Section(NSLocalizedString("questionGeneration.conversations", comment: "")) {
                                ForEach(filteredConversations.indices, id: \.self) { index in
                                    let conversation = filteredConversations[index]
                                    let conversationId = conversation["id"] as? String ?? ""
                                    let conversationPreview = extractConversationPreview(from: conversation)

                                    ArchiveConversationSelectionCard(
                                        conversationTitle: conversationPreview,
                                        isSelected: selectedConversations.contains(conversationId),
                                        onToggle: {
                                            if selectedConversations.contains(conversationId) {
                                                selectedConversations.remove(conversationId)
                                            } else {
                                                selectedConversations.insert(conversationId)
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        // Show questions only if filter allows
                        if (selectedFilter == .all || selectedFilter == .questions) && !filteredQuestions.isEmpty {
                            Section(NSLocalizedString("questionGeneration.questions", comment: "")) {
                                ForEach(filteredQuestions) { question in
                                    ArchiveQuestionSelectionCard(
                                        question: question,
                                        isSelected: selectedQuestions.contains(question.id),
                                        onToggle: {
                                            if selectedQuestions.contains(question.id) {
                                                selectedQuestions.remove(question.id)
                                            } else {
                                                selectedQuestions.insert(question.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        // Empty state when filters yield no results
                        if filteredConversations.isEmpty && filteredQuestions.isEmpty {
                            Section {
                                Text("No items match the selected filters.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 24)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(NSLocalizedString("questionGeneration.selectArchives", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedConversations.isEmpty && selectedQuestions.isEmpty)
                }
            }
        }
    }

    // MARK: - Helper Functions

    /// Extract conversation preview using AI-generated summary (like LibraryView)
    private func extractConversationPreview(from conversation: [String: Any]) -> String {
        // ✅ Priority 1: Use AI-generated summary (like LibraryView does)
        if let summary = conversation["summary"] as? String, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }

        // ✅ Priority 2: Use title if available
        if let title = conversation["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        // Priority 3: Try to extract from messages array
        if let messages = conversation["messages"] as? [[String: Any]], !messages.isEmpty {
            for message in messages {
                let role = message["role"] as? String ?? ""
                let sender = message["sender"] as? String ?? ""

                if role.lowercased() == "user" || sender.lowercased() == "user" {
                    if let content = message["content"] as? String ?? message["message"] as? String {
                        let words = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                        let limitedWords = words.prefix(50)
                        let preview = limitedWords.joined(separator: " ")
                        return preview + (words.count > 50 ? "..." : "")
                    }
                }
            }
        }

        // Fallback: Check conversationContent
        if let conversationContent = conversation["conversationContent"] as? String, !conversationContent.isEmpty {
            let lines = conversationContent.components(separatedBy: .newlines)
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

                // Skip headers and metadata
                if trimmedLine.hasPrefix("===") ||
                   trimmedLine.hasPrefix("Conversation Archive") ||
                   trimmedLine.hasPrefix("Session archived") ||
                   trimmedLine.hasPrefix("Session:") ||
                   trimmedLine.hasPrefix("Subject:") ||
                   trimmedLine.hasPrefix("Topic:") ||
                   trimmedLine.hasPrefix("Archived:") ||
                   trimmedLine.hasPrefix("Messages:") ||
                   (trimmedLine.hasPrefix("[") && trimmedLine.hasSuffix("]")) ||
                   trimmedLine.isEmpty {
                    continue
                }

                // Look for user message (not prefixed with "AI:")
                if !trimmedLine.hasPrefix("AI:") {
                    var cleanedLine = trimmedLine
                    cleanedLine = cleanedLine.replacingOccurrences(of: "^User:\\s*", with: "", options: .regularExpression)
                    cleanedLine = cleanedLine.replacingOccurrences(of: "^Student:\\s*", with: "", options: .regularExpression)
                    cleanedLine = cleanedLine.replacingOccurrences(of: "^\\[.*?\\]\\s*User:\\s*", with: "", options: .regularExpression)

                    if !cleanedLine.isEmpty {
                        let words = cleanedLine.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                        let limitedWords = words.prefix(50)
                        let preview = limitedWords.joined(separator: " ")
                        return preview + (words.count > 50 ? "..." : "")
                    }
                }
            }
        }

        // Try message count
        let messageCount = conversation["message_count"] as? Int ?? conversation["messageCount"] as? Int ?? 0
        if messageCount > 0 {
            return String.localizedStringWithFormat(NSLocalizedString("questionGeneration.messagesInConversation", comment: ""), messageCount)
        }

        // Ultimate fallback
        return NSLocalizedString("questionGeneration.studySession", comment: "")
    }
}

// MARK: - Selection Cards

struct MistakeSelectionCard: View {
    let mistake: MistakeQuestion
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .orange : .gray)
                    .font(.title2)

                // Mistake content
                VStack(alignment: .leading, spacing: 8) {
                    Text(mistake.question)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack {
                        Text(mistake.subject)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .foregroundColor(.orange)
                            .cornerRadius(4)

                        Spacer()

                        Text(RelativeDateTimeFormatter().localizedString(for: mistake.createdAt, relativeTo: Date()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(isSelected ? Color.orange.opacity(0.1) : Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ArchiveConversationSelectionCard: View {
    let conversationTitle: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .gray)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(conversationTitle)
                        .font(.body)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)

                    Text(NSLocalizedString("questionGeneration.conversation", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ArchiveQuestionSelectionCard: View {
    let question: QuestionSummary
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .gray)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(question.shortQuestionText)
                        .font(.body)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)

                    HStack {
                        Text(question.subject)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)

                        Spacer()

                        Text(RelativeDateTimeFormatter().localizedString(for: question.archivedAt, relativeTo: Date()))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Helper Functions

/// Extract student questions from conversation content, removing archive headers, metadata, and AI responses
private func extractStudentQuestions(from conversationContent: String, title: String) -> String {
    guard !conversationContent.isEmpty else {
        return String.localizedStringWithFormat(NSLocalizedString("questionGeneration.discussionAbout", comment: ""), title)
    }

    var studentQuestions: [String] = []
    let lines = conversationContent.components(separatedBy: .newlines)
    var currentUserMessage = ""
    var isUserMessage = false

    for line in lines {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip archive headers and metadata
        if trimmedLine.hasPrefix("===") ||
           trimmedLine.hasPrefix("Session:") ||
           trimmedLine.hasPrefix("Subject:") ||
           trimmedLine.hasPrefix("Topic:") ||
           trimmedLine.hasPrefix("Archived:") ||
           trimmedLine.hasPrefix("Messages:") ||
           trimmedLine.hasPrefix("Conversation Archive") ||
           trimmedLine.hasPrefix("Session archived") ||
           trimmedLine.hasPrefix("Difficulty Level:") ||
           trimmedLine.hasPrefix("Student Strengths") ||
           trimmedLine.hasPrefix("Areas for Improvement") ||
           trimmedLine.hasPrefix("Key Concepts") ||
           trimmedLine.hasPrefix("Student Engagement") ||
           trimmedLine.hasPrefix("=== Notes ===") ||
           trimmedLine.hasPrefix("Archive notes") ||
           trimmedLine.isEmpty {
            continue
        }

        // Detect user messages (format: "[timestamp] User:" or just "User:")
        if trimmedLine.contains("User:") {
            // Save previous user message if any
            if !currentUserMessage.isEmpty {
                studentQuestions.append(currentUserMessage.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            // Extract the message after "User:"
            if let userIndex = trimmedLine.range(of: "User:")?.upperBound {
                currentUserMessage = String(trimmedLine[userIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                currentUserMessage = ""
            }
            isUserMessage = true
            continue
        }

        // Detect AI messages (stop collecting user message)
        if trimmedLine.contains("AI Assistant:") || trimmedLine.contains("AI:") {
            // Save current user message before switching to AI
            if !currentUserMessage.isEmpty {
                studentQuestions.append(currentUserMessage.trimmingCharacters(in: .whitespacesAndNewlines))
                currentUserMessage = ""
            }
            isUserMessage = false
            continue
        }

        // If we're in a user message and this is a continuation line, append it
        if isUserMessage && !trimmedLine.isEmpty {
            if !currentUserMessage.isEmpty {
                currentUserMessage += " "
            }
            currentUserMessage += trimmedLine
        }
    }

    // Add the last user message if any
    if !currentUserMessage.isEmpty {
        studentQuestions.append(currentUserMessage.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // If no questions found, return a fallback
    if studentQuestions.isEmpty {
        return String.localizedStringWithFormat(NSLocalizedString("questionGeneration.discussionAbout", comment: ""), title)
    }

    // Combine all student questions, limiting to reasonable length
    let combined = studentQuestions.joined(separator: "; ")
    let maxLength = 500 // Limit to 500 characters instead of 9882

    if combined.count > maxLength {
        return String(combined.prefix(maxLength)) + "..."
    }

    return combined
}
