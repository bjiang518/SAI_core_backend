//
//  MistakeReviewView.swift
//  StudyAI
//
//  Created by Claude Code on 9/20/25.
//

import SwiftUI
import Lottie

// MARK: - Practice Generation Errors

/// ✅ SECURITY: Comprehensive error handling for practice generation
enum PracticeGenerationError: LocalizedError {
    case noMistakesSelected
    case tooManyMistakes
    case invalidSubject
    case invalidURL
    case notAuthenticated
    case rateLimitExceeded
    case serverError
    case invalidResponse
    case invalidResponseFormat
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noMistakesSelected:
            return "Please select at least one mistake to generate practice questions."
        case .tooManyMistakes:
            return "Too many mistakes selected. Please select \(AppConstants.maxSelectedMistakes) or fewer mistakes."
        case .invalidSubject:
            return "Invalid subject selected. Please try again."
        case .invalidURL:
            return "Unable to connect to the server. Please check your settings."
        case .notAuthenticated:
            return "Please log in again to generate practice questions."
        case .rateLimitExceeded:
            return "Too many requests. Please wait a moment and try again."
        case .serverError:
            return "Server is experiencing issues. Please try again later."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .invalidResponseFormat:
            return "Unable to parse the generated questions. Please try again."
        case .httpError(let code):
            return "Request failed with error code \(code). Please try again."
        }
    }
}

// MARK: - Main View
struct MistakeReviewView: View {
    @StateObject private var mistakeService = MistakeReviewService()
    @State private var selectedSubject: String?

    // NEW: Dual slider filters
    @State private var selectedSeverity: SeverityLevel = .all
    @State private var selectedTimeRange: FilterTimeRange = .allTime

    // NEW: Hierarchical filtering state (multi-select)
    @State private var selectedDetailedBranches: Set<String> = []

    @State private var showingMistakeList = false
    @State private var showingInstructions = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // SECTION 1: Compact Subject Selection
                    if mistakeService.isLoading {
                        ProgressView(NSLocalizedString("mistakeReview.loadingSubjects", comment: ""))
                            .frame(height: 100)
                    } else if mistakeService.subjectsWithMistakes.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)

                            Text(NSLocalizedString("mistakeReview.noMistakesFound", comment: ""))
                                .font(.headline)
                                .foregroundColor(.green)

                            Text(NSLocalizedString("mistakeReview.noMistakesMessage", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        CompactSubjectSelector(
                            subjects: mistakeService.subjectsWithMistakes,
                            selectedSubject: $selectedSubject
                        )
                        .onChange(of: selectedSubject) { _, _ in
                            // Clear filters when subject changes
                            selectedDetailedBranches.removeAll()
                        }
                    }

                    // SECTION 2: Dual Slider Filters (Severity + Time)
                    if selectedSubject != nil {
                        DualSliderFilters(
                            selectedSeverity: $selectedSeverity,
                            selectedTimeRange: $selectedTimeRange
                        )
                        .padding(.horizontal)
                    }

                    // SECTION 3: Taxonomy Filter (Chips/Tree Mode)
                    if let subject = selectedSubject {
                        let taxonomyData = mistakeService.getBaseBranches(
                            for: subject,
                            timeRange: selectedTimeRange.mistakeTimeRange
                        )

                        TaxonomyFilterView(
                            subject: subject,
                            taxonomyData: taxonomyData,
                            selectedDetailedBranches: $selectedDetailedBranches
                        )
                        .padding(.horizontal)
                    }

                    // SECTION 4: Start Review Button
                    if selectedSubject != nil && !mistakeService.subjectsWithMistakes.isEmpty {
                        let mistakeCount = calculateFilteredMistakeCount()

                        Button(action: {
                            showingMistakeList = true
                        }) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)

                                Text("Start Review (\(mistakeCount) \(mistakeCount == 1 ? "Mistake" : "Mistakes"))")
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(mistakeCount > 0 ? Color.blue : Color.gray)
                            .cornerRadius(12)
                        }
                        .disabled(mistakeCount == 0)
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .navigationTitle(NSLocalizedString("mistakeReview.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingInstructions = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.body)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .alert(NSLocalizedString("mistakeReview.instructions.title", comment: ""), isPresented: $showingInstructions) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("mistakeReview.instructions.message", comment: ""))
            }
            .task {
                // ✅ DEBUG: Print short-term status for debugging bidirectional tracking
                printShortTermStatusDebugInfo()

                await mistakeService.fetchSubjectsWithMistakes(timeRange: selectedTimeRange.mistakeTimeRange)
            }
            .onChange(of: selectedTimeRange) { _, newRange in
                Task {
                    await mistakeService.fetchSubjectsWithMistakes(timeRange: newRange.mistakeTimeRange)
                }
            }
            .sheet(isPresented: $showingMistakeList) {
                if let subject = selectedSubject {
                    MistakeQuestionListView(
                        subject: subject,
                        selectedDetailedBranches: selectedDetailedBranches,
                        selectedSeverity: selectedSeverity,
                        timeRange: selectedTimeRange.mistakeTimeRange
                    )
                }
            }
        }
    }

    // MARK: - Helper Methods

    /// Calculate filtered mistake count based on hierarchical filters and severity
    private func calculateFilteredMistakeCount() -> Int {
        guard let selectedSubject = selectedSubject else { return 0 }

        let localStorage = QuestionLocalStorage.shared
        var allMistakes = localStorage.getMistakeQuestions(subject: selectedSubject)

        // Filter by time range
        allMistakes = mistakeService.filterByTimeRange(allMistakes, timeRange: selectedTimeRange.mistakeTimeRange)

        // Filter by severity (error type)
        allMistakes = allMistakes.filter { mistake in
            let errorType = mistake["errorType"] as? String
            return selectedSeverity.matches(errorType: errorType)
        }

        // Filter by detailed branches (multi-select)
        if !selectedDetailedBranches.isEmpty {
            allMistakes = allMistakes.filter { mistake in
                guard let detailedBranch = mistake["detailedBranch"] as? String else {
                    return false
                }
                return selectedDetailedBranches.contains(detailedBranch)
            }
        }

        return allMistakes.count
    }

    /// DEBUG: Print comprehensive short-term status for bidirectional tracking verification
    private func printShortTermStatusDebugInfo() {
        let statusService = ShortTermStatusService.shared
        let status = statusService.status

        print("\n" + String(repeating: "=", count: 80))
        print("🔍 SHORT-TERM STATUS DEBUG INFO (Bidirectional Tracking)")
        print(String(repeating: "=", count: 80))

        // Overall statistics
        let totalKeys = status.activeWeaknesses.count
        let weaknessKeys = status.activeWeaknesses.filter { $0.value.value > 0 }
        let masteryKeys = status.activeWeaknesses.filter { $0.value.value < 0 }
        let neutralKeys = status.activeWeaknesses.filter { $0.value.value == 0 }

        print("📊 OVERALL STATISTICS:")
        print("   Total Keys: \(totalKeys)")
        print("   Weaknesses (value > 0): \(weaknessKeys.count)")
        print("   Mastery (value < 0): \(masteryKeys.count)")
        print("   Neutral (value = 0): \(neutralKeys.count)")

        // Group by subject
        var keysBySubject: [String: [(key: String, weakness: WeaknessValue)]] = [:]
        for (key, weakness) in status.activeWeaknesses {
            let components = key.split(separator: "/").map(String.init)
            guard let subject = components.first else { continue }
            keysBySubject[subject, default: []].append((key, weakness))
        }

        // Print subject-by-subject breakdown
        for (subject, keys) in keysBySubject.sorted(by: { $0.key < $1.key }) {
            print("\n" + String(repeating: "-", count: 80))
            print("📚 SUBJECT: \(subject) (\(keys.count) keys)")
            print(String(repeating: "-", count: 80))

            // Sort by value (most negative first, then most positive)
            let sortedKeys = keys.sorted { $0.weakness.value < $1.weakness.value }

            for (key, weakness) in sortedKeys {
                let statusEmoji = weakness.value > 0 ? "⚠️" : (weakness.value < 0 ? "✅" : "➖")
                let statusLabel = weakness.value > 0 ? "WEAKNESS" : (weakness.value < 0 ? "MASTERY" : "NEUTRAL")

                print("\n\(statusEmoji) [\(statusLabel)] Key: \(key)")
                print("   Value: \(String(format: "%.2f", weakness.value)) (Attempts: \(weakness.totalAttempts), Correct: \(weakness.correctAttempts))")
                print("   First Detected: \(formatDate(weakness.firstDetected))")
                print("   Last Attempt: \(formatDate(weakness.lastAttempt))")

                // Conditional tracking data
                if weakness.value > 0 {
                    // Weakness tracking
                    if !weakness.recentErrorTypes.isEmpty {
                        print("   Error Types: \(weakness.recentErrorTypes.joined(separator: ", "))")
                    }
                    if !weakness.recentQuestionIds.isEmpty {
                        print("   Recent Questions: \(weakness.recentQuestionIds.prefix(3).joined(separator: ", "))...")
                    }
                } else if weakness.value < 0 {
                    // Mastery tracking
                    if !weakness.masteryQuestions.isEmpty {
                        print("   Mastery Questions: \(weakness.masteryQuestions.prefix(3).joined(separator: ", "))...")
                    }
                }
            }
        }

        print("\n" + String(repeating: "=", count: 80))
        print("🔍 END OF SHORT-TERM STATUS DEBUG INFO")
        print(String(repeating: "=", count: 80) + "\n")
    }

    /// Helper: Format date for debug output
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Mistake Question List View
struct MistakeQuestionListView: View {
    let subject: String
    let selectedDetailedBranches: Set<String>
    let selectedSeverity: SeverityLevel
    let timeRange: MistakeTimeRange

