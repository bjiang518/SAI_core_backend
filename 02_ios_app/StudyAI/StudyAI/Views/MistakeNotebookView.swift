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

    var body: some View {
        NavigationView {
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

    private let localStorage = QuestionLocalStorage.shared

    /// Load mistakes from LOCAL storage (primary source)
    func loadLocalMistakes() async {
        isLoading = true
        defer { isLoading = false }

        // Get all wrong questions from local storage
        let allQuestions = localStorage.getLocalQuestions()
        let mistakes = allQuestions.filter { ($0["isCorrect"] as? Bool) == false }

        // Group by error type
        var grouped: [String: [LocalMistake]] = [:]

        for mistakeData in mistakes {
            let errorType = (mistakeData["errorType"] as? String)?.isEmpty == false
                ? (mistakeData["errorType"] as? String ?? "analyzing")
                : "analyzing"

            let mistake = LocalMistake(
                id: mistakeData["id"] as? String ?? "",
                questionText: mistakeData["questionText"] as? String ?? "",
                studentAnswer: mistakeData["studentAnswer"] as? String ?? "",
                correctAnswer: mistakeData["answerText"] as? String ?? "",
                subject: mistakeData["subject"] as? String ?? "",
                errorType: mistakeData["errorType"] as? String,
                errorEvidence: mistakeData["errorEvidence"] as? String,
                errorConfidence: mistakeData["errorConfidence"] as? Double,
                learningSuggestion: mistakeData["learningSuggestion"] as? String,
                errorAnalysisStatus: mistakeData["errorAnalysisStatus"] as? String ?? "pending",
                archivedAt: mistakeData["archivedAt"] as? String ?? ""
            )

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

        print("📚 [Notebook] Loaded \(mistakes.count) mistakes from local storage")
        print("📊 [Notebook] Grouped into \(mistakeGroups.count) error types")
    }
}

// MARK: - Models

struct MistakeGroup: Identifiable {
    var id: String { errorType }
    let errorType: String
    let mistakes: [LocalMistake]
    let count: Int

    var displayName: String {
        errorType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var icon: String {
        switch errorType {
        case "conceptual_misunderstanding": return "brain.head.profile"
        case "procedural_error": return "list.bullet.clipboard"
        case "calculation_mistake": return "function"
        case "reading_comprehension": return "book.closed"
        case "notation_error": return "textformat"
        case "incomplete_work": return "doc.text"
        case "careless_mistake": return "exclamationmark.triangle"
        case "analyzing": return "ellipsis.circle"
        default: return "questionmark.circle"
        }
    }

    var color: Color {
        switch errorType {
        case "conceptual_misunderstanding": return .purple
        case "procedural_error": return .orange
        case "calculation_mistake": return .red
        case "reading_comprehension": return .blue
        case "notation_error": return .green
        case "incomplete_work": return .yellow
        case "careless_mistake": return .pink
        case "analyzing": return .gray
        default: return .secondary
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
}
