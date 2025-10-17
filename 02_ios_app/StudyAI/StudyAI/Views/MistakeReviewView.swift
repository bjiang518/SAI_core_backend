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
                                .font(.title2)
                                .foregroundColor(.orange)

                            Text("Learn from your mistakes")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }

                        Text("Select a subject and time range to review questions you got wrong")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)

                    // Time Range Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Time Range")
                            .font(.headline)

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
                            Text("Subjects with Mistakes")
                                .font(.headline)

                            if let timeRange = selectedTimeRange {
                                Text("(\(timeRange.rawValue))")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }

                        if mistakeService.isLoading {
                            ProgressView("Loading subjects...")
                                .frame(height: 100)
                        } else if mistakeService.subjectsWithMistakes.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.green)

                                Text("No mistakes found!")
                                    .font(.headline)
                                    .foregroundColor(.green)

                                Text("Great job! You haven't made any mistakes in the selected time range.")
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
                                    .font(.title2)

                                Text("Start Review")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Mistake Review")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
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
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)

                Text(range.rawValue)
                    .font(.caption)
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
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .red)

                Text(subject.subject)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)

                Text("\(subject.mistakeCount) mistake\(subject.mistakeCount == 1 ? "" : "s")")
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
                                    .font(.title2)

                                Text("Let's do them again")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
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
                            Text(selectedQuestions.count == mistakeService.mistakes.count ? "Deselect All" : "Select All")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }

                        Spacer()

                        Text("\(selectedQuestions.count) selected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: {
                            isSelectionMode = false
                            selectedQuestions.removeAll()
                        }) {
                            Text("Cancel")
                                .font(.subheadline)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                Group {
                    if mistakeService.isLoading {
                        ProgressView("Loading mistakes...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if mistakeService.mistakes.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(.green)

                            Text("No mistakes found!")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("You haven't made any mistakes in \(subject.lowercased()) during this time period.")
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
                                .font(.title2)

                            Text("Generate PDF (\(selectedQuestions.count) questions)")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("\(subject) Mistakes")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
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
                                .font(.title2)

                            Text(isSelected ? "Selected" : "Select")
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
                Text("Question:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text(question.rawQuestionText)  // ✅ Display full original question from image
                    .font(.body)
                    .fontWeight(.medium)
            }

            // Your incorrect answer
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Answer:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text(question.studentAnswer.isEmpty ? "No answer provided" : question.studentAnswer)
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
                Text("Correct Answer:")
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
                        Text("Show Explanation")
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