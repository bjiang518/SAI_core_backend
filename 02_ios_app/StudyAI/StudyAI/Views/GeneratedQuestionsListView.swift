//
//  GeneratedQuestionsListView.swift
//  StudyAI
//
//  Created by Claude Code on 12/21/24.
//

import SwiftUI
import os.log

struct GeneratedQuestionsListView: View {
    let questions: [QuestionGenerationService.GeneratedQuestion]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedQuestion: QuestionGenerationService.GeneratedQuestion?
    @State private var showingQuestionDetail = false
    @State private var searchText = ""

    private let logger = Logger(subsystem: "com.studyai", category: "GeneratedQuestionsList")

    var filteredQuestions: [QuestionGenerationService.GeneratedQuestion] {
        if searchText.isEmpty {
            return questions
        }
        return questions.filter { question in
            question.question.localizedCaseInsensitiveContains(searchText) ||
            question.topic.localizedCaseInsensitiveContains(searchText) ||
            question.type.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                if questions.count > 3 {
                    searchSection
                }

                // Questions List
                if filteredQuestions.isEmpty {
                    emptyStateView
                } else {
                    questionsListSection
                }
            }
            .navigationTitle("Generated Questions")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(trailing: closeButton)
            .sheet(isPresented: $showingQuestionDetail) {
                if let selectedQuestion = selectedQuestion {
                    GeneratedQuestionDetailView(question: selectedQuestion)
                }
            }
            .onAppear {
                logger.info("📝 Generated questions list appeared with \(questions.count) questions")
            }
        }
    }

    private var searchSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundColor(.secondary)

                TextField("Search questions or topics...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // Filter summary
            HStack {
                Text("\(filteredQuestions.count) of \(questions.count) questions")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Spacer()

                if !searchText.isEmpty {
                    Text("Filtered by: \"\(searchText)\"")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var questionsListSection: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(filteredQuestions) { question in
                    QuestionListCard(
                        question: question,
                        onTap: {
                            selectedQuestion = question
                            showingQuestionDetail = true
                        }
                    )
                }

                // Stats Summary at bottom
                if filteredQuestions.count == questions.count {
                    questionsSummary
                        .padding(.top, 24)
                }
            }
            .padding()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "questionmark.folder")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text(searchText.isEmpty ? "No Questions Generated" : "No Matching Questions")
                    .font(.title3)
                    .fontWeight(.medium)

                Text(searchText.isEmpty ?
                     "Questions will appear here after generation" :
                     "Try adjusting your search terms")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !searchText.isEmpty {
                Button("Clear Search") {
                    searchText = ""
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }

            Spacer()
        }
        .padding()
    }

    private var questionsSummary: some View {
        VStack(spacing: 20) {
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("Question Summary")
                    .font(.title3)
                    .fontWeight(.semibold)

                // Type breakdown
                let typeBreakdown = Dictionary(grouping: questions) { $0.type }
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(Array(typeBreakdown.keys), id: \.self) { type in
                        SummaryCard(
                            title: type.displayName,
                            count: typeBreakdown[type]?.count ?? 0,
                            icon: type.icon,
                            color: .blue
                        )
                    }
                }

                // Difficulty breakdown
                let difficultyBreakdown = Dictionary(grouping: questions) { $0.difficulty }
                HStack(spacing: 20) {
                    ForEach(Array(difficultyBreakdown.keys.sorted()), id: \.self) { difficulty in
                        VStack(spacing: 4) {
                            Text("\(difficultyBreakdown[difficulty]?.count ?? 0)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(difficultyColor(difficulty))

                            Text(difficulty.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    private var closeButton: some View {
        Button("Done") {
            dismiss()
        }
        .font(.body.bold())
    }

    private func difficultyColor(_ difficulty: String) -> Color {
        switch difficulty.lowercased() {
        case "beginner": return .green
        case "intermediate": return .orange
        case "advanced": return .red
        default: return .gray
        }
    }
}

struct QuestionListCard: View {
    let question: QuestionGenerationService.GeneratedQuestion
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with type and difficulty
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: question.typeIcon)
                            .font(.body)
                            .foregroundColor(question.difficultyColor)

                        Text(question.type.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(question.difficultyColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(question.difficultyColor.opacity(0.1))
                    .cornerRadius(6)

                    Spacer()

                    Text(question.difficulty.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }

                // Question text
                Text(question.question)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                // Topic and metadata
                HStack {
                    Label(question.topic, systemImage: "tag.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let timeEstimate = question.timeEstimate {
                        Label(timeEstimate, systemImage: "clock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let points = question.points {
                        Label("\(points) pts", systemImage: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                // Preview of answer/explanation
                if !question.explanation.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)

                        Text(question.explanation.prefix(80) + (question.explanation.count > 80 ? "..." : ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.top, 4)
                }

                // Footer
                HStack {
                    Spacer()

                    HStack(spacing: 4) {
                        Text("View Details")
                            .font(.caption)
                            .foregroundColor(.blue)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SummaryCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.body.bold())
                    .foregroundColor(.primary)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.05))
        .cornerRadius(8)
    }
}

#Preview {
    let sampleQuestions = [
        QuestionGenerationService.GeneratedQuestion(
            question: "What is the derivative of x² + 3x - 5?",
            type: .calculation,
            correctAnswer: "2x + 3",
            explanation: "Using the power rule, the derivative of x² is 2x, and the derivative of 3x is 3.",
            topic: "Calculus",
            difficulty: "intermediate",
            points: 10,
            timeEstimate: "2 min",
            options: nil
        ),
        QuestionGenerationService.GeneratedQuestion(
            question: "Which of the following is a prime number?",
            type: .multipleChoice,
            correctAnswer: "17",
            explanation: "17 is only divisible by 1 and itself, making it a prime number.",
            topic: "Number Theory",
            difficulty: "beginner",
            points: 5,
            timeEstimate: "1 min",
            options: ["15", "16", "17", "18"]
        )
    ]

    GeneratedQuestionsListView(questions: sampleQuestions)
}