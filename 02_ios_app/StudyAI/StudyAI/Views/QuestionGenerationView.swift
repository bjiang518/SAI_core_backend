//
//  QuestionGenerationView.swift
//  StudyAI
//
//  Created by Claude Code on 12/21/24.
//

import SwiftUI
import Foundation
import os.log

struct QuestionGenerationView: View {
    @StateObject private var questionService = QuestionGenerationService.shared
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var profileService = ProfileService.shared
    @StateObject private var mistakeService = MistakeReviewService()
    @StateObject private var archiveService = QuestionArchiveService.shared
    @StateObject private var libraryService = LibraryDataService.shared
    @State private var inputSubject = ""
    @State private var selectedTemplate: TemplateType = .randomPractice
    @State private var showingQuestionsList = false
    @State private var generatedQuestions: [QuestionGenerationService.GeneratedQuestion] = []
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var availableMistakes: [MistakeQuestion] = []
    @State private var availableConversations: [[String: Any]] = []  // Use actual conversation objects
    @State private var availableQuestions: [QuestionSummary] = []
    @State private var selectedConversations: Set<String> = []
    @State private var selectedQuestions: Set<String> = []
    @State private var selectedMistakes: Set<String> = [] // Add selected mistakes tracking
    @State private var selectedDifficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty = .intermediate
    @State private var questionCount = 5
    @State private var selectedQuestionType: QuestionGenerationService.GeneratedQuestion.QuestionType = .any
    @State private var selectedMistakeNotebook = ""
    @State private var selectedArchiveSession = ""
    @State private var isLoadingData = false
    @State private var selectedSubject = ""
    @State private var showingMistakeSelection = false // Add mistake selection sheet state
    @State private var showingArchiveSelection = false // Add archive selection sheet state
    @State private var showingInfoAlert = false // Add info alert state
    @Environment(\.dismiss) private var dismiss

    private let logger = Logger(subsystem: "com.studyai", category: "QuestionGeneration")
    private let dataAdapter = QuestionGenerationDataAdapter.shared

    enum TemplateType: String, CaseIterable {
        case randomPractice = "random"
        case fromMistakes = "mistake_based"
        case fromArchives = "conversation_based"

        var displayName: String {
            switch self {
            case .randomPractice: return NSLocalizedString("questionGeneration.template.randomPractice", comment: "")
            case .fromMistakes: return NSLocalizedString("questionGeneration.template.fromMistakes", comment: "")
            case .fromArchives: return NSLocalizedString("questionGeneration.template.fromArchives", comment: "")
            }
        }

        var description: String {
            switch self {
            case .randomPractice: return NSLocalizedString("questionGeneration.description.randomPractice", comment: "")
            case .fromMistakes: return NSLocalizedString("questionGeneration.description.fromMistakes", comment: "")
            case .fromArchives: return NSLocalizedString("questionGeneration.description.fromArchives", comment: "")
            }
        }

        var iconName: String {
            switch self {
            case .randomPractice: return "dice.fill"
            case .fromMistakes: return "xmark.circle.fill"
            case .fromArchives: return "books.vertical.fill"
            }
        }