    @StateObject private var mistakeService = MistakeReviewService()
    @StateObject private var questionGenerationService = QuestionGenerationService.shared
    @StateObject private var profileService = ProfileService.shared
    @State private var selectedQuestions: Set<String> = []
    @State private var isSelectionMode = false
    @State private var showingPDFGenerator = false
    @State private var isGeneratingPractice = false
    @State private var generatedQuestions: [QuestionGenerationService.GeneratedQuestion] = []
    @State private var showingPracticeQuestions = false
    @State private var showingConfigurationSheet = false // ✅ NEW: Show configuration before generating
    @State private var generationError: String? = nil // ✅ OPTIMIZATION: Error handling
    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed Properties

    /// Filter mistakes by hierarchical filters and severity
    private var filteredMistakes: [MistakeQuestion] {
        var filtered = mistakeService.mistakes

        // Filter by severity (error type)
        filtered = filtered.filter { mistake in
            selectedSeverity.matches(errorType: mistake.errorType)
        }

        // Filter by detailed branches (multi-select)
        if !selectedDetailedBranches.isEmpty {
            filtered = filtered.filter { mistake in
                guard let detailedBranch = mistake.detailedBranch else {
                    return false
                }
                return selectedDetailedBranches.contains(detailedBranch)
            }
        }

        return filtered
    }

