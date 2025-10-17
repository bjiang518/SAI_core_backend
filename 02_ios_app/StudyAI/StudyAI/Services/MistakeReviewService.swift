//
//  MistakeReviewService.swift
//  StudyAI
//
//  Created by Claude Code on 9/20/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class MistakeReviewService: ObservableObject {
    @Published var isLoading = false
    @Published var subjectsWithMistakes: [SubjectMistakeCount] = []
    @Published var mistakes: [MistakeQuestion] = []
    @Published var errorMessage: String?

    private let questionLocalStorage = QuestionLocalStorage.shared

    /// Fetch subjects with mistake counts from LOCAL STORAGE ONLY
    func fetchSubjectsWithMistakes(timeRange: MistakeTimeRange? = nil) async {
        print("🔍 [MistakeReview] === FETCHING SUBJECTS FROM LOCAL STORAGE ===")
        print("🔍 [MistakeReview] Time range: \(timeRange?.rawValue ?? "All Time") (ignored for local)")

        isLoading = true
        errorMessage = nil

        // ✅ Fetch from local storage only
        let subjectData = questionLocalStorage.getSubjectsWithMistakes()

        // Convert to SubjectMistakeCount
        let subjects = subjectData.map { item in
            SubjectMistakeCount(
                subject: item.subject,
                mistakeCount: item.count,
                icon: getSubjectIcon(item.subject)
            )
        }

        print("✅ [MistakeReview] Successfully fetched subjects from local storage")
        print("📊 [MistakeReview] Found \(subjects.count) subjects with mistakes:")
        for subject in subjects {
            print("   - \(subject.subject): \(subject.mistakeCount) mistakes")
        }

        self.subjectsWithMistakes = subjects
        isLoading = false
        print("🔍 [MistakeReview] === FETCH SUBJECTS COMPLETE ===\n")
    }

    /// Fetch mistakes from LOCAL STORAGE ONLY
    func fetchMistakes(subject: String?, timeRange: MistakeTimeRange) async {
        print("🔍 [MistakeReview] === FETCHING MISTAKES FROM LOCAL STORAGE ===")
        print("🔍 [MistakeReview] Subject: \(subject ?? "All Subjects")")
        print("🔍 [MistakeReview] Time range: \(timeRange.rawValue) (ignored for local)")

        isLoading = true
        errorMessage = nil

        // ✅ Fetch from local storage only
        let mistakeData = questionLocalStorage.getMistakeQuestions(subject: subject)

        // Convert to MistakeQuestion format
        var mistakes: [MistakeQuestion] = []
        for data in mistakeData {
            if let id = data["id"] as? String,
               let subject = data["subject"] as? String,
               let questionText = data["questionText"] as? String,
               let answerText = data["answerText"] as? String {

                let studentAnswer = data["studentAnswer"] as? String ?? ""
                let feedback = data["feedback"] as? String ?? ""
                let archivedAtString = data["archivedAt"] as? String ?? ""

                // ✅ Extract rawQuestionText (full original question from image)
                let rawQuestionText = data["rawQuestionText"] as? String ?? questionText

                // Parse date from archivedAt string
                let dateFormatter = ISO8601DateFormatter()
                let createdAt = dateFormatter.date(from: archivedAtString) ?? Date()

                // Extract grading data
                let points = (data["points"] as? Float).map(Double.init) ?? 0.0
                let maxPoints = (data["maxPoints"] as? Float).map(Double.init) ?? 1.0
                let confidence = (data["confidence"] as? Float).map(Double.init) ?? 0.0
                let tags = data["tags"] as? [String] ?? []
                let notes = data["notes"] as? String ?? ""

                let mistake = MistakeQuestion(
                    id: id,
                    subject: subject,
                    question: questionText,
                    rawQuestionText: rawQuestionText,  // ✅ Pass full question text
                    correctAnswer: answerText,
                    studentAnswer: studentAnswer,
                    explanation: feedback,
                    createdAt: createdAt,
                    confidence: confidence,
                    pointsEarned: points,
                    pointsPossible: maxPoints,
                    tags: tags,
                    notes: notes
                )
                mistakes.append(mistake)
            }
        }

        print("✅ [MistakeReview] Successfully fetched mistakes from local storage")
        print("📊 [MistakeReview] Total mistakes retrieved: \(mistakes.count)")

        if mistakes.isEmpty {
            print("⚠️ [MistakeReview] No mistakes found in local storage")
        } else {
            print("📋 [MistakeReview] Mistake summary:")
            for (index, mistake) in mistakes.prefix(5).enumerated() {
                print("   \(index + 1). [\(mistake.subject)] \(mistake.question.prefix(50))...")
                print("      Student: \(mistake.studentAnswer.prefix(30))...")
                print("      Correct: \(mistake.correctAnswer.prefix(30))...")
            }
            if mistakes.count > 5 {
                print("   ... and \(mistakes.count - 5) more")
            }
        }

        self.mistakes = mistakes
        isLoading = false
        print("🔍 [MistakeReview] === FETCH MISTAKES COMPLETE ===\n")
    }

    /// Get mistake statistics from LOCAL STORAGE ONLY
    func getMistakeStats() async -> MistakeStats? {
        print("🔍 [MistakeReview] === FETCHING STATS FROM LOCAL STORAGE ===")

        let allMistakes = questionLocalStorage.getMistakeQuestions()
        let subjectData = questionLocalStorage.getSubjectsWithMistakes()

        let stats = MistakeStats(
            totalMistakes: allMistakes.count,
            subjectsWithMistakes: subjectData.count,
            mistakesLastWeek: 0,  // Time filtering not implemented for local
            mistakesLastMonth: 0  // Time filtering not implemented for local
        )

        print("✅ [MistakeReview] Successfully calculated stats from local storage")
        print("📊 [MistakeReview] Stats summary:")
        print("   - Total mistakes: \(stats.totalMistakes)")
        print("   - Subjects with mistakes: \(stats.subjectsWithMistakes)")
        print("   - Note: Time-based filtering not available for local storage")

        print("🔍 [MistakeReview] === FETCH STATS COMPLETE ===\n")
        return stats
    }

    /// Get icon for subject
    private func getSubjectIcon(_ subject: String) -> String {
        switch subject.lowercased() {
        case "math", "mathematics": return "📐"
        case "physics": return "⚛️"
        case "chemistry": return "🧪"
        case "biology": return "🧬"
        case "english": return "📚"
        case "history": return "📜"
        case "science": return "🔬"
        default: return "📖"
        }
    }
}