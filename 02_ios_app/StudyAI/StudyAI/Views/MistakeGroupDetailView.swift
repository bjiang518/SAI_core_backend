//
//  MistakeGroupDetailView.swift
//  StudyAI
//
//  Detailed view for mistakes within a specific error type group
//

import SwiftUI

struct MistakeGroupDetailView: View {
    let group: MistakeGroup
    @State private var expandedMistakeIds: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Group Header
                groupHeaderCard

                // Mistakes list
                ForEach(group.mistakes) { mistake in
                    MistakeCard(
                        mistake: mistake,
                        isExpanded: expandedMistakeIds.contains(mistake.id)
                    ) {
                        toggleExpanded(mistake.id)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(group.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var groupHeaderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: group.icon)
                    .foregroundColor(group.color)
                    .font(.title)

                VStack(alignment: .leading) {
                    Text(group.displayName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(group.count) mistake\(group.count == 1 ? "" : "s") in this category")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    private func toggleExpanded(_ id: String) {
        if expandedMistakeIds.contains(id) {
            expandedMistakeIds.remove(id)
        } else {
            expandedMistakeIds.insert(id)
        }
    }
}

// MARK: - Mistake Card

struct MistakeCard: View {
    let mistake: LocalMistake
    let isExpanded: Bool
    let onTap: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question
            VStack(alignment: .leading, spacing: 6) {
                Text("Question")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                SmartLaTeXView(mistake.questionText, fontSize: 14, colorScheme: colorScheme, strategy: .mathjax)
            }

            // Your answer (wrong)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your Answer")
                    .font(.caption)
                    .foregroundColor(.red)
                    .textCase(.uppercase)

                SmartLaTeXView(mistake.studentAnswer.isEmpty ? "No answer" : mistake.studentAnswer, fontSize: 14, colorScheme: colorScheme, strategy: .mathjax)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.1))
            )

            // Correct answer
            VStack(alignment: .leading, spacing: 6) {
                Text("Correct Answer")
                    .font(.caption)
                    .foregroundColor(.green)
                    .textCase(.uppercase)

                SmartLaTeXView(mistake.correctAnswer, fontSize: 14, colorScheme: colorScheme, strategy: .mathjax)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.1))
            )

            // Error analysis (if available)
            if mistake.errorAnalysisStatus == "completed" {
                Button(action: onTap) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)

                        Text("View Analysis")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.yellow.opacity(0.1))
                    )
                }
                .buttonStyle(PlainButtonStyle())

                if isExpanded {
                    AnalysisDetailView(mistake: mistake)
                        .transition(.opacity)
                }
            } else if mistake.errorAnalysisStatus == "pending" || mistake.errorAnalysisStatus == "processing" {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Analyzing mistake...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            } else if mistake.errorAnalysisStatus == "failed" {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Analysis unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
        )
    }
}

// MARK: - Analysis Detail View

struct AnalysisDetailView: View {
    let mistake: LocalMistake

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Evidence
            if let evidence = mistake.errorEvidence {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("What Went Wrong")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }

                    SmartLaTeXView(evidence, fontSize: 14, colorScheme: colorScheme, strategy: .mathjax)
                }
            }

            Divider()

            // Learning suggestion
            if let suggestion = mistake.learningSuggestion {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("How to Improve")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                    }

                    SmartLaTeXView(suggestion, fontSize: 14, colorScheme: colorScheme, strategy: .mathjax)
                }
            }

            // Debug info (optional)
            #if DEBUG
            if let errorType = mistake.errorType {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEBUG INFO")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text("Error Type: \(errorType)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let confidence = mistake.errorConfidence {
                        Text("Confidence: \(String(format: "%.2f", confidence))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("Status: \(mistake.errorAnalysisStatus)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.1))
                )
            }
            #endif
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Preview

struct MistakeGroupDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MistakeGroupDetailView(
                group: MistakeGroup(
                    errorType: "procedural_error",
                    mistakes: [
                        LocalMistake(
                            id: "1",
                            questionText: "Solve for x: 2x + 5 = 13",
                            studentAnswer: "x = 9",
                            correctAnswer: "x = 4",
                            subject: "Algebra",
                            errorType: "procedural_error",
                            errorEvidence: "Student added 5 instead of subtracting",
                            errorConfidence: 0.9,
                            learningSuggestion: "Remember to do the inverse operation",
                            errorAnalysisStatus: "completed",
                            archivedAt: "2025-01-25T12:00:00Z"
                        )
                    ],
                    count: 1
                )
            )
        }
    }
}