        var color: Color {
            switch self {
            case .randomPractice: return .blue
            case .fromMistakes: return .orange
            case .fromArchives: return .green
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
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

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("questionGeneration.title", comment: ""))
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
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingQuestionsList) {
                GeneratedQuestionsListView(questions: generatedQuestions)
            }
            .sheet(isPresented: $showingMistakeSelection) {
                MistakeSelectionView(
                    mistakes: availableMistakes,
                    selectedMistakes: $selectedMistakes
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
            case .fromMistakes:
                MistakeBasedConfig(
                    mistakes: availableMistakes,
                    isLoading: isLoadingData,
                    selectedMistakes: $selectedMistakes,
                    onShowSelection: { showingMistakeSelection = true }
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
                        Text(selectedDifficulty.rawValue.capitalized)
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
                                Text(difficulty.rawValue.capitalized).tag(difficulty)
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
        VStack(spacing: 16) {
            if let progress = questionService.generationProgress {
                Text(progress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            ProgressView()
                .progressViewStyle(LinearProgressViewStyle(tint: selectedTemplate.color))
        }
        .padding()
        .background(selectedTemplate.color.opacity(0.05))
        .cornerRadius(12)
    }

    private var recentQuestionsPreview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(NSLocalizedString("questionGeneration.generatedQuestions", comment: ""))
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button(NSLocalizedString("questionGeneration.viewAll", comment: "")) {
                    showingQuestionsList = true
                }
                .font(.subheadline)
                .foregroundColor(selectedTemplate.color)
            }

            VStack(spacing: 8) {
                ForEach(generatedQuestions.prefix(3)) { question in
                    QuestionGenerationPreviewCard(question: question)
                }
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
                await mistakeService.fetchMistakes(subject: nil, timeRange: .thisMonth)
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
        case .fromMistakes:
            return !selectedMistakes.isEmpty
        case .fromArchives:
            return !selectedConversations.isEmpty || !selectedQuestions.isEmpty
        }
    }

    private func generateQuestions() {

        Task {
            do {
                let questions = try await performGeneration()

                await MainActor.run {
                    self.generatedQuestions = questions
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

    private func performGeneration() async throws -> [QuestionGenerationService.GeneratedQuestion] {
        let userProfile = dataAdapter.createUserProfile()

        switch selectedTemplate {
        case .randomPractice:
            let mostCommonSubjects = dataAdapter.getMostCommonSubjects()

            let primarySubject = !selectedSubject.isEmpty ? selectedSubject : (mostCommonSubjects.first ?? NSLocalizedString("questionGeneration.defaultSubject.mathematics", comment: ""))

            let focusAreas = dataAdapter.getFocusAreas()

            let focusNotes = focusAreas.isEmpty ?
                NSLocalizedString("questionGeneration.focusNotes.diversePractice", comment: "") :
                String.localizedStringWithFormat(NSLocalizedString("questionGeneration.focusNotes.improvementAreas", comment: ""), focusAreas.joined(separator: ", "))

            let config = QuestionGenerationService.RandomQuestionsConfig(
                topics: mostCommonSubjects.isEmpty ? [primarySubject] : mostCommonSubjects,
                focusNotes: focusNotes,
                difficulty: selectedDifficulty,
                questionCount: questionCount,
                questionType: selectedQuestionType
            )


            let result = await questionService.generateRandomQuestions(
                subject: primarySubject,
                config: config,
                userProfile: userProfile
            )

            switch result {
            case .success(let questions):
                return questions
            case .failure(let error):
                throw error
            }

        case .fromMistakes:
            guard !selectedMistakes.isEmpty else {
                throw NSError(domain: "QuestionGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("questionGeneration.noMistakes", comment: "")])
            }

            // Filter to only selected mistakes
            let selectedMistakeObjects = availableMistakes.filter { selectedMistakes.contains($0.id) }

            // Convert selected mistake data using the adapter
            let mistakeData = selectedMistakeObjects.map { mistake in
                QuestionGenerationService.MistakeData(
                    originalQuestion: mistake.question,
                    userAnswer: mistake.studentAnswer,
                    correctAnswer: mistake.correctAnswer,
                    mistakeType: NSLocalizedString("questionGeneration.mistakeType.incorrectAnswer", comment: ""),
                    topic: mistake.subject,
                    date: ISO8601DateFormatter().string(from: mistake.createdAt),
                    tags: mistake.tags  // Pass tags from source question
                )
            }

            // Get the most common subject from selected mistakes
            let mistakeSubjects = Array(Set(selectedMistakeObjects.map { $0.subject }))
            let primarySubject = mistakeSubjects.first ?? NSLocalizedString("questionGeneration.defaultSubject.mathematics", comment: "")

            let config = QuestionGenerationService.RandomQuestionsConfig(
                topics: mistakeSubjects,
                focusNotes: NSLocalizedString("questionGeneration.focusNotes.addressMistakes", comment: ""),
                difficulty: selectedDifficulty,
                questionCount: questionCount,
                questionType: selectedQuestionType
            )

            let result = await questionService.generateMistakeBasedQuestions(
                subject: primarySubject,
                mistakes: mistakeData,
                config: config,
                userProfile: userProfile
            )

            switch result {
            case .success(let questions):
                return questions
            case .failure(let error):
                throw error
            }

        case .fromArchives:
            guard !availableConversations.isEmpty else {
                throw NSError(domain: "QuestionGeneration", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("questionGeneration.noArchives", comment: "")])
            }

            // Filter to only selected conversations
            let selectedConversationObjects = availableConversations.filter { conversation in
                if let conversationId = conversation["id"] as? String {
                    return selectedConversations.contains(conversationId)
                }
                return false
            }

            // Convert real conversation data using the adapter
            let conversationData = selectedConversationObjects.map { conversation in
                let title = conversation["title"] as? String ?? NSLocalizedString("questionGeneration.untitled", comment: "")
                let subject = conversation["subject"] as? String ?? NSLocalizedString("questionGeneration.generalSubject", comment: "")
                let content = conversation["conversationContent"] as? String ?? ""

                // ✅ Extract only student questions (remove archive headers, metadata, and AI responses)
                let studentQuestions = extractStudentQuestions(from: content, title: title)

                return QuestionGenerationService.ConversationData(
                    date: ISO8601DateFormatter().string(from: Date()),
                    topics: [subject],
                    studentQuestions: studentQuestions,
                    difficultyLevel: NSLocalizedString("questionGeneration.difficulty.intermediate", comment: ""),
                    strengths: [NSLocalizedString("questionGeneration.strengths.activeParticipation", comment: "")],
                    weaknesses: [NSLocalizedString("questionGeneration.weaknesses.morePractice", comment: "")],
                    keyConcepts: title,
                    engagement: NSLocalizedString("questionGeneration.engagement.high", comment: "")
                )
            }

            // Get the most common subject from conversations
            let conversationSubjects = Array(Set(selectedConversationObjects.compactMap { conversation in
                conversation["subject"] as? String
            })).filter { !$0.isEmpty && $0 != NSLocalizedString("questionGeneration.generalDiscussion", comment: "") }
            let primarySubject = conversationSubjects.first ?? NSLocalizedString("questionGeneration.defaultSubject.mathematics", comment: "")

            let config = QuestionGenerationService.RandomQuestionsConfig(
                topics: conversationSubjects.isEmpty ? [primarySubject] : conversationSubjects,
                focusNotes: NSLocalizedString("questionGeneration.focusNotes.conversationPatterns", comment: ""),
                difficulty: selectedDifficulty,
                questionCount: questionCount,
                questionType: selectedQuestionType
            )

            let result = await questionService.generateConversationBasedQuestions(
                subject: primarySubject,
                conversations: conversationData,
                config: config,
                userProfile: userProfile
            )

            switch result {
            case .success(let questions):
                return questions
            case .failure(let error):
                throw error
            }
        }
    }
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
            Text(question.question)
                .font(.subheadline)
                .fontWeight(.medium)
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
                            HStack(spacing: 6) {
                                Image(systemName: "list.bullet")
                                    .font(.caption)
                                Text(NSLocalizedString("common.select", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
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
                    // Selection Controls
                    HStack {
                        Button(action: {
                            let totalItems = conversations.count + questions.count
                            let selectedItems = selectedConversations.count + selectedQuestions.count

                            if selectedItems == totalItems {
                                selectedConversations.removeAll()
                                selectedQuestions.removeAll()
                            } else {
                                // Extract conversation IDs for selection
                                let conversationIds = conversations.compactMap { $0["id"] as? String }
                                selectedConversations = Set(conversationIds)
                                selectedQuestions = Set(questions.map { $0.id })
                            }
                        }) {
                            let totalItems = conversations.count + questions.count
                            let selectedItems = selectedConversations.count + selectedQuestions.count

                            Text(selectedItems == totalItems ? NSLocalizedString("common.deselectAll", comment: "") : NSLocalizedString("common.selectAll", comment: ""))
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
                        if !conversations.isEmpty {
                            Section(NSLocalizedString("questionGeneration.conversations", comment: "")) {
                                ForEach(conversations.indices, id: \.self) { index in
                                    let conversation = conversations[index]
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

                        if !questions.isEmpty {
                            Section(NSLocalizedString("questionGeneration.questions", comment: "")) {
                                ForEach(questions) { question in
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
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(NSLocalizedString("questionGeneration.selectArchives", comment: ""))
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
                    .disabled(selectedConversations.isEmpty && selectedQuestions.isEmpty)
                }
            }
        }
    }

    // MARK: - Helper Functions

    /// Extract conversation preview (first user message) similar to library view
    private func extractConversationPreview(from conversation: [String: Any]) -> String {
        // Try to extract from messages array first
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