//
//  ResultsView.swift
//  StudyAI
//
//  Created by Claude Code on 9/14/25.
//  AI analysis results display view
//

import SwiftUI

struct ResultsView: View {
    let result: HomeworkResult
    let flowController: HomeworkFlowController
    
    @State private var selectedQuestion: QuestionResult?
    @State private var showingActionSheet = false
    @State private var animateScore = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with score
            headerSection
            
            // Questions list
            questionsSection
            
            // Actions
            actionsSection
        }
        .background(Color.black)
        .navigationBarHidden(true)
        .sheet(item: $selectedQuestion) { question in
            QuestionDetailView(question: question)
        }
        .confirmationDialog("Choose Action", isPresented: $showingActionSheet) {
            Button("Start New Homework") {
                flowController.handle(.resetFlow)
            }
            
            Button("Save Results") {
                saveResults()
            }
            
            Button("Share Results") {
                shareResults()
            }
            
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).delay(0.3)) {
                animateScore = true
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 20) {
            // Title
            Text("Analysis Complete")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            // Score circle
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: animateScore ? CGFloat(result.overallScore) : 0)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(Int(result.overallScore * 100))%")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Score")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            // Score interpretation
            Text(scoreInterpretation)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(scoreColor)
            
            // Processing stats
            HStack(spacing: 30) {
                StatItem(
                    icon: "doc.text.fill",
                    value: "\(result.questions.count)",
                    label: "Questions"
                )
                
                StatItem(
                    icon: "clock.fill",
                    value: String(format: "%.1fs", result.processingTime),
                    label: "Processed"
                )
                
                StatItem(
                    icon: "checkmark.circle.fill",
                    value: "\(correctAnswersCount)",
                    label: "Correct"
                )
            }
        }
        .padding(.top, 40)
        .padding(.bottom, 30)
        .background(
            LinearGradient(
                colors: [scoreColor.opacity(0.2), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Question Breakdown")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(result.questions.count) questions")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(result.questions) { question in
                        QuestionRowView(
                            question: question,
                            onTap: {
                                selectedQuestion = question
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: 16) {
            // Suggested actions
            if !result.suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggested Next Steps")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    ForEach(result.suggestedActions, id: \.self) { action in
                        HStack(spacing: 12) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.yellow)
                            
                            Text(action)
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.9))
                            
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            // Main actions
            HStack(spacing: 12) {
                Button("More Options") {
                    showingActionSheet = true
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.2))
                .cornerRadius(12)
                
                Button("New Homework") {
                    flowController.handle(.resetFlow)
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Computed Properties
    
    private var scoreColor: Color {
        if result.overallScore >= 0.8 { return .green }
        if result.overallScore >= 0.6 { return .orange }
        return .red
    }
    
    private var scoreInterpretation: String {
        if result.overallScore >= 0.9 { return "Excellent Work!" }
        if result.overallScore >= 0.8 { return "Great Job!" }
        if result.overallScore >= 0.7 { return "Good Progress" }
        if result.overallScore >= 0.6 { return "Keep Improving" }
        return "Needs Practice"
    }
    
    private var correctAnswersCount: Int {
        result.questions.filter { $0.isCorrect }.count
    }
    
    // MARK: - Actions
    
    private func saveResults() {
        // TODO: Implement save functionality
        print("Saving results...")
    }
    
    private func shareResults() {
        // TODO: Implement share functionality
        print("Sharing results...")
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

// MARK: - Question Row View

struct QuestionRowView: View {
    let question: QuestionResult
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Question number and status
                ZStack {
                    Circle()
                        .fill(question.isCorrect ? Color.green : Color.red)
                        .frame(width: 32, height: 32)
                    
                    if question.isCorrect {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text("\(question.questionNumber)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // Question content
                VStack(alignment: .leading, spacing: 4) {
                    Text("Question \(question.questionNumber)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(question.questionText)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                    
                    // Confidence indicator
                    HStack(spacing: 4) {
                        Text("Confidence:")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text("\(Int(question.confidence * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(confidenceColor(question.confidence))
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.6 { return .yellow }
        return .orange
    }
}

// MARK: - Question Detail View

struct QuestionDetailView: View {
    let question: QuestionResult
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Question
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Question \(question.questionNumber)")
                            .font(.headline)
                        
                        Text(question.questionText)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    // Answers
                    if let studentAnswer = question.studentAnswer {
                        AnswerSection(title: "Your Answer", answer: studentAnswer, isCorrect: question.isCorrect)
                    }
                    
                    if let correctAnswer = question.correctAnswer {
                        AnswerSection(title: "Correct Answer", answer: correctAnswer, isCorrect: true)
                    }
                    
                    // Feedback
                    if !question.feedback.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Feedback")
                                .font(.headline)
                            
                            Text(question.feedback)
                                .font(.body)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Hints
                    if !question.hints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hints")
                                .font(.headline)
                            
                            ForEach(Array(question.hints.enumerated()), id: \.offset) { index, hint in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(index + 1).")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Text(hint)
                                        .font(.subheadline)
                                }
                                .padding()
                                .background(Color.yellow.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Question Detail")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AnswerSection: View {
    let title: String
    let answer: String
    let isCorrect: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isCorrect ? .green : .red)
            }
            
            Text(answer)
                .font(.body)
                .padding()
                .background((isCorrect ? Color.green : Color.red).opacity(0.1))
                .cornerRadius(8)
        }
    }
}

#Preview {
    let sampleResult = HomeworkResult(
        overallScore: 0.85,
        questions: [
            QuestionResult(
                questionNumber: 1,
                questionText: "What is 2 + 2?",
                correctAnswer: "4",
                studentAnswer: "4",
                isCorrect: true,
                confidence: 0.95,
                feedback: "Correct! Great job.",
                hints: []
            )
        ],
        processingTime: 2.5
    )
    
    ResultsView(result: sampleResult, flowController: HomeworkFlowController())
}