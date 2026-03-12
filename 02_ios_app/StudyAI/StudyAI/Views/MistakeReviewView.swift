//
//  MistakeReviewView.swift
//  StudyAI
//
//  Created by Claude Code on 9/20/25.
//

import SwiftUI
import Lottie
import PDFKit  // ✅ For PDF export functionality
import AVFoundation  // ✅ For iOS system unlock sound

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

// MARK: - Active Filter
enum MistakeActiveFilter: String, CaseIterable {
    case active = "Active"
    case all = "All"
    case goodAt = "GoodAt"

    var localizedName: String {
        switch self {
        case .active: return NSLocalizedString("mistakeReview.filter.active", comment: "")
        case .all: return NSLocalizedString("mistakeReview.filter.allFilter", comment: "")
        case .goodAt: return NSLocalizedString("mistakeReview.filter.goodAt", comment: "Good At")
        }
    }
}

// MARK: - Main View
struct MistakeReviewView: View {
    @StateObject private var mistakeService = MistakeReviewService()
    @StateObject private var themeManager = ThemeManager.shared
    @State private var selectedSubject: String?

    init(initialSubject: String? = nil) {
        if let subject = initialSubject {
            _selectedSubject = State(initialValue: subject)
        }
    }

    // NEW: Dual slider filters
    @State private var selectedSeverity: SeverityLevel = .all
    @State private var selectedTimeRange: FilterTimeRange = .allTime

    // NEW: Hierarchical filtering state (multi-select)
    @State private var selectedDetailedBranches: Set<String> = []

    // Active / All toggle
    @State private var activeFilter: MistakeActiveFilter = .active

    @State private var showingMistakeList = false
    @State private var showingInstructions = false
    @ObservedObject private var appState = AppState.shared
    @State private var isCategorizingMistakes = false
    @State private var unclassifiedCount: Int = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
                                .foregroundColor(DesignTokens.Colors.success)

                            Text(NSLocalizedString("mistakeReview.noMistakesFound", comment: ""))
                                .font(.headline)
                                .foregroundColor(DesignTokens.Colors.success)

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

