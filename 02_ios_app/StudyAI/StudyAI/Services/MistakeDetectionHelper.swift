//
//  MistakeDetectionHelper.swift
//  StudyAI
//
//  Detects unarchived mistakes on current page for error analysis prompting
//

import Foundation

class MistakeDetectionHelper {
    static let shared = MistakeDetectionHelper()

    private let localStorage = QuestionLocalStorage.shared

    private init() {}

    /// Detect unarchived mistakes from current session/page
    /// Returns questions that are:
    /// 1. Incorrect (isCorrect == false)
    /// 2. NOT already archived in local storage
    func getUnarchivedMistakes(from questions: [ParsedQuestion]) -> [ParsedQuestion] {
        // Get all archived question IDs
        let archivedQuestionIds = Set(localStorage.getAllArchivedQuestionIds())

        // Filter: incorrect AND not archived
        let mistakes = questions.filter { question in
            // Check if incorrect (not graded as CORRECT)
            // Include INCORRECT, EMPTY, and PARTIAL_CREDIT
            guard let grade = question.grade else { return false }
            guard grade != "CORRECT" else { return false }

            // Check if not already archived
            return !archivedQuestionIds.contains(question.id)
        }

        print("🔍 [MistakeDetection] Found \(mistakes.count) unarchived mistakes out of \(questions.count) total questions")
        return mistakes
    }

    /// Check if current page has unarchived mistakes
    func hasUnarchivedMistakes(in questions: [ParsedQuestion]) -> Bool {
        return !getUnarchivedMistakes(from: questions).isEmpty
    }

    /// Get count of unarchived mistakes
    func getUnarchivedMistakeCount(in questions: [ParsedQuestion]) -> Int {
        return getUnarchivedMistakes(from: questions).count
    }
}

// MARK: - QuestionLocalStorage Extension

private extension QuestionLocalStorage {
    /// Get all archived question IDs from local storage
    func getAllArchivedQuestionIds() -> [String] {
        let allQuestions = getLocalQuestions()
        return allQuestions.compactMap { $0["id"] as? String }
    }
}
