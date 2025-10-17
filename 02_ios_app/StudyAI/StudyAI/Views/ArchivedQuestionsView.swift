//
//  ArchivedQuestionsView.swift
//  StudyAI
//
//  Created by Claude Code on 9/4/25.
//

import SwiftUI

struct ArchivedQuestionsView: View {
    @StateObject private var questionArchiveService = QuestionArchiveService.shared
    @State private var questions: [QuestionSummary] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var selectedSubject: String? = nil
    @State private var searchText = ""
    
    private let subjects = ["Math", "Physics", "Chemistry", "Biology", "English", "History", "Other"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Compact Filter Bar
                if !questions.isEmpty {
                    filterBar
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                // Content
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if questions.isEmpty {
                    emptyState
                } else {
                    questionsList
                }
            }
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadQuestions() }
        }
    }
    
    // MARK: - Compact Filter Bar
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.gray)
                    TextField("Search", text: $searchText)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .frame(width: 100)
                
                // Subject Pills
                ForEach(subjects, id: \.self) { subject in
                    Button(subject) {
                        selectedSubject = selectedSubject == subject ? nil : subject
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(selectedSubject == subject ? Color.blue : Color.gray.opacity(0.1))
                    .foregroundColor(selectedSubject == subject ? .white : .primary)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Questions List
    
    private var questionsList: some View {
        List(filteredQuestions, id: \.id) { question in
            NavigationLink(destination: QuestionDetailView(questionId: question.id)) {
                CompactQuestionCard(question: question)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("No archived questions")
                .font(.headline)
                .foregroundColor(.gray)
            
            Text("Archive questions to review later")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Computed Properties
    
    private var filteredQuestions: [QuestionSummary] {
        questions.filter { question in
            let matchesSubject = selectedSubject == nil || question.subject.contains(selectedSubject!)
            let matchesSearch = searchText.isEmpty || 
                question.questionText.localizedCaseInsensitiveContains(searchText) ||
                question.subject.localizedCaseInsensitiveContains(searchText)
            return matchesSubject && matchesSearch
        }
    }
    
    // MARK: - Actions
    
    private func loadQuestions() {
        isLoading = true
        Task {
            do {
                let fetchedQuestions = try await questionArchiveService.fetchArchivedQuestions(limit: 100)
                await MainActor.run {
                    self.questions = fetchedQuestions
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Compact Question Card

struct CompactQuestionCard: View {
    let question: QuestionSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header Row
            HStack {
                // Subject Badge
                Text(shortSubject)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(subjectColor.opacity(0.2))
                    .foregroundColor(subjectColor)
                    .cornerRadius(4)
                
                Spacer()
                
                // Confidence & Visual Indicators
                HStack(spacing: 4) {
                    if question.hasVisualElements {
                        Image(systemName: "photo.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    
                    Circle()
                        .fill(confidenceColor)
                        .frame(width: 6, height: 6)
                }
            }
            
            // Question Text
            Text(question.questionText)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // Footer
            HStack {
                Text(timeAgo)
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                Spacer()
                
                if let tags = question.tags, !tags.isEmpty {
                    Text("• \(tags.count)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }
    
    private var shortSubject: String {
        switch question.subject {
        case "Mathematics": return "Math"
        case "Computer Science": return "CS"
        case "Foreign Language": return "Lang"
        default: return question.subject
        }
    }
    
    private var subjectColor: Color {
        switch question.subject {
        case "Mathematics", "Math": return .blue
        case "Physics": return .purple
        case "Chemistry": return .green
        case "Biology": return .orange
        case "English": return .red
        case "History": return .brown
        default: return .gray
        }
    }
    
    private var confidenceColor: Color {
        guard let confidence = question.confidence else { return .gray }
        return confidence > 0.8 ? .green : confidence > 0.6 ? .orange : .red
    }
    
    private var timeAgo: String {
        let now = Date()
        let interval = now.timeIntervalSince(question.archivedAt)
        
        if interval < 3600 { // < 1 hour
            return "\(Int(interval / 60))m"
        } else if interval < 86400 { // < 1 day
            return "\(Int(interval / 3600))h"
        } else {
            return "\(Int(interval / 86400))d"
        }
    }
}

// MARK: - Minimal Question Detail View

struct QuestionDetailView: View {
    let questionId: String
    @StateObject private var questionArchiveService = QuestionArchiveService.shared
    @State private var question: ArchivedQuestion?
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 100)
            } else if let question = question {
                VStack(alignment: .leading, spacing: 16) {
                    // Grading Badge (if graded)
                    if question.isGraded, let grade = question.grade {
                        HStack(spacing: 8) {
                            Image(systemName: gradeIcon(grade))
                                .foregroundColor(gradeColor(grade))
                            Text(grade.displayName)
                                .font(.headline)
                                .foregroundColor(gradeColor(grade))
                            if let points = question.points, let maxPoints = question.maxPoints {
                                Text("(\(String(format: "%.1f", points))/\(String(format: "%.1f", maxPoints)))")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(gradeColor(grade).opacity(0.1))
                        .cornerRadius(12)
                    }

                    // Question (Clean version for preview)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Q")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.blue)
                                .cornerRadius(4)

                            Text(question.subject)
                                .font(.caption)
                                .foregroundColor(.gray)

                            Spacer()

                            Circle()
                                .fill(confidenceColor(question.confidence))
                                .frame(width: 8, height: 8)
                        }

                        Text(question.questionText)
                            .font(.body)
                            .fontWeight(.medium)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)

                    // Raw Question (Full original text from image)
                    if let rawText = question.rawQuestionText, rawText != question.questionText {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("Original Question")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Text(rawText)
                                .font(.callout)
                                .foregroundColor(.black)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.03))
                        .cornerRadius(12)
                    }

                    // Student Answer
                    if let studentAnswer = question.studentAnswer, !studentAnswer.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Text("Student Answer")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Text(studentAnswer)
                                .font(.body)
                                .foregroundColor(.black)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(12)
                    }

                    // Correct Answer
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("A")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.green)
                                .cornerRadius(4)

                            Text("Correct Answer")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        Text(question.answerText)
                            .font(.body)
                            .foregroundColor(.black)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(12)

                    // AI Feedback
                    if let feedback = question.feedback, !feedback.isEmpty, feedback != "No feedback provided" {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "bubble.left.fill")
                                    .font(.caption)
                                    .foregroundColor(.purple)
                                Text("AI Feedback")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Text(feedback)
                                .font(.body)
                                .foregroundColor(.black)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(12)
                    }

                    // Tags & Notes (if any)
                    if let tags = question.tags, !tags.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(8)
                            }
                        }
                    }

                    if let notes = question.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "note.text")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text("Your Notes")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            Text(notes)
                                .font(.callout)
                                .foregroundColor(.black)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadQuestion() }
    }
    
    private func loadQuestion() {
        Task {
            do {
                let fetchedQuestion = try await questionArchiveService.getQuestionDetails(questionId: questionId)
                await MainActor.run {
                    self.question = fetchedQuestion
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func confidenceColor(_ confidence: Float?) -> Color {
        guard let confidence = confidence else { return .gray }
        return confidence > 0.8 ? .green : confidence > 0.6 ? .orange : .red
    }

    private func gradeIcon(_ grade: GradeResult) -> String {
        switch grade {
        case .correct: return "checkmark.circle.fill"
        case .incorrect: return "xmark.circle.fill"
        case .empty: return "minus.circle.fill"
        case .partialCredit: return "checkmark.circle"
        }
    }

    private func gradeColor(_ grade: GradeResult) -> Color {
        switch grade {
        case .correct: return .green
        case .incorrect: return .red
        case .empty: return .gray
        case .partialCredit: return .orange
        }
    }
}

#Preview {
    ArchivedQuestionsView()
}