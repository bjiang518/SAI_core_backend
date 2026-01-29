//
//  MistakeReviewView.swift
//  StudyAI
//
//  Created by Claude Code on 9/20/25.
//

import SwiftUI

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
    @State private var selectedTimeRange: MistakeTimeRange? = nil

    // NEW: Hierarchical filtering state
    @State private var selectedBaseBranch: String?
    @State private var selectedDetailedBranch: String?
    @State private var selectedErrorType: String?

    @State private var showingMistakeList = false
    @State private var showingInstructions = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // SECTION 1: Subject Selection (TOP)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(NSLocalizedString("mistakeReview.subjectsTitle", comment: ""))
                                .font(.title3)
                                .fontWeight(.semibold)

                            if let timeRange = selectedTimeRange {
                                Text("(\(timeRange.displayName))")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }

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
                            CarouselSubjectSelector(
                                subjects: mistakeService.subjectsWithMistakes,
                                selectedSubject: $selectedSubject
                            )
                            .onChange(of: selectedSubject) { _, _ in
                                // Clear hierarchical filters when subject changes
                                selectedBaseBranch = nil
                                selectedDetailedBranch = nil
                                selectedErrorType = nil
                            }
                        }
                    }
                    .padding()

                    // SECTION 2: Hierarchical Navigation (Drill-Down)
                    if let subject = selectedSubject {
                        VStack(spacing: 24) {
                            // Base Branch Selection
                            baseBranchSection(for: subject)

                            // Detailed Branch Selection (show only if base branch selected)
                            if let baseBranch = selectedBaseBranch {
                                detailedBranchSection(for: subject, baseBranch: baseBranch)
                            }

                            // Error Type Filter (conditional, show when subject selected)
                            errorTypeSection(for: subject)

                            // Clear Filters Button (show if any filter is active)
                            if selectedBaseBranch != nil || selectedDetailedBranch != nil || selectedErrorType != nil {
                                clearFiltersButton
                            }
                        }
                    }

                    // Time Range Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text(NSLocalizedString("mistakeReview.timeRangeTitle", comment: ""))
                            .font(.title3)
                            .fontWeight(.semibold)

                        HStack(spacing: 12) {
                            ForEach(MistakeTimeRange.allCases) { range in
                                TimeRangeButton(
                                    range: range,
                                    isSelected: selectedTimeRange == range,
                                    action: {
                                        if selectedTimeRange == range {
                                            selectedTimeRange = nil
                                        } else {
                                            selectedTimeRange = range
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .padding()

                    // SECTION 3: Raw Mistake Questions (Filtered by selectedSubject)
                    // Review Button
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
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer(minLength: 100)
                }
                .padding()
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
                await mistakeService.fetchSubjectsWithMistakes(timeRange: selectedTimeRange)
            }
            .onChange(of: selectedTimeRange) { _, newRange in
                Task {
                    await mistakeService.fetchSubjectsWithMistakes(timeRange: newRange)
                }
            }
            .sheet(isPresented: $showingMistakeList) {
                if let subject = selectedSubject {
                    MistakeQuestionListView(
                        subject: subject,
                        baseBranch: selectedBaseBranch,
                        detailedBranch: selectedDetailedBranch,
                        errorType: selectedErrorType,
                        timeRange: selectedTimeRange ?? .allTime
                    )
                }
            }
        }
    }

    // MARK: - Helper Methods

    /// Calculate filtered mistake count based on hierarchical filters
    private func calculateFilteredMistakeCount() -> Int {
        guard let selectedSubject = selectedSubject else { return 0 }

        let localStorage = QuestionLocalStorage.shared
        var allMistakes = localStorage.getMistakeQuestions(subject: selectedSubject)

        // Filter by time range
        if let timeRange = selectedTimeRange {
            allMistakes = mistakeService.filterByTimeRange(allMistakes, timeRange: timeRange)
        }

        // Filter by base branch
        if let baseBranch = selectedBaseBranch {
            allMistakes = allMistakes.filter { mistake in
                (mistake["baseBranch"] as? String) == baseBranch
            }
        }

        // Filter by detailed branch
        if let detailedBranch = selectedDetailedBranch {
            allMistakes = allMistakes.filter { mistake in
                (mistake["detailedBranch"] as? String) == detailedBranch
            }
        }

        // Filter by error type
        if let errorType = selectedErrorType {
            allMistakes = allMistakes.filter { mistake in
                (mistake["errorType"] as? String) == errorType
            }
        }

        return allMistakes.count
    }

    // MARK: - Hierarchical Navigation Sections

    /// Base Branch selection section
    private func baseBranchSection(for subject: String) -> some View {
        let branches = mistakeService.getBaseBranches(for: subject, timeRange: selectedTimeRange)

        return VStack(alignment: .leading, spacing: 12) {
            Text("📖 Select Chapter")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)

            if branches.isEmpty {
                Text("No mistakes with taxonomy data yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(branches) { branch in
                            Button(action: {
                                if selectedBaseBranch == branch.baseBranch {
                                    selectedBaseBranch = nil
                                    selectedDetailedBranch = nil
                                } else {
                                    selectedBaseBranch = branch.baseBranch
                                    selectedDetailedBranch = nil
                                }
                            }) {
                                HStack {
                                    Image(systemName: selectedBaseBranch == branch.baseBranch ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedBaseBranch == branch.baseBranch ? .blue : .gray)

                                    Text(branch.baseBranch)
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Text("\(branch.mistakeCount)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.red)
                                        .cornerRadius(12)
                                }
                                .padding()
                                .background(selectedBaseBranch == branch.baseBranch ? Color.blue.opacity(0.1) : Color(.systemGray6))
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)
            }
        }
    }

    /// Detailed Branch selection section
    private func detailedBranchSection(for subject: String, baseBranch: String) -> some View {
        let branches = mistakeService.getDetailedBranches(for: subject, baseBranch: baseBranch, timeRange: selectedTimeRange)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(baseBranch)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Select Topic")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal)

            if branches.isEmpty {
                Text("No specific topics found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(branches) { branch in
                            Button(action: {
                                if selectedDetailedBranch == branch.detailedBranch {
                                    selectedDetailedBranch = nil
                                } else {
                                    selectedDetailedBranch = branch.detailedBranch
                                }
                            }) {
                                HStack {
                                    Image(systemName: selectedDetailedBranch == branch.detailedBranch ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedDetailedBranch == branch.detailedBranch ? .blue : .gray)

                                    Text(branch.detailedBranch)
                                        .font(.body)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Text("\(branch.mistakeCount)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.red)
                                        .cornerRadius(12)
                                }
                                .padding()
                                .background(selectedDetailedBranch == branch.detailedBranch ? Color.blue.opacity(0.1) : Color(.systemGray6))
                                .cornerRadius(10)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 250)
            }
        }
    }

    /// Error Type filter section
    private func errorTypeSection(for subject: String) -> some View {
        let errorTypes = mistakeService.getErrorTypeCounts(
            for: subject,
            baseBranch: selectedBaseBranch,
            detailedBranch: selectedDetailedBranch,
            timeRange: selectedTimeRange
        )

        return VStack(alignment: .leading, spacing: 12) {
            Text("🎯 Filter by Error Type")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.horizontal)

            if errorTypes.isEmpty {
                Text("No error analysis data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(errorTypes) { errorType in
                            Button(action: {
                                if selectedErrorType == errorType.errorType {
                                    selectedErrorType = nil
                                } else {
                                    selectedErrorType = errorType.errorType
                                }
                            }) {
                                VStack(spacing: 8) {
                                    Image(systemName: errorType.icon)
                                        .font(.title2)
                                        .foregroundColor(selectedErrorType == errorType.errorType ? .white : errorType.color)

                                    Text(errorType.displayName)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(selectedErrorType == errorType.errorType ? .white : .primary)

                                    Text("\(errorType.mistakeCount)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(selectedErrorType == errorType.errorType ? .white : errorType.color)
                                }
                                .frame(width: 100, height: 100)
                                .background(selectedErrorType == errorType.errorType ? errorType.color : errorType.color.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    /// Clear Filters button
    private var clearFiltersButton: some View {
        Button(action: {
            selectedBaseBranch = nil
            selectedDetailedBranch = nil
            selectedErrorType = nil
        }) {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body)

                Text("Clear Filters")
                    .font(.body)
                    .fontWeight(.medium)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.red.opacity(0.1))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal)
    }
}

// MARK: - Supporting Views
struct TimeRangeButton: View {
    let range: MistakeTimeRange
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: range.icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .white : .blue)

                Text(range.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .blue)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isSelected ? Color.blue : Color.blue.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Carousel Subject Selector

struct CarouselSubjectSelector: View {
    let subjects: [SubjectMistakeCount]
    @Binding var selectedSubject: String?
    @Namespace private var animation

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { proxy in
                HStack(spacing: 20) {
                    // Add leading spacer for centering
                    Spacer()
                        .frame(width: UIScreen.main.bounds.width / 2 - 80)

                    ForEach(subjects, id: \.subject) { subject in
                        GeometryReader { geometry in
                            CarouselSubjectCard(
                                subject: subject,
                                isSelected: selectedSubject == subject.subject,
                                geometry: geometry,
                                action: {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                        if selectedSubject == subject.subject {
                                            selectedSubject = nil
                                        } else {
                                            selectedSubject = subject.subject
                                        }
                                    }
                                }
                            )
                        }
                        .frame(width: 160, height: 180)
                        .id(subject.subject)
                    }

                    // Add trailing spacer for centering
                    Spacer()
                        .frame(width: UIScreen.main.bounds.width / 2 - 80)
                }
                .onChange(of: selectedSubject) { _, newValue in
                    if let selected = newValue {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            proxy.scrollTo(selected, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(height: 200)
    }
}

struct CarouselSubjectCard: View {
    let subject: SubjectMistakeCount
    let isSelected: Bool
    let geometry: GeometryProxy
    let action: () -> Void

    // Calculate how far this card is from the center of the screen
    private var distanceFromCenter: CGFloat {
        let cardCenter = geometry.frame(in: .global).midX
        let screenCenter = UIScreen.main.bounds.width / 2
        return cardCenter - screenCenter
    }

    // Scale based on distance from center: 1.2 at center, 0.75 at edges
    private var scale: CGFloat {
        let normalizedDistance = abs(distanceFromCenter) / (UIScreen.main.bounds.width / 2)
        let scale = 1.2 - (normalizedDistance * 0.45)
        return max(0.75, min(1.2, scale))
    }

    // Opacity based on distance: 1.0 at center, 0.5 at edges
    private var opacity: Double {
        let normalizedDistance = abs(distanceFromCenter) / (UIScreen.main.bounds.width / 2)
        let opacity = 1.0 - (normalizedDistance * 0.5)
        return max(0.5, min(1.0, opacity))
    }

    // Y offset for parallax effect
    private var yOffset: CGFloat {
        let normalizedDistance = distanceFromCenter / (UIScreen.main.bounds.width / 2)
        return normalizedDistance * 15
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Text(subject.subject)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text("\(subject.mistakeCount)")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(isSelected ? .white : .red)

                Text(subject.mistakeCount == 1 ? "Mistake" : "Mistakes")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
            }
            .frame(width: 160, height: 180)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.red : Color(.systemGray6))
                    .shadow(color: isSelected ? Color.red.opacity(0.4) : Color.black.opacity(0.1),
                           radius: isSelected ? 12 : 4,
                           x: 0,
                           y: isSelected ? 8 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.red : Color.clear, lineWidth: 3)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(y: yOffset)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: scale)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: opacity)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: yOffset)
    }
}

// MARK: - Mistake Question List View
struct MistakeQuestionListView: View {
    let subject: String
    let baseBranch: String?  // NEW: Hierarchical filter
    let detailedBranch: String?  // NEW: Hierarchical filter
    let errorType: String?  // NEW: Error type filter
    let timeRange: MistakeTimeRange

    @StateObject private var mistakeService = MistakeReviewService()
    @State private var selectedQuestions: Set<String> = []
    @State private var isSelectionMode = false
    @State private var showingPDFGenerator = false
    @State private var isGeneratingPractice = false
    @State private var generatedQuestions: [String] = []
    @State private var showingPracticeQuestions = false
    @State private var generationError: String? = nil // ✅ OPTIMIZATION: Error handling
    @Environment(\.dismiss) private var dismiss

    // MARK: - Computed Properties

    /// Filter mistakes by hierarchical filters
    private var filteredMistakes: [MistakeQuestion] {
        var filtered = mistakeService.mistakes

        // Filter by base branch
        if let baseBranch = baseBranch {
            filtered = filtered.filter { $0.baseBranch == baseBranch }
        }

        // Filter by detailed branch
        if let detailedBranch = detailedBranch {
            filtered = filtered.filter { $0.detailedBranch == detailedBranch }
        }

        // Filter by error type
        if let errorType = errorType {
            filtered = filtered.filter { $0.errorType == errorType }
        }

        return filtered
    }

    var body: some View {
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

                                Text(NSLocalizedString("mistakeReview.letsDoAgain", comment: ""))
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

                //✅ Generate Practice Button (ENHANCED with error analysis)
                if isSelectionMode && !selectedQuestions.isEmpty {
                    Button(action: {
                        Task {
                            await generatePracticeFromMistakes()
                        }
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
            // ✅ OPTIMIZATION: Error alert for practice generation
            .alert("Practice Generation Failed", isPresented: .constant(generationError != nil)) {
                Button("Retry") {
                    Task {
                        await generatePracticeFromMistakes()
                    }
                }
                Button("Cancel", role: .cancel) {
                    generationError = nil
                }
            } message: {
                Text(generationError ?? "An unknown error occurred")
            }
        }
    }

    // ✅ OPTIMIZED: Generate practice from selected mistakes with validation and error handling
    private func generatePracticeFromMistakes() async {
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

            // ✅ OPTIMIZATION: Use error analysis fields from model (no double fetch!)
            let mistakesData: [[String: Any]] = selectedMistakes.map { mistake in
                var data: [String: Any] = [
                    "question_text": mistake.rawQuestionText,
                    "student_answer": mistake.studentAnswer,
                    "correct_answer": mistake.correctAnswer,
                    "subject": mistake.subject
                ]

                // Add error analysis fields (already in model!)
                if let errorType = mistake.errorType {
                    data["error_type"] = errorType
                }
                if let errorEvidence = mistake.errorEvidence {
                    data["error_evidence"] = errorEvidence
                }
                if let primaryConcept = mistake.primaryConcept {
                    data["primary_concept"] = primaryConcept
                }
                if let secondaryConcept = mistake.secondaryConcept {
                    data["secondary_concept"] = secondaryConcept
                }

                return data
            }

            // ✅ SECURITY: Validate count using constants
            let requestedCount = min(selectedMistakes.count * AppConstants.practiceQuestionsMultiplier,
                                    AppConstants.maxPracticeQuestions)

            // ✅ SECURITY: Use environment variable for URL (configurable)
            let baseURL = ProcessInfo.processInfo.environment["BACKEND_URL"] ?? "https://sai-backend-production.up.railway.app"
            guard let url = URL(string: "\(baseURL)/api/ai/generate-from-mistakes") else {
                throw PracticeGenerationError.invalidURL
            }

            guard let token = AuthenticationService.shared.getAuthToken() else {
                throw PracticeGenerationError.notAuthenticated
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = AppConstants.apiTimeoutSeconds

            let requestBody: [String: Any] = [
                "subject": subject,
                "mistakes_data": mistakesData,
                "count": requestedCount
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PracticeGenerationError.invalidResponse
            }

            // ✅ BETTER ERROR HANDLING: Check status codes
            switch httpResponse.statusCode {
            case 200...299:
                // Success - parse response
                break
            case 401:
                throw PracticeGenerationError.notAuthenticated
            case 429:
                throw PracticeGenerationError.rateLimitExceeded
            case 500...599:
                throw PracticeGenerationError.serverError
            default:
                throw PracticeGenerationError.httpError(httpResponse.statusCode)
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let questions = json["questions"] as? [[String: Any]] {

                // Extract question texts
                generatedQuestions = questions.compactMap { q in
                    q["question"] as? String
                }

                // Show success
                await MainActor.run {
                    showingPracticeQuestions = true
                }
            } else {
                throw PracticeGenerationError.invalidResponseFormat
            }

        } catch let error as PracticeGenerationError {
            generationError = error.localizedDescription
        } catch {
            generationError = "An unexpected error occurred. Please try again."
        }
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

    @State private var showingExplanation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Selection header
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
                .padding(.bottom, 8)
            }
            // Question with subquestion hierarchy support
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("mistakeReview.questionLabel", comment: ""))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                // ✅ Render with subquestion support (match Library approach)
                SubquestionAwareTextView(
                    text: question.rawQuestionText,
                    fontSize: 16
                )
                .textSelection(.enabled)
                .onAppear {
                    #if DEBUG
                    print("🖼️ [MistakeReview-Render] Question ID: \(question.id) - questionImageUrl: '\(question.questionImageUrl ?? "nil")'")
                    #endif
                }

                // ✅ Add image rendering for Pro Mode questions
                if let imageUrl = question.questionImageUrl, !imageUrl.isEmpty {
                    QuestionImageView(imageUrl: imageUrl)
                        .padding(.top, 8)
                        .onAppear {
                            #if DEBUG
                            print("🖼️ [MistakeReview-Render] ✅ RENDERING QuestionImageView with imageUrl: '\(imageUrl)'")
                            #endif
                        }
                } else {
                    EmptyView()
                        .onAppear {
                            #if DEBUG
                            print("🖼️ [MistakeReview-Render] ❌ NOT RENDERING - imageUrl is: '\(question.questionImageUrl ?? "nil")'")
                            #endif
                        }
                }
            }

            // ✅ OPTIMIZATION: Error Analysis Visualization (always visible if available)
            if question.hasErrorAnalysis {
                errorAnalysisSection
            } else if question.isAnalyzing {
                analyzingSection
            }

            // ✅ FOLDED SECTION: Answer Details & Explanation
            Button(action: {
                showingExplanation.toggle()
                #if DEBUG
                if showingExplanation {
                    // Detailed logs when unfolding
                    print("📋 [MistakeReview-Detail] === UNFOLDING QUESTION DETAILS ===")
                    print("   Question ID: \(question.id)")
                    print("   Subject: \(question.subject)")
                    print("   Created At: \(question.createdAt)")
                    print("   Raw Question Text Length: \(question.rawQuestionText.count) chars")
                    print("   Raw Question Text: \(question.rawQuestionText.prefix(100))...")
                    print("   Question Preview (short): \(question.question.prefix(50))...")
                    print("   Student Answer: \(question.studentAnswer.prefix(50))...")
                    print("   Correct Answer: \(question.correctAnswer.prefix(50))...")
                    print("   Explanation: \(question.explanation.prefix(50))...")
                    print("   Has Image: \(question.questionImageUrl != nil)")
                    if let imageUrl = question.questionImageUrl {
                        print("   Image URL: \(imageUrl)")
                        print("   Image file exists: \(FileManager.default.fileExists(atPath: imageUrl))")
                    }
                    print("   Points: \(question.pointsEarned)/\(question.pointsPossible)")
                    print("   Confidence: \(question.confidence)")
                    print("   Has Error Analysis: \(question.hasErrorAnalysis)")
                    if question.hasErrorAnalysis {
                        print("   Error Type: \(question.errorType ?? "N/A")")
                        print("   Primary Concept: \(question.primaryConcept ?? "N/A")")
                        print("   Secondary Concept: \(question.secondaryConcept ?? "N/A")")
                        print("   Weakness Key: \(question.weaknessKey ?? "N/A")")
                    }
                    print("   Tags: \(question.tags)")
                    print("   Notes: \(question.notes)")
                    print("📋 [MistakeReview-Detail] === END DETAILS ===\n")
                }
                #endif
            }) {
                HStack {
                    Image(systemName: showingExplanation ? "chevron.down" : "chevron.right")
                    Text(showingExplanation ? "Hide Details" : "Show Answer & Explanation")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())

            if showingExplanation {
                VStack(alignment: .leading, spacing: 16) {
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

            // Footer with metadata (subject badge removed, only date)
            HStack {
                Spacer()

                Text(RelativeDateTimeFormatter().localizedString(for: question.createdAt, relativeTo: Date()))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(isSelectionMode && isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelectionMode && isSelected ? Color.blue : Color.clear, lineWidth: 2)
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
    let questions: [String]
    let subject: String
    @Environment(\.dismiss) private var dismiss

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

                    // Questions
                    ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Question \(index + 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(question)
                                .font(.body)

                            // Answer space
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your Answer:")
                                    .font(.caption)
                                    .fontWeight(.semibold)

                                TextEditor(text: .constant(""))
                                    .frame(height: 80)
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 2)
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
                        let isSubquestion = part.lowercased().contains("subquestion") || isSubquestionFormat(part)
                        print("")
                        print("   📋 Part \(index + 1):")
                        print("      Content: \(part.prefix(50))...")
                        print("      Contains 'subquestion': \(part.lowercased().contains("subquestion"))")
                        print("      Matches regex pattern: \(isSubquestionFormat(part))")
                        print("      → Rendering as: \(isSubquestion ? "✅ SUBQUESTION (with arrow)" : "⚪ PARENT (regular text)")")
                        return ()
                    }()
                    #endif

                    VStack(alignment: .leading, spacing: 8) {
                        // Highlight subquestion part if it contains "Subquestion" or starts with a letter/number + ")"
                        if part.lowercased().contains("subquestion") || isSubquestionFormat(part) {
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


#Preview {
    MistakeReviewView()
}