//
//  NewPracticeSheet.swift
//  StudyAI
//
//  Bottom sheet for generating a new practice session.
//  Design mirrors QuestionGenerationView exactly.
//  Presented from PracticeLibraryView via .sheet.
//

import SwiftUI
import os.log
import Lottie

struct NewPracticeSheet: View {
    /// Called with the newly created session after generation succeeds.
    let onSessionCreated: (PracticeSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var questionService = QuestionGenerationService.shared
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var sessionManager = PracticeSessionManager.shared
    @StateObject private var archiveService = QuestionArchiveService.shared
    @StateObject private var libraryService = LibraryDataService.shared
    @StateObject private var themeManager = ThemeManager.shared

    // Tab selection
    @State private var selectedTab: Tab = .random

    // Common config
    @State private var selectedDifficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty = .intermediate
    @State private var questionCount: Int = 5
    @State private var selectedQuestionType: QuestionGenerationService.GeneratedQuestion.QuestionType = .any

    // Random tab
    @State private var selectedSubject: String = ""

    // Archive tab
    @State private var availableConversations: [[String: Any]] = []
    @State private var availableQuestions: [QuestionSummary] = []
    @State private var selectedConversations: Set<String> = []
    @State private var selectedQuestions: Set<String> = []
    @State private var isLoadingArchives: Bool = false
    @State private var showingArchiveSelection: Bool = false

    // Generation state
    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    // Difficulty bar animation

    private let dataAdapter = QuestionGenerationDataAdapter.shared
    private let logger = Logger(subsystem: "com.studyai", category: "NewPracticeSheet")

    // ── Pre-configuration (set at init time for todo shortcuts) ──────────
    private let initialConversationId: String?

    /// Default init — opens in random tab with no pre-selection.
    init(onSessionCreated: @escaping (PracticeSession) -> Void) {
        self.onSessionCreated = onSessionCreated
        self.initialConversationId = nil
    }

    /// Shortcut init — pre-configures tab, subject, and/or conversation.
    init(
        onSessionCreated: @escaping (PracticeSession) -> Void,
        initialTab: Tab,
        initialSubject: String = "",
        initialConversationId: String? = nil
    ) {
        self.onSessionCreated = onSessionCreated
        self.initialConversationId = initialConversationId
        _selectedTab = State(initialValue: initialTab)
        _selectedSubject = State(initialValue: initialSubject)
    }

    enum Tab: String, CaseIterable {
        case random = "random"
        case archive = "conversation_based"

        var displayName: String {
            switch self {
            case .random: return NSLocalizedString("questionGeneration.template.randomPractice", comment: "")
            case .archive: return NSLocalizedString("questionGeneration.template.fromArchives", comment: "")
            }
        }

        var description: String {
            switch self {
            case .random: return NSLocalizedString("questionGeneration.description.randomPractice", comment: "")
            case .archive: return NSLocalizedString("questionGeneration.description.fromArchives", comment: "")
            }
        }

        var iconName: String {
            switch self {
            case .random: return "dice.fill"
            case .archive: return "books.vertical.fill"
            }
        }

        var color: Color {
            switch self {
            case .random: return .blue
            case .archive: return .green
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Subject picker (affects random practice generation)
                    subjectPickerSection

                    // Generation type cards
                    generationTypeSelection

                    // Shared config (difficulty, count, type)
                    generalConfigurationSection

                    // Generate button
                    generateButton

                    // Lottie progress (shown below button while generating)
                    if questionService.isGenerating {
                        progressSection
                    }

                    if !questionService.isGenerating {
                        Spacer(minLength: 100)
                    }
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("newPractice.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                }
            }
        }
        .alert(NSLocalizedString("newPractice.error.title", comment: ""), isPresented: $showingError) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingArchiveSelection) {
            ArchiveSelectionView(
                conversations: availableConversations,
                questions: availableQuestions,
                selectedConversations: $selectedConversations,
                selectedQuestions: $selectedQuestions
            )
        }
        .onAppear { loadArchivesIfNeeded() }
        // Auto-select conversation once archives load (concept-review shortcut)
        .onChange(of: availableConversations.count) { _, _ in
            guard let convId = initialConversationId,
                  !availableConversations.isEmpty,
                  selectedConversations.isEmpty else { return }
            if availableConversations.contains(where: {
                ($0["sessionId"] as? String) == convId || ($0["id"] as? String) == convId
            }) {
                selectedConversations = [convId]
            }
        }
    }

    // MARK: - Subject Picker

    private var subjectPickerSection: some View {
        let subjects = dataAdapter.getMostCommonSubjects()
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(subjects, id: \.self) { subject in
                        let isSelected = selectedSubject == subject
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedSubject = subject
                                proxy.scrollTo(subject, anchor: .center)
                            }
                        }) {
                            Text(BranchLocalizer.localized(subject))
                                .font(isSelected ? .subheadline : .caption)
                                .fontWeight(isSelected ? .bold : .medium)
                                .foregroundColor(isSelected ? themeManager.accentColor : .secondary)
                                .padding(.horizontal, isSelected ? 16 : 12)
                                .padding(.vertical, isSelected ? 10 : 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(isSelected ? themeManager.accentColor.opacity(0.1) : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(isSelected ? themeManager.accentColor : Color.gray.opacity(0.25), lineWidth: isSelected ? 1.5 : 1)
                                        )
                                )
                                .scaleEffect(isSelected ? 1.05 : 0.95)
                                .opacity(isSelected ? 1.0 : 0.7)
                        }
                        .buttonStyle(.plain)
                        .id(subject)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .onAppear {
                if selectedSubject.isEmpty, let first = subjects.first {
                    selectedSubject = first
                    proxy.scrollTo(first, anchor: .center)
                }
            }
        }
    }

    // MARK: - Generation Type Cards

    private var generationTypeSelection: some View {
        VStack(spacing: 16) {
            ForEach(Tab.allCases, id: \.self) { tab in
                let archiveCount = selectedConversations.count + selectedQuestions.count
                NewPracticeTypeCard(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    archiveSelectionCount: tab == .archive ? archiveCount : 0,
                    onTap: {
                        selectedTab = tab
                        if tab == .archive {
                            loadArchivesIfNeeded()
                            showingArchiveSelection = true
                        }
                    }
                )
            }
        }
    }

    // MARK: - General Config (difficulty + count + type)

    private var generalConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 16) {
                difficultyColorBar

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("questionGeneration.numberOfQuestions", comment: ""))
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(questionCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedTab.color.opacity(0.1))
                            .cornerRadius(6)
                    }
                    VStack(spacing: 8) {
                        HStack {
                            Text("1").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text("10").font(.caption).foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(questionCount) },
                            set: { questionCount = Int($0) }
                        ), in: 1...10, step: 1)
                        .accentColor(selectedTab.color)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("questionGeneration.questionType", comment: ""))
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        Text(selectedQuestionType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(selectedTab.color.opacity(0.1))
                            .cornerRadius(6)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(QuestionGenerationService.GeneratedQuestion.QuestionType.generatableTypes, id: \.self) { type in
                            Button(action: { selectedQuestionType = type }) {
                                VStack(spacing: 4) {
                                    Image(systemName: type.icon)
                                        .font(.title3)
                                        .foregroundColor(selectedQuestionType == type ? selectedTab.color : .secondary)
                                    Text(type.displayName)
                                        .font(.caption2)
                                        .foregroundColor(selectedQuestionType == type ? selectedTab.color : .secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedQuestionType == type ? selectedTab.color.opacity(0.1) : Color.gray.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedQuestionType == type ? selectedTab.color : Color.clear, lineWidth: 2)
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

    // MARK: - Difficulty Color Bar

    private var difficultyColorBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("questionGeneration.difficultyLevel", comment: ""))
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Text(selectedDifficulty.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(difficultyColor(selectedDifficulty))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(difficultyColor(selectedDifficulty).opacity(0.12))
                    .cornerRadius(6)
                    .animation(.easeInOut(duration: 0.2), value: selectedDifficulty)
            }

            GeometryReader { geo in
                let adaptiveExtW: CGFloat = 64
                let mainW = geo.size.width - adaptiveExtW
                let segW = mainW / 3
                let barH: CGFloat = 10
                let trackTopY: CGFloat = 13
                let thumbD: CGFloat = 22
                let thumbTopY: CGFloat = (36 - thumbD) / 2

                let thumbX: CGFloat = {
                    switch selectedDifficulty {
                    case .beginner:     return segW * 0.5 - thumbD / 2
                    case .intermediate: return segW * 1.5 - thumbD / 2
                    case .advanced:     return segW * 2.5 - thumbD / 2
                    case .adaptive:     return mainW + adaptiveExtW - thumbD
                    }
                }()

                ZStack(alignment: .topLeading) {
                    HStack(spacing: 1) {
                        Rectangle().fill(Color.green.opacity(1.0))
                        Rectangle().fill(Color.orange.opacity(isIntermediateSegActive ? 1.0 : 0.2))
                        Rectangle().fill(Color.red.opacity(isAdvancedSegActive ? 1.0 : 0.2))
                    }
                    .frame(width: mainW, height: barH)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .offset(x: 0, y: trackTopY)

                    Path { p in
                        let y = trackTopY + barH / 2
                        p.move(to: CGPoint(x: mainW + 6, y: y))
                        p.addLine(to: CGPoint(x: mainW + adaptiveExtW - thumbD - 6, y: y))
                    }
                    .stroke(
                        Color.purple.opacity(selectedDifficulty == .adaptive ? 0.75 : 0.35),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 5])
                    )
                    .animation(.easeInOut(duration: 0.2), value: selectedDifficulty)

                    AdaptiveGlowDot(isActive: selectedDifficulty == .adaptive)
                        .offset(x: mainW + adaptiveExtW - thumbD, y: trackTopY + barH / 2 - 8)
                        .animation(.easeInOut(duration: 0.25), value: selectedDifficulty)

                    Circle()
                        .fill(.white)
                        .frame(width: thumbD, height: thumbD)
                        .shadow(color: difficultyColor(selectedDifficulty).opacity(0.4), radius: 5)
                        .overlay(Circle().stroke(difficultyColor(selectedDifficulty), lineWidth: 2.5))
                        .offset(x: thumbX, y: thumbTopY)
                        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: selectedDifficulty)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = value.location.x
                            if x < segW {
                                selectedDifficulty = .beginner
                            } else if x < segW * 2 {
                                selectedDifficulty = .intermediate
                            } else if x < mainW {
                                selectedDifficulty = .advanced
                            } else {
                                selectedDifficulty = .adaptive
                            }
                        }
                )
            }
            .frame(height: 36)
        }
    }

    private var isIntermediateSegActive: Bool {
        selectedDifficulty == .intermediate || selectedDifficulty == .advanced || selectedDifficulty == .adaptive
    }

    private var isAdvancedSegActive: Bool {
        selectedDifficulty == .advanced || selectedDifficulty == .adaptive
    }

    private func difficultyColor(_ d: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty) -> Color {
        switch d {
        case .beginner:     return .green
        case .intermediate: return .orange
        case .advanced:     return .red
        case .adaptive:     return .purple
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button(action: generate) {
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
                    colors: [selectedTab.color, selectedTab.color.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
        }
        .disabled(questionService.isGenerating || !canGenerate)
        .opacity(questionService.isGenerating || !canGenerate ? 0.6 : 1.0)
    }

    private var canGenerate: Bool {
        guard authService.isAuthenticated else { return false }
        switch selectedTab {
        case .random: return true
        case .archive: return !selectedConversations.isEmpty || !selectedQuestions.isEmpty
        }
    }

    // MARK: - Progress Section (Lottie below button)

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

    // MARK: - Generation Logic

    private func generate() {
        Task {
            do {
                try await performGeneration()

                // generateQuestionsV2 already saved the session internally;
                // retrieve it via currentSessionId to avoid duplicate saves.
                guard let sid = questionService.currentSessionId,
                      let session = sessionManager.getSession(id: sid) else {
                    throw NSError(domain: "PracticeGen", code: -2, userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString("newPractice.error.sessionNotFound", comment: "")
                    ])
                }

                await MainActor.run {
                    dismiss()
                    onSessionCreated(session)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func performGeneration() async throws {
        let userProfile = dataAdapter.createUserProfile()

        switch selectedTab {
        case .random:
            let subjects = dataAdapter.getMostCommonSubjects()
            let primary = selectedSubject.isEmpty ? (subjects.first ?? "Mathematics") : selectedSubject
            let weaknessTopics = dataAdapter.getWeaknessTopics(for: primary)
            let mixedTopics = dataAdapter.getMixedTopicsWithMastery(for: primary, weaknessTopics: weaknessTopics)
            let focusNotes = dataAdapter.getPersonalizedFocusNotes(for: primary)

            let config = QuestionGenerationService.RandomQuestionsConfig(
                topics: mixedTopics.isEmpty ? [primary] : mixedTopics,
                focusNotes: focusNotes,
                difficulty: selectedDifficulty,
                questionCount: questionCount,
                questionType: selectedQuestionType
            )

            let result = await questionService.generateQuestionsV2(
                subject: primary,
                mode: 1,
                config: config,
                userProfile: userProfile,
                shortTermContext: questionService.buildShortTermContext(subject: primary)
            )
            if case .failure(let e) = result { throw e }

        case .archive:
            guard !selectedConversations.isEmpty || !selectedQuestions.isEmpty else {
                throw NSError(domain: "PracticeGen", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("newPractice.error.noSelection", comment: "")
                ])
            }

            let filteredConversations = availableConversations.filter { selectedConversations.contains($0["id"] as? String ?? "") }
            let filteredQuestions = availableQuestions.filter { selectedQuestions.contains($0.id) }

            let allSubjects = Set(
                filteredConversations.compactMap { $0["subject"] as? String }.filter { !$0.isEmpty } +
                filteredQuestions.map { $0.subject }.filter { !$0.isEmpty }
            )
            guard allSubjects.count <= 1 else {
                throw NSError(domain: "PracticeGen", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString("newPractice.error.multipleSubjects",
                        value: "Selected items span multiple subjects. Please select items from one subject only.",
                        comment: "")
                ])
            }
            let subject = allSubjects.first ?? "General"

            let config = QuestionGenerationService.RandomQuestionsConfig(
                topics: [subject],
                focusNotes: nil,
                difficulty: selectedDifficulty,
                questionCount: questionCount,
                questionType: selectedQuestionType
            )

            // Convert conversations to ConversationData (same mapping as QuestionGenerationView)
            let conversationData: [QuestionGenerationService.ConversationData] = filteredConversations.map { conv in
                let title = conv["title"] as? String ?? conv["summary"] as? String ?? "Conversation"
                let content = conv["conversationContent"] as? String ?? ""
                let summary = conv["summary"] as? String ?? ""
                let keyTopics: [String]
                if let arr = conv["keyTopics"] as? [String] {
                    keyTopics = arr
                } else if let json = conv["keyTopics"] as? String,
                          let data = json.data(using: .utf8),
                          let decoded = try? JSONSerialization.jsonObject(with: data) as? [String] {
                    keyTopics = decoded
                } else {
                    keyTopics = [subject]
                }
                return QuestionGenerationService.ConversationData(
                    date: conv["createdAt"] as? String ?? ISO8601DateFormatter().string(from: Date()),
                    topics: keyTopics,
                    studentQuestions: content.isEmpty ? title : content,
                    keyConcepts: summary.isEmpty ? title : summary
                )
            }

            // Convert questions to backend dict format
            let questionData: [[String: Any]] = filteredQuestions.map { q in
                var dict: [String: Any] = [
                    "question_text": q.questionText,
                    "topic": q.subject,
                    "date": ISO8601DateFormatter().string(from: q.archivedAt),
                    "is_correct": q.grade == .correct || q.grade == .partialCredit
                ]
                if let ans = q.studentAnswer, !ans.isEmpty { dict["student_answer"] = ans }
                if let correct = q.answerText, !correct.isEmpty { dict["correct_answer"] = correct }
                if let grade = q.grade { dict["grade"] = grade.rawValue }
                if let tags = q.tags, !tags.isEmpty { dict["tags"] = tags }
                if let qType = q.questionType, !qType.isEmpty { dict["question_type"] = qType }
                return dict
            }

            let result = await questionService.generateQuestionsV2(
                subject: subject,
                mode: 3,
                config: config,
                userProfile: userProfile,
                conversationData: conversationData,
                questionData: questionData
            )
            if case .failure(let e) = result { throw e }
        }
    }

    // MARK: - Data Loading

    private func loadArchivesIfNeeded() {
        guard !isLoadingArchives, availableConversations.isEmpty, availableQuestions.isEmpty else { return }
        isLoadingArchives = true

        Task {
            async let convs = libraryService.fetchConversationsOnly()
            async let qs = (try? archiveService.fetchArchivedQuestions(limit: 100)) ?? []

            let (conversations, questions) = await (convs, qs)
            await MainActor.run {
                self.availableConversations = conversations
                self.availableQuestions = questions
                self.isLoadingArchives = false
            }
        }
    }
}

// MARK: - NewPracticeTypeCard

private struct NewPracticeTypeCard: View {
    let tab: NewPracticeSheet.Tab
    let isSelected: Bool
    let archiveSelectionCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(tab.color.opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 50, height: 50)
                    Image(systemName: tab.iconName)
                        .font(.title2)
                        .foregroundColor(tab.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(tab.displayName)
                        .font(.body.bold())
                        .foregroundColor(.primary)
                    if tab == .archive && archiveSelectionCount > 0 {
                        Text(NSLocalizedString("newPractice.archiveSelected",
                            value: "已选择 \(archiveSelectionCount) 项",
                            comment: "Archive items selected count"))
                            .font(.footnote)
                            .foregroundColor(tab.color)
                    } else {
                        Text(tab.description)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                if tab == .archive {
                    Image(systemName: archiveSelectionCount > 0 ? "checkmark.circle.fill" : "chevron.right")
                        .font(.title3)
                        .foregroundColor(archiveSelectionCount > 0 ? tab.color : .secondary)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(tab.color)
                }
            }
            .padding()
            .background(isSelected ? tab.color.opacity(0.05) : Color.gray.opacity(0.1))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? tab.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
