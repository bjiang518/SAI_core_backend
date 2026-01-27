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
    @State private var showingMistakeList = false
    @State private var showingInstructions = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // ✅ NEW: Recent Mistakes Section (Active Weaknesses)
                    RecentMistakesSection()

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

                    // Subject Selection
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
                            .frame(height: 150)
                        } else {
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 16) {
                                ForEach(mistakeService.subjectsWithMistakes) { subject in
                                    SubjectCard(
                                        subject: subject,
                                        isSelected: selectedSubject == subject.subject,
                                        action: { selectedSubject = subject.subject }
                                    )
                                }
                            }
                        }
                    }

                    // Review Button
                    if selectedSubject != nil && !mistakeService.subjectsWithMistakes.isEmpty {
                        Button(action: {
                            showingMistakeList = true
                        }) {
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)

                                Text(NSLocalizedString("mistakeReview.startReview", comment: ""))
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
                        timeRange: selectedTimeRange ?? .allTime
                    )
                }
            }
        }
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

struct SubjectCard: View {
    let subject: SubjectMistakeCount
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: subject.icon)
                    .font(.title3)
                    .foregroundColor(isSelected ? .white : .red)

                Text(subject.subject)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)

                Text(subject.mistakeCount == 1 ?
                     NSLocalizedString("mistakeReview.mistakeSingular", comment: "") :
                     String.localizedStringWithFormat(NSLocalizedString("mistakeReview.mistakePlural", comment: ""), subject.mistakeCount))
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(height: 100)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.red : Color.red.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.red : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Mistake Question List View
struct MistakeQuestionListView: View {
    let subject: String
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

    var body: some View {
        NavigationView {
            VStack {
                // Selection Mode Buttons
                if !mistakeService.mistakes.isEmpty && !isSelectionMode {
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
                            if selectedQuestions.count == mistakeService.mistakes.count {
                                selectedQuestions.removeAll()
                            } else {
                                selectedQuestions = Set(mistakeService.mistakes.map { $0.id })
                            }
                        }) {
                            Text(selectedQuestions.count == mistakeService.mistakes.count ?
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
                    } else if mistakeService.mistakes.isEmpty {
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
                            ForEach(mistakeService.mistakes) { mistake in
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
                    let selectedMistakes = mistakeService.mistakes.filter { selectedQuestions.contains($0.id) }
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
            let selectedMistakes = mistakeService.mistakes.filter { selectedQuestions.contains($0.id) }

            #if DEBUG
            print("🎯 [Practice] Generating from \(selectedMistakes.count) selected mistakes")
            #endif

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
                    #if DEBUG
                    print("   ✓ Error type: \(errorType)")
                    #endif
                }
                if let errorEvidence = mistake.errorEvidence {
                    data["error_evidence"] = errorEvidence
                }
                if let primaryConcept = mistake.primaryConcept {
                    data["primary_concept"] = primaryConcept
                    #if DEBUG
                    print("   ✓ Concept: \(primaryConcept)")
                    #endif
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

                #if DEBUG
                print("✅ [Practice] Generated \(generatedQuestions.count) questions")
                #endif

                // Show success
                await MainActor.run {
                    showingPracticeQuestions = true
                }
            } else {
                throw PracticeGenerationError.invalidResponseFormat
            }

        } catch let error as PracticeGenerationError {
            #if DEBUG
            print("❌ [Practice] Validation error: \(error.localizedDescription)")
            #endif
            generationError = error.localizedDescription
        } catch {
            #if DEBUG
            print("❌ [Practice] Unexpected error: \(error.localizedDescription)")
            #endif
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
            // Question
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("mistakeReview.questionLabel", comment: ""))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                // ✅ Use EnhancedMathText for LaTeX/math rendering
                EnhancedMathText(question.rawQuestionText, fontSize: 16)
                    .fontWeight(.medium)
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

            // ✅ OPTIMIZATION: Error Analysis Visualization
            if question.hasErrorAnalysis {
                errorAnalysisSection
            } else if question.isAnalyzing {
                analyzingSection
            }

            // Explanation toggle
            if !question.explanation.isEmpty && question.explanation != "No explanation provided" {
                Button(action: { showingExplanation.toggle() }) {
                    HStack {
                        Image(systemName: showingExplanation ? "chevron.down" : "chevron.right")
                        Text(NSLocalizedString("mistakeReview.showExplanation", comment: ""))
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }

                if showingExplanation {
                    // ✅ Use EnhancedMathText for math support in explanations
                    EnhancedMathText(question.explanation, fontSize: 13)
                        .padding(.top, 4)
                        .foregroundColor(.secondary)
                }
            }

            // Footer with metadata
            HStack {
                Text(question.subject)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)

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
            // Error type badge
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

            // What went wrong
            if let evidence = question.errorEvidence {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("What Went Wrong")
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

            // Learning suggestion
            if let suggestion = question.learningSuggestion {
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

    // Helper functions for error type display
    private func errorDisplayName(for errorType: String) -> String {
        switch errorType {
        case "conceptual_misunderstanding": return "Conceptual Error"
        case "procedural_error": return "Process Error"
        case "calculation_mistake": return "Calculation Error"
        case "careless_mistake": return "Careless Error"
        case "reading_comprehension": return "Reading Error"
        case "incomplete_answer": return "Incomplete Answer"
        case "wrong_method": return "Wrong Method"
        case "memory_lapse": return "Memory Lapse"
        case "time_pressure": return "Time Pressure"
        default: return "Other Error"
        }
    }

    private func errorIcon(for errorType: String) -> String {
        switch errorType {
        case "conceptual_misunderstanding": return "brain.head.profile"
        case "procedural_error": return "list.bullet.clipboard"
        case "calculation_mistake": return "function"
        case "careless_mistake": return "exclamationmark.circle"
        case "reading_comprehension": return "book"
        case "incomplete_answer": return "ellipsis.circle"
        case "wrong_method": return "arrow.triangle.branch"
        case "memory_lapse": return "questionmark.circle"
        case "time_pressure": return "clock"
        default: return "questionmark"
        }
    }

    private func errorColor(for errorType: String) -> Color {
        switch errorType {
        case "conceptual_misunderstanding": return .purple
        case "procedural_error": return .blue
        case "calculation_mistake": return .orange
        case "careless_mistake": return .yellow
        case "reading_comprehension": return .green
        case "incomplete_answer": return .pink
        case "wrong_method": return .red
        case "memory_lapse": return .gray
        case "time_pressure": return .brown
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

#Preview {
    MistakeReviewView()
}