    var body: some View {
        ZStack {
            // Main content
            NavigationView {
                VStack {
                    // Selection Mode Buttons
                    if !filteredMistakes.isEmpty && !isSelectionMode {
                    VStack(spacing: 12) {
                        Button(action: {
                            isSelectionMode = true
                        }) {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .font(.title3)

                                Text("Let's practise them")
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
                    }
                    .padding(.top)
                }

                // Selection Controls
                if isSelectionMode {
                    HStack {
                        Button(action: {
                            if selectedQuestions.count == filteredMistakes.count {
                                selectedQuestions.removeAll()
                            } else {
                                selectedQuestions = Set(filteredMistakes.map { $0.id })
                            }
                        }) {
                            Text(selectedQuestions.count == filteredMistakes.count ?
                                 NSLocalizedString("common.deselectAll", comment: "") :
                                 NSLocalizedString("common.selectAll", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }

                        Spacer()

                        Text(String.localizedStringWithFormat(NSLocalizedString("mistakeReview.selectedCount", comment: ""), selectedQuestions.count))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: {
                            isSelectionMode = false
                            selectedQuestions.removeAll()
                        }) {
                            Text(NSLocalizedString("common.cancel", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                Group {
                    if mistakeService.isLoading {
                        ProgressView(NSLocalizedString("mistakeReview.loadingMistakes", comment: ""))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredMistakes.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.green)

                            Text(NSLocalizedString("mistakeReview.noMistakesFound", comment: ""))
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(String.localizedStringWithFormat(NSLocalizedString("mistakeReview.noMistakesInSubject", comment: ""), subject))
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else {
                        List {
                            ForEach(filteredMistakes) { mistake in
                                MistakeQuestionCard(
                                    question: mistake,
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedQuestions.contains(mistake.id),
                                    onToggleSelection: { toggleSelection(mistake.id) }
                                )
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                    }
                }

                //✅ Generate Practice Button (ENHANCED with configuration UI)
                if isSelectionMode && !selectedQuestions.isEmpty {
                    Button(action: {
                        // Show configuration sheet instead of immediately generating
                        showingConfigurationSheet = true
                    }) {
                        HStack {
                            if isGeneratingPractice {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "brain.head.profile")
                                    .font(.title3)

                                Text("Generate Practice (\(selectedQuestions.count) mistakes)")
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(isGeneratingPractice ? Color.gray : Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(isGeneratingPractice)
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle(String.localizedStringWithFormat(NSLocalizedString("mistakeReview.subjectMistakes", comment: ""), subject))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .task {
                await mistakeService.fetchMistakes(subject: subject, timeRange: timeRange)
            }
            .sheet(isPresented: $showingPDFGenerator) {
                if !selectedQuestions.isEmpty {
                    let selectedMistakes = filteredMistakes.filter { selectedQuestions.contains($0.id) }
                    PDFPreviewView(
                        questions: selectedMistakes,
                        subject: subject,
                        timeRange: timeRange
                    )
                }
            }
            .sheet(isPresented: $showingPracticeQuestions) {
                PracticeQuestionsView(questions: generatedQuestions, subject: subject)
            }
            .sheet(isPresented: $showingConfigurationSheet) {
                // ✅ NEW: Show configuration sheet before generating
                PracticeConfigurationSheet(
                    mistakeCount: selectedQuestions.count,
                    onGenerate: { difficulty, questionTypes, count in
                        Task {
                            // Generate with user-selected parameters
                            await generatePracticeFromMistakes(
                                difficulty: difficulty,
                                questionTypes: questionTypes,
                                questionCount: count
                            )
                        }
                    }
                )
            }
            // ✅ OPTIMIZATION: Error alert for practice generation
            .alert("Practice Generation Failed", isPresented: .constant(generationError != nil)) {
                Button("Retry") {
                    // Show configuration sheet again
                    generationError = nil
                    showingConfigurationSheet = true
                }
                Button("Cancel", role: .cancel) {
                    generationError = nil
                }
            } message: {
                Text(generationError ?? "An unknown error occurred")
            }
        }

        // Lottie Animation Overlay (when generating questions)
        if isGeneratingPractice {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Text("Generating Questions...")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    if let progress = questionGenerationService.generationProgress {
                        Text(progress)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                LottieView(
                    animationName: "Bubbles x2",
                    loopMode: .loop,
                    animationSpeed: 1.0,
                    powerSavingProgress: 0.7
                )
                .frame(width: 150, height: 150)
                .padding(.bottom, 40)
            }
            .transition(.scale.combined(with: .opacity))
        }
        }
        .animation(.easeInOut(duration: 0.3), value: isGeneratingPractice)
    }

    // ✅ OPTIMIZED: Generate practice from selected mistakes with user-configured parameters
    private func generatePracticeFromMistakes(
        difficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty,
        questionTypes: Set<QuestionGenerationService.GeneratedQuestion.QuestionType>,
        questionCount: Int
    ) async {
        isGeneratingPractice = true
        generationError = nil
        defer { isGeneratingPractice = false }

        do {
            // Get selected mistakes
            let selectedMistakes = filteredMistakes.filter { selectedQuestions.contains($0.id) }

            // ✅ VALIDATION #1: Check selection count
            guard !selectedMistakes.isEmpty else {
                throw PracticeGenerationError.noMistakesSelected
            }

            guard selectedMistakes.count <= AppConstants.maxSelectedMistakes else {
                throw PracticeGenerationError.tooManyMistakes
            }

            // ✅ VALIDATION #2: Validate subject (use existing Subject enum)
            let validSubjects = Subject.allCases.map { $0.rawValue }
            guard validSubjects.contains(subject) else {
                throw PracticeGenerationError.invalidSubject
            }

            // ✅ OPTIMIZED: Convert to MistakeData with error analysis (minimal fields)
            let mistakesData = selectedMistakes.map { convertToMistakeData($0) }

            // ✅ OPTIMIZED: Build topics from hierarchical taxonomy
            let topics = Set(selectedMistakes.compactMap {
                $0.detailedBranch ?? $0.baseBranch ?? $0.subject
            }).sorted()

            // ✅ OPTIMIZED: Build focus notes from specific issues
            let specificIssues = selectedMistakes.compactMap { $0.specificIssue }
            let focusNotes = specificIssues.isEmpty ? nil :
                "Address these specific issues: \(specificIssues.joined(separator: "; "))"

            // ✅ Create config with user-selected parameters
            // Determine which question type to use (if multiple selected, use .any)
            let questionType = questionTypes.count == 1 ? questionTypes.first! : .any

            let config = QuestionGenerationService.RandomQuestionsConfig(
                topics: topics,
                focusNotes: focusNotes,
                difficulty: difficulty,
                questionCount: questionCount,
                questionType: questionType
            )

            // ✅ Build user profile from ProfileService (with fallback to cached or defaults)
            let cachedProfile = profileService.currentProfile ?? profileService.loadCachedProfile()
            let gradeLevel = cachedProfile?.gradeLevel ?? "8"
            let location = cachedProfile?.country ?? "US"

            let userProfile = QuestionGenerationService.UserProfile(
                grade: gradeLevel,
                location: location,
                preferences: [:]
            )

            DebugSettings.shared.logGeneration("Using user profile - Grade: \(gradeLevel), Location: \(location)")

            // ✅ Call optimized service
            print("🎯 [MistakeReview] Generating practice with user-selected configuration:")
            print("   - Mistakes: \(mistakesData.count)")
            print("   - Difficulty: \(difficulty.rawValue)")
            print("   - Question Count: \(questionCount)")
            print("   - Question Types: \(questionTypes.map { $0.rawValue }.joined(separator: ", "))")
            print("   - Topics: \(topics)")

            let result = await QuestionGenerationService.shared.generateMistakeBasedQuestions(
                subject: subject,
                mistakes: mistakesData,
                config: config,
                userProfile: userProfile
            )

            switch result {
            case .success(let questions):
                await MainActor.run {
                    // ✅ FIX: Keep full GeneratedQuestion objects instead of just text
                    generatedQuestions = questions
                    showingPracticeQuestions = true
                }
                print("🎉 Generated \(questions.count) targeted practice questions with type-based rendering")

            case .failure(_):
                throw PracticeGenerationError.serverError
            }

        } catch let error as PracticeGenerationError {
            generationError = error.localizedDescription
        } catch {
            generationError = "An unexpected error occurred. Please try again."
        }
    }

    /// ✅ OPTIMIZED: Convert MistakeQuestion to minimal MistakeData with error analysis
    private func convertToMistakeData(_ mistake: MistakeQuestion) -> QuestionGenerationService.MistakeData {
        return QuestionGenerationService.MistakeData(
            // Core data
            originalQuestion: mistake.rawQuestionText,
            userAnswer: mistake.studentAnswer,
            correctAnswer: mistake.correctAnswer,

            // Error analysis (3 critical fields)
            errorType: mistake.errorType,
            baseBranch: mistake.baseBranch,
            detailedBranch: mistake.detailedBranch,

            // Optional context
            specificIssue: mistake.specificIssue,
            questionImageUrl: mistake.questionImageUrl
        )
    }

    private func toggleSelection(_ questionId: String) {
        if selectedQuestions.contains(questionId) {
            selectedQuestions.remove(questionId)
        } else {
            selectedQuestions.insert(questionId)
        }
    }
}

// MARK: - Mistake Question Card
struct MistakeQuestionCard: View {
    let question: MistakeQuestion
    let isSelectionMode: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void

    @State private var isExpanded = false  // ✅ Changed: Card starts folded
    @State private var imageExpanded = false  // ✅ New: Image expansion state

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Selection header (always visible)
            if isSelectionMode {
                HStack {
                    Button(action: onToggleSelection) {
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .blue : .gray)
                                .font(.title3)

                            Text(isSelected ?
                                 NSLocalizedString("mistakeReview.selected", comment: "") :
                                 NSLocalizedString("mistakeReview.select", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(isSelected ? .blue : .gray)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()
                }
            }

            // ✅ Header: Question preview (always visible)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // ✅ Just subject and preview text
                    Text(question.subject)
                        .font(.headline)
                        .lineLimit(1)

                    Text(question.question.prefix(80) + (question.question.count > 80 ? "..." : ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(RelativeDateTimeFormatter().localizedString(for: question.createdAt, relativeTo: Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // ✅ Thumbnail image (tappable to expand)
            if let imageUrl = question.questionImageUrl, !imageUrl.isEmpty {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        imageExpanded.toggle()
                    }
                }) {
                    QuestionImageView(imageUrl: imageUrl)
                        .frame(maxHeight: imageExpanded ? 200 : 80)  // ✅ Small thumbnail or expanded
                        .clipped()
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // ✅ Expand/Collapse Button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    Text(isExpanded ? "Hide Details" : "Show Full Question & Analysis")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())

            // ✅ Expanded content (folded by default)
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // ✅ Full question text
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("mistakeReview.questionLabel", comment: ""))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        // ✅ Render with subquestion support (NO "Subquestion" text)
                        SubquestionAwareTextView(
                            text: question.rawQuestionText,
                            fontSize: 16
                        )
                        .textSelection(.enabled)
                    }

                    // ✅ Error Analysis section (moved inside expanded content)
                    if question.hasErrorAnalysis {
                        errorAnalysisSection
                    } else if question.isAnalyzing {
                        analyzingSection
                    }

                    // Your incorrect answer
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("mistakeReview.yourAnswerLabel", comment: ""))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        // ✅ Use EnhancedMathText for math support in student answers
                        EnhancedMathText(
                            question.studentAnswer.isEmpty ?
                            NSLocalizedString("mistakeReview.noAnswer", comment: "") :
                            question.studentAnswer,
                            fontSize: 16
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // Correct answer
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("mistakeReview.correctAnswerLabel", comment: ""))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        // ✅ Use EnhancedMathText for math support in correct answers
                        EnhancedMathText(question.correctAnswer, fontSize: 16)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                            )
                    }

                    // Explanation (if available)
                    if !question.explanation.isEmpty && question.explanation != "No explanation provided" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Explanation")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            // ✅ Use EnhancedMathText for math support in explanations
                            EnhancedMathText(question.explanation, fontSize: 14)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.05))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(isSelectionMode && isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelectionMode && isSelected ? Color.blue : Color.gray.opacity(0.2),  // ✅ Lighter border
                    lineWidth: isSelectionMode && isSelected ? 2 : 1  // ✅ Thinner when not selected
                )
        )
    }

    // ✅ OPTIMIZATION: Error analysis section
    private var errorAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // NEW: Hierarchical breadcrumb
            if let baseBranch = question.baseBranch,
               let detailedBranch = question.detailedBranch,
               !baseBranch.isEmpty,
               !detailedBranch.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("Math")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(baseBranch)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(detailedBranch)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }

            // Error type badge (updated for 3 types)
            if let errorType = question.errorType {
                HStack(spacing: 8) {
                    Image(systemName: errorIcon(for: errorType))
                        .foregroundColor(errorColor(for: errorType))
                        .font(.caption)

                    Text(errorDisplayName(for: errorType))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(errorColor(for: errorType))

                    Spacer()

                    if let confidence = question.errorConfidence {
                        Text("\(Int(confidence * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(errorColor(for: errorType).opacity(0.1))
                .cornerRadius(6)
            }

            // NEW: Specific issue section
            if let specificIssue = question.specificIssue, !specificIssue.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("What Went Wrong")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    Text(specificIssue)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)
            }

            // Evidence section (existing)
            if let evidence = question.errorEvidence, !evidence.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Evidence")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    Text(evidence)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                .padding(10)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }

            // Learning suggestion (existing)
            if let suggestion = question.learningSuggestion, !suggestion.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("How to Improve")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    Text(suggestion)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                .padding(10)
                .background(Color.yellow.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }

    // ✅ OPTIMIZATION: Analyzing section
    private var analyzingSection: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Analyzing mistake with AI...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    // Helper functions for error type display (updated for 3 types)
    private func errorDisplayName(for errorType: String) -> String {
        switch errorType {
        case "execution_error": return "Execution Error"
        case "conceptual_gap": return "Concept Gap"
        case "needs_refinement": return "Needs Refinement"
        default: return "Unknown Error"
        }
    }

    private func errorIcon(for errorType: String) -> String {
        switch errorType {
        case "execution_error": return "exclamationmark.circle"
        case "conceptual_gap": return "brain.head.profile"
        case "needs_refinement": return "star.circle"
        default: return "questionmark"
        }
    }

    private func errorColor(for errorType: String) -> Color {
        switch errorType {
        case "execution_error": return .yellow
        case "conceptual_gap": return .red
        case "needs_refinement": return .blue
        default: return .secondary
        }
    }
}

// MARK: - Practice Questions View
struct PracticeQuestionsView: View {
    let questions: [QuestionGenerationService.GeneratedQuestion]
    let subject: String
    @Environment(\.dismiss) private var dismiss
    @State private var expandedQuestions: Set<UUID> = []
    @State private var currentAnswers: [UUID: String] = [:]
    @State private var gradedQuestions: [UUID: GradeResult] = [:] // UUID -> GradeResult
    @State private var showingGradedAlert = false
    @State private var lastGradedResult: (correct: Int, total: Int)?

    struct GradeResult {
        let isCorrect: Bool
        let correctAnswer: String
        let feedback: String
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)

                        Text("Targeted Practice")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("\(questions.count) questions based on your mistakes")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .onAppear {
                        #if DEBUG
                        print("🎯 ============================================")
                        print("🎯 PRACTICE QUESTIONS VIEW LOADED")
                        print("🎯 ============================================")
                        print("📊 Total Questions: \(questions.count)")
                        print("📚 Subject: \(subject)")
                        print("")
                        for (index, question) in questions.enumerated() {
                            print("📝 Question #\(index + 1):")
                            print("   Type: \(question.type.rawValue)")
                            print("   Difficulty: \(question.difficulty)")
                            print("   Question: \(question.question.prefix(80))...")
                            print("   Correct Answer: \(question.correctAnswer)")
                            if let options = question.options {
                                print("   Options: \(options)")
                            }
                            print("")
                        }
                        print("🎯 ============================================")
                        #endif
                    }

                    // Progress indicator
                    if !gradedQuestions.isEmpty {
                        HStack {
                            Text("Progress: \(gradedQuestions.count)/\(questions.count) answered")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(correctCount)/\(gradedQuestions.count) correct")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(correctCount == gradedQuestions.count ? .green : .orange)
                        }
                        .padding(.horizontal)
                    }

                    // Questions with type-based rendering
                    ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                        PracticeQuestionCard(
                            questionNumber: index + 1,
                            question: question,
                            subject: subject,
                            isExpanded: expandedQuestions.contains(question.id),
                            currentAnswer: currentAnswers[question.id] ?? "",
                            gradeResult: gradedQuestions[question.id],
                            onToggleExpand: {
                                toggleExpand(question.id)
                            },
                            onAnswerChange: { newAnswer in
                                currentAnswers[question.id] = newAnswer
                            },
                            onSubmitAnswer: {
                                Task {
                                    await submitAnswer(for: question)
                                }
                            }
                        )
                    }

                    // Final summary button
                    if gradedQuestions.count == questions.count {
                        Button(action: {
                            showingGradedAlert = true
                        }) {
                            HStack {
                                Image(systemName: "chart.bar.doc.horizontal")
                                    .font(.title3)
                                Text("View Final Summary")
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle(subject)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Practice Complete!", isPresented: $showingGradedAlert) {
                Button("Done", role: .cancel) {
                    dismiss()
                }
            } message: {
                if let result = lastGradedResult {
                    Text("You got \(result.correct) out of \(result.total) questions correct (\(Int(Double(result.correct)/Double(result.total) * 100))%)")
                }
            }
        }
    }

    private var correctCount: Int {
        gradedQuestions.values.filter { $0.isCorrect }.count
    }

    private func toggleExpand(_ questionId: UUID) {
        if expandedQuestions.contains(questionId) {
            expandedQuestions.remove(questionId)
        } else {
            expandedQuestions.insert(questionId)
        }
    }

    private func submitAnswer(for question: QuestionGenerationService.GeneratedQuestion) async {
        guard let userAnswer = currentAnswers[question.id], !userAnswer.isEmpty else {
            return
        }

        #if DEBUG
        print("📤 ============================================")
        print("📤 SUBMITTING ANSWER FOR GRADING")
        print("📤 ============================================")
        print("🔹 Question ID: \(question.id)")
        print("🔹 Question Type: \(question.type.rawValue)")
        print("🔹 Question Text: \(question.question.prefix(100))...")
        print("🔹 Student Answer: \(userAnswer)")
        print("🔹 Subject: \(subject)")
        print("🔹 Using Deep Reasoning: true")
        print("🔹 Model Provider: gemini")
        print("")
        print("⏳ Sending request to NetworkService.gradeSingleQuestion()...")
        #endif

        // Use backend API for grading (supports semantic understanding, partial credit, etc.)
        do {
            let response = try await NetworkService.shared.gradeSingleQuestion(
                questionText: question.question,
                studentAnswer: userAnswer,
                subject: subject,
                questionType: question.type.rawValue,
                contextImageBase64: nil,
                parentQuestionContent: nil,
                useDeepReasoning: true,  // Pro Mode grading
                modelProvider: "gemini"
            )

            #if DEBUG
            print("")
            print("✅ RECEIVED GRADING RESPONSE")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            if let grade = response.grade {
                print("📊 Grade Result:")
                print("   ✓ Is Correct: \(grade.isCorrect ? "✅ YES" : "❌ NO")")
                print("   ✓ Correct Answer: \(grade.correctAnswer ?? question.correctAnswer)")
                print("   ✓ Feedback Length: \(grade.feedback.count) characters")
                print("")
                print("📝 AI Feedback:")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print(grade.feedback)
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            } else if let error = response.error {
                print("❌ ERROR in response: \(error)")
            } else {
                print("⚠️ No grade data in response")
            }
            print("📤 ============================================")
            #endif

            if let grade = response.grade {
                await MainActor.run {
                    gradedQuestions[question.id] = GradeResult(
                        isCorrect: grade.isCorrect,
                        correctAnswer: grade.correctAnswer ?? question.correctAnswer,
                        feedback: grade.feedback
                    )

                    #if DEBUG
                    print("💾 Stored grade result for question \(question.id)")
                    print("📈 Progress: \(gradedQuestions.count)/\(questions.count) answered")
                    #endif

                    // Update final result if all questions answered
                    if gradedQuestions.count == questions.count {
                        let correct = gradedQuestions.values.filter { $0.isCorrect }.count
                        lastGradedResult = (correct: correct, total: questions.count)

                        #if DEBUG
                        print("🎊 ALL QUESTIONS COMPLETED!")
                        print("📊 Final Score: \(correct)/\(questions.count) (\(Int(Double(correct)/Double(questions.count) * 100))%)")
                        #endif
                    }

                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(grade.isCorrect ? .success : .error)
                }
            }
        } catch {
            #if DEBUG
            print("❌ ============================================")
            print("❌ GRADING FAILED")
            print("❌ ============================================")
            print("Error: \(error.localizedDescription)")
            print("Full error: \(error)")
            print("❌ ============================================")
            #endif
            print("❌ Failed to grade answer: \(error.localizedDescription)")
            // Could show error alert here
        }
    }
}

// MARK: - Practice Question Card
struct PracticeQuestionCard: View {
    let questionNumber: Int
    let question: QuestionGenerationService.GeneratedQuestion
    let subject: String
    let isExpanded: Bool
    let currentAnswer: String
    let gradeResult: PracticeQuestionsView.GradeResult?
    let onToggleExpand: () -> Void
    let onAnswerChange: (String) -> Void
    let onSubmitAnswer: () -> Void

    @State private var answerText: String = ""
    @State private var selectedOption: String = ""
    @State private var isSubmitting: Bool = false

    private var isGraded: Bool {
        gradeResult != nil
    }

    private var isCorrect: Bool {
        gradeResult?.isCorrect ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question Header
            Button(action: onToggleExpand) {
                HStack {
                    // Question number badge
                    ZStack {
                        Circle()
                            .fill(isGraded ? (isCorrect ? Color.green : Color.red) : Color.blue)
                            .frame(width: 36, height: 36)

                        if isGraded {
                            Image(systemName: isCorrect ? "checkmark" : "xmark")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .bold))
                        } else {
                            Text("\(questionNumber)")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .bold))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Question \(questionNumber)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            // Question type badge
                            Image(systemName: question.type.icon)
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text(question.type.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // Difficulty badge
                            Text(question.difficulty)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                Divider()

                // Question text
                Text(question.question)
                    .font(.body)
                    .padding(.vertical, 4)
                    .onAppear {
                        #if DEBUG
                        print("🔍 ============================================")
                        print("🔍 RENDERING QUESTION CARD #\(questionNumber)")
                        print("🔍 ============================================")
                        print("📝 Type: \(question.type.rawValue)")
                        print("📝 Question: \(question.question)")
                        if let options = question.options {
                            print("📝 Options Available: \(options.count)")
                            for (idx, option) in options.enumerated() {
                                print("   [\(idx + 1)] \(option)")
                            }
                        }
                        print("📝 Expected Answer: \(question.correctAnswer)")
                        print("📝 Is Graded: \(isGraded)")
                        if isGraded {
                            print("📝 Result: \(isCorrect ? "✅ CORRECT" : "❌ INCORRECT")")
                        }
                        print("🔍 ============================================")
                        #endif
                    }

                // Answer input
                if !isGraded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Answer:")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        // Type-specific input
                        switch question.type {
                        case .multipleChoice:
                            if let options = question.options {
                                #if DEBUG
                                let _ = print("🎨 Rendering MULTIPLE CHOICE input with \(options.count) options")
                                #endif
                                PracticeMCInput(options: options, selectedOption: $selectedOption)
                                    .onChange(of: selectedOption) { _, newValue in
                                        #if DEBUG
                                        print("✏️ User selected MC option: \(newValue)")
                                        #endif
                                        onAnswerChange(newValue)
                                    }
                            }

                        case .trueFalse:
                            #if DEBUG
                            let _ = print("🎨 Rendering TRUE/FALSE input")
                            #endif
                            PracticeTFInput(selectedOption: $selectedOption)
                                .onChange(of: selectedOption) { _, newValue in
                                    #if DEBUG
                                    print("✏️ User selected T/F option: \(newValue)")
                                    #endif
                                    onAnswerChange(newValue)
                                }

                        default:
                            #if DEBUG
                            let _ = print("🎨 Rendering TEXT EDITOR for type: \(question.type.rawValue)")
                            #endif
                            TextEditor(text: $answerText)
                                .frame(height: 80)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .onChange(of: answerText) { _, newValue in
                                    #if DEBUG
                                    print("✏️ User typed text: \(newValue.prefix(50))...")
                                    #endif
                                    onAnswerChange(newValue)
                                }
                        }

                        Button(action: {
                            #if DEBUG
                            print("🔘 Submit button pressed for question #\(questionNumber)")
                            print("   Answer: \(currentAnswer)")
                            #endif
                            isSubmitting = true
                            onSubmitAnswer()
                        }) {
                            HStack {
                                if isSubmitting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark.circle")
                                    Text("Submit Answer")
                                }
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isSubmitDisabled ? Color.gray : Color.blue)
                            .cornerRadius(8)
                        }
                        .disabled(isSubmitDisabled)
                    }
                } else {
                    // Show graded result
                    VStack(alignment: .leading, spacing: 12) {
                        // User's answer
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 16))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your Answer")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(currentAnswer)
                                    .font(.body)
                            }
                        }
                        .padding(12)
                        .background(isCorrect ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        .cornerRadius(8)

                        // Correct answer (if incorrect)
                        if !isCorrect, let result = gradeResult {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Correct Answer")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    Text(result.correctAnswer)
                                        .font(.body)
                                }
                            }
                            .padding(12)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }

                        // Explanation
                        if let result = gradeResult {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "bubble.left.fill")
                                    .foregroundColor(.purple)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Explanation")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    Text(result.feedback)
                                        .font(.body)
                                }
                            }
                            .padding(12)
                            .background(Color.purple.opacity(0.05))
                            .cornerRadius(8)
                        }
                    }
                    .onAppear {
                        #if DEBUG
                        print("📊 ============================================")
                        print("📊 DISPLAYING GRADED RESULT #\(questionNumber)")
                        print("📊 ============================================")
                        print("🎯 Result: \(isCorrect ? "✅ CORRECT" : "❌ INCORRECT")")
                        print("📝 Student Answer: \(currentAnswer)")
                        if let result = gradeResult {
                            print("💡 Correct Answer: \(result.correctAnswer)")
                            print("📚 Feedback: \(result.feedback)")
                        }
                        print("📊 ============================================")
                        #endif
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2)
        .onAppear {
            answerText = currentAnswer
            selectedOption = currentAnswer
        }
        .onChange(of: gradeResult) { _, _ in
            // Reset submitting state when grade result arrives
            isSubmitting = false
        }
    }

