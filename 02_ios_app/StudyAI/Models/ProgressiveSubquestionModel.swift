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

    public enum CodingKeys: String, CodingKey {
        case id
        case questionText = "question_text"
        case studentAnswer = "student_answer"
        case questionType = "question_type"
        case needImage = "need_image"
    }
}
