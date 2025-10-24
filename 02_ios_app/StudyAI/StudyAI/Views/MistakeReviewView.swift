//
//  MistakeReviewView.swift
//  StudyAI
//
//  Created by Claude Code on 9/20/25.
//

import SwiftUI

// MARK: - Main View
struct MistakeReviewView: View {
    @StateObject private var mistakeService = MistakeReviewService()
    @State private var selectedSubject: String?
    @State private var selectedTimeRange: MistakeTimeRange? = nil
    @State private var showingMistakeList = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.title)
                                .foregroundColor(.orange)

                            Text(NSLocalizedString("mistakeReview.header.title", comment: ""))
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }

                        Text(NSLocalizedString("mistakeReview.header.subtitle", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)

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
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
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

                // Generate PDF Button
                if isSelectionMode && !selectedQuestions.isEmpty {
                    Button(action: {
                        showingPDFGenerator = true
                    }) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .font(.title3)

                            Text(String.localizedStringWithFormat(NSLocalizedString("mistakeReview.generatePDF", comment: ""), selectedQuestions.count))
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

                Text(question.rawQuestionText)  // ✅ Display full original question from image
                    .font(.body)
                    .fontWeight(.medium)
            }

            // Your incorrect answer
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("mistakeReview.yourAnswerLabel", comment: ""))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text(question.studentAnswer.isEmpty ?
                     NSLocalizedString("mistakeReview.noAnswer", comment: "") :
                     question.studentAnswer)
                    .font(.body)
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

                Text(question.correctAnswer)
                    .font(.body)
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
                    Text(question.explanation)
                        .font(.caption)
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
}

#Preview {
    MistakeReviewView()
}