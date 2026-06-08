//
//  ProgressiveSubquestionModel.swift
//  StudyAI
//
//  Subquestion model for hierarchical homework grading
//

import Foundation

/// Subquestion within a parent question (for hierarchical structure)
public struct ProgressiveSubquestion: Codable, Identifiable {
    public let id: String
    public let questionText: String
    public let studentAnswer: String
    public let questionType: String?
    public let needImage: Bool?
    public let workingSteps: [String]?

    public enum CodingKeys: String, CodingKey {
        case id
        case questionText  = "question_text"
        case studentAnswer = "student_answer"
        case questionType  = "question_type"
        case needImage     = "need_image"
        case workingSteps  = "working_steps"
    }

    /// Whether the parsed answer field looks non-empty (used to route grade vs solve).
    public var hasStudentAnswer: Bool {
        let trimmed = studentAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let placeholders: Set<String> = ["?", "_", "—", "-", "...", "n/a", "na"]
        return !placeholders.contains(trimmed.lowercased())
    }

    /// True if the parsed answer is the "answer is in the image" sentinel.
    /// See `ProgressiveQuestion.answerInImageSentinel` for context.
    public var hasAnswerInImage: Bool {
        return studentAnswer == ProgressiveQuestion.answerInImageSentinel
    }
}
