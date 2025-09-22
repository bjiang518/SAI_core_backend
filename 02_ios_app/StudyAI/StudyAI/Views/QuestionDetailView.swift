//
//  QuestionDetailView.swift
//  StudyAI
//
//  Created by Claude Code on 12/21/24.
//

import SwiftUI
import os.log

struct GeneratedQuestionDetailView: View {
    let question: QuestionGenerationService.GeneratedQuestion
    @Environment(\.dismiss) private var dismiss
    @State private var userAnswer = ""
    @State private var selectedOption: String?
    @State private var hasSubmitted = false
    @State private var showingExplanation = false
    @State private var isCorrect = false

    private let logger = Logger(subsystem: "com.studyai", category: "QuestionDetail")

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Question Header
                    questionHeader

                    // Question Content
                    questionContent

                    // Answer Input Section
                    answerInputSection

                    // Submit Button
                    if !hasSubmitted {
                        submitButton
                    }

                    // Results Section
                    if hasSubmitted {
                        resultsSection
                    }

                    // Explanation Section
                    if showingExplanation {
                        explanationSection
                    }

                    // Question Metadata
                    questionMetadata

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .navigationTitle("Question Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: closeButton)
            .onAppear {
                logger.info("📝 Question detail view appeared for: \(question.type.displayName)")
            }
        }
    }

    private var questionHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Type and Difficulty Tags
            HStack {
                Label(question.type.displayName, systemImage: question.typeIcon)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(question.difficultyColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(question.difficultyColor.opacity(0.1))
                    .cornerRadius(20)

                Text(question.difficulty.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(question.difficultyColor)
                    .cornerRadius(20)

                Spacer()

                if let points = question.points {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("\(points) pts")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                }
            }

            // Topic and Time Estimate
            HStack {
                Label(question.topic, systemImage: "tag.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if let timeEstimate = question.timeEstimate {
                    Label(timeEstimate, systemImage: "clock.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Question")
                .font(.title3)
                .fontWeight(.semibold)

            Text(question.question)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        }
    }

    private var answerInputSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Your Answer")
                .font(.title3)
                .fontWeight(.semibold)

            Group {
                switch question.type {
                case .multipleChoice:
                    multipleChoiceInput
                case .trueFalse:
                    trueFalseInput
                case .shortAnswer, .calculation, .essay:
                    textAnswerInput
                }
            }
            .disabled(hasSubmitted)
        }
    }

    private var multipleChoiceInput: some View {
        VStack(spacing: 12) {
            if let options = question.options {
                ForEach(options, id: \.self) { option in
                    Button(action: { selectedOption = option }) {
                        HStack {
                            Image(systemName: selectedOption == option ? "largecircle.fill.circle" : "circle")
                                .font(.title3)
                                .foregroundColor(selectedOption == option ? .blue : .secondary)

                            Text(option)
                                .font(.body)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                        .padding()
                        .background(selectedOption == option ? Color.blue.opacity(0.05) : Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedOption == option ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var trueFalseInput: some View {
        HStack(spacing: 24) {
            Button(action: { selectedOption = "True" }) {
                HStack {
                    Image(systemName: selectedOption == "True" ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(selectedOption == "True" ? .green : .secondary)

                    Text("True")
                        .font(.body.bold())
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedOption == "True" ? Color.green.opacity(0.05) : Color.gray.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selectedOption == "True" ? Color.green : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: { selectedOption = "False" }) {
                HStack {
                    Image(systemName: selectedOption == "False" ? "xmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(selectedOption == "False" ? .red : .secondary)

                    Text("False")
                        .font(.body.bold())
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedOption == "False" ? Color.red.opacity(0.05) : Color.gray.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selectedOption == "False" ? Color.red : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private var textAnswerInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            if question.type == .essay {
                TextEditor(text: $userAnswer)
                    .frame(minHeight: 120)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            } else {
                TextField("Enter your answer...", text: $userAnswer)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            }

            Text(question.type == .essay ? "Provide a detailed explanation" : "Type your answer above")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var submitButton: some View {
        Button(action: submitAnswer) {
            HStack(spacing: 12) {
                Image(systemName: "paperplane.fill")
                    .font(.headline)

                Text("Submit Answer")
                    .font(.body.bold())
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [.blue, .blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .disabled(!canSubmit())
        }
        .opacity(canSubmit() ? 1.0 : 0.6)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Results")
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 24) {
                // Correctness indicator
                HStack(spacing: 12) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(isCorrect ? .green : .red)

                    Text(isCorrect ? "Correct!" : "Incorrect")
                        .font(.body.bold())
                        .foregroundColor(isCorrect ? .green : .red)
                }

                Spacer()

                Button(action: { showingExplanation.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.body)

                        Text(showingExplanation ? "Hide Explanation" : "Show Explanation")
                            .font(.subheadline)
                    }
                    .foregroundColor(.blue)
                }
            }

            // Answer comparison
            VStack(alignment: .leading, spacing: 16) {
                // User's answer
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Answer:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(getCurrentAnswer())
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding()
                        .background(isCorrect ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isCorrect ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
                        )
                }

                // Correct answer
                VStack(alignment: .leading, spacing: 12) {
                    Text("Correct Answer:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(question.correctAnswer)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding()
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.title3)
                    .foregroundColor(.yellow)

                Text("Explanation")
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            Text(question.explanation)
                .font(.body)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)

        }
        .padding()
        .background(Color.yellow.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }

    private var questionMetadata: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Question Info")
                .font(.title3)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                MetadataRow(label: "Type", value: question.type.displayName, icon: question.typeIcon)
                MetadataRow(label: "Topic", value: question.topic, icon: "tag")
                MetadataRow(label: "Difficulty", value: question.difficulty.capitalized, icon: "chart.bar")

                if let timeEstimate = question.timeEstimate {
                    MetadataRow(label: "Time Estimate", value: timeEstimate, icon: "clock")
                }

                if let points = question.points {
                    MetadataRow(label: "Points", value: "\(points)", icon: "star")
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
    }

    private var closeButton: some View {
        Button("Done") {
            dismiss()
        }
        .font(.body.bold())
    }

    private func canSubmit() -> Bool {
        switch question.type {
        case .multipleChoice, .trueFalse:
            return selectedOption != nil
        case .shortAnswer, .calculation, .essay:
            return !userAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func getCurrentAnswer() -> String {
        switch question.type {
        case .multipleChoice, .trueFalse:
            return selectedOption ?? ""
        case .shortAnswer, .calculation, .essay:
            return userAnswer
        }
    }

    private func submitAnswer() {
        hasSubmitted = true
        let currentAnswer = getCurrentAnswer()

        // Simple correctness check (in a real app, this would be more sophisticated)
        isCorrect = currentAnswer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ==
                   question.correctAnswer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        showingExplanation = true
        logger.info("📝 Answer submitted: \(isCorrect ? "Correct" : "Incorrect")")
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    let sampleQuestion = QuestionGenerationService.GeneratedQuestion(
        question: "What is the derivative of the function f(x) = x² + 3x - 5?",
        type: .calculation,
        correctAnswer: "2x + 3",
        explanation: "Using the power rule for derivatives: the derivative of x² is 2x, the derivative of 3x is 3, and the derivative of a constant (-5) is 0. Therefore, f'(x) = 2x + 3.",
        topic: "Calculus - Derivatives",
        difficulty: "intermediate",
        points: 15,
        timeEstimate: "3 min",
        options: nil
    )

    GeneratedQuestionDetailView(question: sampleQuestion)
}