                    // SECTION 1b: Active / All toggle
                    Picker("", selection: $activeFilter) {
                        ForEach(MistakeActiveFilter.allCases, id: \.self) { filter in
                            Text(filter.localizedName).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: activeFilter) { _, newFilter in
                        if newFilter == .goodAt {
                            selectedDetailedBranches.removeAll()
                        }
                    }

                    // SECTION 2: Dual Slider Filters (Severity + Time) — hidden for Good At tab
                    if selectedSubject != nil && activeFilter != .goodAt {
                        DualSliderFilters(
                            selectedSeverity: $selectedSeverity,
                            selectedTimeRange: $selectedTimeRange
                        )
                        .padding(.horizontal)
                    }

                    // SECTION 3: Taxonomy Filter OR Good At View
                    if let subject = selectedSubject {
                        if activeFilter == .goodAt {
                            let goodAtData = mistakeService.getGoodAtBranches(
                                for: subject,
                                timeRange: selectedTimeRange.mistakeTimeRange
                            )
                            GoodAtTaxonomyView(goodAtData: goodAtData)
                                .padding(.horizontal)
                        } else {
                            let taxonomyData = mistakeService.getBaseBranches(
                                for: subject,
                                timeRange: selectedTimeRange.mistakeTimeRange,
                                activeFilter: activeFilter,
                                severity: selectedSeverity
                            )
                            TaxonomyFilterView(
                                subject: subject,
                                taxonomyData: taxonomyData,
                                selectedDetailedBranches: $selectedDetailedBranches
                            )
                            .padding(.horizontal)
                        }
                    }

                    // SECTION 4: Action Buttons — hidden for Good At tab
                    if selectedSubject != nil && !mistakeService.subjectsWithMistakes.isEmpty && activeFilter != .goodAt {
                        let mistakeCount = calculateFilteredMistakeCount()

                        HStack(spacing: 12) {
                            // Primary: Start Review
                            Button(action: {
                                print("▶️ [MistakeReviewView] 'Start Review' tapped — opening MistakeQuestionListView sheet. selectedTab=\(appState.selectedTab), shouldDismissPracticeStack=\(appState.shouldDismissPracticeStack)")
                                showingMistakeList = true
                            }) {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                        .font(.title3)

                                    Text(String(format: NSLocalizedString("mistakeReview.startReview", comment: ""), mistakeCount))
                                        .font(.body)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(mistakeCount > 0 ? themeManager.accentColor : Color.gray)
                                .cornerRadius(12)
                            }
                            .disabled(mistakeCount == 0)
                            .buttonStyle(PlainButtonStyle())

                            // Secondary: Categorize Mistakes (only shown when unclassified > 0)
                            if unclassifiedCount > 0 {
                                Button(action: {
                                    guard let subject = selectedSubject else { return }
                                    isCategorizingMistakes = true
                                    Task {
                                        let questions = getUnclassifiedQuestions(subject: subject)
                                        await ErrorAnalysisQueueService.shared.categorizeQuestions(questions)
                                        // Refresh subjects + taxonomy so uncategorized bucket shrinks
                                        await mistakeService.fetchSubjectsWithMistakes(timeRange: selectedTimeRange.mistakeTimeRange)
                                        refreshUnclassifiedCount()
                                        isCategorizingMistakes = false
                                    }
                                }) {
                                    Group {
                                        if isCategorizingMistakes {
                                            HStack(spacing: 6) {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(0.8)
                                                Text(NSLocalizedString("mistakeReview.categorizing", comment: "Categorizing…"))
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                            }
                                        } else {
                                            HStack(spacing: 6) {
                                                Image(systemName: "sparkles")
                                                    .font(.subheadline)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(NSLocalizedString("mistakeReview.categorizeMistakes", comment: "Categorize"))
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                    Text("\(unclassifiedCount) \(NSLocalizedString("mistakeReview.uncategorized", comment: "unclassified"))")
                                                        .font(.caption2)
                                                        .opacity(0.85)
                                                }
                                            }
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .frame(width: 130, height: 56)
                                    .background(isCategorizingMistakes ? Color.orange.opacity(0.7) : Color.orange)
                                    .cornerRadius(12)
                                }
                                .disabled(isCategorizingMistakes)
                                .buttonStyle(PlainButtonStyle())
                                .animation(.easeInOut(duration: 0.2), value: isCategorizingMistakes)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .navigationTitle(NSLocalizedString("mistakeReview.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingInstructions = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.body)
                    }
                }
            }
            .alert(NSLocalizedString("mistakeReview.instructions.title", comment: ""), isPresented: $showingInstructions) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("mistakeReview.instructions.message", comment: ""))
            }
            .task {
                await mistakeService.fetchSubjectsWithMistakes(timeRange: selectedTimeRange.mistakeTimeRange)

                // ✅ Auto-select first subject if available and none selected
                if selectedSubject == nil, let firstSubject = mistakeService.subjectsWithMistakes.first {
                    selectedSubject = firstSubject.subject
                }
                refreshUnclassifiedCount()
            }
            .onChange(of: selectedTimeRange) { _, newRange in
                Task {
                    await mistakeService.fetchSubjectsWithMistakes(timeRange: newRange.mistakeTimeRange)
                    refreshUnclassifiedCount()
                }
            }
            .onChange(of: selectedSubject) { _, _ in
                refreshUnclassifiedCount()
            }
            .sheet(isPresented: $showingMistakeList) {
                if let subject = selectedSubject {
                    MistakeQuestionListView(
                        subject: subject,
                        selectedDetailedBranches: selectedDetailedBranches,
                        selectedSeverity: selectedSeverity,
                        timeRange: selectedTimeRange.mistakeTimeRange,
                        activeFilter: activeFilter
                    )
                }
            }
            .onChange(of: appState.shouldDismissPracticeStack) { _, shouldDismiss in
                if shouldDismiss {
                    print("🔴 [MistakeReviewView] shouldDismissPracticeStack fired → dismissing showingMistakeList. selectedTab=\(appState.selectedTab)")
                    showingMistakeList = false
                    appState.shouldDismissPracticeStack = false
                }
            }
    }

    // MARK: - Helper Methods

    /// Recompute unclassified count from local storage for the current subject.
    /// Called on load, subject change, time range change, and after categorization.
    private func refreshUnclassifiedCount() {
        guard let subject = selectedSubject else {
            unclassifiedCount = 0
            return
        }
        unclassifiedCount = getUnclassifiedQuestions(subject: subject).count
    }

    /// Return all mistake questions for a subject that have no baseBranch classification.
    private func getUnclassifiedQuestions(subject: String) -> [[String: Any]] {
        let localStorage = currentUserQuestionStorage()
        let allMistakes = localStorage.getMistakeQuestions(subject: subject)
        return allMistakes.filter { q in
            let base = q["baseBranch"] as? String ?? ""
            return base.isEmpty
        }
    }

    /// Calculate filtered mistake count based on hierarchical filters and severity
    private func calculateFilteredMistakeCount() -> Int {
        guard let selectedSubject = selectedSubject else { return 0 }

        let localStorage = currentUserQuestionStorage()
        var allMistakes = localStorage.getMistakeQuestions(subject: selectedSubject)

        // Filter by time range
        allMistakes = mistakeService.filterByTimeRange(allMistakes, timeRange: selectedTimeRange.mistakeTimeRange)

        // Filter by active weakness
        if activeFilter == .active {
            let activeWeaknesses = ShortTermStatusService.shared.status.activeWeaknesses
            allMistakes = allMistakes.filter { mistake in
                guard let key = mistake["weaknessKey"] as? String, !key.isEmpty else {
                    return true // no key → include (safe fallback)
                }
                return (activeWeaknesses[key]?.value ?? 0) > 0
            }
        }

        // Filter by severity (error type)
        allMistakes = allMistakes.filter { mistake in
            let errorType = mistake["errorType"] as? String
            return selectedSeverity.matches(errorType: errorType)
        }

        // Filter by detailed branches (multi-select)
        if !selectedDetailedBranches.isEmpty {
            allMistakes = allMistakes.filter { mistake in
                let branch = (mistake["detailedBranch"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                if let detailedBranch = branch {
                    return selectedDetailedBranches.contains(detailedBranch)
                } else {
                    return selectedDetailedBranches.contains(MistakeReviewService.uncategorizedKey)
                }
            }
        }

        return allMistakes.count
    }

}

// MARK: - Mistake Question List View

/// Thin Identifiable wrapper so [WeaknessPracticeQuestion] can drive .sheet(item:).
private struct DoThemAgainItem: Identifiable {
    let id = UUID()
    let questions: [WeaknessPracticeQuestion]
}

struct MistakeQuestionListView: View {
    let subject: String
    let selectedDetailedBranches: Set<String>
    let selectedSeverity: SeverityLevel
    let timeRange: MistakeTimeRange
    let activeFilter: MistakeActiveFilter

    @StateObject private var mistakeService = MistakeReviewService()
    @ObservedObject private var questionGenerationService = QuestionGenerationService.shared
    @ObservedObject private var profileService = ProfileService.shared
    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var sessionManager = PracticeSessionManager.shared
    @ObservedObject private var appState = AppState.shared
    @State private var selectedQuestions: Set<String> = []
    @State private var isSelectionMode = false
    @State private var showingPDFGenerator = false
    @State private var isGeneratingPractice = false
    @State private var showingConfigurationSheet = false
    @State private var generationError: String? = nil
    /// Non-nil → shows QuestionSheetView as a sheet (generated, resumed, or "do them again")
    @State private var activePracticeSession: PracticeSession? = nil
    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed Properties

    /// The most recent incomplete mistake-based session for this subject, if any.
    private var incompleteSession: PracticeSession? {
        sessionManager.incompleteSessions.first {
            ($0.generationType == "Mistake-Based Practice" || $0.generationType == "Mistake-Based") && $0.subject == subject
        }
    }

    /// Filter mistakes by hierarchical filters, severity, and active status
    private var filteredMistakes: [MistakeQuestion] {
        var filtered = mistakeService.mistakes

        // Filter by active weakness
        if activeFilter == .active {
            let activeWeaknesses = ShortTermStatusService.shared.status.activeWeaknesses
            filtered = filtered.filter { mistake in
                guard let key = mistake.weaknessKey, !key.isEmpty else {
                    return true // no key → include (safe fallback)
                }
                return (activeWeaknesses[key]?.value ?? 0) > 0
            }
        }

        // Filter by severity (error type)
        filtered = filtered.filter { mistake in
            selectedSeverity.matches(errorType: mistake.errorType)
        }

        // Filter by detailed branches (multi-select)
        if !selectedDetailedBranches.isEmpty {
            filtered = filtered.filter { mistake in
                let branch = (mistake.detailedBranch ?? "").isEmpty ? nil : mistake.detailedBranch
                if let detailedBranch = branch {
                    return selectedDetailedBranches.contains(detailedBranch)
                } else {
                    // question has no detailedBranch → include only if "Uncategorized" chip is selected
                    return selectedDetailedBranches.contains(MistakeReviewService.uncategorizedKey)
                }
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
                    // Resume button — shown when an incomplete session exists for this subject (top)
                    if !filteredMistakes.isEmpty && !isSelectionMode, let session = incompleteSession {
                        Button(action: {
                            activePracticeSession = session
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.body)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("mistakeReview.resumePractice", comment: ""))
                                        .font(.body)
                                        .fontWeight(.semibold)

                                    Text(String(format: NSLocalizedString("mistakeReview.questionsLeftDone", comment: ""), session.remainingQuestions, Int(session.progressPercentage * 100)))
                                        .font(.caption)
                                        .opacity(0.85)
                                }

                                Spacer()

                                // Mini progress bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.3)).frame(height: 4)
                                        Capsule().fill(Color.white)
                                            .frame(width: geo.size.width * session.progressPercentage, height: 4)
                                    }
                                }
                                .frame(width: 60, height: 4)

                                Button(action: {
                                    sessionManager.deleteSession(id: session.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal)
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
                                .foregroundColor(themeManager.accentColor)
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
                                .foregroundColor(DesignTokens.Colors.error)
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
                                .foregroundColor(DesignTokens.Colors.success)

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

                //✅ Bottom action buttons
                if !filteredMistakes.isEmpty && !isSelectionMode {
                    Button(action: { isSelectionMode = true }) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .font(.title3)
                            Text(NSLocalizedString("mistakeReview.letsPractise", comment: ""))
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(DesignTokens.Colors.success)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal)
                    .padding(.bottom)
                }

                //✅ Generate Practice Button (ENHANCED with configuration UI)
                if isSelectionMode && !selectedQuestions.isEmpty {
                    VStack(spacing: 10) {
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

                                    Text(String(format: NSLocalizedString("mistakeReview.generatePractice", comment: ""), selectedQuestions.count))
                                        .font(.body)
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(isGeneratingPractice ? Color.gray : themeManager.accentColor)
                            .cornerRadius(12)
                        }
                        .disabled(isGeneratingPractice)
                        .buttonStyle(PlainButtonStyle())

                        Button(action: { doThemAgain() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.title3)
                                Text(String(format: NSLocalizedString("mistakeReview.doThemAgain", comment: ""), selectedQuestions.count))
                                    .font(.body)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(themeManager.accentColor)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(themeManager.accentColor.opacity(0.12))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(themeManager.accentColor.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle(String.localizedStringWithFormat(NSLocalizedString("mistakeReview.subjectMistakes", comment: ""), PracticeSessionManager.localizeSubject(subject)))
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
            .sheet(isPresented: $showingConfigurationSheet) {
                // ✅ NEW: Show configuration sheet before generating
                PracticeConfigurationSheet(
                    mistakeCount: selectedQuestions.count,
                    selectedMistakes: filteredMistakes.filter { selectedQuestions.contains($0.id) },
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
            // Error alert for practice generation
            .alert(NSLocalizedString("mistakeReview.generationFailed", comment: ""), isPresented: Binding(get: { generationError != nil }, set: { _ in generationError = nil })) {
                Button(NSLocalizedString("common.retry", comment: "")) {
                    generationError = nil
                    showingConfigurationSheet = true
                }
                Button("Cancel", role: .cancel) {
                    generationError = nil
                }
            } message: {
                Text(generationError ?? "An unknown error occurred")
            }
            .sheet(item: $activePracticeSession) { session in
                QuestionSheetView(session: session)
            }
            .onChange(of: appState.shouldDismissPracticeStack) { _, shouldDismiss in
                if shouldDismiss {
                    activePracticeSession = nil
                }
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
                    Text(NSLocalizedString("mistakeReview.generatingQuestions", comment: ""))
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

    /// Re-attempt the selected original mistake questions using the existing WeaknessPracticeView.
    /// Loads full question data (including questionType/options) from local storage by ID.
    private func doThemAgain() {
        let selected = filteredMistakes.filter { selectedQuestions.contains($0.id) }
        guard !selected.isEmpty else { return }

        let localStorage = currentUserQuestionStorage()
        let allStoredQuestions = localStorage.getLocalQuestions()
        let idSet = Set(selected.map { $0.id })

        // Build a lookup dictionary for O(1) access per item
        var storedById: [String: [String: Any]] = [:]
        for storedQ in allStoredQuestions {
            guard let qId = storedQ["id"] as? String, idSet.contains(qId) else { continue }
            storedById[qId] = storedQ
        }

        // Preserve selection order by iterating the ordered selected array
        var result: [WeaknessPracticeQuestion] = []
        for mistake in selected {
            guard let storedQ = storedById[mistake.id],
                  let questionText = storedQ["questionText"] as? String,
                  let correctAnswer = storedQ["answerText"] as? String else {
                // Fallback: build from MistakeQuestion fields (no questionType/options)
                let pq = WeaknessPracticeQuestion(
                    id: UUID(uuidString: mistake.id) ?? UUID(),
                    questionText: mistake.question,
                    questionType: "short_answer",
                    options: nil,
                    correctAnswer: mistake.correctAnswer,
                    isOriginalMistake: true,
                    originalQuestionId: mistake.id,
                    studentAnswer: mistake.studentAnswer,
                    questionImageUrl: mistake.questionImageUrl,
                    rawQuestionText: mistake.rawQuestionText.isEmpty ? nil : mistake.rawQuestionText,
                    weaknessKey: mistake.weaknessKey
                )
                result.append(pq)
                continue
            }

            let questionType = storedQ["questionType"] as? String ?? "short_answer"
            let options = storedQ["options"] as? [String]
            let studentAnswer = storedQ["studentAnswer"] as? String
            let questionImageUrl = storedQ["questionImageUrl"] as? String
            let rawText = storedQ["rawQuestionText"] as? String
            let weaknessKey = storedQ["weaknessKey"] as? String ?? mistake.weaknessKey

            let pq = WeaknessPracticeQuestion(
                id: UUID(uuidString: mistake.id) ?? UUID(),
                questionText: questionText,
                questionType: questionType,
                options: options,
                correctAnswer: correctAnswer,
                isOriginalMistake: true,
                originalQuestionId: mistake.id,
                studentAnswer: studentAnswer,
                questionImageUrl: questionImageUrl,
                rawQuestionText: (rawText?.isEmpty == false) ? rawText : questionText,
                weaknessKey: weaknessKey
            )
            result.append(pq)
        }

        // Convert WeaknessPracticeQuestions to GeneratedQuestions and create a PracticeSession
        let generated = result.map { PracticeSessionManager.convert($0, subject: subject) }
        let session = PracticeSession(
            id: UUID().uuidString,
            questions: generated,
            generationType: "Mistake-Based Practice",
            subject: subject,
            difficulty: "intermediate",
            questionType: "any",
            createdDate: Date(),
            lastAccessedDate: Date(),
            completedQuestionIds: [],
            answers: [:]
        )
        PracticeSessionManager.shared.saveSession(session)
        activePracticeSession = session
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

            // ✅ VALIDATION #2: Validate subject — allow standard enum values and AI-generated "Others: X" subjects
            let validSubjects = Subject.allCases.map { $0.rawValue }
            guard validSubjects.contains(subject) || subject.hasPrefix("Others:") else {
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

            let result = await QuestionGenerationService.shared.generateQuestionsV2(
                subject: subject,
                mode: 2,
                config: config,
                userProfile: userProfile,
                mistakesData: mistakesData
            )

            switch result {
            case .success(let questions):
                await MainActor.run {
                    // Session already saved by QuestionGenerationService; retrieve it for QuestionSheetView
                    if let sid = QuestionGenerationService.shared.currentSessionId,
                       let session = PracticeSessionManager.shared.getSession(id: sid) {
                        activePracticeSession = session
                    }
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

    private static let relativeDateFormatter = RelativeDateTimeFormatter()

    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false
    @State private var imageExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Selection header (always visible)
            if isSelectionMode {
                HStack {
                    Button(action: onToggleSelection) {
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? themeManager.accentColor : .gray)
                                .font(.title3)

                            Text(isSelected ?
                                 NSLocalizedString("mistakeReview.selected", comment: "") :
                                 NSLocalizedString("mistakeReview.select", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(isSelected ? themeManager.accentColor : .gray)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()
                }
            }

            // ✅ Header: Date + Question preview (always visible)
            HStack {
                Spacer()
                Text(Self.relativeDateFormatter.localizedString(for: question.createdAt, relativeTo: Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !isExpanded {
                SmartLaTeXView(
                    question.question,
                    fontSize: 14,
                    colorScheme: colorScheme,
                    strategy: .mathjax
                )
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text(isExpanded ? NSLocalizedString("mistakeReview.hideDetails", comment: "") : NSLocalizedString("mistakeReview.showFullQuestion", comment: ""))
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .foregroundColor(themeManager.accentColor)
            }
            .buttonStyle(PlainButtonStyle())

            // ✅ Expanded content (folded by default)
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. Full question text
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("mistakeReview.questionLabel", comment: ""))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        SmartLaTeXView(
                            question.rawQuestionText,
                            fontSize: 16,
                            colorScheme: colorScheme,
                            strategy: .mathjax
                        )
                        .textSelection(.enabled)
                    }

                    // 2. Branch breadcrumb (from error analysis)
                    if let baseBranch = question.baseBranch,
                       let detailedBranch = question.detailedBranch,
                       !baseBranch.isEmpty,
                       !detailedBranch.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text(PracticeSessionManager.localizeSubject(question.subject))
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text(BranchLocalizer.localized(baseBranch))
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text(BranchLocalizer.localized(detailedBranch))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                    }

                    // 3. Student answer
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("mistakeReview.yourAnswerLabel", comment: ""))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        SmartLaTeXView(
                            question.studentAnswer.isEmpty ?
                            NSLocalizedString("mistakeReview.noAnswer", comment: "") :
                            question.studentAnswer,
                            fontSize: 16,
                            colorScheme: colorScheme,
                            strategy: .mathjax
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DesignTokens.Colors.error.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(DesignTokens.Colors.error.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // 4. What Went Wrong (specificIssue + evidence)
                    if question.hasErrorAnalysis {
                        if let specificIssue = question.specificIssue, !specificIssue.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(DesignTokens.Colors.warning)
                                        .font(.caption)
                                    Text(NSLocalizedString("mistakeReview.whatWentWrong", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                }
                                Text(specificIssue)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                            .padding(10)
                            .background(DesignTokens.Colors.warning.opacity(0.05))
                            .cornerRadius(8)
                        }

                        if let evidence = question.errorEvidence, !evidence.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(themeManager.accentColor)
                                        .font(.caption)
                                    Text(NSLocalizedString("mistakeReview.evidence", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                }
                                Text(evidence)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                            .padding(10)
                            .background(themeManager.accentColor.opacity(0.05))
                            .cornerRadius(8)
                        }
                    } else if question.isAnalyzing {
                        analyzingSection
                    }

                    // 5. Correct answer
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("mistakeReview.correctAnswerLabel", comment: ""))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        SmartLaTeXView(
                            question.correctAnswer,
                            fontSize: 16,
                            colorScheme: colorScheme,
                            strategy: .mathjax
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DesignTokens.Colors.success.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(DesignTokens.Colors.success.opacity(0.3), lineWidth: 1)
                        )
                    }

                    // 6. Explanation
                    if !question.explanation.isEmpty && question.explanation != "No explanation provided" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("mistakeReview.explanation", comment: ""))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            SmartLaTeXView(
                                question.explanation,
                                fontSize: 14,
                                colorScheme: colorScheme,
                                strategy: .mathjax
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(themeManager.accentColor.opacity(0.05))
                            .cornerRadius(8)
                        }
                    }

                    // 7. Error classification badge
                    if question.hasErrorAnalysis, let errorType = question.errorType {
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

                    // 8. How to Improve
                    if question.hasErrorAnalysis,
                       let suggestion = question.learningSuggestion,
                       !suggestion.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(DesignTokens.Colors.warning)
                                    .font(.caption)
                                Text(NSLocalizedString("mistakeReview.howToImprove", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                            Text(suggestion)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        .padding(10)
                        .background(DesignTokens.Colors.warning.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(isSelectionMode && isSelected ? themeManager.accentColor.opacity(0.1) : Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelectionMode && isSelected ? themeManager.accentColor : Color.gray.opacity(0.2),  // ✅ Lighter border
                    lineWidth: isSelectionMode && isSelected ? 2 : 1  // ✅ Thinner when not selected
                )
        )
    }

    // ✅ OPTIMIZATION: Analyzing section
    private var analyzingSection: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text(NSLocalizedString("mistakeReview.analyzingMistake", comment: ""))
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
        case "execution_error": return NSLocalizedString("mistakeReview.errorType.executionError", comment: "")
        case "conceptual_gap": return NSLocalizedString("mistakeReview.errorType.conceptualGap", comment: "")
        case "needs_refinement": return NSLocalizedString("mistakeReview.errorType.needsRefinement", comment: "")
        default: return NSLocalizedString("mistakeReview.errorType.unknown", comment: "")
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
    /// Pass a non-nil value to persist progress (new session) or restore it (resume).
    var sessionId: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var expandedQuestions: Set<UUID> = []
    @State private var currentAnswers: [UUID: String] = [:]
    @State private var gradedQuestions: [UUID: GradeResult] = [:] // UUID -> GradeResult

    private let sessionManager = PracticeSessionManager.shared

    // UserDefaults key prefix for grading persistence
    private func gradeKey(_ id: UUID) -> String { "mistake_practice_grade_\(id.uuidString)" }

    // ✅ PDF Export state
    @StateObject private var pdfGenerator = PDFGeneratorService()
    @State private var showingPDFPreview = false
    @State private var pdfDocument: PDFDocument?

    // ✅ Mark Progress Slider state
    @State private var slideOffset: CGFloat = 0
    @State private var isSliding = false
    @State private var hasTriggeredMarkProgress = false
    @State private var hasMarkedProgress = false

    // ✅ NEW: Mastery celebration state
    @ObservedObject private var statusService = ShortTermStatusService.shared
    @State private var showingMasteryCelebration = false
    @State private var masteredWeakness: String? = nil

    struct GradeResult: Equatable {
        let isCorrect: Bool
        let correctAnswer: String
        let feedback: String
        let wasInstantGraded: Bool  // ✅ NEW: Track if graded instantly vs AI
        let matchScore: Double?  // ✅ NEW: Matching score (if instant graded)
    }

    var body: some View {
        NavigationView {
            mainContent
                .navigationTitle(subject)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("common.done", comment: "")) {
                            dismiss()
                        }
                    }
                }
                .fullScreenCover(isPresented: $showingPDFPreview) {
                    if let document = pdfDocument {
                        NavigationView {
                            PDFKitView(document: document)
                                .ignoresSafeArea()
                                .navigationTitle(subject)
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .navigationBarTrailing) {
                                        Button(NSLocalizedString("common.done", comment: "")) {
                                            showingPDFPreview = false
                                        }
                                    }
                                }
                        }
                    }
                }
                .onChange(of: statusService.recentMasteries.count) { _, _ in
                    if let latestMastery = statusService.recentMasteries.last {
                        handleMasteryAchievement(latestMastery)
                    }
                }
        }
        .overlay {
            if showingMasteryCelebration, let weakness = masteredWeakness {
                masteryCelebrationView(for: weakness)
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                progressIndicator
                questionsList

                if gradedQuestions.count == questions.count {
                    accuracyCardWithSlideToMark
                        .padding(.horizontal)
                        .transition(.opacity)
                }

                pdfExportButton
            }
            .padding()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(NSLocalizedString("mistakeReview.targetedPractice", comment: ""))
                .font(.title)
                .fontWeight(.bold)

            Text(String(format: NSLocalizedString("mistakeReview.questionsBasedOnMistakes", comment: ""), questions.count))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .onAppear {
            logPracticeQuestionsDebug()
            restoreSavedProgress()
        }
    }

    /// Restore any previously graded answers from UserDefaults.
    private func restoreSavedProgress() {
        for question in questions {
            let key = gradeKey(question.id)
            guard let data = UserDefaults.standard.data(forKey: key),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let isCorrect       = dict["isCorrect"]       as? Bool   ?? false
            let correctAnswer   = dict["correctAnswer"]   as? String ?? question.correctAnswer
            let feedback        = dict["feedback"]        as? String ?? ""
            let wasInstant      = dict["wasInstantGraded"] as? Bool  ?? false
            let matchScore      = dict["matchScore"]      as? Double

            gradedQuestions[question.id] = GradeResult(
                isCorrect: isCorrect,
                correctAnswer: correctAnswer,
                feedback: feedback,
                wasInstantGraded: wasInstant,
                matchScore: matchScore
            )
            currentAnswers[question.id] = dict["userAnswer"] as? String ?? ""
        }
    }

    /// Persist a grade result to UserDefaults and update session progress.
    private func persistGrade(questionId: UUID, userAnswer: String, result: GradeResult) {
        let dict: [String: Any] = [
            "isCorrect":       result.isCorrect,
            "correctAnswer":   result.correctAnswer,
            "feedback":        result.feedback,
            "wasInstantGraded": result.wasInstantGraded,
            "matchScore":      result.matchScore as Any,
            "userAnswer":      userAnswer
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict) {
            UserDefaults.standard.set(data, forKey: gradeKey(questionId))
        }
        if let sid = sessionId {
            sessionManager.updateProgress(
                sessionId: sid,
                completedQuestionId: questionId.uuidString,
                answer: userAnswer,
                isCorrect: result.isCorrect
            )
        }
    }

    @ViewBuilder
    private var progressIndicator: some View {
        if !gradedQuestions.isEmpty {
            HStack {
                Text(String(format: NSLocalizedString("mistakeReview.progressAnswered", comment: ""), gradedQuestions.count, questions.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: NSLocalizedString("mistakeReview.correctCount", comment: ""), correctCount, gradedQuestions.count))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(correctCount == gradedQuestions.count ? DesignTokens.Colors.success : DesignTokens.Colors.warning)
            }
            .padding(.horizontal)
        }
    }

    private var questionsList: some View {
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
    }

    private var pdfExportButton: some View {
        Button(action: {
            Task {
                await generatePDF()
            }
        }) {
            HStack {
                if pdfGenerator.isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text("Exporting... \(Int(pdfGenerator.generationProgress * 100))%")
                        .font(.body)
                        .fontWeight(.semibold)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.title3)
                    Text(NSLocalizedString("mistakeReview.exportToPDF", comment: ""))
                        .font(.body)
                        .fontWeight(.semibold)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: pdfGenerator.isGenerating ? [Color.gray, Color.gray.opacity(0.8)] : [Color.blue, Color.blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .disabled(pdfGenerator.isGenerating)
        .padding(.horizontal)
    }

    // MARK: - Helper Methods

    private func logPracticeQuestionsDebug() {
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

    private func handleMasteryAchievement(_ mastery: (key: String, timestamp: Date)) {
        masteredWeakness = formatWeaknessKey(mastery.key)
        showingMasteryCelebration = true

        // Play success sound
        AudioServicesPlaySystemSound(1054)

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
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
        print("🔹 Correct Answer: \(question.correctAnswer)")
        print("🔹 Subject: \(subject)")
        print("")
        #endif

        // ✅ OPTIMIZATION: Try client-side matching first
        // Convert array options to dictionary format if needed
        let optionsDict: [String: String]?
        if let optionsArray = question.options {
            // Convert ["option1", "option2", "option3"] to ["A": "option1", "B": "option2", "C": "option3"]
            let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
            optionsDict = Dictionary(uniqueKeysWithValues: zip(letters.prefix(optionsArray.count), optionsArray))
        } else {
            optionsDict = nil
        }

        let matchResult = AnswerMatchingService.shared.matchAnswer(
            userAnswer: userAnswer,
            correctAnswer: question.correctAnswer,
            questionType: question.type.rawValue,
            options: optionsDict
        )

        #if DEBUG
        print("🎯 Matching Result:")
        print("   Match Score: \(String(format: "%.1f%%", matchResult.matchScore * 100))")
        print("   Is Exact Match: \(matchResult.isExactMatch)")
        print("   Should Skip AI: \(matchResult.shouldSkipAIGrading)")
        print("")
        #endif

        // If match score >= 90%, grade instantly without AI call
        if matchResult.shouldSkipAIGrading {
            #if DEBUG
            print("⚡ INSTANT GRADING (score >= 90%)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("✅ Skipping AI grading - instant match detected!")
            print("📤 ============================================")
            #endif

            // Instant grade result (curve to 100% correct if >= 90%)
            let instantFeedback: String
            if matchResult.isExactMatch {
                instantFeedback = NSLocalizedString("mistakeReview.feedbackExact", comment: "")
            } else {
                instantFeedback = NSLocalizedString("mistakeReview.feedbackCorrect", comment: "")
            }

            await MainActor.run {
                let result = GradeResult(
                    isCorrect: true,
                    correctAnswer: question.correctAnswer,
                    feedback: instantFeedback,
                    wasInstantGraded: true,
                    matchScore: matchResult.matchScore
                )
                gradedQuestions[question.id] = result
                persistGrade(questionId: question.id, userAnswer: userAnswer, result: result)

                #if DEBUG
                print("💾 Stored INSTANT grade result for question \(question.id)")
                print("📈 Progress: \(gradedQuestions.count)/\(questions.count) answered")
                #endif

                // Haptic feedback - success
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }

            return  // Skip AI grading
        }

        // If match score < 90%, send to AI for deep analysis
        #if DEBUG
        print("🤖 AI GRADING (score < 90%)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⏳ Sending to Gemini deep mode for analysis...")
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
                useDeepReasoning: true  // Gemini deep mode for nuanced grading
            )

            #if DEBUG
            print("")
            print("✅ RECEIVED AI GRADING RESPONSE")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            if let grade = response.grade {
                print("📊 Grade Result:")
                print("   ✓ Is Correct: \(grade.isCorrect ? "✅ YES" : "❌ NO")")
                print("   ✓ Score: \(String(format: "%.1f%%", grade.score * 100))")
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
                    let result = GradeResult(
                        isCorrect: grade.isCorrect,
                        correctAnswer: grade.correctAnswer ?? question.correctAnswer,
                        feedback: grade.feedback,
                        wasInstantGraded: false,
                        matchScore: matchResult.matchScore
                    )
                    gradedQuestions[question.id] = result
                    persistGrade(questionId: question.id, userAnswer: userAnswer, result: result)

                    #if DEBUG
                    print("💾 Stored AI grade result for question \(question.id)")
                    print("📈 Progress: \(gradedQuestions.count)/\(questions.count) answered")
                    #endif

                    // Haptic feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(grade.isCorrect ? .success : .error)
                }
            }
        } catch {
            #if DEBUG
            print("❌ ============================================")
            print("❌ AI GRADING FAILED")
            print("❌ ============================================")
            print("Error: \(error.localizedDescription)")
            print("Full error: \(error)")
            print("❌ ============================================")
            #endif
            print("❌ Failed to grade answer: \(error.localizedDescription)")
            // Could show error alert here
        }
    }

    // MARK: - Accuracy Card with Slide to Mark Progress

    private var accuracyCardWithSlideToMark: some View {
        let correctCount = gradedQuestions.values.filter { $0.isCorrect }.count
        let incorrectCount = gradedQuestions.count - correctCount
        let accuracy = gradedQuestions.isEmpty ? 0.0 : (Double(correctCount) / Double(gradedQuestions.count)) * 100

        return VStack(spacing: 20) {
            // Top section: Accuracy stats
            VStack(spacing: 16) {
                // Big accuracy percentage
                Text(String(format: "%.0f%%", accuracy))
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(DesignTokens.Colors.success)

                Text(NSLocalizedString("mistakeReview.accuracy", comment: ""))
                    .font(.headline)
                    .foregroundColor(.secondary)

                Divider()
                    .padding(.vertical, 8)

                // Detailed stats (horizontal)
                HStack(spacing: 24) {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(DesignTokens.Colors.success)
                            Text("\(correctCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        Text(NSLocalizedString("mistakeReview.correct", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(DesignTokens.Colors.error)
                            Text("\(incorrectCount)")
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        Text(NSLocalizedString("mistakeReview.incorrect", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.top, 20)

            // Bottom section: Slide to mark progress
            if !hasMarkedProgress {
                slideToMarkProgressTrack
                    .padding(.bottom, 20)
            } else {
                // Progress already marked indicator
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(DesignTokens.Colors.success)
                    Text(NSLocalizedString("mistakeReview.progressAlreadyMarked", comment: ""))
                        .font(.headline)
                        .foregroundColor(DesignTokens.Colors.success)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(DesignTokens.Colors.success.opacity(0.1))
                .cornerRadius(12)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }

    // Slide to mark progress track (Liquid Glass Style)
    private var slideToMarkProgressTrack: some View {
        GeometryReader { geometry in
            let trackWidth = geometry.size.width
            let sliderWidth: CGFloat = 60
            let maxOffset = trackWidth - sliderWidth - 8

            ZStack(alignment: .leading) {
                // Background track - Liquid Glass Effect
                RoundedRectangle(cornerRadius: 30)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .frame(height: 60)

                // Progress fill (grows as user slides)
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: slideOffset + sliderWidth + 4, height: 60)
                    .opacity(slideOffset > 0 ? 1.0 : 0.0)

                // Instruction text (fades as slider moves)
                HStack {
                    Spacer()
                    Text(NSLocalizedString("mistakeReview.slideToMarkProgress", comment: ""))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary.opacity(0.6))
                        .opacity(1.0 - (slideOffset / maxOffset))
                    Spacer()
                }
                .frame(height: 60)

                // Sliding button - Magnifying Glass Effect
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

                            if newOffset >= maxOffset * 1.0 && !hasTriggeredMarkProgress {
                                hasTriggeredMarkProgress = true
                                markProgress()

                                // iOS unlock sound effect
                                AudioServicesPlaySystemSound(1100)

                                // Haptic feedback
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)

                                // Reset slider with animation
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
                            hasTriggeredMarkProgress = false
                        }
                )
            }
        }
        .frame(height: 60)
    }

    // MARK: - Mark Progress

    private func markProgress() {
        guard !hasMarkedProgress else { return }
        hasMarkedProgress = true

        print("📊 [MarkProgress] Marking progress for \(questions.count) practice questions")

        // Count correct/incorrect for daily progress
        var correctCount = 0
        var totalCount = 0

        // Update ShortTermStatusService based on correctness
        for question in questions {
            guard let gradeResult = gradedQuestions[question.id] else { continue }

            totalCount += 1
            if gradeResult.isCorrect {
                correctCount += 1
            }

            // Get error keys from the question (if available)
            if let baseBranch = question.baseBranch,
               let detailedBranch = question.detailedBranch {
                let weaknessKey = "\(subject)/\(baseBranch)/\(detailedBranch)"

                if gradeResult.isCorrect {
                    // Record correct attempt - reduces weakness value
                    print("✅ [MarkProgress] Correct answer for: \(weaknessKey)")
                    ShortTermStatusService.shared.recordCorrectAttempt(
                        key: weaknessKey,
                        retryType: .firstTime,
                        questionId: question.id.uuidString
                    )
                } else {
                    // Record mistake - increases weakness value
                    print("❌ [MarkProgress] Incorrect answer for: \(weaknessKey)")
                    if let errorType = question.errorType {
                        ShortTermStatusService.shared.recordMistake(
                            key: weaknessKey,
                            errorType: errorType,
                            questionId: question.id.uuidString
                        )
                    }
                }
            } else {
                print("⚠️ [MarkProgress] Question \(question.id) missing error taxonomy keys")
            }
        }

        // ✅ NEW: Update daily progress counters (local-only, like random practice)
        if totalCount > 0 {
            print("📊 [MarkProgress] Updating daily progress: \(correctCount)/\(totalCount) questions for \(subject)")

            // Update local progress counters only
            // Backend sync happens manually via Settings or automatic schedule
            PointsEarningManager.shared.markHomeworkProgress(
                subject: subject,
                numberOfQuestions: totalCount,
                numberOfCorrectQuestions: correctCount
            )
        }

        print("✅ [MarkProgress] Progress marked successfully (LOCAL ONLY)")

        // Archive only mistake questions; concept extraction for correct ones
        archiveMistakesAndExtractConcepts()
    }

    /// Archive incorrect answers to local storage + error analysis; run concept extraction for correct answers.
    private func archiveMistakesAndExtractConcepts() {
        let sessionId = self.sessionId ?? UUID().uuidString

        var mistakeData: [[String: Any]] = []
        var correctData: [[String: Any]] = []

        for question in questions {
            guard let gradeResult = gradedQuestions[question.id] else { continue }
            let studentAnswer = currentAnswers[question.id] ?? ""

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
                "grade": gradeResult.isCorrect ? "CORRECT" : "INCORRECT",
                "points": gradeResult.isCorrect ? (question.points ?? 1) : 0,
                "maxPoints": question.points ?? 1,
                "feedback": gradeResult.feedback,
                "isGraded": true,
                "isCorrect": gradeResult.isCorrect,
                "errorType": question.errorType as Any,
                "baseBranch": question.baseBranch as Any,
                "detailedBranch": question.detailedBranch as Any,
                "weaknessKey": question.weaknessKey as Any
            ]

            if gradeResult.isCorrect {
                correctData.append(questionData)
            } else {
                mistakeData.append(questionData)
            }
        }

        // Save only mistakes to local storage
        if !mistakeData.isEmpty {
            let idMappings = currentUserQuestionStorage().saveQuestions(mistakeData)
            for (index, mapping) in idMappings.enumerated() {
                if mapping.savedId != mapping.originalId {
                    mistakeData[index]["id"] = mapping.savedId
                }
            }

            ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
                sessionId: sessionId,
                wrongQuestions: mistakeData
            )
        }

        // Concept extraction for correct answers (NOT saved to storage)
        if !correctData.isEmpty {
            ErrorAnalysisQueueService.shared.queueConceptExtractionForCorrectAnswers(
                sessionId: sessionId,
                correctQuestions: correctData
            )
        }

        print("📚 [MarkProgress] Archived \(mistakeData.count) mistakes, concept extraction for \(correctData.count) correct")
    }

    // MARK: - PDF Export

    private func generatePDF() async {
        let document = await pdfGenerator.generatePracticePDF(
            questions: questions,
            subject: subject,
            generationType: "Targeted Practice"
        )

        await MainActor.run {
            self.pdfDocument = document
            if document != nil {
                self.showingPDFPreview = true
            }
        }
    }

    // MARK: - Mastery Celebration

    /// Format weakness key for user-friendly display
    /// Example: "Mathematics/Algebra - Foundations/Linear Equations - One Variable" → "Linear Equations in Algebra"
    private func formatWeaknessKey(_ key: String) -> String {
        let components = key.split(separator: "/").map(String.init)

        if components.count >= 3 {
            // Extract detailed branch (last component) and base branch (middle component)
            let detailedBranch = BranchLocalizer.localized(components[2])
            let baseBranch = BranchLocalizer.localized(components[1])

            return "\(detailedBranch) (\(baseBranch))"
        } else if components.count == 2 {
            // Fallback: just use the last component
            return BranchLocalizer.localized(components[1])
        } else {
            // Fallback: use the whole key
            return key
        }
    }

    /// Celebration view for mastered weakness
    @ViewBuilder
    private func masteryCelebrationView(for weakness: String) -> some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissCelebration()
                }

            // Celebration card
            VStack(spacing: 24) {
                // Trophy icon with animation
                Image(systemName: "trophy.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.yellow)
                    .shadow(color: .yellow.opacity(0.5), radius: 20, x: 0, y: 0)
                    .scaleEffect(showingMasteryCelebration ? 1.0 : 0.1)
                    .animation(.spring(response: 0.6, dampingFraction: 0.5), value: showingMasteryCelebration)

                VStack(spacing: 12) {
                    Text(NSLocalizedString("mistakeReview.masteredWeakness", comment: ""))
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text(weakness)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignTokens.Colors.success)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text(NSLocalizedString("mistakeReview.keepUpGreatWork", comment: ""))
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // Dismiss button
                Button(action: {
                    dismissCelebration()
                }) {
                    Text(NSLocalizedString("common.continue", comment: ""))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [DesignTokens.Colors.success, DesignTokens.Colors.success.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
        }
        .transition(.opacity.combined(with: .scale))
    }

    private func dismissCelebration() {
        withAnimation(.easeOut(duration: 0.3)) {
            showingMasteryCelebration = false
        }

        // Clear the mastery from the service after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            statusService.clearRecentMasteries()
            masteredWeakness = nil
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

    // ✅ NEW: Archive and follow-up state
    @State private var isArchiving: Bool = false
    @State private var isArchived: Bool = false
    @State private var showingArchiveSuccess: Bool = false

    @ObservedObject private var appState = AppState.shared
    @Environment(\.dismiss) private var dismiss

    private var isGraded: Bool {
        gradeResult != nil
    }

    private var isCorrect: Bool {
        gradeResult?.isCorrect ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question Header — full-width tappable area
            Button(action: onToggleExpand) {
                HStack {
                    // Question number badge
                    ZStack {
                        Circle()
                            .fill(isGraded ? (isCorrect ? DesignTokens.Colors.success : DesignTokens.Colors.error) : Color.blue)
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
                        Text(String(format: NSLocalizedString("mistakeReview.questionNumber", comment: ""), questionNumber))
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
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                Divider()

                // Question text
                MarkdownLaTeXText(question.question, fontSize: 16, isStreaming: false)
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
                        Text(NSLocalizedString("mistakeReview.yourAnswerColon", comment: ""))
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
                                    Text(NSLocalizedString("mistakeReview.submitAnswer", comment: ""))
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
                                Text(NSLocalizedString("mistakeReview.yourAnswer", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                Text(currentAnswer)
                                    .font(.body)
                            }
                        }
                        .padding(12)
                        .background(isCorrect ? DesignTokens.Colors.success.opacity(0.1) : DesignTokens.Colors.error.opacity(0.1))
                        .cornerRadius(8)

                        // Correct answer (if incorrect)
                        if !isCorrect, let result = gradeResult {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(DesignTokens.Colors.warning)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(NSLocalizedString("mistakeReview.correctAnswer", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    Text(result.correctAnswer)
                                        .font(.body)
                                }
                            }
                            .padding(12)
                            .background(DesignTokens.Colors.warning.opacity(0.1))
                            .cornerRadius(8)
                        }

                        // Explanation
                        if let result = gradeResult {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: result.wasInstantGraded ? "bolt.fill" : "brain.head.profile")
                                    .foregroundColor(result.wasInstantGraded ? .yellow : .purple)
                                    .font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(NSLocalizedString("mistakeReview.explanation", comment: ""))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)

                                        // ✅ NEW: Badge showing grading method
                                        if result.wasInstantGraded {
                                            HStack(spacing: 3) {
                                                Image(systemName: "bolt.fill")
                                                    .font(.system(size: 8))
                                                Text(NSLocalizedString("mistakeReview.gradingInstant", comment: ""))
                                                    .font(.system(size: 9))
                                                    .fontWeight(.semibold)
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule()
                                                    .fill(Color.yellow)
                                            )
                                        } else {
                                            HStack(spacing: 3) {
                                                Image(systemName: "brain.head.profile")
                                                    .font(.system(size: 8))
                                                Text(NSLocalizedString("mistakeReview.gradingAI", comment: ""))
                                                    .font(.system(size: 9))
                                                    .fontWeight(.semibold)
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(
                                                Capsule()
                                                    .fill(Color.purple)
                                            )
                                        }
                                    }
                                    Text(result.feedback)
                                        .font(.body)
                                }
                            }
                            .padding(12)
                            .background(result.wasInstantGraded ? Color.yellow.opacity(0.05) : Color.purple.opacity(0.05))
                            .cornerRadius(8)
                        }

                        // ✅ NEW: Action buttons (Follow-up + Archive) side by side
                        HStack(spacing: 12) {
                            // Follow-up button (left)
                            Button(action: askAIForHelp) {
                                HStack(spacing: 8) {
                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                        .font(.body)
                                    Text(NSLocalizedString("mistakeReview.followUp", comment: ""))
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    LinearGradient(
                                        colors: [Color.orange, Color.orange.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                                .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
                            }

                            // Archive button (right)
                            Button(action: archiveQuestion) {
                                HStack(spacing: 8) {
                                    if isArchiving {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else if isArchived {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.body)
                                        Text(NSLocalizedString("mistakeReview.archived", comment: ""))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    } else {
                                        Image(systemName: "books.vertical.fill")
                                            .font(.body)
                                        Text(NSLocalizedString("mistakeReview.archiveQuestion", comment: ""))
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    LinearGradient(
                                        colors: isArchived ?
                                            [Color.green, Color.green.opacity(0.8)] :
                                            [Color.purple, Color.purple.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                            }
                            .disabled(isArchiving || isArchived)
                        }
                        .padding(.top, 8)
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
        .alert(NSLocalizedString("mistakeReview.questionArchived", comment: ""), isPresented: $showingArchiveSuccess) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("mistakeReview.questionArchivedMessage", comment: ""))
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

    // MARK: - Archive and Follow-up Actions

    /// Archive the answered question to local storage
    private func archiveQuestion() {
        guard gradeResult != nil else { return }

        isArchiving = true

        print("📚 [Archive] Starting archive for mistake practice question: \(question.question.prefix(50))...")

        Task {
            // Build question data for archiving
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
                "studentAnswer": currentAnswer,
                "grade": isCorrect ? "CORRECT" : "INCORRECT",
                "points": isCorrect ? (question.points ?? 1) : 0,
                "maxPoints": question.points ?? 1,
                "feedback": gradeResult?.feedback ?? "",
                "isGraded": true,
                "isCorrect": isCorrect,
                // ✅ Include error keys for short-term status tracking
                "errorType": question.errorType as Any,
                "baseBranch": question.baseBranch as Any,
                "detailedBranch": question.detailedBranch as Any,
                "weaknessKey": question.weaknessKey as Any
            ]

            print("📚 [Archive] Archive data - Subject: \(subject), Correct: \(isCorrect)")

            // Save to local storage
            _ = currentUserQuestionStorage().saveQuestions([questionData])

            await MainActor.run {
                isArchiving = false
                isArchived = true
                showingArchiveSuccess = true
                print("📚 [Archive] ✅ Mistake practice question archived successfully")
            }
        }
    }

    /// Open AI chat with question context
    private func askAIForHelp() {
        // Construct user message for AI
        let userMessage = """
I need help understanding this question from my mistake practice:

Question: \(question.question)

My answer was: \(currentAnswer)

Can you help me understand this better and explain the solution?
"""

        // Navigate to chat with question context and deep mode for first message
        appState.navigateToChatWithMessage(userMessage, subject: subject, useDeepMode: true)

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Practice Input Components

/// Multiple Choice Input for Practice Questions
struct PracticeMCInput: View {
    let options: [String]
    @Binding var selectedOption: String
    @Environment(\.colorScheme) var colorScheme

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
                        SmartLaTeXView(option, fontSize: 16, colorScheme: colorScheme)
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
                    Text(NSLocalizedString("common.true", comment: ""))
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(selectedOption == "True" ?
                            DesignTokens.Colors.success.opacity(0.2) : Color(.systemGray6))
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
                    Text(NSLocalizedString("common.false", comment: ""))
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(selectedOption == "False" ?
                            DesignTokens.Colors.error.opacity(0.2) : Color(.systemGray6))
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

    // Pre-compiled once at struct load time — avoids recompiling on every render
    private static let subquestionRegexes: [NSRegularExpression] = {
        let patterns = [
            "^[a-z]\\)",
            "^\\d+\\)",
            "^\\([a-z]\\)",
            "^\\(\\d+\\)",
            "^Part [a-z]:",
            "^Part \\d+:",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

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
                                    .foregroundColor(DesignTokens.Colors.warning)
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
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return Self.subquestionRegexes.contains { $0.firstMatch(in: trimmed, range: range) != nil }
    }
}

// MARK: - Practice Configuration Sheet
struct PracticeConfigurationSheet: View {
    let mistakeCount: Int
    let selectedMistakes: [MistakeQuestion]
    let onGenerate: (QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty, Set<QuestionGenerationService.GeneratedQuestion.QuestionType>, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDifficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty = .intermediate
    @State private var selectedQuestionType: QuestionGenerationService.GeneratedQuestion.QuestionType = .any
    @State private var questionCount: Int = 5

    // Each element: (label, questionsNeeded)
    private var weaknessHints: [(label: String, needed: Int)] {
        let service = ShortTermStatusService.shared
        var keyInfo: [String: (label: String, errorTypes: [String])] = [:]
        for mistake in selectedMistakes {
            guard let key = mistake.weaknessKey,
                  let base = mistake.baseBranch,
                  let detail = mistake.detailedBranch,
                  !base.isEmpty, !detail.isEmpty else { continue }
            if keyInfo[key] == nil { keyInfo[key] = (label: detail, errorTypes: []) }
            if let et = mistake.errorType { keyInfo[key]!.errorTypes.append(et) }
        }
        var hints: [(label: String, needed: Int)] = []
        for (key, info) in keyInfo {
            guard let weakness = service.status.activeWeaknesses[key], weakness.value > 0 else { continue }
            let weights = info.errorTypes.isEmpty ? [1.5] : info.errorTypes.map { service.errorTypeWeight($0) }
            let avgWeight = weights.reduce(0, +) / Double(weights.count)
            let decrement = 1.0 * avgWeight * 0.6 * 1.0
            guard decrement > 0 else { continue }
            hints.append((label: info.label, needed: Int(ceil(weakness.value / decrement))))
        }
        return hints.sorted { $0.needed < $1.needed }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    configCard
                    generateButton
                }
                .padding(.vertical)
            }
            .navigationTitle(NSLocalizedString("mistakeReview.practiceConfiguration", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("mistakeReview.configurePractice", comment: ""))
                .font(.title2)
                .fontWeight(.bold)
            Text(String(format: NSLocalizedString("mistakeReview.basedOnMistakes", comment: ""), mistakeCount))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }

    private var configCard: some View {
        VStack(spacing: 16) {
            difficultyColorBar
            countSlider
            weaknessHintsSection
            questionTypeGrid
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
        .padding(.horizontal)
    }

    private var countSlider: some View {
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
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
            VStack(spacing: 8) {
                HStack {
                    Text("1").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("10").font(.caption).foregroundColor(.secondary)
                }
                Slider(value: Binding(get: { Double(questionCount) }, set: { questionCount = Int($0) }),
                       in: 1...10, step: 1)
                    .accentColor(.blue)
            }
        }
    }

    @ViewBuilder
    private var weaknessHintsSection: some View {
        if !weaknessHints.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(weaknessHints, id: \.label) { hint in
                    let cleared = hint.needed <= questionCount
                    HStack(spacing: 6) {
                        Image(systemName: cleared ? "checkmark.circle.fill" : "circle.dotted")
                            .font(.caption)
                            .foregroundColor(cleared ? DesignTokens.Colors.success : .secondary)
                        Text("\(hint.needed) more question\(hint.needed == 1 ? "" : "s") to clear \(hint.label) weakness")
                            .font(.caption)
                            .foregroundColor(cleared ? DesignTokens.Colors.success : .secondary)
                    }
                }
            }
        }
    }

    private var questionTypeGrid: some View {
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
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(QuestionGenerationService.GeneratedQuestion.QuestionType.generatableTypes, id: \.self) { type in
                    let isSelected = selectedQuestionType == type
                    Button(action: { selectedQuestionType = type }) {
                        VStack(spacing: 4) {
                            Image(systemName: type.icon)
                                .font(.title3)
                                .foregroundColor(isSelected ? .blue : .secondary)
                            Text(type.displayName)
                                .font(.caption2)
                                .foregroundColor(isSelected ? .blue : .secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var generateButton: some View {
        Button(action: {
            onGenerate(selectedDifficulty, Set([selectedQuestionType]), questionCount)
            dismiss()
        }) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                Text(String(format: NSLocalizedString("mistakeReview.generateCount", comment: ""), questionCount))
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
        .padding(.bottom)
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
                            if x < segW { selectedDifficulty = .beginner }
                            else if x < segW * 2 { selectedDifficulty = .intermediate }
                            else if x < mainW { selectedDifficulty = .advanced }
                            else { selectedDifficulty = .adaptive }
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
            return NSLocalizedString("difficulty.desc.beginner", comment: "")
        case .intermediate:
            return NSLocalizedString("difficulty.desc.intermediate", comment: "")
        case .advanced:
            return NSLocalizedString("difficulty.desc.advanced", comment: "")
        case .adaptive:
            return NSLocalizedString("difficulty.desc.adaptive", comment: "")
        }
    }
}


#Preview {
    MistakeReviewView()
}

// MARK: - AdaptiveGlowDot
// Owns its own animation state so parent views don't re-render on each animation tick.
struct AdaptiveGlowDot: View {
    let isActive: Bool
    @State private var phase: Double = 0

    var body: some View {
        Circle()
            .fill(AngularGradient(
                colors: [
                    DesignTokens.Colors.Cute.lavender,
                    DesignTokens.Colors.Cute.blue,
                    DesignTokens.Colors.Cute.mint,
                    DesignTokens.Colors.Cute.peach,
                    DesignTokens.Colors.Cute.lavender
                ],
                center: .center
            ))
            .hueRotation(.degrees(phase * 360))
            .frame(width: 16, height: 16)
            .shadow(color: Color.purple.opacity(isActive ? 0.85 : 0.25),
                    radius: isActive ? 9 : 3)
            .scaleEffect(isActive ? 1.15 : 0.9)
            .onAppear {
                withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}