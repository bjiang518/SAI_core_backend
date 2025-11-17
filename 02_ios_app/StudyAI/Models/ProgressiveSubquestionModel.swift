//
//  ProgressiveSubquestionModel.swift
//  StudyAI
//
//  Subquestion model for hierarchical homework grading
//

import Foundation

/// Subquestion within a parent question (for hierarchical structure)
struct ProgressiveSubquestion: Codable, Identifiable {
    let id: String
    let questionText: String
    let studentAnswer: String
    let questionType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case questionText = "question_text"
        case studentAnswer = "student_answer"
        case questionType = "question_type"
    }
}
