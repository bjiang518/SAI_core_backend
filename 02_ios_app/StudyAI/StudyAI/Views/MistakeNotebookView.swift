//
//  MistakeNotebookView.swift
//  StudyAI
//
//  Mistake Notebook with AI-powered error analysis
//  Reads from LOCAL storage (primary source)
//

import SwiftUI
import Combine

struct MistakeNotebookView: View {
    @StateObject private var viewModel = MistakeNotebookViewModel()
    @State private var selectedTag: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Recent mistakes from LOCAL storage
                    if viewModel.isLoading {
                        ProgressView("Loading mistakes from local storage...")
                            .padding()
                    } else if viewModel.mistakeGroups.isEmpty {
                        emptyStateView
                    } else {
                        // Error pattern summary (only when tags exist)
                        if !viewModel.topMicroTags.isEmpty {
                            ErrorPatternSummaryCard(
                                topTags: viewModel.topMicroTags,
                                onTagTap: { tag in selectedTag = tag }
                            )
                        }
                        mistakeGroupsList
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
            .task {
                await viewModel.loadLocalMistakes()
            }
            .refreshable {
                await viewModel.loadLocalMistakes()
            }
            .sheet(item: Binding(
                get: { selectedTag.map { TagSelection(tag: $0) } },
                set: { selectedTag = $0?.tag }
            )) { selection in
                TaggedMistakesSheet(
                    tag: selection.tag,
                    mistakes: viewModel.mistakes(for: selection.tag)
                )
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mistake Notebook")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Review your mistakes with AI-powered insights")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Analysis status indicator
            if ErrorAnalysisQueueService.shared.isAnalyzing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Analyzing mistakes...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Mistakes Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Complete homework to see mistake analysis here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var mistakeGroupsList: some View {
        ForEach(viewModel.mistakeGroups) { group in
            NavigationLink(destination: MistakeGroupDetailView(group: group)) {
                MistakeGroupCard(group: group)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

// MARK: - Mistake Group Card

struct MistakeGroupCard: View {
    let group: MistakeGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: group.icon)
                    .foregroundColor(group.color)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.displayName)
                        .font(.headline)

                    Text("\(group.count) mistake\(group.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Empty State View

struct EmptyNotebookView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Mistakes Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Complete homework to see mistake analysis here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - View Model

@MainActor
class MistakeNotebookViewModel: ObservableObject {
    @Published var mistakeGroups: [MistakeGroup] = []
    @Published var isLoading = false

    private let localStorage = currentUserQuestionStorage()
    private var rawMistakes: [[String: Any]] = []

    /// Top error micro tags across all mistakes, sorted by frequency.
    var topMicroTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for m in rawMistakes {
            for tag in (m["errorMicroTags"] as? [String] ?? []) {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    /// All mistakes that carry a given micro tag.
    func mistakes(for tag: String) -> [LocalMistake] {
        rawMistakes
            .filter { ($0["errorMicroTags"] as? [String] ?? []).contains(tag) }
            .map { LocalMistake(from: $0) }
    }

    /// Load mistakes from LOCAL storage (primary source)
    func loadLocalMistakes() async {
        isLoading = true
        defer { isLoading = false }

        // Get all wrong questions from local storage
        let allQuestions = localStorage.getLocalQuestions()
        let mistakes = allQuestions.filter { ($0["isCorrect"] as? Bool) == false }
        rawMistakes = mistakes

        // Group by error type
        var grouped: [String: [LocalMistake]] = [:]

        for mistakeData in mistakes {
            let errorType = (mistakeData["errorType"] as? String)?.isEmpty == false
                ? (mistakeData["errorType"] as? String ?? "analyzing")
                : "analyzing"

            let mistake = LocalMistake(from: mistakeData)

            if grouped[errorType] == nil {
                grouped[errorType] = []
            }
            grouped[errorType]?.append(mistake)
        }

        // Convert to groups
        mistakeGroups = grouped.map { errorType, mistakes in
            MistakeGroup(
                errorType: errorType,
                mistakes: mistakes,
                count: mistakes.count
            )
        }
        .sorted { $0.count > $1.count }

        debugPrint("📚 [Notebook] Loaded \(mistakes.count) mistakes from local storage")
        debugPrint("📊 [Notebook] Grouped into \(mistakeGroups.count) error types")
    }
}

// MARK: - Models

struct MistakeGroup: Identifiable {
    var id: String { errorType }
    let errorType: String
    let mistakes: [LocalMistake]
    let count: Int

    var displayName: String {
        switch errorType {
        case "execution_error":  return NSLocalizedString("mistakeReview.errorType.executionError", comment: "")
        case "conceptual_gap":   return NSLocalizedString("mistakeReview.errorType.conceptualGap", comment: "")
        case "needs_refinement": return NSLocalizedString("mistakeReview.errorType.needsRefinement", comment: "")
        default: return errorType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var icon: String {
        switch errorType {
        case "execution_error":  return "exclamationmark.triangle"
        case "conceptual_gap":   return "brain.head.profile"
        case "needs_refinement": return "sparkles"
        case "analyzing":        return "ellipsis.circle"
        default:                 return "questionmark.circle"
        }
    }

    var color: Color {
        switch errorType {
        case "execution_error":  return .orange
        case "conceptual_gap":   return .purple
        case "needs_refinement": return .blue
        case "analyzing":        return .gray
        default:                 return .secondary
        }
    }
}

struct LocalMistake: Identifiable {
    let id: String
    let questionText: String
    let studentAnswer: String
    let correctAnswer: String
    let subject: String
    let errorType: String?
    let errorEvidence: String?
    let errorConfidence: Double?
    let learningSuggestion: String?
    let errorAnalysisStatus: String
    let archivedAt: String
    let errorMicroTags: [String]

    init(from data: [String: Any]) {
        id                  = data["id"]                  as? String ?? ""
        questionText        = data["questionText"]        as? String ?? ""
        studentAnswer       = data["studentAnswer"]       as? String ?? ""
        correctAnswer       = data["answerText"]          as? String ?? ""
        subject             = data["subject"]             as? String ?? ""
        errorType           = data["errorType"]           as? String
        errorEvidence       = data["errorEvidence"]       as? String
        errorConfidence     = data["errorConfidence"]     as? Double
        learningSuggestion  = data["learningSuggestion"]  as? String
        errorAnalysisStatus = data["errorAnalysisStatus"] as? String ?? "pending"
        archivedAt          = data["archivedAt"]          as? String ?? ""
        errorMicroTags      = data["errorMicroTags"]      as? [String] ?? []
    }
}

// MARK: - Tag Selection (for .sheet(item:))

private struct TagSelection: Identifiable {
    let tag: String
    var id: String { tag }
}

// MARK: - Error Pattern Summary Card

struct ErrorPatternSummaryCard: View {
    let topTags: [(tag: String, count: Int)]
    let onTagTap: (String) -> Void

    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(DesignTokens.Colors.error)
                    .font(.caption)
                Text(NSLocalizedString("mistakeNotebook.recurringPatterns",
                                      value: "Recurring Error Patterns",
                                      comment: ""))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(topTags, id: \.tag) { item in
                        Button(action: { onTagTap(item.tag) }) {
                            HStack(spacing: 5) {
                                Text(TagLocalization.displayName(for: item.tag))
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                Text("×\(item.count)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(DesignTokens.Colors.error.opacity(0.15))
                                    .cornerRadius(8)
                            }
                            .foregroundColor(DesignTokens.Colors.error)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DesignTokens.Colors.error.opacity(0.08))
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DesignTokens.Colors.error.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Tagged Mistakes Sheet

struct TaggedMistakesSheet: View {
    let tag: String
    let mistakes: [LocalMistake]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationStack {
            List {
                ForEach(mistakes) { mistake in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mistake.subject)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SmartLaTeXView(mistake.questionText, fontSize: 14,
                                       colorScheme: colorScheme, strategy: .mathjax)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let suggestion = mistake.learningSuggestion, !suggestion.isEmpty {
                            Text(suggestion)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle(TagLocalization.displayName(for: tag))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) { dismiss() }
                }
            }
        }
    }
}