    private var isSubmitDisabled: Bool {
        if isSubmitting {
            return true
        }

        switch question.type {
        case .multipleChoice, .trueFalse:
            return selectedOption.isEmpty
        default:
            return answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

// MARK: - Practice Input Components

/// Multiple Choice Input for Practice Questions
struct PracticeMCInput: View {
    let options: [String]
    @Binding var selectedOption: String

    var body: some View {
        VStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    #if DEBUG
                    print("🎯 MC Option Selected: \(option)")
                    #endif
                    selectedOption = option
                } label: {
                    HStack {
                        Image(systemName: selectedOption == option ?
                              "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedOption == option ? .blue : .gray)
                            .font(.title3)
                        Text(option)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding()
                    .background(selectedOption == option ?
                                Color.blue.opacity(0.1) : Color(.systemGray6))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .onAppear {
            #if DEBUG
            print("🎨 PracticeMCInput appeared with \(options.count) options:")
            for (idx, opt) in options.enumerated() {
                print("   [\(idx + 1)] \(opt)")
            }
            #endif
        }
    }
}

/// True/False Input for Practice Questions
struct PracticeTFInput: View {
    @Binding var selectedOption: String

    var body: some View {
        HStack(spacing: 16) {
            Button {
                #if DEBUG
                print("🎯 T/F Option Selected: True")
                #endif
                selectedOption = "True"
            } label: {
                HStack {
                    Image(systemName: selectedOption == "True" ?
                          "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedOption == "True" ? .green : .gray)
                        .font(.title3)
                    Text("True")
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(selectedOption == "True" ?
                            Color.green.opacity(0.2) : Color(.systemGray6))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())

            Button {
                #if DEBUG
                print("🎯 T/F Option Selected: False")
                #endif
                selectedOption = "False"
            } label: {
                HStack {
                    Image(systemName: selectedOption == "False" ?
                          "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedOption == "False" ? .red : .gray)
                        .font(.title3)
                    Text("False")
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(selectedOption == "False" ?
                            Color.red.opacity(0.2) : Color(.systemGray6))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .onAppear {
            #if DEBUG
            print("🎨 PracticeTFInput appeared")
            #endif
        }
    }
}


// MARK: - Subquestion-Aware Text Renderer

/// Shared component for rendering questions with subquestion support
/// Splits text by "\n\n" and highlights subquestion parts with indentation
struct SubquestionAwareTextView: View {
    let text: String
    let fontSize: CGFloat

    var body: some View {
        #if DEBUG
        let _ = print("📝 [SubquestionAware] Body evaluating")
        let _ = print("   Text length: \(text.count) chars")
        let _ = print("   Font size: \(fontSize)")
        #endif

        VStack(alignment: .leading, spacing: 12) {
            // Split by double newline to separate parent and subquestion content
            let parts = text.components(separatedBy: "\n\n")

            #if DEBUG
            let _ = print("   Split into \(parts.count) parts")
            #endif

            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    #if DEBUG
                    let _ = {
                        let isSubquestion = isSubquestionFormat(part)  // ✅ Removed "subquestion" text check
                        print("")
                        print("   📋 Part \(index + 1):")
                        print("      Content: \(part.prefix(50))...")
                        print("      Matches regex pattern: \(isSubquestionFormat(part))")
                        print("      → Rendering as: \(isSubquestion ? "✅ SUBQUESTION (with arrow)" : "⚪ PARENT (regular text)")")
                        return ()
                    }()
                    #endif

                    VStack(alignment: .leading, spacing: 8) {
                        // ✅ Highlight subquestion part if it starts with a letter/number + ")" (NO "Subquestion" text check)
                        if isSubquestionFormat(part) {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                    .padding(.top, 4)
                                EnhancedMathText(part, fontSize: fontSize)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                        } else {
                            // Parent content or regular text
                            EnhancedMathText(part, fontSize: fontSize - 1)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Check if text matches common subquestion formats like "a)", "1)", "(a)", etc.
    private func isSubquestionFormat(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for patterns: "a)", "1)", "(a)", "(1)", "Part a:", "Part 1:"
        let subquestionPatterns: [(pattern: String, description: String)] = [
            ("^[a-z]\\)", "a), b), c)"),
            ("^\\d+\\)", "1), 2), 3)"),
            ("^\\([a-z]\\)", "(a), (b), (c)"),
            ("^\\(\\d+\\)", "(1), (2), (3)"),
            ("^Part [a-z]:", "Part a:, Part b:"),
            ("^Part \\d+:", "Part 1:, Part 2:"),
        ]

        for (pattern, description) in subquestionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                if regex.firstMatch(in: trimmed, range: range) != nil {
                    #if DEBUG
                    print("      🎯 Matched pattern: \(description)")
                    #endif
                    return true
                }
            }
        }

        return false
    }
}

// MARK: - Practice Configuration Sheet
struct PracticeConfigurationSheet: View {
    let mistakeCount: Int
    let onGenerate: (QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty, Set<QuestionGenerationService.GeneratedQuestion.QuestionType>, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDifficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty = .intermediate
    @State private var selectedQuestionTypes: Set<QuestionGenerationService.GeneratedQuestion.QuestionType> = [.any]
    @State private var questionCount: Int = 5

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Configure Practice Questions")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Based on \(mistakeCount) selected mistake\(mistakeCount == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    // Question Types Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Question Types")
                            .font(.headline)
                            .padding(.horizontal)

                        Text("Select which types of questions to generate:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach([QuestionGenerationService.GeneratedQuestion.QuestionType.any] + QuestionGenerationService.GeneratedQuestion.QuestionType.allCases.filter { $0 != .any }, id: \.self) { type in
                                    QuestionTypeChip(
                                        type: type,
                                        isSelected: selectedQuestionTypes.contains(type),
                                        onTap: {
                                            toggleQuestionType(type)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Difficulty Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Difficulty Level")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 10) {
                            ForEach(QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty.allCases, id: \.self) { difficulty in
                                DifficultyOption(
                                    difficulty: difficulty,
                                    isSelected: selectedDifficulty == difficulty,
                                    onTap: {
                                        selectedDifficulty = difficulty
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Question Count Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Number of Questions")
                                .font(.headline)
                            Spacer()
                            Text("\(questionCount)")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal)

                        Slider(value: Binding(
                            get: { Double(questionCount) },
                            set: { questionCount = Int($0) }
                        ), in: 1...10, step: 1)
                            .tint(.blue)
                            .padding(.horizontal)

                        HStack {
                            Text("1 question")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("10 questions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Generate Button
                    Button(action: {
                        // Call onGenerate with selected parameters
                        let typesToUse = selectedQuestionTypes.isEmpty ? [.any] : selectedQuestionTypes
                        onGenerate(selectedDifficulty, typesToUse, questionCount)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .font(.title3)
                            Text("Generate \(questionCount) Questions")
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .padding(.vertical)
            }
            .navigationTitle("Practice Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggleQuestionType(_ type: QuestionGenerationService.GeneratedQuestion.QuestionType) {
        if type == .any {
            // If "Any" is selected, clear all other selections
            selectedQuestionTypes = [.any]
        } else {
            // Remove "Any" if specific type is selected
            selectedQuestionTypes.remove(.any)

            // Toggle the specific type
            if selectedQuestionTypes.contains(type) {
                selectedQuestionTypes.remove(type)
                // If no types selected, default to "Any"
                if selectedQuestionTypes.isEmpty {
                    selectedQuestionTypes = [.any]
                }
            } else {
                selectedQuestionTypes.insert(type)
            }
        }
    }
}

// MARK: - Question Type Chip
struct QuestionTypeChip: View {
    let type: QuestionGenerationService.GeneratedQuestion.QuestionType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.caption)
                Text(type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Difficulty Option
struct DifficultyOption: View {
    let difficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(difficulty.displayName)
                        .font(.body)
                        .fontWeight(.semibold)

                    Text(difficultyDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(difficulty.color)
                        .font(.title3)
                }
            }
            .padding()
            .background(isSelected ? difficulty.color.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? difficulty.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var difficultyDescription: String {
        switch difficulty {
        case .beginner:
            return "Foundation-building questions for new concepts"
        case .intermediate:
            return "Balanced questions for practice and review"
        case .advanced:
            return "Challenging questions to push understanding"
        case .adaptive:
            return "AI-adjusted difficulty based on your mistakes"
        }
    }
}


#Preview {
    MistakeReviewView()
}